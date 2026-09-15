from datetime import datetime, time, timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from core.models import (CheckIn, Event, EventRegistration, Gym, Location,
                         Member, Membership, MembershipPlan, Sale, SaleItem,
                         StaffProfile, User)
from core.utils import gym_today

API_PREFIX = "/api/v1"


class AnalyticsCheckInBadgeTests(TestCase):
    """
    Part A: the check_ins block on GET /analytics/. All three cases from
    the spec's Definition of Done. Uses gym-local "today" (Asia/Manila)
    derived from the real clock, not a frozen time, so these stay
    correct without a time-mocking dependency — every check-in is placed
    relative to that "today", never at a fixed calendar date.
    """

    def setUp(self):
        self.gym = Gym.objects.create(
            name="Iron Works", slug="iron-works-analytics", timezone="Asia/Manila")
        self.location = Location.objects.create(gym=self.gym, name="Main")
        self.owner = User.objects.create_user(
            email="owner@ironworks-analytics.test", password="testpass123")
        StaffProfile.objects.create(
            user=self.owner, gym=self.gym, role=StaffProfile.OWNER,
            default_location=self.location)

        self.tz = ZoneInfo(self.gym.timezone)
        self.today = timezone.now().astimezone(self.tz).date()
        self.yesterday = self.today - timedelta(days=1)

        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)

    def _checkin_at(self, target_date):
        """
        Builds a checked_in_at that's always safely in the past, regardless
        of what time it actually is when the suite runs. Anchored to the
        current gym-local time-of-day (minus a small buffer) rather than a
        fixed hour — a fixed hour like 09:00 can land in the future if the
        suite happens to run earlier than that in Manila time, which is
        exactly the bug this fix replaces.
        """
        now_local = timezone.now().astimezone(self.tz)
        time_of_day = (now_local - timedelta(minutes=2)).time()
        dt = datetime.combine(target_date, time_of_day, tzinfo=self.tz)
        return CheckIn.objects.create(
            gym=self.gym, visit_type=CheckIn.WALKIN, visitor_name="Walk-in",
            category=CheckIn.REGULAR, amount_charged=Decimal("100.00"),
            location=self.location, checked_in_at=dt,
        )

    def test_yesterday_zero_gives_null_change_pct(self):
        # Gym's first day has no yesterday — change_pct must be null,
        # not a division-by-zero crash or a bogus 0.0.
        self._checkin_at(self.today)

        resp = self.client.get(f"{API_PREFIX}/analytics/")
        self.assertEqual(resp.status_code, 200)
        ci = resp.data["check_ins"]
        self.assertEqual(ci["today"], 1)
        self.assertEqual(ci["yesterday"], 0)
        self.assertIsNone(ci["change_pct"])

    def test_voided_checkin_counted_in_neither_day(self):
        # One valid check-in yesterday (so the denominator isn't zero),
        # one voided check-in today that must not count anywhere.
        self._checkin_at(self.yesterday)
        voided = self._checkin_at(self.today)
        voided.voided_at = timezone.now()
        voided.save(update_fields=["voided_at"])

        resp = self.client.get(f"{API_PREFIX}/analytics/")
        self.assertEqual(resp.status_code, 200)
        ci = resp.data["check_ins"]
        self.assertEqual(ci["today"], 0)
        self.assertEqual(ci["yesterday"], 1)
        self.assertEqual(ci["change_pct"], -100.0)

    def test_late_manila_checkin_counts_for_correct_date(self):
        # A 23:30 Manila check-in near the gym-local day boundary must
        # land on its own date, not roll into the next day through a
        # naive UTC-date comparison. Placed on "yesterday" (not "today")
        # so the checked_in_at value is always safely in the past —
        # today's clean() rejects a future checked_in_at, and "23:30
        # today" would be in the future for most of the actual day.
        self._checkin_at(datetime.combine(self.yesterday, time(hour=23, minute=30),
                                          tzinfo=self.tz))

        resp = self.client.get(f"{API_PREFIX}/analytics/")
        self.assertEqual(resp.status_code, 200)
        ci = resp.data["check_ins"]
        self.assertEqual(ci["yesterday"], 1)
        self.assertEqual(ci["today"], 0)


