from datetime import datetime, time, timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from core.models import CheckIn, Gym, Location, StaffProfile, User

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