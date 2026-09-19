import hmac
import logging
import threading
import uuid
from django.conf import settings as dj_settings
from django.db import IntegrityError
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.generics import DestroyAPIView, ListAPIView, ListCreateAPIView, RetrieveAPIView
from rest_framework.response import Response
from rest_framework.exceptions import MethodNotAllowed, ValidationError
from rest_framework_simplejwt.views import TokenObtainPairView
from rest_framework_simplejwt.views import TokenObtainPairView
from django.utils import timezone

from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo
from . import qr as qr_lib
from .mixins import GymScopedViewSet
from .models import CheckIn, Member, Membership, MembershipPlan, RenewalReminder, Subscription, User
from .permissions import IsGymMember, IsGymStaff, IsOwner, IsOwnerOrReadOnly, SubscriptionActive
from .serializers import (CheckInSerializer, CheckInWriteSerializer,
                          ClaimAccountSerializer, ExpiringMemberSerializer,
                          FlexTokenObtainPairSerializer, MeCheckInSerializer,
                          MeMemberSummarySerializer, MeSerializer, MemberRestDaysSerializer,
                          MemberSerializer, MembershipPlanSerializer,
                          MembershipSerializer, MemberWriteSerializer,
                          RenewalReminderSerializer, SubscriptionSerializer,
                          VerifyQrSerializer)
from .utils import generate_claim_code, generate_temp_password, gym_today

from rest_framework.permissions import AllowAny
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from .serializers import SignupSerializer

from .serializers import (ChangePasswordSerializer, StaffCreateSerializer,
                          StaffMemberSerializer)
from .models import StaffProfile
from django.db import transaction
from django.db.models import Count, Exists, F, IntegerField, OuterRef, Q, Subquery
from django.http import Http404
from django.shortcuts import get_object_or_404
from .models import Booking, TimeSlot
from .serializers import BookingCreateSerializer, BookingSerializer, TimeSlotSerializer


from rest_framework.exceptions import PermissionDenied
from .models import Announcement, Comment, Event, EventRegistration, EventResult, Like
from .models import Product, Sale, SaleItem, StockAdjustment
from .models import DeviceToken, NotificationSend
from .notifications import send_to_users
from .permissions import CanEngage, IsGymUser, IsGymStaffOrReadOnly
from .serializers import (AnnouncementSerializer, CommentSerializer, EventRegistrationSerializer,
                          EventResultInputSerializer, EventResultSerializer,
                          EventSerializer, LikeSerializer, MemberEventRegistrationSerializer,
                          ProductSerializer, SaleCreateSerializer, SaleSerializer,
                          StockAdjustmentInputSerializer, StockAdjustmentSerializer)
from .serializers import DeviceTokenSerializer
from django.db.models import Sum, DecimalField
from django.contrib.admin.models import LogEntry, CHANGE
from django.db.models.functions import Coalesce, TruncDate, TruncHour
from decimal import Decimal
from rest_framework.permissions import IsAuthenticated
from .permissions import ClassesEnabled, IsGymMember, IsGymStaff, IsOwner, IsOwnerOrReadOnly

class FlexTokenObtainPairView(TokenObtainPairView):
    serializer_class = FlexTokenObtainPairSerializer
    throttle_scope = "login"


class MeView(RetrieveAPIView):
    serializer_class = MeSerializer

    def get_object(self):
        return self.request.user


from .serializers import GymSettingsSerializer  # add to your existing serializers import


