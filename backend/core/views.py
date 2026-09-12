import hashlib
import hmac
from django.conf import settings as dj_settings
from django.db import IntegrityError
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.generics import ListAPIView, RetrieveAPIView
from rest_framework.response import Response
from rest_framework.exceptions import MethodNotAllowed, ValidationError
from rest_framework_simplejwt.views import TokenObtainPairView
from rest_framework_simplejwt.views import TokenObtainPairView
from django.utils import timezone

from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo
from .mixins import GymScopedViewSet
from .models import CheckIn, Member, Membership, MembershipPlan, Subscription, User
from .permissions import IsGymMember, IsGymStaff, IsOwner, IsOwnerOrReadOnly, SubscriptionActive
from .serializers import (CheckInSerializer, CheckInWriteSerializer,
                          ClaimAccountSerializer,
                          FlexTokenObtainPairSerializer, MeCheckInSerializer,
                          MeMemberSummarySerializer, MeSerializer, MemberRestDaysSerializer,
                          MemberSerializer, MembershipPlanSerializer,
                          MembershipSerializer, MemberWriteSerializer,
                          SubscriptionSerializer)
from .utils import generate_claim_code, gym_today

from rest_framework.permissions import AllowAny
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from .serializers import SignupSerializer

from .serializers import (ChangePasswordSerializer, StaffCreateSerializer,
                          StaffMemberSerializer)
from .models import StaffProfile
from django.db import transaction
from django.db.models import Count, F, Q
from django.http import Http404
from django.shortcuts import get_object_or_404
from .models import Booking, TimeSlot
from .serializers import BookingCreateSerializer, BookingSerializer, TimeSlotSerializer


from rest_framework.exceptions import PermissionDenied
from .models import Announcement, Event, EventRegistration, EventResult
from .models import Product, Sale, SaleItem, StockAdjustment
from .permissions import IsGymUser, IsGymStaffOrReadOnly
from .serializers import (AnnouncementSerializer, EventRegistrationSerializer,
                          EventResultInputSerializer, EventResultSerializer,
                          EventSerializer, MemberEventRegistrationSerializer,
                          ProductSerializer, SaleCreateSerializer, SaleSerializer,
                          StockAdjustmentInputSerializer, StockAdjustmentSerializer)
from django.db.models import Sum, DecimalField
from django.db.models.functions import Coalesce, TruncDate
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


class SubscriptionCheckoutView(APIView):
    """
    Owner-only. Creates a PayMongo checkout session and hands the
    Flutter app back a redirect URL to open.

    Deliberately refuses (501) rather than guessing at PayMongo's
    request shape without a real sandbox to test against — a wrong
    field name or auth header here would only surface once someone
    actually tries to pay. Fill in the real POST to PayMongo's
    checkout-sessions API once PAYMONGO_SECRET_KEY and
    PAYMONGO_SUBSCRIPTION_PRICE_CENTAVOS are set for real.
    """
    permission_classes = [IsGymStaff, IsOwner]

    def post(self, request):
        if not dj_settings.PAYMONGO_SECRET_KEY or not dj_settings.PAYMONGO_SUBSCRIPTION_PRICE_CENTAVOS:
            return Response(
                {"detail": "PayMongo is not yet configured for this environment."},
                status=status.HTTP_501_NOT_IMPLEMENTED,
            )
        # TODO: POST to PayMongo's checkout-sessions API with the
        # gym's subscription.paymongo_customer_id (creating one first if
        # blank), PAYMONGO_SUBSCRIPTION_PRICE_CENTAVOS, and success/cancel
        # redirect URLs back into the app. Return {"checkout_url": ...}.
        return Response(
            {"detail": "PayMongo checkout is not yet wired up."},
            status=status.HTTP_501_NOT_IMPLEMENTED,
        )