class Analytics1DHourlySeriesTests(TestCase):
    """
    revenue.series for range=1D — one point per gym-local hour from
    midnight through the current in-progress hour, not a single
    whole-day total. Uses the real clock (like the check-in badge
    tests above), so a couple of tests guard against the rare window
    right after gym-local midnight where "N minutes ago" would land
    on yesterday.
    """

    def setUp(self):
        self.gym = Gym.objects.create(
            name="Iron Works", slug="iron-works-hourly", timezone="Asia/Manila")
        self.location = Location.objects.create(gym=self.gym, name="Main")
        self.owner = User.objects.create_user(
            email="owner@ironworks-hourly.test", password="testpass123")
        StaffProfile.objects.create(
            user=self.owner, gym=self.gym, role=StaffProfile.OWNER,
            default_location=self.location)

        self.tz = ZoneInfo(self.gym.timezone)
        self.now_local = timezone.now().astimezone(self.tz)
        self.current_hour = self.now_local.hour

        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)

    def _at(self, minutes_ago):
        return self.now_local - timedelta(minutes=minutes_ago)

    def _get_series(self):
        resp = self.client.get(f"{API_PREFIX}/analytics/", {"range": "1D"})
        self.assertEqual(resp.status_code, 200)
        return resp.data["revenue"]["series"]

    def test_series_has_one_point_per_hour_through_now(self):
        series = self._get_series()
        self.assertEqual(len(series), self.current_hour + 1)
        for i, point in enumerate(series):
            self.assertIn("T", point["date"])  # full datetime, not a bare date
            parsed = datetime.fromisoformat(point["date"]).astimezone(self.tz)
            self.assertEqual(parsed.hour, i)
        last = datetime.fromisoformat(series[-1]["date"]).astimezone(self.tz)
        self.assertEqual(last.hour, self.current_hour)

    def test_empty_hours_are_zero_filled(self):
        series = self._get_series()
        for point in series:
            self.assertEqual(point["amount"], "0.00")

    def test_sale_and_checkin_land_in_their_own_hour_buckets(self):
        if self.current_hour < 2:
            self.skipTest("too close to gym-local midnight for a safe 90m offset")

        Sale.objects.create(
            gym=self.gym, total_amount=Decimal("40.00"), sold_at=self._at(5))
        CheckIn.objects.create(
            gym=self.gym, visit_type=CheckIn.WALKIN, visitor_name="Walk-in",
            category=CheckIn.REGULAR, amount_charged=Decimal("25.00"),
            location=self.location, checked_in_at=self._at(90),
        )

        series = self._get_series()
        recent_hour = self._at(5).hour
        older_hour = self._at(90).hour
        self.assertEqual(series[recent_hour]["amount"], "40.00")
        self.assertEqual(series[older_hour]["amount"], "25.00")

    def test_all_four_revenue_sources_summed_in_same_hour(self):
        plan = MembershipPlan.objects.create(
            gym=self.gym, name="1-Month", category="Regular",
            duration_value=1, duration_unit="MONTH", price=Decimal("1000.00"))
        member = Member.objects.create(
            gym=self.gym, home_location=self.location, first_name="Ana",
            last_name="Cruz", member_type=Member.MEMBER)
        membership = Membership.objects.create(
            gym=self.gym, member=member, plan=plan, start_date=gym_today(self.gym))
        Membership.objects.filter(pk=membership.pk).update(created_at=self._at(5))

        CheckIn.objects.create(
            gym=self.gym, visit_type=CheckIn.WALKIN, visitor_name="Walk-in",
            category=CheckIn.REGULAR, amount_charged=Decimal("25.00"),
            location=self.location, checked_in_at=self._at(5),
        )
        Sale.objects.create(
            gym=self.gym, total_amount=Decimal("40.00"), sold_at=self._at(5))

        event = Event.objects.create(
            gym=self.gym, title="Fall Classic",
            event_date=gym_today(self.gym), registration_fee=Decimal("500.00"))
        EventRegistration.objects.create(
            gym=self.gym, event=event, member=member,
            payment_status=EventRegistration.PAID, amount_due=Decimal("500.00"),
            paid_at=self._at(5),
        )

        series = self._get_series()
        hour = self._at(5).hour
        self.assertEqual(series[hour]["amount"], "1565.00")

    def test_voided_sale_and_checkin_excluded(self):
        voided_sale = Sale.objects.create(
            gym=self.gym, total_amount=Decimal("40.00"), sold_at=self._at(5))
        voided_sale.voided_at = timezone.now()
        voided_sale.save(update_fields=["voided_at"])

        voided_checkin = CheckIn.objects.create(
            gym=self.gym, visit_type=CheckIn.WALKIN, visitor_name="Ghost",
            category=CheckIn.REGULAR, amount_charged=Decimal("25.00"),
            location=self.location, checked_in_at=self._at(5),
        )
        voided_checkin.voided_at = timezone.now()
        voided_checkin.save(update_fields=["voided_at"])

        series = self._get_series()
        hour = self._at(5).hour
        self.assertEqual(series[hour]["amount"], "0.00")

    def test_yesterdays_activity_not_included(self):
        Sale.objects.create(
            gym=self.gym, total_amount=Decimal("999.00"),
            sold_at=self.now_local - timedelta(hours=25))

        series = self._get_series()
        total = sum(Decimal(p["amount"]) for p in series)
        self.assertEqual(total, Decimal("0.00"))


class Analytics1WAnd1MStillUseDailyBucketsTests(TestCase):
    """
    Regression guard: adding hourly buckets for 1D must not change how
    1W/1M build their series — still one point per calendar day.
    """

    def setUp(self):
        self.gym = Gym.objects.create(
            name="Iron Works", slug="iron-works-daily-regress", timezone="Asia/Manila")
        self.location = Location.objects.create(gym=self.gym, name="Main")
        self.owner = User.objects.create_user(
            email="owner@ironworks-daily-regress.test", password="testpass123")
        StaffProfile.objects.create(
            user=self.owner, gym=self.gym, role=StaffProfile.OWNER,
            default_location=self.location)
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)

    def test_1w_series_is_seven_daily_points(self):
        resp = self.client.get(f"{API_PREFIX}/analytics/", {"range": "1W"})
        self.assertEqual(resp.status_code, 200)
        series = resp.data["revenue"]["series"]
        self.assertEqual(len(series), 7)
        for point in series:
            self.assertRegex(point["date"], r"^\d{4}-\d{2}-\d{2}$")

    def test_1m_series_is_thirty_daily_points(self):
        resp = self.client.get(f"{API_PREFIX}/analytics/", {"range": "1M"})
        self.assertEqual(resp.status_code, 200)
        series = resp.data["revenue"]["series"]
        self.assertEqual(len(series), 30)
        for point in series:
            self.assertRegex(point["date"], r"^\d{4}-\d{2}-\d{2}$")