class GymSettingsView(APIView):
    """
    Owner-only settings toggle(s) for the gym itself. Deliberately uses
    GymSettingsSerializer's explicit one-field list, not a generic Gym
    serializer, so nothing else on Gym becomes writable here by accident.
    """
    permission_classes = [IsGymStaff, IsOwner, SubscriptionActive]

    def patch(self, request):
        gym = request.user.gym
        serializer = GymSettingsSerializer(gym, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(MeSerializer(request.user).data)


class SubscriptionView(RetrieveAPIView):
    """
    Owner AND staff can read this — a blocked gym's front-desk staff
    should see "trial ends in 3 days" too, not just the owner. Never
    SubscriptionActive-gated: this is exactly how a blocked owner finds
    out why, and it must keep answering while blocked.
    """
    serializer_class = SubscriptionSerializer
    permission_classes = [IsGymStaff]

    def get_object(self):
        gym = self.request.user.gym
        # Every gym gets one at signup (0018) and every pre-Stage-10 gym
        # was backfilled as active (0019) — this is a last-resort safety
        # net, not the expected path, for a gym that somehow slipped
        # through both.
        subscription, _ = Subscription.objects.get_or_create(
            gym=gym, defaults={"status": Subscription.ACTIVE,
                               "trial_ends_at": timezone.now()})
        return subscription


class SubscriptionPaymentInfoView(APIView):
    """
    Owner AND staff can read this, same reasoning as SubscriptionView —
    it's what the "how to pay" screen renders, and it must keep
    answering while the gym is blocked. Never SubscriptionActive-gated.
    """
    permission_classes = [IsGymStaff]

    def get(self, request):
        return Response({
            "price_monthly_centavos": dj_settings.SUBSCRIPTION_PRICE_MONTHLY_CENTAVOS,
            "price_yearly_centavos": dj_settings.SUBSCRIPTION_PRICE_YEARLY_CENTAVOS,
            "payment_instructions": dj_settings.SUBSCRIPTION_PAYMENT_INSTRUCTIONS,
            "contact_info": dj_settings.SUBSCRIPTION_CONTACT_INFO,
        })

class MembershipPlanViewSet(GymScopedViewSet):
    queryset = MembershipPlan.objects.all()
    serializer_class = MembershipPlanSerializer
    permission_classes = [IsGymStaff, IsOwnerOrReadOnly]

    def create(self, request, *args, **kwargs):
        try:
            return super().create(request, *args, **kwargs)
        except IntegrityError:
            raise ValidationError(
                {"name": "A plan with this name and category already exists."}
            )

BOOKING_HORIZON_DAYS = 14


@transaction.atomic
def create_booking(gym, member, slot_id, date, created_by):
    """
    Locks the TimeSlot row for the duration of the check, so two members
    racing for the last spot queue behind each other instead of both
    reading the same count. Different slots don't block each other — the
    lock is per row.
    """
    try:
        slot = TimeSlot.objects.select_for_update().get(
            pk=slot_id, gym=gym, is_active=True)
    except (TimeSlot.DoesNotExist, ValueError, TypeError):
        # DRF's exception handler turns Http404 into a 404 response —
        # never a 403, so we don't confirm another gym's slot id exists.
        raise Http404("Time slot not found.")

    if date.isoweekday() not in slot.days_of_week_set():
        raise ValidationError({"date": "This slot doesn't run on that day."})

    today = gym_today(gym)
    if date < today:
        raise ValidationError({"date": "Can't book a date in the past."})
    if date > today + timedelta(days=BOOKING_HORIZON_DAYS):
        raise ValidationError(
            {"date": f"Bookings can only be made up to {BOOKING_HORIZON_DAYS} days ahead."})

        # An archived member has been removed from the gym and must not hold
    # a slot. This is a deliberate, explicit check — not a side effect of
    # the membership-status check below, which only looks at
    # active/expired/no_membership and wouldn't catch an archived member
    # who happens to still have a live membership row.
    if member.archived_at:
        raise ValidationError({"detail":
            "Your membership record is no longer active at this gym. "
            "Please talk to gym staff."})

    annotated = Member.objects.filter(gym=gym, pk=member.pk).with_status(today).first()
    if annotated.membership_status in ("expired", "no_membership"):
        raise ValidationError(
            {"detail": "An active membership is required to book a slot."})

    booked = Booking.objects.filter(
        time_slot=slot, date=date, canceled_at__isnull=True).count()
    if booked >= slot.capacity:
        raise ValidationError({"detail": "This slot is fully booked."})

    try:
        return Booking.objects.create(
            gym=gym, member=member, time_slot=slot, date=date,
            created_by=created_by,
        )
    except IntegrityError:
        raise ValidationError(
            {"detail": "You already have a booking for this slot and date."})


class TimeSlotViewSet(GymScopedViewSet):
    queryset = TimeSlot.objects.all()
    serializer_class = TimeSlotSerializer
    permission_classes = [IsGymStaff, IsOwnerOrReadOnly, ClassesEnabled]

    def _parse_date(self, request):
        date_str = request.query_params.get("date")
        if date_str:
            try:
                return datetime.strptime(date_str, "%Y-%m-%d").date()
            except ValueError:
                raise ValidationError({"date": "Use YYYY-MM-DD."})
        return self.today

    def get_queryset(self):
        day = self._parse_date(self.request)
        return super().get_queryset().annotate(
            booked_count=Count(
                "bookings",
                filter=Q(bookings__date=day, bookings__canceled_at__isnull=True),
            )
        )

    def destroy(self, request, *args, **kwargs):
        raise MethodNotAllowed("DELETE", detail="Set is_active to false instead.")

    @action(detail=True, methods=["get"], url_path="bookings")
    def bookings(self, request, pk=None):
        slot = self.get_object()
        day = self._parse_date(request)
        qs = (Booking.objects
              .filter(time_slot=slot, date=day, canceled_at__isnull=True)
              .select_related("member"))
        data = [
            {"id": str(b.id), "member_name": b.member.full_name,
             "member_code": b.member.member_code}
            for b in qs
        ]
        return Response(data)


class ScheduleView(APIView):
    permission_classes = [IsGymMember, ClassesEnabled]

    def get(self, request):
        gym = request.user.gym
        member = request.user.member_profile
        today = gym_today(gym)

        date_str = request.query_params.get("date")
        if date_str:
            try:
                day = datetime.strptime(date_str, "%Y-%m-%d").date()
            except ValueError:
                raise ValidationError({"date": "Use YYYY-MM-DD."})
        else:
            day = today

        weekday = day.isoweekday()
        slots = TimeSlot.objects.filter(gym=gym, is_active=True).annotate(
            booked_count=Count(
                "bookings",
                filter=Q(bookings__date=day, bookings__canceled_at__isnull=True),
            )
        )

        results = []
        for slot in slots:
            if weekday not in slot.days_of_week_set():
                continue
            my_booking = Booking.objects.filter(
                time_slot=slot, date=day, member=member, canceled_at__isnull=True
            ).first()
            results.append({
                "id": str(slot.id),
                "label": slot.label,
                "start_time": slot.start_time,
                "end_time": slot.end_time,
                "capacity": slot.capacity,
                "booked_count": slot.booked_count,
                "spots_left": max(slot.capacity - slot.booked_count, 0),
                "my_booking_id": str(my_booking.id) if my_booking else None,
            })
        return Response(results)


class BookingCreateView(APIView):
    permission_classes = [IsGymMember, ClassesEnabled]

    def post(self, request):
        s = BookingCreateSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        booking = create_booking(
            gym=request.user.gym,
            member=request.user.member_profile,
            slot_id=s.validated_data["time_slot"],
            date=s.validated_data["date"],
            created_by=request.user,
        )
        return Response(BookingSerializer(booking).data, status=status.HTTP_201_CREATED)


class MyBookingsView(ListAPIView):
    permission_classes = [IsGymMember, ClassesEnabled]
    serializer_class = BookingSerializer

    def get_queryset(self):
        qs = Booking.objects.filter(member=self.request.user.member_profile)
        if self.request.query_params.get("upcoming") == "1":
            today = gym_today(self.request.user.gym)
            qs = qs.filter(date__gte=today, canceled_at__isnull=True)
        return qs


class BookingCancelView(APIView):
    permission_classes = [IsGymMember, ClassesEnabled]

    def post(self, request, pk=None):
        # 404, never 403 — doesn't confirm the booking id exists at all
        # if it isn't the caller's.
        booking = get_object_or_404(
            Booking, pk=pk, member=request.user.member_profile)

        today = gym_today(request.user.gym)
        if booking.date < today:
            raise ValidationError(
                {"detail": "This booking already happened and can't be cancelled."})

        if booking.canceled_at is None:
            booking.canceled_at = timezone.now()
            booking.save(update_fields=["canceled_at", "updated_at"])

        return Response(BookingSerializer(booking).data, status=status.HTTP_200_OK)


class MemberViewSet(GymScopedViewSet):
    queryset = Member.objects.all()
    search_fields = ["first_name", "last_name", "phone", "member_code"]
    ordering_fields = ["first_name", "last_name", "created_at"]

    def get_serializer_class(self):
        if self.action in ("create", "update", "partial_update"):
            return MemberWriteSerializer
        return MemberSerializer

    def get_queryset(self):
        qs = Member.objects.filter(gym=self.gym).visible().with_status(self.today)
        mtype = self.request.query_params.get("type")
        if mtype == "prospect":
            qs = qs.prospects()
        elif mtype == "member":
            qs = qs.members()
        status_filter = self.request.query_params.get("status")
        if status_filter:
            qs = qs.filter(membership_status=status_filter)
        return qs.select_related("home_location")

    def create(self, request, *args, **kwargs):
        try:
            return super().create(request, *args, **kwargs)
        except IntegrityError:
            raise ValidationError({"id": "A member with this id already exists."})

    def destroy(self, request, *args, **kwargs):
        raise MethodNotAllowed("DELETE", detail="Use POST /members/{id}/archive/ instead.")

    @action(detail=True, methods=["get"])
    def memberships(self, request, pk=None):
        member = self.get_object()
        qs = member.memberships.all()
        return Response(MembershipSerializer(qs, many=True).data)

    @action(detail=True, methods=["post"])
    def renew(self, request, pk=None):
        member = self.get_object()
        plan_id = request.data.get("plan_id")
        if not plan_id:
            raise ValidationError({"plan_id": "This field is required."})
        try:
            plan = MembershipPlan.objects.get(id=plan_id, gym=self.gym, is_active=True)
        except (MembershipPlan.DoesNotExist, ValueError, TypeError):
            raise ValidationError({"plan_id": "Plan not found for your gym."})
        ms = Membership.renew(member, plan, self.today, created_by=request.user)
        return Response(MembershipSerializer(ms).data, status=status.HTTP_201_CREATED)

    @action(detail=False, methods=["get"], url_path="expiring")
    def expiring(self, request):
        """
        Phase 5 A2 — the renewal worklist. Built directly on top of
        get_queryset(), which already does .visible().with_status(self.today)
        — the 7-day "expiring" rule and the visibility rule both live
        there and only there; this adds the two fixed conditions A2
        specifies (member type, expiring status), the ordering, and the
        latest-reminder-per-current-membership annotation.
        """
        latest_membership = (
            Membership.objects
            .filter(member=OuterRef("pk"), canceled_at__isnull=True)
            .order_by("-end_date", "-start_date", "-id")
        )
        latest_reminder = (
            RenewalReminder.objects
            .filter(membership_id=OuterRef("current_membership_id"))
            .order_by("-contacted_at", "-id")
        )
        qs = (
            self.get_queryset()
            .members()
            .filter(membership_status="expiring")
            .annotate(
                current_membership_id=Subquery(latest_membership.values("id")[:1]),
            )
            .annotate(
                reminder_contacted_at=Subquery(
                    latest_reminder.values("contacted_at")[:1]
                ),
                reminder_contacted_by_name=Subquery(
                    latest_reminder.values("contacted_by__full_name")[:1]
                ),
            )
            .order_by("current_end_date", "id")
        )
        serializer = ExpiringMemberSerializer(
            qs, many=True, context={"today": self.today}
        )
        return Response(serializer.data)

    @action(detail=True, methods=["post"], url_path="remind")
    def remind(self, request, pk=None):
        """
        Phase 5 A3 — marks a member as contacted about their upcoming
        renewal. One message for two different causes (no current
        membership, or a current membership outside the expiring
        window) — same shape as A9's deliberate collisions elsewhere:
        the caller doesn't need to tell them apart, both just mean
        "not applicable right now". Re-runs with_status(self.today)
        rather than re-deriving the window in Python, for the same
        reason expiring() reuses get_queryset() — one rule, one place.

        current_membership_id is annotated onto this SAME query rather
        than resolved separately via member.current_membership — a
        renewal landing between two separate resolutions of "the
        current membership" could otherwise attach the reminder to a
        different membership than the one membership_status was
        actually validated against, which is exactly the row A1's
        keying decision depends on getting right.
        """
        member = self.get_object()
        latest_membership = (
            Membership.objects
            .filter(member=OuterRef("pk"), canceled_at__isnull=True)
            .order_by("-end_date", "-start_date", "-id")
        )
        annotated = (
            Member.objects.filter(pk=member.pk, gym=self.gym)
            .with_status(self.today)
            .annotate(
                current_membership_id=Subquery(latest_membership.values("id")[:1]),
            )
            .first()
        )
        if annotated is None or annotated.membership_status != "expiring":
            raise ValidationError(
                {"detail": "This member isn't in the renewal window."}
            )

        s = RenewalReminderSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        try:
            # Savepoint around the write, same reason MemberWriteSerializer's
            # claim_code retry loop uses one: a caught IntegrityError still
            # leaves the outer (per-request) transaction aborted at the
            # database level unless the failing statement ran inside its
            # own atomic block, whose rollback-on-exception is what
            # actually clears that state.
            with transaction.atomic():
                s.save(
                    gym=self.gym,
                    member=member,
                    membership_id=annotated.current_membership_id,
                    contacted_at=timezone.now(),
                    contacted_by=request.user,
                )
        except IntegrityError:
            raise ValidationError(
                {"id": "A renewal reminder with this id already exists."}
            )
        return Response(s.data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"], permission_classes=[IsGymStaff, IsOwner])
    def archive(self, request, pk=None):
        member = self.get_object()
        member.archived_at = timezone.now()
        member.archived_by = request.user
        member.save()
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["post"], url_path="claim-code")
    def claim_code(self, request, pk=None):
        member = self.get_object()
        if member.user_id is not None:
            raise ValidationError(
                {"detail": "This member's account is already claimed."}
            )

        member = None
        code = None
        for _ in range(3):
            candidate_code = generate_claim_code()
            expires_at = timezone.now() + timedelta(days=30)
            member = self.get_object()
            member.claim_code = candidate_code
            member.claim_code_expires_at = expires_at
            try:
                member.save(update_fields=["claim_code", "claim_code_expires_at"])
                code = candidate_code
                break
            except IntegrityError:
                continue
        if code is None:
            raise ValidationError(
                {"detail": "Could not generate a unique claim code. Try again."}
            )

        return Response({
            "claim_code": member.claim_code,
            "expires_at": member.claim_code_expires_at,
        })

    @action(detail=True, methods=["post"], url_path="qr-secret/reset",
            permission_classes=[IsGymStaff, IsOwner])
    def qr_secret_reset(self, request, pk=None):
        """
        For a lost phone, or a member who shared their card. Rotates the
        secret and clears qr_last_step — step numbers from the old
        secret carry no meaning against a new one, so an old step
        surviving here would either falsely block the member's first
        real code or (if a step number happened to be smaller) do
        nothing at all. No response body: the raw secret is nobody's
        business but the member's own app, which picks up the new one
        next time it calls GET /me/qr-secret/ (B4 — the owner tells the
        member to tap Refresh card in Settings).
        """
        member = self.get_object()
        member.qr_secret = qr_lib.generate_secret()
        member.qr_last_step = None
        member.save(update_fields=["qr_secret", "qr_last_step", "updated_at"])
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["post"], url_path="reset-password",
            permission_classes=[IsGymStaff])
    def reset_password(self, request, pk=None):
        """
        Front-desk equivalent of "forgot password" — there's no email
        flow, so staff verify the member in person and hand them a new
        temp password to read back. Open to plain staff as well as the
        owner (unlike archive/qr_secret_reset): this is the everyday
        front-desk case, not an owner-only administrative action.

        The temp password is returned in the response body ONLY — never
        logged, never persisted anywhere but the hashed value on the
        user. must_change_password forces the existing set-password
        flow on the member's next login, same as a new staff account.
        """
        member = self.get_object()
        if member.user_id is None:
            raise ValidationError(
                {"detail": "This member hasn't set up app access yet."}
            )

        temp_password = generate_temp_password()
        user = member.user
        user.set_password(temp_password)
        user.must_change_password = True
        user.save(update_fields=["password", "must_change_password"])

        LogEntry.objects.log_actions(
            user_id=request.user.pk,
            queryset=Member.objects.filter(pk=member.pk),
            action_flag=CHANGE,
            change_message="Reset app password (front-desk reset)",
        )

        return Response({"temp_password": temp_password})

