from django.core.management.base import BaseCommand
from django.db.models import F
from datetime import timedelta

from core.models import Gym, Member, NotificationSend, Product, StaffProfile
from core.notifications import send_to_users
from core.utils import gym_today


class Command(BaseCommand):
    """
    Renewal reminders and the low-stock digest — A5. Run once a day (see
    A6 for how it's scheduled); safe to run any number of times in the
    same gym-local day because every send is gated on a NotificationSend
    row that either already exists or gets created right before sending.
    """
    help = "Sends renewal reminders and the low-stock digest, once per gym per day."

    def handle(self, *args, **options):
        for gym in Gym.objects.all():
            today = gym_today(gym)
            self._send_renewal_reminders(gym, today)
            self._send_low_stock_digest(gym, today)

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
                _, created = NotificationSend.objects.get_or_create(
                    user=member.user, kind=kind, subject_id=membership.id,
                )
                if not created:
                    continue
                send_to_users(
                    [member.user],
                    title="FlexDesk",
                    body=f"Your membership at {gym.name} ends {phrase}.",
                    data={"type": "renewal", "id": str(membership.id)},
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

        NotificationSend.objects.create(user=owner.user, kind=kind, subject_id=None)

        if len(low_stock) == 1:
            body = f"{low_stock[0].name} is running low."
        else:
            body = f"{len(low_stock)} products are running low."

        send_to_users(
            [owner.user], title="FlexDesk", body=body,
            data={"type": "inventory", "id": None},
        )
