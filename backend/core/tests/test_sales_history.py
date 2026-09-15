from datetime import datetime, timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from core.models import (CheckIn, Gym, Location, Member, Membership,
                         MembershipPlan, Sale, StaffProfile, User)
from core.utils import gym_today

API_PREFIX = "/api/v1"


class SalesHistoryGroupedTests(TestCase):
    """
    GET /analytics/sales-history/?range=1D|1W — transactions grouped by
    gym-local calendar day, {period, groups}. Not paginated (Phase A of
    the Sales History screen). 1M keeps the old flat/paginated shape
    until Phase B replaces it with weekly rollups.
    """

    def setUp(self):
        self.gym = Gym.objects.create(
            name="Iron Works", slug="iron-works-sales-history", timezone="Asia/Manila")
        self.location = Location.objects.create(gym=self.gym, name="Main")
        self.owner = User.objects.create_user(
            email="owner@ironworks-sales-history.test", password="testpass123")
        StaffProfile.objects.create(
            user=self.owner, gym=self.gym, role=StaffProfile.OWNER,
            default_location=self.location)

        self.tz = ZoneInfo(self.gym.timezone)
        self.today = gym_today(self.gym)

        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)

    def _at(self, minutes_ago):
        return timezone.now().astimezone(self.tz) - timedelta(minutes=minutes_ago)

    def test_defaults_to_1d_grouped_shape(self):
        CheckIn.objects.create(
            gym=self.gym, visit_type=CheckIn.WALKIN, visitor_name="Mark",
            category=CheckIn.REGULAR, amount_charged=Decimal("75.00"),
            location=self.location, checked_in_at=self._at(30),
        )

        resp = self.client.get(f"{API_PREFIX}/analytics/sales-history/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["period"], {"total": "75.00", "order_count": 1})
        self.assertEqual(len(resp.data["groups"]), 1)
        group = resp.data["groups"][0]
        self.assertEqual(group["date"], self.today.isoformat())
        self.assertEqual(group["total"], "75.00")
        self.assertEqual(group["order_count"], 1)
        row = group["transactions"][0]
        self.assertEqual(set(row.keys()), {"type", "title", "subtitle", "amount"})
        self.assertEqual(row["title"], "Mark")

    def test_1w_groups_by_day_newest_day_first(self):
        Sale.objects.create(
            gym=self.gym, total_amount=Decimal("99.00"),
            sold_at=self._at(60 * 24 * 3))  # 3 days ago
        Sale.objects.create(
            gym=self.gym, total_amount=Decimal("50.00"), sold_at=self._at(5))

        resp = self.client.get(f"{API_PREFIX}/analytics/sales-history/", {"range": "1W"})
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["period"], {"total": "149.00", "order_count": 2})
        self.assertEqual(len(resp.data["groups"]), 2)
        # Newest day's group comes first.
        self.assertEqual(resp.data["groups"][0]["date"], self.today.isoformat())
        self.assertEqual(resp.data["groups"][0]["total"], "50.00")
        self.assertEqual(resp.data["groups"][1]["total"], "99.00")

    def test_multiple_transactions_same_day_share_one_group(self):
        Sale.objects.create(
            gym=self.gym, total_amount=Decimal("40.00"), sold_at=self._at(5))
        Sale.objects.create(
            gym=self.gym, total_amount=Decimal("60.00"), sold_at=self._at(15))

        resp = self.client.get(f"{API_PREFIX}/analytics/sales-history/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.data["groups"]), 1)
        group = resp.data["groups"][0]
        self.assertEqual(group["total"], "100.00")
        self.assertEqual(group["order_count"], 2)
        # Transactions within a group stay newest-first too.
        amounts = [t["amount"] for t in group["transactions"]]
        self.assertEqual(amounts, ["40.00", "60.00"])

    def test_1d_excludes_items_from_yesterday(self):
        Sale.objects.create(
            gym=self.gym, total_amount=Decimal("99.00"),
            sold_at=self._at(60 * 24 + 30))  # just over a day ago

        resp = self.client.get(f"{API_PREFIX}/analytics/sales-history/", {"range": "1D"})
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["period"]["order_count"], 0)
        self.assertEqual(resp.data["groups"], [])

    def test_invalid_range_rejected(self):
        resp = self.client.get(f"{API_PREFIX}/analytics/sales-history/", {"range": "3M"})
        self.assertEqual(resp.status_code, 400)

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

        resp = self.client.get(f"{API_PREFIX}/analytics/sales-history/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["period"]["order_count"], 0)
        self.assertEqual(resp.data["groups"], [])

    def test_non_owner_forbidden(self):
        staff_user = User.objects.create_user(
            email="staff@ironworks-sales-history.test", password="testpass123")
        StaffProfile.objects.create(
            user=staff_user, gym=self.gym, role=StaffProfile.STAFF,
            default_location=self.location)
        client = APIClient()
        client.force_authenticate(user=staff_user)

        resp = client.get(f"{API_PREFIX}/analytics/sales-history/")
        self.assertEqual(resp.status_code, 403)


class SalesHistoryWeeklyRollupTests(TestCase):
    """
    GET /analytics/sales-history/?range=1M — weekly rollup cards
    (Phase B). Buckets are 7-day chunks counted from start_date
    (today - 29), so for a fresh 30-day window that's always 4 full
    weeks plus a short 2-day trailing bucket (today-1..today) that's
    always the "in_progress" one.
    """

    def setUp(self):
        self.gym = Gym.objects.create(
            name="Iron Works", slug="iron-works-sales-history-1m", timezone="Asia/Manila")
        self.location = Location.objects.create(gym=self.gym, name="Main")
        self.owner = User.objects.create_user(
            email="owner@ironworks-sales-history-1m.test", password="testpass123")
        StaffProfile.objects.create(
            user=self.owner, gym=self.gym, role=StaffProfile.OWNER,
            default_location=self.location)

        self.tz = ZoneInfo(self.gym.timezone)
        self.today = gym_today(self.gym)
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)

    def _at_days_ago(self, days_ago):
        # A safe (already-past) time of day on a specific past date --
        # same "now minus a small buffer" trick used elsewhere in this
        # suite, just combined with an arbitrary past date instead of
        # always being relative to "now".
        now_local = timezone.now().astimezone(self.tz)
        time_of_day = (now_local - timedelta(minutes=5)).time()
        target_date = self.today - timedelta(days=days_ago)
        return datetime.combine(target_date, time_of_day, tzinfo=self.tz)

    def _get(self):
        resp = self.client.get(f"{API_PREFIX}/analytics/sales-history/", {"range": "1M"})
        self.assertEqual(resp.status_code, 200)
        return resp.data["weeks"]

    def test_five_buckets_for_a_fresh_30_day_window(self):
        weeks = self._get()
        self.assertEqual(len(weeks), 5)
        for w in weeks:
            self.assertEqual(
                set(w.keys()),
                {"start_date", "end_date", "total", "order_count",
                 "categories", "status", "change_pct"},
            )
            self.assertEqual(
                set(w["categories"].keys()), {"membership", "retail", "walk_ins"})

    def test_newest_bucket_is_always_in_progress_and_short(self):
        weeks = self._get()
        newest = weeks[0]
        self.assertEqual(newest["status"], "in_progress")
        self.assertEqual(newest["change_pct"], None)
        self.assertEqual(newest["start_date"], (self.today - timedelta(days=1)).isoformat())
        self.assertEqual(newest["end_date"], self.today.isoformat())

    def test_oldest_bucket_is_opener_when_not_peak(self):
        # A small amount in the oldest bucket, a larger one elsewhere --
        # the oldest should read "opener", not "peak".
        Sale.objects.create(
            gym=self.gym, total_amount=Decimal("100.00"), sold_at=self._at_days_ago(25))
        Sale.objects.create(
            gym=self.gym, total_amount=Decimal("500.00"), sold_at=self._at_days_ago(12))

        weeks = self._get()
        oldest = weeks[-1]
        self.assertEqual(oldest["total"], "100.00")
        self.assertEqual(oldest["status"], "opener")
        self.assertEqual(oldest["change_pct"], None)

    def test_peak_is_highest_completed_week_excluding_in_progress(self):
        # Amounts placed in each of the 4 completed buckets, plus a
        # much larger one in the in-progress bucket -- peak must still
        # land on the highest COMPLETED week (bucket2, 500), not the
        # in-progress one despite its bigger total.
        Sale.objects.create(
            gym=self.gym, total_amount=Decimal("100.00"), sold_at=self._at_days_ago(25))  # bucket0
        Sale.objects.create(
            gym=self.gym, total_amount=Decimal("300.00"), sold_at=self._at_days_ago(18))  # bucket1
        Sale.objects.create(
            gym=self.gym, total_amount=Decimal("500.00"), sold_at=self._at_days_ago(12))  # bucket2
        Sale.objects.create(
            gym=self.gym, total_amount=Decimal("200.00"), sold_at=self._at_days_ago(5))   # bucket3
        Sale.objects.create(
            gym=self.gym, total_amount=Decimal("9999.00"), sold_at=self._at_days_ago(1))  # in-progress

        weeks = self._get()
        by_total = {w["total"]: w for w in weeks}
        self.assertEqual(by_total["9999.00"]["status"], "in_progress")
        self.assertEqual(by_total["500.00"]["status"], "peak")
        self.assertEqual(by_total["100.00"]["status"], "opener")
        # bucket1 (300) vs bucket0 (100): +200%.
        self.assertEqual(by_total["300.00"]["status"], "change")
        self.assertEqual(by_total["300.00"]["change_pct"], 200.0)
        # bucket3 (200) vs bucket2/peak (500): -60%.
        self.assertEqual(by_total["200.00"]["status"], "change")
        self.assertEqual(by_total["200.00"]["change_pct"], -60.0)

    def test_category_breakdown_and_order_count(self):
        plan = MembershipPlan.objects.create(
            gym=self.gym, name="1-Month", category="Regular",
            duration_value=1, duration_unit="MONTH", price=Decimal("1000.00"))
        member = Member.objects.create(
            gym=self.gym, home_location=self.location, first_name="Ana",
            last_name="Cruz", member_type=Member.MEMBER)
        membership = Membership.objects.create(
            gym=self.gym, member=member, plan=plan, start_date=self.today)
        Membership.objects.filter(pk=membership.pk).update(
            created_at=self._at_days_ago(5))

        CheckIn.objects.create(
            gym=self.gym, visit_type=CheckIn.WALKIN, visitor_name="Walk-in",
            category=CheckIn.REGULAR, amount_charged=Decimal("25.00"),
            location=self.location, checked_in_at=self._at_days_ago(5),
        )
        Sale.objects.create(
            gym=self.gym, total_amount=Decimal("40.00"), sold_at=self._at_days_ago(5))

        weeks = self._get()
        bucket3 = weeks[1]  # the most recent COMPLETED bucket (today-8..-2)
        self.assertEqual(bucket3["order_count"], 3)
        self.assertEqual(bucket3["total"], "1065.00")
        self.assertEqual(bucket3["categories"], {
            "membership": "1000.00", "retail": "40.00", "walk_ins": "25.00",
        })

    def test_voided_sale_and_checkin_excluded(self):
        voided_sale = Sale.objects.create(
            gym=self.gym, total_amount=Decimal("40.00"), sold_at=self._at_days_ago(5))
        voided_sale.voided_at = timezone.now()
        voided_sale.save(update_fields=["voided_at"])

        weeks = self._get()
        self.assertTrue(all(w["total"] == "0.00" for w in weeks))
        self.assertTrue(all(w["order_count"] == 0 for w in weeks))

    def test_non_owner_forbidden(self):
        staff_user = User.objects.create_user(
            email="staff@ironworks-sales-history-1m.test", password="testpass123")
        StaffProfile.objects.create(
            user=staff_user, gym=self.gym, role=StaffProfile.STAFF,
            default_location=self.location)
        client = APIClient()
        client.force_authenticate(user=staff_user)

        resp = client.get(f"{API_PREFIX}/analytics/sales-history/", {"range": "1M"})
        self.assertEqual(resp.status_code, 403)