ANALYTICS_RANGE_DAYS = {"1D": 1, "1W": 7, "1M": 30, "3M": 90}


def _money_str(value):
    return str((value or Decimal("0")).quantize(Decimal("0.01")))


def _revenue_for_window(gym, tz, start_dt, end_dt):
    """
    Sums the four revenue sources over an explicit UTC range. Same
    day-range pattern as CheckInViewSet, just parameterized to an
    arbitrary window instead of one gym-local day.
    """
    membership_total = Membership.objects.filter(
        gym=gym, created_at__gte=start_dt, created_at__lt=end_dt
    ).aggregate(total=Coalesce(Sum("price_paid"), Decimal("0"),
                               output_field=DecimalField()))["total"]

    checkin_total = CheckIn.objects.filter(
        gym=gym, visit_type=CheckIn.WALKIN, voided_at__isnull=True,
        checked_in_at__gte=start_dt, checked_in_at__lt=end_dt,
    ).aggregate(total=Coalesce(Sum("amount_charged"), Decimal("0"),
                               output_field=DecimalField()))["total"]

    event_total = EventRegistration.objects.filter(
        gym=gym, payment_status=EventRegistration.PAID,
        paid_at__gte=start_dt, paid_at__lt=end_dt,
    ).aggregate(total=Coalesce(Sum("amount_due"), Decimal("0"),
                               output_field=DecimalField()))["total"]

    # Voided sales never happened, same rule as voided check-ins.
    sale_total = Sale.objects.filter(
        gym=gym, voided_at__isnull=True,
        sold_at__gte=start_dt, sold_at__lt=end_dt,
    ).aggregate(total=Coalesce(Sum("total_amount"), Decimal("0"),
                               output_field=DecimalField()))["total"]

    return membership_total, checkin_total, event_total, sale_total


def _daily_series(gym, tz, start_dt, end_dt, start_date, end_date):
    """
    One point per gym-local calendar day across the whole range, days with
    no revenue included as zero so the chart doesn't skip gaps. Filters by
    the UTC range FIRST, then buckets with TruncDate(tzinfo=tz) — bucketing
    without the range filter first would scan every row ever created.
    """
    totals = {}

    def _accumulate(qs, date_field, amount_field, extra_filter):
        rows = (
            qs.filter(gym=gym, **extra_filter,
                     **{f"{date_field}__gte": start_dt, f"{date_field}__lt": end_dt})
            .annotate(day=TruncDate(date_field, tzinfo=tz))
            .values("day")
            .annotate(total=Sum(amount_field))
        )
        for row in rows:
            totals[row["day"]] = totals.get(row["day"], Decimal("0")) + (row["total"] or Decimal("0"))

    _accumulate(Membership.objects, "created_at", "price_paid", {})
    _accumulate(CheckIn.objects, "checked_in_at", "amount_charged",
               {"visit_type": CheckIn.WALKIN, "voided_at__isnull": True})
    _accumulate(EventRegistration.objects, "paid_at", "amount_due",
               {"payment_status": EventRegistration.PAID})
    _accumulate(Sale.objects, "sold_at", "total_amount", {"voided_at__isnull": True})
    series = []
    day = start_date
    while day <= end_date:
        series.append({"date": day.isoformat(), "amount": _money_str(totals.get(day))})
        day += timedelta(days=1)
    return series


def _hourly_series(gym, tz, start_dt, end_dt, now_local):
    """
    1D only: one point per gym-local hour, from midnight through the
    current in-progress hour — the intraday equivalent of
    _daily_series's "through today, never into the future" rule.
    Same four revenue sources and the same start_dt/end_dt query
    window as the rest of the 1D response, just bucketed by TruncHour
    instead of TruncDate.
    """
    totals = {}

    def _accumulate(qs, date_field, amount_field, extra_filter):
        rows = (
            qs.filter(gym=gym, **extra_filter,
                     **{f"{date_field}__gte": start_dt, f"{date_field}__lt": end_dt})
            .annotate(hour=TruncHour(date_field, tzinfo=tz))
            .values("hour")
            .annotate(total=Sum(amount_field))
        )
        for row in rows:
            totals[row["hour"]] = totals.get(row["hour"], Decimal("0")) + (row["total"] or Decimal("0"))

    _accumulate(Membership.objects, "created_at", "price_paid", {})
    _accumulate(CheckIn.objects, "checked_in_at", "amount_charged",
               {"visit_type": CheckIn.WALKIN, "voided_at__isnull": True})
    _accumulate(EventRegistration.objects, "paid_at", "amount_due",
               {"payment_status": EventRegistration.PAID})
    _accumulate(Sale.objects, "sold_at", "total_amount", {"voided_at__isnull": True})

    series = []
    hour = start_dt.astimezone(tz).replace(minute=0, second=0, microsecond=0)
    last_hour = now_local.replace(minute=0, second=0, microsecond=0)
    while hour <= last_hour:
        series.append({"date": hour.isoformat(), "amount": _money_str(totals.get(hour))})
        hour += timedelta(hours=1)
    return series


class AnalyticsView(APIView):
    """
    Owner-only revenue + check-in snapshot for the Reports/Home cards.
    No new Sale table — aggregates existing Membership/CheckIn/
    EventRegistration rows, same as the rest of the analytics plan.
    """
    permission_classes = [IsGymStaff, IsOwner, SubscriptionActive]

    def get(self, request):
        gym = request.user.gym
        range_key = request.query_params.get("range", "1M")
        if range_key not in ANALYTICS_RANGE_DAYS:
            raise ValidationError({"range": "Must be one of 1D, 1W, 1M, 3M."})

        n = ANALYTICS_RANGE_DAYS[range_key]
        tz = ZoneInfo(gym.timezone)
        today = gym_today(gym)

        start_date = today - timedelta(days=n - 1)
        start_dt = datetime.combine(start_date, time.min, tzinfo=tz)
        end_dt = datetime.combine(today + timedelta(days=1), time.min, tzinfo=tz)

        prev_end_date = start_date - timedelta(days=1)
        prev_start_date = prev_end_date - timedelta(days=n - 1)
        prev_start_dt = datetime.combine(prev_start_date, time.min, tzinfo=tz)
        prev_end_dt = start_dt  # previous window ends exactly where this one starts

        m_total, c_total, e_total, s_total = _revenue_for_window(gym, tz, start_dt, end_dt)
        total = m_total + c_total + e_total + s_total

        prev_m, prev_c, prev_e, prev_s = _revenue_for_window(
            gym, tz, prev_start_dt, prev_end_dt)
        prev_total = prev_m + prev_c + prev_e + prev_s
        change_pct = None if prev_total == 0 else round(
            float((total - prev_total) / prev_total * 100), 1)

        def _pct(part):
            return 0.0 if total == 0 else round(float(part / total * 100), 1)

        breakdown = [
            {"category": "membership", "label": "Memberships",
             "amount": _money_str(m_total), "pct": _pct(m_total)},
            {"category": "day_pass", "label": "Day Passes",
             "amount": _money_str(c_total), "pct": _pct(c_total)},
            {"category": "event", "label": "Events / Others",
             "amount": _money_str(e_total), "pct": _pct(e_total)},
            {"category": "merch", "label": "Merch & Drinks",
             "amount": _money_str(s_total), "pct": _pct(s_total)},
        ]

        if range_key == "1D":
            now_local = timezone.now().astimezone(tz)
            series = _hourly_series(gym, tz, start_dt, end_dt, now_local)
        else:
            series = _daily_series(gym, tz, start_dt, end_dt, start_date, today)

        # --- Part A: check-in badge, always today vs yesterday --------
        # Deliberately does NOT vary with `range` — see the comment on
        # the frontend spec doc for why: a bare percentage next to a
        # range-toggled card invites the wrong reading. This is always
        # "vs yesterday" regardless of what range the sales card shows.
        gym_today_date = today
        gym_yesterday_date = today - timedelta(days=1)

        def _checkin_count(day):
            day_start = datetime.combine(day, time.min, tzinfo=tz)
            day_end = day_start + timedelta(days=1)
            return CheckIn.objects.filter(
                gym=gym, voided_at__isnull=True,
                checked_in_at__gte=day_start, checked_in_at__lt=day_end,
            ).count()

        ci_today = _checkin_count(gym_today_date)
        ci_yesterday = _checkin_count(gym_yesterday_date)
        ci_change_pct = None if ci_yesterday == 0 else round(
            (ci_today - ci_yesterday) / ci_yesterday * 100, 1)

        return Response({
            "range": range_key,
            "revenue": {
                "total": _money_str(total),
                "change_pct": change_pct,
                "series": series,
                "breakdown": breakdown,
            },
            "check_ins": {
                "today": ci_today,
                "yesterday": ci_yesterday,
                "change_pct": ci_change_pct,
            },
        })


