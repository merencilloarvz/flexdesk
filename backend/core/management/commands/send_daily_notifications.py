import logging
from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo

from django.core.management.base import BaseCommand
from django.db.models import F, Sum

from core.models import (CheckIn, Gym, Member, NotificationSend, Product, Sale,
                         StaffProfile, Subscription)
from core.notifications import send_to_users
from core.utils import gym_today

logger = logging.getLogger(__name__)


class Command(BaseCommand):
    """
    Renewal reminders, the low-stock digest, trial/subscription-ending
    reminders, and the daily sales summary — runs once a day, at 8:00 AM
    Philippine time (Railway cron; see the project's scheduling setup).
    Safe to run any number of times in the same gym-local day because
    every send is gated on a NotificationSend row that either already
    exists or gets created right before sending.
    """
    help = ("Sends renewal reminders, the low-stock digest, trial-ending "
           "reminders, and the daily sales summary, once per gym per day.")

    def handle(self, *args, **options):
        for gym in Gym.objects.all():
            try:
                today = gym_today(gym)
                self._send_renewal_reminders(gym, today)
                self._send_low_stock_digest(gym, today)
                self._send_trial_reminders(gym, today)
                self._send_daily_summary(gym, today)
            except Exception:
                # One gym's bad data (or anything else) must not cost
                # every gym after it its notifications for the day.
                logger.exception("send_daily_notifications failed for gym %s", gym.id)
                continue

    def _send_renewal_reminders(self, gym, today):
        # with_status's current_end_date comes from the same "latest
        # non-canceled membership" subquery used everywhere else expiry
        # is computed — reused here rather than re-deriving the rule.
        members = (
            Member.objects.visible().members()
            .filter(gym=gym, user__isnull=False)
            .with_status(today)
        )

        for kind, target_date, phrase in (
            ("renewal_3day", today + timedelta(days=3), "in 3 days"),
            ("renewal_lastday", today, "today"),
        ):
            for member in members.filter(current_end_date=target_date):
                membership = member.current_membership
                if membership is None:
                    continue

                # Check for an existing send BEFORE sending, and only
                # record one AFTER send_to_users returns. Recording first
                # (the old order) would mark a member as notified even if
                # the send itself never went out, and every later run
                # would then silently skip them forever — exactly the
                # failure this phase exists to prevent. A duplicate push,
                # if a race lands between the check and the create below,
                # is far cheaper than a member never being told. This
                # does mean the DB constraint no longer atomically
                # guarantees "once" the way get_or_create did — that's
                # accepted here; send_to_users never raises by design, so
                # this mainly guards against anything else in this block
                # failing, which is still worth having.
                already_sent = NotificationSend.objects.filter(
                    user=member.user, kind=kind, subject_id=membership.id,
                ).exists()
                if already_sent:
                    continue

                send_to_users(
                    [member.user],
                    title="FlexDesk",
                    body=f"Your membership at {gym.name} ends {phrase}.",
                    data={"type": "renewal", "id": str(membership.id)},
                    notif_type="renewal",
                )

                NotificationSend.objects.create(
                    user=member.user, kind=kind, subject_id=membership.id,
                )

    def _send_low_stock_digest(self, gym, today):
        owner = StaffProfile.objects.filter(gym=gym, role=StaffProfile.OWNER).first()
        if owner is None:
            return

        low_stock = list(Product.objects.filter(
            gym=gym, is_active=True, stock_quantity__lte=F("low_stock_threshold"),
        ))
        if not low_stock:
            return

        # Date-suffixed kind rather than a sent_at range check — see A4.
        # subject_id stays null (this isn't about one product), so the
        # uniqueness that matters here is this exists() check, not the
        # DB constraint: Postgres never treats two NULLs as equal, so a
        # plain UniqueConstraint on (user, kind, NULL) can't by itself
        # stop a same-day double-send the way it does for the renewal
        # kinds above, where subject_id is a real membership id.
        kind = f"low_stock_digest_{today:%Y_%m_%d}"
        already_sent = NotificationSend.objects.filter(
            user=owner.user, kind=kind, subject_id=None,
        ).exists()
        if already_sent:
            return

        # Same send-before-record ordering as _send_renewal_reminders,
        # and for the same reason.
        if len(low_stock) == 1:
            body = f"{low_stock[0].name} is running low."
        else:
            body = f"{len(low_stock)} products are running low."

        send_to_users(
            [owner.user], title="FlexDesk", body=body,
            data={"type": "inventory", "id": None},
            notif_type="inventory",
        )

        NotificationSend.objects.create(user=owner.user, kind=kind, subject_id=None)

    def _send_trial_reminders(self, gym, today):
        subscription = Subscription.objects.filter(gym=gym).first()
        if subscription is None or subscription.status != Subscription.TRIALING:
            return

        owner = StaffProfile.objects.filter(gym=gym, role=StaffProfile.OWNER).first()
        if owner is None:
            return

        tz = ZoneInfo(gym.timezone)
        trial_end_date = subscription.trial_ends_at.astimezone(tz).date()

        for kind, target_date, phrase in (
            ("trial_3day", today + timedelta(days=Subscription.EXPIRING_SOON_DAYS), "in 3 days"),
            ("trial_lastday", today, "today"),
        ):
            if trial_end_date != target_date:
                continue

            already_sent = NotificationSend.objects.filter(
                user=owner.user, kind=kind, subject_id=subscription.id,
            ).exists()
            if already_sent:
                continue

            send_to_users(
                [owner.user], title="FlexDesk",
                body=f"Your free trial ends {phrase}. Subscribe to keep FlexDesk running.",
                data={"type": "trial_ending", "id": str(subscription.id)},
                notif_type="trial_ending",
            )

            NotificationSend.objects.create(
                user=owner.user, kind=kind, subject_id=subscription.id,
            )

    def _send_daily_summary(self, gym, today):
        owner = StaffProfile.objects.filter(gym=gym, role=StaffProfile.OWNER).first()
        if owner is None:
            return

        yesterday = today - timedelta(days=1)
        kind = f"daily_summary_{yesterday:%Y_%m_%d}"
        already_sent = NotificationSend.objects.filter(
            user=owner.user, kind=kind, subject_id=None,
        ).exists()
        if already_sent:
            return

        # Explicit gym-local day -> UTC range, same shape as
        # CheckInViewSet.get_queryset — never a bare __date lookup, which
        # would use settings.TIME_ZONE (UTC) instead of the gym's.
        tz = ZoneInfo(gym.timezone)
        start = datetime.combine(yesterday, time.min, tzinfo=tz)
        end = start + timedelta(days=1)

        sales_qs = Sale.objects.filter(
            gym=gym, voided_at__isnull=True, sold_at__gte=start, sold_at__lt=end)
        total_sales = sales_qs.aggregate(total=Sum("total_amount"))["total"] or 0
        checkins_count = CheckIn.objects.filter(
            gym=gym, voided_at__isnull=True, checked_in_at__gte=start, checked_in_at__lt=end,
        ).count()

        if total_sales == 0 and checkins_count == 0:
            return

        new_members_count = Member.objects.filter(
            gym=gym, created_at__gte=start, created_at__lt=end).count()

        body = (f"₱{total_sales:,.0f} in sales · {checkins_count} check-ins · "
               f"{new_members_count} new member{'s' if new_members_count != 1 else ''}")

        send_to_users(
            [owner.user], title=f"Yesterday at {gym.name}", body=body,
            data={"type": "daily_summary", "id": None},
            notif_type="daily_summary",
        )

        NotificationSend.objects.create(user=owner.user, kind=kind, subject_id=None)
