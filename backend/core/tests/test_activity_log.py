from datetime import datetime, time, timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from core.models import (CheckIn, Gym, Location, Member, Membership,
                         MembershipPlan, Product, Sale, SaleItem,
                         StaffProfile, User)
from core.utils import gym_today

API_PREFIX = "/api/v1"


class ActivityLogTests(TestCase):
    """
    GET /analytics/activity-log/ — merges today's walk-in check-ins,
    membership purchases, and POS sales into one newest-first feed.
    """

    def setUp(self):
        self.gym = Gym.objects.create(
            name="Iron Works", slug="iron-works-activity", timezone="Asia/Manila")
        self.location = Location.objects.create(gym=self.gym, name="Main")
        self.owner = User.objects.create_user(
            email="owner@ironworks-activity.test", password="testpass123")
        StaffProfile.objects.create(
            user=self.owner, gym=self.gym, role=StaffProfile.OWNER,
            default_location=self.location)

        self.tz = ZoneInfo(self.gym.timezone)
        self.today = gym_today(self.gym)

        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)

    def _at(self, minutes_ago):
        # Anchored to "now minus N minutes" (not a fixed clock hour) so
        # these never land in the future regardless of when the suite runs.
        return timezone.now().astimezone(self.tz) - timedelta(minutes=minutes_ago)

    def test_merges_and_sorts_three_sources_newest_first(self):
        CheckIn.objects.create(
            gym=self.gym, visit_type=CheckIn.WALKIN, visitor_name="Mark Alvarez",
            category=CheckIn.REGULAR, amount_charged=Decimal("75.00"),
            location=self.location, checked_in_at=self._at(30),
        )

        plan = MembershipPlan.objects.create(
            gym=self.gym, name="1-Month", category="Regular",
            duration_value=1, duration_unit="MONTH", price=Decimal("1200.00"))
        member = Member.objects.create(
            gym=self.gym, home_location=self.location, first_name="Arvz",
            last_name="M.", member_type=Member.MEMBER)
        membership = Membership.objects.create(
            gym=self.gym, member=member, plan=plan, start_date=self.today)
        Membership.objects.filter(pk=membership.pk).update(created_at=self._at(20))

        product = Product.objects.create(
            gym=self.gym, name="Whey Protein Shake (Choco)", price=Decimal("100.00"))
        sale = Sale.objects.create(gym=self.gym, total_amount=Decimal("100.00"),
                                   sold_at=self._at(10))
        SaleItem.objects.create(
            gym=self.gym, sale=sale, product=product,
            product_name=product.name, unit_price=product.price,
            quantity=1, line_total=product.price)

        resp = self.client.get(f"{API_PREFIX}/analytics/activity-log/")
        self.assertEqual(resp.status_code, 200)
        activities = resp.data["activities"]
        self.assertEqual(len(activities), 3)
        # Newest first: sale (10m ago), membership (20m ago), check-in (30m ago).
        self.assertEqual(activities[0]["type"], "retail")
        self.assertEqual(activities[0]["title"], "Whey Protein Shake (Choco)")
        self.assertEqual(activities[1]["type"], "member")
        self.assertEqual(activities[1]["title"], "Arvz M.")
        self.assertIn("New Membership", activities[1]["subtitle"])
        self.assertEqual(activities[2]["type"], "walk_in")
        self.assertEqual(activities[2]["title"], "Mark Alvarez")
        self.assertEqual(activities[2]["amount"], "75.00")

    def test_excludes_voided_checkins_and_sales(self):
        voided_checkin = CheckIn.objects.create(
            gym=self.gym, visit_type=CheckIn.WALKIN, visitor_name="Ghost",
            category=CheckIn.REGULAR, amount_charged=Decimal("50.00"),
            location=self.location, checked_in_at=self._at(5),
        )
        voided_checkin.voided_at = timezone.now()
        voided_checkin.save(update_fields=["voided_at"])

        voided_sale = Sale.objects.create(
            gym=self.gym, total_amount=Decimal("40.00"),
            sold_at=self._at(5))
        voided_sale.voided_at = timezone.now()
        voided_sale.save(update_fields=["voided_at"])

        resp = self.client.get(f"{API_PREFIX}/analytics/activity-log/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["activities"], [])

    def test_excludes_member_checkins(self):
        member = Member.objects.create(
            gym=self.gym, home_location=self.location, first_name="Regular",
            last_name="Member", member_type=Member.MEMBER)

        CheckIn.objects.create(
            gym=self.gym, visit_type=CheckIn.MEMBER, member=member,
            location=self.location, checked_in_at=self._at(5),
        )

        resp = self.client.get(f"{API_PREFIX}/analytics/activity-log/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["activities"], [])

    def test_limit_param_caps_results(self):
        for i in range(3):
            CheckIn.objects.create(
                gym=self.gym, visit_type=CheckIn.WALKIN, visitor_name=f"Guest {i}",
                category=CheckIn.REGULAR, amount_charged=Decimal("50.00"),
                location=self.location, checked_in_at=self._at(i + 1),
            )

        resp = self.client.get(f"{API_PREFIX}/analytics/activity-log/?limit=2")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.data["activities"]), 2)

    def test_only_today_is_included(self):
        CheckIn.objects.create(
            gym=self.gym, visit_type=CheckIn.WALKIN, visitor_name="Yesterday Guest",
            category=CheckIn.REGULAR, amount_charged=Decimal("50.00"),
            location=self.location,
            checked_in_at=self._at(60 * 24 + 30),
        )

        resp = self.client.get(f"{API_PREFIX}/analytics/activity-log/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["activities"], [])

    def test_non_owner_forbidden(self):
        staff_user = User.objects.create_user(
            email="staff@ironworks-activity.test", password="testpass123")
        StaffProfile.objects.create(
            user=staff_user, gym=self.gym, role=StaffProfile.STAFF,
            default_location=self.location)
        client = APIClient()
        client.force_authenticate(user=staff_user)

        resp = client.get(f"{API_PREFIX}/analytics/activity-log/")
        self.assertEqual(resp.status_code, 403)