def _fmt_time(dt, tz):
    # No platform-specific strftime flags ("%-I"/"%#I") — this runs the
    # same on Windows dev machines and Linux deploys.
    local = dt.astimezone(tz)
    hour = local.hour % 12 or 12
    period = "AM" if local.hour < 12 else "PM"
    return f"{hour}:{local.minute:02d} {period}"


def _activity_rows_raw(gym, tz, start_dt, end_dt):
    """
    Shared by ActivityLogView, SalesHistoryView's day-grouped 1D/1W
    response, and (in a later phase) 1M's weekly rollups — merges
    walk-in check-ins, membership purchases/renewals, and POS sales
    over the given window into one newest-first list of {type, title,
    subtitle, amount, at} rows. `amount` is kept as Decimal and `at`
    as the raw datetime so callers can group/sum precisely; format and
    strip them at the point each view builds its own response shape.
    """
    activities = []

    walkins = CheckIn.objects.filter(
        gym=gym, visit_type=CheckIn.WALKIN, voided_at__isnull=True,
        checked_in_at__gte=start_dt, checked_in_at__lt=end_dt,
    )
    for c in walkins:
        activities.append({
            "type": "walk_in",
            "title": c.visitor_name or "Walk-in",
            "subtitle": f"Walk-in Pass · {_fmt_time(c.checked_in_at, tz)}",
            "amount": c.amount_charged or Decimal("0"),
            "at": c.checked_in_at,
        })

    memberships = Membership.objects.filter(
        gym=gym, created_at__gte=start_dt, created_at__lt=end_dt,
    ).select_related("member")
    for m in memberships:
        kind = "Renewal" if m.previous_id else "New Membership"
        duration = (
            f"{m.duration_value}-{m.duration_unit.title()}"
            if m.duration_value and m.duration_unit else ""
        )
        subtitle_label = f"{duration} {kind}".strip() if duration else kind
        activities.append({
            "type": "member",
            "title": m.member.full_name,
            "subtitle": f"{subtitle_label} · {_fmt_time(m.created_at, tz)}",
            "amount": m.price_paid or Decimal("0"),
            "at": m.created_at,
        })

    sales = Sale.objects.filter(
        gym=gym, voided_at__isnull=True,
        sold_at__gte=start_dt, sold_at__lt=end_dt,
    ).prefetch_related("items")
    for s in sales:
        items = list(s.items.all())
        if items:
            title = items[0].product_name
            if len(items) > 1:
                title = f"{title} +{len(items) - 1} more"
        else:
            title = "Retail sale"
        activities.append({
            "type": "retail",
            "title": title,
            "subtitle": f"Retail POS · {_fmt_time(s.sold_at, tz)}",
            "amount": s.total_amount or Decimal("0"),
            "at": s.sold_at,
        })

    activities.sort(key=lambda a: a["at"], reverse=True)
    return activities


def _activity_rows(gym, tz, start_dt, end_dt):
    """
    ActivityLogView's shape: {type, title, subtitle, amount} with
    amount formatted as a string and no `at` field.
    """
    rows = _activity_rows_raw(gym, tz, start_dt, end_dt)
    return [
        {
            "type": r["type"],
            "title": r["title"],
            "subtitle": r["subtitle"],
            "amount": _money_str(r["amount"]),
        }
        for r in rows
    ]


def _grouped_sales_history(gym, tz, start_dt, end_dt):
    """
    SalesHistoryView's 1D/1W shape: transactions grouped by gym-local
    calendar day, newest day first (each day's own transactions stay
    newest-first too, since the input is already sorted that way and
    grouping preserves order). No pagination -- a single day or week's
    worth of transactions is small enough to return in full, and the
    reference design shows a complete list ending in "End of ...
    records", not a "load more".
    """
    rows = _activity_rows_raw(gym, tz, start_dt, end_dt)

    period_total = Decimal("0")
    groups_by_date = {}
    order = []
    for r in rows:
        day = r["at"].astimezone(tz).date()
        if day not in groups_by_date:
            groups_by_date[day] = {"total": Decimal("0"), "transactions": []}
            order.append(day)
        groups_by_date[day]["total"] += r["amount"]
        groups_by_date[day]["transactions"].append({
            "type": r["type"],
            "title": r["title"],
            "subtitle": r["subtitle"],
            "amount": _money_str(r["amount"]),
        })
        period_total += r["amount"]

    groups = [
        {
            "date": day.isoformat(),
            "total": _money_str(groups_by_date[day]["total"]),
            "order_count": len(groups_by_date[day]["transactions"]),
            "transactions": groups_by_date[day]["transactions"],
        }
        for day in order
    ]

    return {
        "period": {
            "total": _money_str(period_total),
            "order_count": len(rows),
        },
        "groups": groups,
    }


_CATEGORY_KEY = {"member": "membership", "retail": "retail", "walk_in": "walk_ins"}


def _weekly_rollups(gym, tz, start_date, today):
    """
    SalesHistoryView's 1M shape: transactions bucketed into 7-day
    chunks counted from start_date -- same anchor the chart's own 1M
    bucketing uses. 30 isn't divisible by 7, so the newest bucket can
    be a short trailing partial week; that's expected, not a bug.

    Each bucket gets a total, order count, and a
    membership/retail/walk_ins amount breakdown, plus a status:
    - the newest bucket (the one that reaches `today`) is always
      "in_progress" -- more of today's transactions could still land
      before the day ends.
    - the highest-total bucket among the REST is "peak" -- an
      in-progress bucket hasn't finished accumulating yet, so it
      can't fairly win that comparison.
    - the oldest bucket is "opener" (no earlier bucket to diff
      against) unless it's also the peak, which wins.
    - everything else is "change" with change_pct vs. the previous
      (chronologically earlier) bucket's total; a zero-total previous
      bucket leaves change_pct null rather than dividing by zero.
    """
    start_dt = datetime.combine(start_date, time.min, tzinfo=tz)
    end_dt = datetime.combine(today + timedelta(days=1), time.min, tzinfo=tz)
    rows = _activity_rows_raw(gym, tz, start_dt, end_dt)

    bucket_bounds = []
    d = start_date
    while d <= today:
        bucket_end = min(d + timedelta(days=6), today)
        bucket_bounds.append((d, bucket_end))
        d = bucket_end + timedelta(days=1)

    buckets = [
        {
            "start_date": b_start, "end_date": b_end,
            "total": Decimal("0"), "order_count": 0,
            "categories": {"membership": Decimal("0"), "retail": Decimal("0"),
                          "walk_ins": Decimal("0")},
        }
        for b_start, b_end in bucket_bounds
    ]

    for r in rows:
        day = r["at"].astimezone(tz).date()
        for bucket in buckets:
            if bucket["start_date"] <= day <= bucket["end_date"]:
                bucket["total"] += r["amount"]
                bucket["order_count"] += 1
                bucket["categories"][_CATEGORY_KEY[r["type"]]] += r["amount"]
                break

    # The loop above always stops once bucket_end reaches `today`, so
    # the last bucket built is always the one containing it.
    in_progress_idx = len(buckets) - 1
    completed_indexes = [i for i in range(len(buckets)) if i != in_progress_idx]
    peak_idx = (
        max(completed_indexes, key=lambda i: buckets[i]["total"])
        if completed_indexes else None
    )

    result = []
    for i, b in enumerate(buckets):
        if i == in_progress_idx:
            status, change_pct = "in_progress", None
        elif i == peak_idx:
            status, change_pct = "peak", None
        elif i == 0:
            status, change_pct = "opener", None
        else:
            prev_total = buckets[i - 1]["total"]
            status = "change"
            change_pct = (
                None if prev_total == 0
                else round(float((b["total"] - prev_total) / prev_total * 100), 1)
            )
        result.append({
            "start_date": b["start_date"].isoformat(),
            "end_date": b["end_date"].isoformat(),
            "total": _money_str(b["total"]),
            "order_count": b["order_count"],
            "categories": {k: _money_str(v) for k, v in b["categories"].items()},
            "status": status,
            "change_pct": change_pct,
        })

    result.reverse()  # newest first
    return {"weeks": result}


class ActivityLogView(APIView):
    """
    Owner-only "Today's Activity Log" feed for the dashboard — merges
    today's walk-in check-ins, membership purchases/renewals, and POS
    sales into one newest-first list. Read-only: doesn't touch any of
    the three sources' own write paths, just reads and re-shapes them.
    """
    permission_classes = [IsGymStaff, IsOwner, SubscriptionActive]

    def get(self, request):
        gym = request.user.gym
        tz = ZoneInfo(gym.timezone)
        today = gym_today(gym)
        start_dt = datetime.combine(today, time.min, tzinfo=tz)
        end_dt = start_dt + timedelta(days=1)

        try:
            limit = int(request.query_params.get("limit", 5))
        except ValueError:
            raise ValidationError({"limit": "Must be an integer."})
        limit = max(1, min(limit, 20))

        activities = _activity_rows(gym, tz, start_dt, end_dt)
        return Response({"activities": activities[:limit]})