class SubscriptionWebhookView(APIView):
    """
    No auth — PayMongo calls this directly, so the signature header is
    the ONLY thing standing between "a real payment happened" and
    "anyone who finds this URL can mark themselves subscribed". Verify
    first, parse second — never the other way around.

    PayMongo signs with a `Paymongo-Signature` header shaped like
    `t=<timestamp>,te=<test-mode signature>,li=<live-mode signature>`,
    each signature being HMAC-SHA256(webhook_secret, f"{t}.{raw_body}")
    hex-encoded. This has NOT been exercised against a real PayMongo
    sandbox event yet — verify it against an actual webhook delivery
    before this goes live, per the Stage 10 plan.
    """
    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request):
        secret = dj_settings.PAYMONGO_WEBHOOK_SECRET
        if not secret:
            return Response(status=status.HTTP_503_SERVICE_UNAVAILABLE)

        if not self._verify_signature(request, secret):
            return Response(status=status.HTTP_400_BAD_REQUEST)

        event_type = request.data.get("data", {}).get("attributes", {}).get("type")
        payment_data = request.data.get("data", {}).get("attributes", {}).get("data", {})
        attributes = payment_data.get("attributes", {}) if isinstance(payment_data, dict) else {}
        paymongo_customer_id = attributes.get("billing", {}).get("customer_id") \
            if isinstance(attributes.get("billing"), dict) else None

        subscription = None
        if paymongo_customer_id:
            subscription = Subscription.objects.filter(
                paymongo_customer_id=paymongo_customer_id).first()

        if subscription is None:
            # Nothing here identifies a gym we know about yet — this is
            # expected for events unrelated to a subscription (or before
            # checkout has stamped a customer id onto it). Acknowledge
            # so PayMongo doesn't keep retrying, but change nothing.
            return Response(status=status.HTTP_200_OK)

        if event_type == "payment.paid":
            subscription.status = Subscription.ACTIVE
            subscription.save(update_fields=["status", "updated_at"])
        elif event_type == "payment.failed":
            subscription.status = Subscription.PAST_DUE
            subscription.save(update_fields=["status", "updated_at"])

        return Response(status=status.HTTP_200_OK)

    @staticmethod
    def _verify_signature(request, secret):
        header = request.headers.get("Paymongo-Signature", "")
        parts = dict(p.split("=", 1) for p in header.split(",") if "=" in p)
        timestamp, test_sig, live_sig = parts.get("t"), parts.get("te"), parts.get("li")
        signature = live_sig or test_sig
        if not (timestamp and signature):
            return False

        signed_payload = f"{timestamp}.{request.body.decode('utf-8')}"
        expected = hmac.new(
            secret.encode("utf-8"), signed_payload.encode("utf-8"), hashlib.sha256
        ).hexdigest()
        return hmac.compare_digest(expected, signature)

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

class AnnouncementViewSet(GymScopedViewSet):
    queryset = Announcement.objects.all()
    serializer_class = AnnouncementSerializer
    permission_classes = [IsGymUser, IsGymStaffOrReadOnly]

    def perform_create(self, serializer):
        serializer.save(gym=self.gym, created_by=self.request.user)

@transaction.atomic
def create_sale(gym, items, user, member=None):
    """
    Each decrement is a single conditional UPDATE. Postgres evaluates the
    stock check and the write together, so two concurrent sales of the
    last unit can't both succeed — the second one matches zero rows and
    we roll the whole sale back. A read-then-write would let both through
    and drive stock negative.
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
            product = Product.objects.get(pk=pid, gym=gym, is_active=True)
        except (Product.DoesNotExist, ValueError, TypeError):
            # 404, not 403 — never confirms another gym's product id exists.
            raise Http404("Product not found.")

        updated = (Product.objects
                   .filter(pk=product.pk, stock_quantity__gte=qty)
                   .update(stock_quantity=F("stock_quantity") - qty))
        if updated == 0:
            raise ValidationError({
                "detail": f"Not enough stock for {product.name}. "
                          f"{product.stock_quantity} left."
            })

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
        return super().get_queryset().annotate(
            registration_count=Count(
                "registrations", filter=Q(registrations__canceled_at__isnull=True)
            )
        ).order_by("-event_date", "id")

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