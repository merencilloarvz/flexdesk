from datetime import timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from core.models import CheckIn, Gym, Location, Sale, StaffProfile, User
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


class SalesHistoryMonthlyPaginatedTests(TestCase):
    """
    GET /analytics/sales-history/?range=1M — still the old flat,
    paginated shape for now (Phase B replaces this with weekly rollup
    cards); this just guards that Phase A's 1D/1W change didn't also
    change 1M's behavior.
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
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)

    def _at(self, minutes_ago):
        return timezone.now().astimezone(self.tz) - timedelta(minutes=minutes_ago)

    def test_1m_still_returns_paginated_envelope(self):
        CheckIn.objects.create(
            gym=self.gym, visit_type=CheckIn.WALKIN, visitor_name="Mark",
            category=CheckIn.REGULAR, amount_charged=Decimal("75.00"),
            location=self.location, checked_in_at=self._at(30),
        )

        resp = self.client.get(f"{API_PREFIX}/analytics/sales-history/", {"range": "1M"})
        self.assertEqual(resp.status_code, 200)
        self.assertIn("count", resp.data)
        self.assertIn("next", resp.data)
        self.assertIn("previous", resp.data)
        self.assertEqual(resp.data["count"], 1)
        row = resp.data["results"][0]
        self.assertEqual(set(row.keys()), {"type", "title", "subtitle", "amount"})

    def test_1m_pagination_splits_across_pages(self):
        checkins = [
            CheckIn(
                gym=self.gym, visit_type=CheckIn.WALKIN, visitor_name=f"Guest {i}",
                category=CheckIn.REGULAR, amount_charged=Decimal("10.00"),
                location=self.location, checked_in_at=self._at(i + 1),
            )
            for i in range(55)
        ]
        CheckIn.objects.bulk_create(checkins)

        resp = self.client.get(f"{API_PREFIX}/analytics/sales-history/", {"range": "1M"})
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["count"], 55)
        self.assertEqual(len(resp.data["results"]), 50)
        self.assertIsNotNone(resp.data["next"])

        resp2 = self.client.get(resp.data["next"])
        self.assertEqual(resp2.status_code, 200)
        self.assertEqual(len(resp2.data["results"]), 5)
        self.assertIsNone(resp2.data["next"])