class SalesHistoryView(APIView):
    """
    Owner-only transaction history for the Sales History screen. Same
    three sources as ActivityLogView, scoped to a full 1D/1W/1M window
    like AnalyticsView instead of just today. Response shape varies by
    range -- same precedent as AnalyticsView's own `series`, which
    already means something different per range:

    - 1D/1W: grouped by gym-local calendar day, {period, groups}. Not
      paginated -- a day or week's worth of transactions is small
      enough to return in full (see _grouped_sales_history).
    - 1M: weekly rollup cards, {weeks: [...]} -- see _weekly_rollups.
      Also not paginated: at most ~5 buckets for a 30-day window.
    """
    permission_classes = [IsGymStaff, IsOwner, SubscriptionActive]

    def get(self, request):
        gym = request.user.gym
        range_key = request.query_params.get("range", "1D")
        if range_key not in ("1D", "1W", "1M"):
            raise ValidationError({"range": "Must be one of 1D, 1W, 1M."})

        n = ANALYTICS_RANGE_DAYS[range_key]
        tz = ZoneInfo(gym.timezone)
        today = gym_today(gym)
        start_date = today - timedelta(days=n - 1)

        if range_key == "1M":
            return Response(_weekly_rollups(gym, tz, start_date, today))

        start_dt = datetime.combine(start_date, time.min, tzinfo=tz)
        end_dt = datetime.combine(today + timedelta(days=1), time.min, tzinfo=tz)
        return Response(_grouped_sales_history(gym, tz, start_dt, end_dt))


class CheckInViewSet(GymScopedViewSet):
    queryset = CheckIn.objects.all()
    search_fields = ["member__first_name", "member__last_name",
                     "member__phone", "member__member_code", "visitor_name"]

    def get_serializer_class(self):
        return CheckInWriteSerializer if self.action == "create" else CheckInSerializer

    def get_queryset(self):
        qs = CheckIn.objects.filter(gym=self.gym).select_related("member", "location")

        date_str = self.request.query_params.get("date")
        if date_str:
            try:
                day = datetime.strptime(date_str, "%Y-%m-%d").date()
            except ValueError:
                raise ValidationError({"date": "Use YYYY-MM-DD."})
        else:
            day = self.today

        # Explicit gym-local day -> UTC range. Never filter with __date directly;
        # that uses settings.TIME_ZONE (UTC), not the gym's timezone, and would
        # put a 7am Manila check-in on yesterday's list.
        tz = ZoneInfo(self.gym.timezone)
        start = datetime.combine(day, time.min, tzinfo=tz)
        end = start + timedelta(days=1)
        return qs.filter(checked_in_at__gte=start, checked_in_at__lt=end)

    def create(self, request, *args, **kwargs):
        try:
            return super().create(request, *args, **kwargs)
        except IntegrityError:
            raise ValidationError({"id": "A check-in with this id already exists."})

    def destroy(self, request, *args, **kwargs):
        raise MethodNotAllowed("DELETE", detail="Use POST /check-ins/{id}/void/ instead.")

    @action(detail=True, methods=["post"])
    def void(self, request, pk=None):
        checkin = self.get_object()
        checkin.voided_at = timezone.now()
        checkin.voided_by = request.user
        checkin.save(update_fields=["voided_at", "voided_by"])
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=False, methods=["post"], url_path="verify-qr")
    def verify_qr(self, request):
        """
        Verifies a scanned QR payload WITHOUT creating a check-in — staff
        confirms on the sheet, then the app calls the existing check-in
        create endpoint. One check-in code path, not two.

        Every failure below is intentionally the exact wording from Phase
        3b's A9, including two deliberate collisions: a nonexistent
        member and another gym's member return the identical message (the
        lookup below can't tell them apart, by construction — it never
        even sees whether a matching id exists elsewhere), and an
        unclaimed member (empty qr_secret) returns the identical message
        as an expired code, so this endpoint never confirms which one it
        was.
        """
        s = VerifyQrSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        parts = s.validated_data["payload"].split("|")

        if parts[0] == qr_lib.CLAIM_PREFIX:
            raise ValidationError(
                {"detail": "That's an account setup code, not a membership card"})

        if len(parts) != 3 or parts[0] != qr_lib.CHECKIN_PREFIX:
            raise ValidationError({"detail": "Couldn't read that code"})

        _, member_id_str, code = parts
        try:
            member_id = uuid.UUID(member_id_str)
        except ValueError:
            raise ValidationError({"detail": "Couldn't read that code"})

        # Gym-scoped by construction — a UUID that doesn't exist at all
        # and a UUID that belongs to a different gym both just miss here,
        # with nothing downstream able to tell the two apart.
        member = Member.objects.filter(pk=member_id, gym=self.gym).first()
        if member is None:
            raise ValidationError({"detail": "This card isn't from your gym"})

        if member.archived_at is not None:
            raise ValidationError(
                {"detail": "This membership is no longer active at your gym"})

        # A3: reject an empty secret BEFORE computing anything — HMAC
        # with an empty key is still a valid, deterministic code, and an
        # unclaimed member must never have a working one.
        expired_message = "That code has expired — ask them to reopen their card"
        if not member.qr_secret:
            raise ValidationError({"detail": expired_message})

        now_step = qr_lib.time_step(timezone.now().timestamp())
        matched_step = None
        for candidate_step in qr_lib.accepted_steps(now_step):
            expected_code = qr_lib.compute_code(member.qr_secret, candidate_step)
            if hmac.compare_digest(expected_code, code):
                matched_step = candidate_step
                break

        if matched_step is None:
            raise ValidationError({"detail": expired_message})

        # A5 replay protection, race-safe: a plain read-then-save lets two
        # concurrent requests both read qr_last_step before either writes
        # it, so both pass the check and both succeed. A single
        # conditional UPDATE makes the check and the write one atomic
        # operation — the second request's UPDATE matches zero rows once
        # the first has already advanced qr_last_step, the same way
        # create_sale()'s stock decrement can't oversell the last unit.
        updated = Member.objects.filter(pk=member.pk).filter(
            Q(qr_last_step__isnull=True) | Q(qr_last_step__lt=matched_step)
        ).update(qr_last_step=matched_step)

        if updated == 0:
            raise ValidationError({"detail": "That code has already been used"})

        annotated = (Member.objects.filter(pk=member.pk, gym=self.gym)
                     .with_status(self.today).first())
        days_remaining = None
        if annotated.current_end_date:
            days_remaining = (annotated.current_end_date - self.today).days

        # "Already checked in today" via gym_today's explicit UTC range —
        # never __date on checked_in_at, same standing rule as everywhere
        # else this endpoint's own queryset applies it.
        tz = ZoneInfo(self.gym.timezone)
        day_start = datetime.combine(self.today, time.min, tzinfo=tz)
        day_end = day_start + timedelta(days=1)
        already_checked_in_today = CheckIn.objects.filter(
            gym=self.gym, member=member, visit_type=CheckIn.MEMBER,
            voided_at__isnull=True,
            checked_in_at__gte=day_start, checked_in_at__lt=day_end,
        ).exists()

        return Response({
            "id": str(member.id),
            "full_name": member.full_name,
            "member_code": member.member_code,
            "membership_status": annotated.membership_status,
            "current_end_date": annotated.current_end_date,
            "days_remaining": days_remaining,
            "already_checked_in_today": already_checked_in_today,
        })


class SignupView(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_scope = "signup"

    def post(self, request):
        s = SignupSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        user = s.save()
        refresh = RefreshToken.for_user(user)
        return Response({
            "access": str(refresh.access_token),
            "refresh": str(refresh),
            "user": MeSerializer(user).data,
        }, status=status.HTTP_201_CREATED)


class ClaimAccountView(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_scope = "claim"

    def post(self, request):
        s = ClaimAccountSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        user = s.save()
        refresh = RefreshToken.for_user(user)
        return Response({
            "access": str(refresh.access_token),
            "refresh": str(refresh),
            "user": MeSerializer(user).data,
        }, status=status.HTTP_201_CREATED)


class ChangePasswordView(APIView):
    def post(self, request):
        s = ChangePasswordSerializer(data=request.data, context={"request": request})
        s.is_valid(raise_exception=True)
        user = request.user
        user.set_password(s.validated_data["new_password"])
        user.must_change_password = False
        user.save(update_fields=["password", "must_change_password"])
        return Response(status=status.HTTP_204_NO_CONTENT)

from .serializers import LogoutSerializer


class LogoutView(APIView):
    """
    Blacklists the submitted refresh token. Always returns 204, even on
    a bad or already-blacklisted token — see LogoutSerializer's
    docstring for why. Deliberately open (no IsAuthenticated) since the
    caller's access token may already be expired by the time they're
    logging out; the refresh token in the body is what's being acted
    on, not the caller's current auth state.
    """
    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request):
        s = LogoutSerializer(data=request.data)
        if s.is_valid():
            s.save()
        return Response(status=status.HTTP_204_NO_CONTENT)

    
class StaffViewSet(viewsets.ModelViewSet):
    permission_classes = [IsGymStaff, IsOwner, SubscriptionActive]
    http_method_names = ["get", "post", "patch", "head", "options"]

    def get_queryset(self):
        return (StaffProfile.objects.filter(gym=self.request.user.gym)
                .select_related("user", "default_location"))

    def get_serializer_class(self):
        return StaffCreateSerializer if self.action == "create" else StaffMemberSerializer

    def get_serializer_context(self):
        ctx = super().get_serializer_context()
        ctx["gym"] = self.request.user.gym
        return ctx

    def create(self, request, *args, **kwargs):
        s = self.get_serializer(data=request.data)
        s.is_valid(raise_exception=True)
        profile = s.save()
        return Response(StaffMemberSerializer(profile).data,
                        status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"])
    def deactivate(self, request, pk=None):
        profile = self.get_object()
        if profile.user_id == request.user.id:
            raise ValidationError({"detail": "You cannot deactivate your own account."})
        profile.user.is_active = False
        profile.user.save(update_fields=["is_active"])
        return Response(status=status.HTTP_204_NO_CONTENT)


class MeSummaryView(APIView):
    """
    One call that fills the member home screen. Every query here starts
    from request.user.member_profile — no member id ever comes from the
    client, which is what makes this endpoint safe by construction.
    """
    permission_classes = [IsGymMember]

    def get(self, request):
        member_profile = request.user.member_profile
        gym = request.user.gym
        today = gym_today(gym)

        # Going through with_status() rather than computing status by hand
        # is the point: the member's status must be derived by the exact
        # same code path as the owner's members list, or the member can
        # see "expired" on a day the gym sees "active".
        member = (
            Member.objects
            .filter(pk=member_profile.pk)
            .with_status(today)
            .first()
        )

        # Gym-local calendar month -> explicit UTC range, same pattern
        # CheckInViewSet.get_queryset uses for a day. Never __month or
        # __date on a datetime column: settings.TIME_ZONE is UTC, the gym
        # is Asia/Manila, and those lookups would silently use the wrong
        # day boundaries.
        tz = ZoneInfo(gym.timezone)
        month_start = today.replace(day=1)
        if month_start.month == 12:
            next_month_start = month_start.replace(year=month_start.year + 1, month=1)
        else:
            next_month_start = month_start.replace(month=month_start.month + 1)
        range_start = datetime.combine(month_start, time.min, tzinfo=tz)
        range_end = datetime.combine(next_month_start, time.min, tzinfo=tz)

        # Voided check-ins excluded from both the count and last_check_in_at
        # — a void means it didn't happen.
        check_ins_this_month = CheckIn.objects.filter(
            member=member,
            voided_at__isnull=True,
            checked_in_at__gte=range_start,
            checked_in_at__lt=range_end,
        ).count()

        last_check_in = (
            CheckIn.objects
            .filter(member=member, voided_at__isnull=True)
            .order_by("-checked_in_at")
            .first()
        )

        # Attached as plain attributes so MeMemberSummarySerializer's
        # plain (non-source) fields can read them directly.
        member.check_ins_this_month = check_ins_this_month
        member.last_check_in_at = last_check_in.checked_in_at if last_check_in else None

        serializer = MeMemberSummarySerializer(member, context={"today": today})
        return Response(serializer.data)


class MeMembershipView(ListAPIView):
    """
    The member's own membership history, newest first — ordering comes
    from Membership.Meta.ordering (-end_date), no need to repeat it here.
    """
    permission_classes = [IsGymMember]
    serializer_class = MembershipSerializer

    def get_queryset(self):
        return Membership.objects.filter(member=self.request.user.member_profile)


class MeCheckInsView(ListAPIView):
    """
    The member's own attendance, newest first. Voided rows are excluded
    entirely — the staff list strikes them through because staff need to
    see a correction happened; a member has no use for that, it just
    raises "why does this say I came in with a line through it?"
    """
    permission_classes = [IsGymMember]
    serializer_class = MeCheckInSerializer

    def get_queryset(self):
        return (
            CheckIn.objects
            .filter(member=self.request.user.member_profile, voided_at__isnull=True)
            .order_by("-checked_in_at")
        )

class MeQrSecretView(APIView):
    """
    Returns the calling member's own QR secret — never by id, always
    request.user.member_profile, so this can never be used to fetch
    anyone else's. Generates the secret lazily on first call (A4): a
    member who has never claimed their account never reaches this view
    at all (IsGymMember requires member_profile), so their qr_secret
    stays blank forever — which is what makes an unclaimed member's code
    unforgeable by construction, not by a permission check (see A3 in
    CheckInViewSet.verify_qr).
    """
    permission_classes = [IsGymMember]
    throttle_scope = "qr_secret"

    def get(self, request):
        member = request.user.member_profile
        if not member.qr_secret:
            member.qr_secret = qr_lib.generate_secret()
            member.save(update_fields=["qr_secret", "updated_at"])

        return Response({
            "secret": member.qr_secret,
            "server_time": timezone.now().timestamp(),
            "period": qr_lib.PERIOD_SECONDS,
            "digits": qr_lib.DIGITS,
        })


logger = logging.getLogger(__name__)


def _notify_announcement(announcement):
    """
    Runs off-thread (see AnnouncementViewSet.perform_create) so an FCM
    outage or slow multicast call can't delay the create response. Must
    never raise into the thread runner — there's no caller left to catch
    it — so the whole body is wrapped, matching the per-gym isolation
    pattern in send_daily_notifications.
    """
    try:
        member_users = list(
            User.objects.filter(
                member_profile__gym=announcement.gym,
                member_profile__archived_at__isnull=True,
                member_profile__member_type=Member.MEMBER,
            )
        )
        if not member_users:
            return

        title = announcement.title[:100]
        body = announcement.body[:150]

        send_to_users(
            member_users, title=title, body=body,
            data={"type": "announcement", "id": str(announcement.id)},
        )

        NotificationSend.objects.bulk_create(
            [
                NotificationSend(user=u, kind="announcement", subject_id=announcement.id)
                for u in member_users
            ],
            ignore_conflicts=True,
        )
    except Exception:
        logger.exception("Failed to send announcement notification for %s", announcement.id)


def _notify_out_of_stock(product):
    """
    Called right after the stock decrement that took `product` from >0 to
    exactly 0 (see create_sale and ProductViewSet.adjust), from inside the
    same select_for_update()-locked block, so this only ever runs once per
    genuine transition — never on a second sale attempted against a
    product already at zero.

    kind is suffixed with the transition's timestamp rather than left as
    a bare "out_of_stock", because subject_id is the product's id and
    doesn't change between transitions. A restock followed by another
    sale that re-empties the same product is a second, distinct event
    that must notify again; a fixed kind would collide with the first
    transition's NotificationSend row (same user/kind/subject_id) and
    silently suppress the second notification. The digest in
    send_daily_notifications solves the same problem the same way, with
    a day-suffixed kind instead of a timestamp-suffixed one.
    """
    try:
        recipients = list(User.objects.filter(staff_profile__gym=product.gym))
        if not recipients:
            return

        send_to_users(
            recipients,
            title="Out of stock",
            body=f"{product.name} is out of stock.",
            data={"type": "out_of_stock", "id": str(product.id)},
        )

        kind = f"out_of_stock_{timezone.now():%Y%m%d%H%M%S%f}"
        NotificationSend.objects.bulk_create(
            [
                NotificationSend(user=u, kind=kind, subject_id=product.id)
                for u in recipients
            ],
            ignore_conflicts=True,
        )
    except Exception:
        logger.exception("Failed to send out-of-stock notification for %s", product.id)


def with_like_state(qs, fk, user):
    """
    Annotates like_count and liked_by_me (read by LikeStateMixin) so a
    list is one query. Subqueries rather than a Count("likes") join: the
    Event queryset already joins registrations for registration_count, and
    a second join would multiply the rows each Count sees.
    """
    likes = Like.objects.filter(**{fk: OuterRef("pk")})
    return qs.annotate(
        like_count=Coalesce(
            Subquery(likes.order_by().values(fk).annotate(n=Count("pk")).values("n")[:1],
                     output_field=IntegerField()),
            0),
        liked_by_me=Exists(likes.filter(user=user)),
    )


class AnnouncementViewSet(GymScopedViewSet):
    queryset = Announcement.objects.all()
    serializer_class = AnnouncementSerializer
    permission_classes = [IsGymUser, IsGymStaffOrReadOnly]

    def get_queryset(self):
        return with_like_state(super().get_queryset(), "announcement",
                               self.request.user)

    def perform_create(self, serializer):
        announcement = serializer.save(gym=self.gym, created_by=self.request.user)
        threading.Thread(
            target=_notify_announcement, args=(announcement,), daemon=True,
        ).start()

@transaction.atomic
def create_sale(gym, items, user, member=None):
    """
    Each decrement is a single conditional UPDATE. Postgres evaluates the
    stock check and the write together, so two concurrent sales of the
    last unit can't both succeed — the second one matches zero rows and
    we roll the whole sale back. A read-then-write would let both through
    and drive stock negative.

    select_for_update() on the initial read additionally locks the row for
    the rest of this transaction, so the "prior quantity" read here and the
    decrement below are atomic as a pair — needed to detect the >0-to-0
    transition for the out-of-stock notification without a race where two
    concurrent sales both see stock_quantity == 1 and both believe they're
    the one hitting zero.
    """
    if not items:
        raise ValidationError({"items": "At least one item is required."})

    # Collapse duplicate product ids by summing quantities — otherwise the
    # same product listed twice gets two separate stock checks that could
    # each pass while the combined total exceeds stock.
    merged = {}
    order = []
    for line in items:
        pid = line["product_id"]
        qty = line["quantity"]
        if qty <= 0:
            raise ValidationError({"items": "Quantity must be greater than zero."})
        if pid not in merged:
            merged[pid] = 0
            order.append(pid)
        merged[pid] += qty

    sale_items = []
    total = Decimal("0.00")

    for pid in order:
        qty = merged[pid]
        try:
            product = Product.objects.select_for_update().get(
                pk=pid, gym=gym, is_active=True,
            )
        except (Product.DoesNotExist, ValueError, TypeError):
            # 404, not 403 — never confirms another gym's product id exists.
            raise Http404("Product not found.")

        prior_qty = product.stock_quantity
        updated = (Product.objects
                   .filter(pk=product.pk, stock_quantity__gte=qty)
                   .update(stock_quantity=F("stock_quantity") - qty))
        if updated == 0:
            raise ValidationError({
                "detail": f"Not enough stock for {product.name}. "
                          f"{product.stock_quantity} left."
            })

        if prior_qty > 0 and prior_qty - qty == 0:
            # Fires after commit, not here — the row lock from
            # select_for_update() is still held at this point, and the
            # FCM call shouldn't run while it's blocking other sales.
            transaction.on_commit(lambda p=product: _notify_out_of_stock(p))

        line_total = product.price * qty
        total += line_total
        sale_items.append(SaleItem(
            gym=gym, product=product, product_name=product.name,
            unit_price=product.price, quantity=qty, line_total=line_total,
        ))

    sale = Sale.objects.create(
        gym=gym, member=member, total_amount=total,
        sold_at=timezone.now(), sold_by=user,
    )
    for item in sale_items:
        item.sale = sale
    SaleItem.objects.bulk_create(sale_items)
    return sale


class ProductViewSet(GymScopedViewSet):
    queryset = Product.objects.all()
    serializer_class = ProductSerializer
    permission_classes = [IsGymStaff, IsOwnerOrReadOnly]
    search_fields = ["name", "category"]
    ordering_fields = ["name", "category", "stock_quantity", "created_at"]

    def get_queryset(self):
        qs = super().get_queryset()
        if self.request.query_params.get("low_stock") == "1":
            qs = qs.filter(stock_quantity__gt=0,
                          stock_quantity__lte=F("low_stock_threshold"))
        if self.request.query_params.get("out_of_stock") == "1":
            qs = qs.filter(stock_quantity__lte=0)
        return qs

    def get_serializer_context(self):
        ctx = super().get_serializer_context()
        ctx["gym"] = self.gym
        return ctx

    def create(self, request, *args, **kwargs):
        try:
            return super().create(request, *args, **kwargs)
        except IntegrityError:
            raise ValidationError({"name": "A product with this name already exists."})

    def destroy(self, request, *args, **kwargs):
        raise MethodNotAllowed("DELETE", detail="Set is_active to false instead.")

    @action(detail=True, methods=["post"], permission_classes=[IsGymStaff])
    def adjust(self, request, pk=None):
        product = self.get_object()
        s = StockAdjustmentInputSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        delta = s.validated_data["delta"]
        reason = s.validated_data.get("reason", "")

        with transaction.atomic():
            # Locked for the same reason as create_sale's decrement: the
            # prior-quantity read and the update need to be atomic as a
            # pair to detect a >0-to-0 transition safely under concurrent
            # adjustments/sales on the same product.
            locked_product = Product.objects.select_for_update().get(pk=product.pk)
            prior_qty = locked_product.stock_quantity

            # stock_quantity + delta >= 0  <=>  stock_quantity >= -delta.
            # For a positive delta, -delta is <= 0, so this always passes.
            updated = (Product.objects
                       .filter(pk=product.pk, stock_quantity__gte=-delta)
                       .update(stock_quantity=F("stock_quantity") + delta))
            if updated == 0:
                product.refresh_from_db(fields=["stock_quantity"])
                raise ValidationError({
                    "detail": f"That would take stock below zero. "
                              f"{product.stock_quantity} on hand."
                })
            StockAdjustment.objects.create(
                gym=self.gym, product=product, delta=delta,
                reason=reason, created_by=request.user,
            )

            if prior_qty > 0 and prior_qty + delta == 0:
                transaction.on_commit(lambda p=product: _notify_out_of_stock(p))

        product.refresh_from_db()
        return Response(ProductSerializer(product).data, status=status.HTTP_200_OK)

    @action(detail=True, methods=["get"])
    def adjustments(self, request, pk=None):
        product = self.get_object()
        qs = product.adjustments.select_related("created_by").all()
        return Response(StockAdjustmentSerializer(qs, many=True).data)


class SaleViewSet(GymScopedViewSet):
    queryset = Sale.objects.all()
    permission_classes = [IsGymStaff]
    http_method_names = ["get", "post", "head", "options"]

    def get_serializer_class(self):
        return SaleCreateSerializer if self.action == "create" else SaleSerializer

    def get_queryset(self):
        qs = super().get_queryset().select_related(
            "member", "sold_by").prefetch_related("items")

        date_str = self.request.query_params.get("date")
        if date_str:
            try:
                day = datetime.strptime(date_str, "%Y-%m-%d").date()
            except ValueError:
                raise ValidationError({"date": "Use YYYY-MM-DD."})
            tz = ZoneInfo(self.gym.timezone)
            start = datetime.combine(day, time.min, tzinfo=tz)
            end = start + timedelta(days=1)
            qs = qs.filter(sold_at__gte=start, sold_at__lt=end)
        return qs

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        member = None
        member_id = serializer.validated_data.get("member")
        if member_id:
            try:
                member = Member.objects.get(pk=member_id, gym=self.gym)
            except (Member.DoesNotExist, ValueError, TypeError):
                raise ValidationError({"member": "Member not found for your gym."})

        sale = create_sale(
            gym=self.gym,
            items=serializer.validated_data["items"],
            user=request.user,
            member=member,
        )
        return Response(SaleSerializer(sale).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"], permission_classes=[IsGymStaff, IsOwner])
    def void(self, request, pk=None):
        sale = self.get_object()
        if sale.voided_at is None:
            with transaction.atomic():
                for item in sale.items.all():
                    Product.objects.filter(pk=item.product_id).update(
                        stock_quantity=F("stock_quantity") + item.quantity)
                sale.voided_at = timezone.now()
                sale.voided_by = request.user
                sale.save(update_fields=["voided_at", "voided_by", "updated_at"])
        return Response(status=status.HTTP_204_NO_CONTENT)


class InventoryAlertsView(APIView):
    """
    Staff-visible, not owner-only — low stock is an operational fact the
    desk needs, and it deliberately contains no money.
    """
    permission_classes = [IsGymStaff, SubscriptionActive]

    def get(self, request):
        gym = request.user.gym
        qs = Product.objects.filter(gym=gym, is_active=True)

        in_stock_count = qs.filter(stock_quantity__gt=F("low_stock_threshold")).count()
        low_stock_count = qs.filter(
            stock_quantity__gt=0, stock_quantity__lte=F("low_stock_threshold")).count()
        out_of_stock_count = qs.filter(stock_quantity__lte=0).count()

        # Sorted in Python, worst first: a gym's product catalog is small,
        # and "stock / threshold ratio" isn't a column Postgres can order
        # by without a computed expression — not worth it for a 5-item cap.
        candidates = list(qs.filter(stock_quantity__lte=F("low_stock_threshold")))

        def sort_key(p):
            is_out = p.stock_quantity <= 0
            ratio = 0 if p.low_stock_threshold == 0 else (
                p.stock_quantity / p.low_stock_threshold)
            return (0 if is_out else 1, ratio)

        candidates.sort(key=sort_key)
        worst = candidates[:5]

        items = [{
            "id": str(p.id),
            "name": p.name,
            "stock_quantity": p.stock_quantity,
            "low_stock_threshold": p.low_stock_threshold,
            "state": "critical" if p.stock_quantity <= 0 else "low",
        } for p in worst]

        return Response({
            "in_stock_count": in_stock_count,
            "low_stock_count": low_stock_count,
            "out_of_stock_count": out_of_stock_count,
            "items": items,
        })
@transaction.atomic
def create_event_registration(gym, member, event_id):
    """
    Same shape as create_booking(): an unlocked existence/ownership check
    first (never confirms another gym's event id), then ordered
    validation, then a capacity lock ONLY when there's something to
    contend for.
    """
    try:
        event = Event.objects.get(pk=event_id, gym=gym)
    except (Event.DoesNotExist, ValueError, TypeError):
        raise Http404("Event not found.")

    if event.canceled_at is not None:
        raise ValidationError({"detail": "This event has been canceled."})

    today = gym_today(gym)
    if today > event.effective_registration_deadline:
        raise ValidationError({"detail": "Registration for this event has closed."})

    if member.archived_at:
        raise ValidationError({"detail":
            "Your membership record is no longer active at this gym. "
            "Please talk to gym staff."})

    # Membership status is deliberately NOT checked here, unlike
    # create_booking(). An event is separately paid for, and gyms want
    # lapsed members and prospects to be able to register — that's how a
    # competition brings people back. Do not "fix" this to match booking.

    if event.capacity is not None:
        # Re-fetch WITH the lock only now — locking an uncapped event's
        # row would serialize every registration for nothing.
        event = Event.objects.select_for_update().get(pk=event.pk)
        registered = EventRegistration.objects.filter(
            event=event, canceled_at__isnull=True).count()
        if registered >= event.capacity:
            raise ValidationError({"detail": "This event is full."})

    try:
        return EventRegistration.objects.create(
            gym=gym, event=event, member=member,
            amount_due=event.registration_fee,
        )
    except IntegrityError:
        raise ValidationError(
            {"detail": "You're already registered for this event."})


class EventViewSet(GymScopedViewSet):
    queryset = Event.objects.all()
    serializer_class = EventSerializer
    permission_classes = [IsGymUser, IsGymStaffOrReadOnly]

    def get_queryset(self):
        qs = super().get_queryset().annotate(
            registration_count=Count(
                "registrations", filter=Q(registrations__canceled_at__isnull=True)
            )
        ).order_by("-event_date", "id")
        return with_like_state(qs, "event", self.request.user)

    def destroy(self, request, *args, **kwargs):
        raise MethodNotAllowed("DELETE", detail="Set canceled_at instead.")

    @action(detail=True, methods=["post"], permission_classes=[IsGymMember])
    def register(self, request, pk=None):
        registration = create_event_registration(
            gym=request.user.gym, member=request.user.member_profile, event_id=pk)
        return Response(MemberEventRegistrationSerializer(registration).data,
                        status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"], permission_classes=[IsGymMember])
    def unregister(self, request, pk=None):
        # 404, never 403 — same "don't confirm the row exists" rule as
        # BookingCancelView.
        registration = get_object_or_404(
            EventRegistration, event_id=pk, member=request.user.member_profile,
            canceled_at__isnull=True)
        registration.canceled_at = timezone.now()
        registration.save(update_fields=["canceled_at", "updated_at"])

        data = MemberEventRegistrationSerializer(registration).data
        if registration.payment_status == EventRegistration.PAID:
            # Do not model a refund — cash came across a counter, it goes
            # back across a counter. This just tells the member that.
            data["detail"] = ("This was marked paid — refunds are handled "
                              "in person at the gym.")
        return Response(data, status=status.HTTP_200_OK)


class EventResultsView(APIView):
    """
    Split from a router @action because GET and POST need different
    permissions (any gym user can read the leaderboard; only staff can
    write it) — a single @action can't express that.
    """
    permission_classes = [IsGymUser]

    def get(self, request, event_id=None):
        event = get_object_or_404(Event, pk=event_id, gym=request.user.gym)
        qs = event.results.select_related("member").all()
        return Response(EventResultSerializer(qs, many=True).data)

    @transaction.atomic
    def post(self, request, event_id=None):
        if not getattr(request.user, "staff_profile", None):
            raise PermissionDenied("Only gym staff can post results.")

        gym = request.user.gym
        event = get_object_or_404(Event, pk=event_id, gym=gym)

        input_serializer = EventResultInputSerializer(data=request.data, many=True)
        input_serializer.is_valid(raise_exception=True)
        entries = input_serializer.validated_data

        ranks = [e["rank"] for e in entries]
        if len(set(ranks)) != len(ranks):
            raise ValidationError({"detail": "Ranks must be unique."})

        member_ids = [e["member"] for e in entries if e.get("member")]
        members_by_id = {
            m.id: m for m in Member.objects.filter(gym=gym, id__in=member_ids)
        }
        for e in entries:
            member_id = e.get("member")
            if member_id and member_id not in members_by_id:
                raise ValidationError(
                    {"detail": f"Member {member_id} not found for your gym."})

        # Validation above is complete before anything below runs — a
        # duplicate-rank submission never deletes the old set.
        event.results.all().delete()
        created = []
        for e in entries:
            member = members_by_id.get(e.get("member"))
            # Snapshotted here, once — see EventResult's docstring in
            # models.py for why this breaks the "don't cache derived
            # state" rule on purpose.
            display_name = member.full_name if member else e.get("display_name", "")
            created.append(EventResult.objects.create(
                gym=gym, event=event, member=member,
                display_name=display_name, rank=e["rank"],
                score_text=e.get("score_text", ""), note=e.get("note", ""),
            ))
        return Response(
            EventResultSerializer(created, many=True).data,
            status=status.HTTP_201_CREATED,
        )


class EventVerifyResultsView(APIView):
    """
    Staff-only. Separate endpoint from EventResultsView.post (rather than
    a body flag there) to mirror the mark-paid/mark-unpaid split on
    EventRegistrationViewSet — same shape of problem, same fix.
    """
    permission_classes = [IsGymStaff]

    def post(self, request, event_id=None):
        event = get_object_or_404(Event, pk=event_id, gym=request.user.gym)
        if not event.results.exists():
            raise ValidationError(
                {"detail": "This event has no results yet — nothing to verify."})
        event.results_verified = True
        event.results_verified_at = timezone.now()
        event.save(update_fields=["results_verified", "results_verified_at",
                                  "updated_at"])
        return Response(EventSerializer(event, context={"request": request}).data)


class EventUnverifyResultsView(APIView):
    """Staff-only. Reset path for EventVerifyResultsView — e.g. an owner
    corrects a score after verifying and wants the verified state cleared."""
    permission_classes = [IsGymStaff]

    def post(self, request, event_id=None):
        event = get_object_or_404(Event, pk=event_id, gym=request.user.gym)
        event.results_verified = False
        event.results_verified_at = None
        event.save(update_fields=["results_verified", "results_verified_at",
                                  "updated_at"])
        return Response(EventSerializer(event, context={"request": request}).data)


class EventRegistrationViewSet(GymScopedViewSet):
    queryset = EventRegistration.objects.all()
    serializer_class = EventRegistrationSerializer
    permission_classes = [IsGymStaff]
    http_method_names = ["get", "post", "head", "options"]

    def get_queryset(self):
        qs = super().get_queryset().select_related("member", "event")
        event_id = self.request.query_params.get("event")
        if event_id:
            qs = qs.filter(event_id=event_id)
        return qs

    def create(self, request, *args, **kwargs):
        raise MethodNotAllowed(
            "POST", detail="Registrations are created via "
                          "/events/{id}/register/, not here.")

    @action(detail=True, methods=["post"], url_path="mark-paid")
    def mark_paid(self, request, pk=None):
        reg = self.get_object()
        reg.payment_status = EventRegistration.PAID
        reg.paid_at = timezone.now()
        reg.marked_paid_by = request.user
        reg.save(update_fields=["payment_status", "paid_at",
                                "marked_paid_by", "updated_at"])
        return Response(EventRegistrationSerializer(reg).data)

    @action(detail=True, methods=["post"], url_path="mark-unpaid")
    def mark_unpaid(self, request, pk=None):
        reg = self.get_object()
        reg.payment_status = EventRegistration.UNPAID
        reg.paid_at = None
        reg.marked_paid_by = None
        reg.save(update_fields=["payment_status", "paid_at",
                                "marked_paid_by", "updated_at"])
        return Response(EventRegistrationSerializer(reg).data)


class MeEventRegistrationsView(ListAPIView):
    permission_classes = [IsGymMember]
    serializer_class = MemberEventRegistrationSerializer

    def get_queryset(self):
        return (EventRegistration.objects
                .filter(member=self.request.user.member_profile)
                .select_related("event"))


class MeRestDaysView(APIView):
    """Lets a member set their own rest days. Nothing else about their
    Member row is writable through this endpoint — see
    MemberRestDaysSerializer's single field."""
    permission_classes = [IsAuthenticated]

    def patch(self, request):
        member = getattr(request.user, "member_profile", None)
        if not member:
            return Response({"detail": "Not a member account."}, status=403)

        serializer = MemberRestDaysSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        member.rest_days = serializer.validated_data["rest_days"]
        member.save(update_fields=["rest_days", "updated_at"])
        return Response({"rest_days": member.rest_days})


class DeviceTokenView(APIView):
    """
    Register/refresh (POST) or remove (DELETE) this device's push token.
    Not gym-scoped — see DeviceToken. Any authenticated account (staff
    or member) can call this; the token is tied to whoever is logged in
    right now, not to their role.
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = DeviceTokenSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        DeviceToken.objects.update_or_create(
            token=serializer.validated_data["token"],
            defaults={
                "user": request.user,
                "platform": serializer.validated_data["platform"],
            },
        )
        return Response(status=status.HTTP_204_NO_CONTENT)

    def delete(self, request):
        token = request.data.get("token", "")
        if not token:
            raise ValidationError({"token": "This field is required."})
        DeviceToken.objects.filter(token=token, user=request.user).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class EngagementViewMixin:
    """
    Shared by the like/comment views, which serve both announcements and
    events: urls.py binds each view to one target with
    as_view(item_model=..., item_field=...). The item is looked up scoped
    to the caller's gym, so another gym's id is a 404 before anything
    else happens — never a 403 that would confirm it exists.
    """
    permission_classes = [CanEngage]
    item_model = None   # Announcement | Event
    item_field = None   # "announcement" | "event" — the FK on Like/Comment

    def get_permissions(self):
        # Same appended SubscriptionActive as GymScopedViewSet: staff writes
        # stop when the gym's subscription lapses, members always pass.
        return [p() for p in self.permission_classes] + [SubscriptionActive()]

    def get_item(self):
        return get_object_or_404(
            self.item_model, pk=self.kwargs["item_id"], gym=self.request.user.gym)


class LikeToggleView(EngagementViewMixin, APIView):
    """
    POST toggles: no like yet -> create one, already liked -> remove it.
    Returns the new like_count / liked_by_me either way.
    """

    def post(self, request, item_id=None):
        item = self.get_item()
        with transaction.atomic():
            removed, _ = Like.objects.filter(
                user=request.user, **{self.item_field: item}).delete()
            if not removed:
                # ignore_conflicts: two simultaneous taps both see "no like
                # yet"; the unique constraint lets one win and the other
                # is a no-op instead of a 500. Same approach as the
                # NotificationSend inserts.
                Like.objects.bulk_create(
                    [Like(gym=request.user.gym, user=request.user,
                          **{self.item_field: item})],
                    ignore_conflicts=True,
                )
        return Response(LikeSerializer(item, context={"request": request}).data)


class CommentListCreateView(EngagementViewMixin, ListCreateAPIView):
    serializer_class = CommentSerializer
    # Oldest first reads top-to-bottom as a thread; ?ordering=-created_at
    # flips it for a "latest first" client.
    ordering_fields = ["created_at"]
    ordering = ["created_at", "id"]

    def get_queryset(self):
        item = self.get_item()
        return Comment.objects.filter(
            gym=self.request.user.gym, **{self.item_field: item},
        ).select_related("user__member_profile", "user__staff_profile")

    def perform_create(self, serializer):
        serializer.save(gym=self.request.user.gym, user=self.request.user,
                        **{self.item_field: self.get_item()})


class CommentDeleteView(EngagementViewMixin, DestroyAPIView):
    def get_object(self):
        item = self.get_item()
        comment = get_object_or_404(
            Comment, pk=self.kwargs["comment_id"],
            gym=self.request.user.gym, **{self.item_field: item})
        # 403 (not 404) here: the comment is already visible to every gym
        # user in the list, so there's no existence to protect. Any staff
        # profile may remove any comment in their gym, for moderation.
        is_staff = getattr(self.request.user, "staff_profile", None) is not None
        if comment.user_id != self.request.user.id and not is_staff:
            raise PermissionDenied("You can only delete your own comments.")
        return comment
