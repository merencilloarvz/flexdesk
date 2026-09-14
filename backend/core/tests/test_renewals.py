import uuid
from datetime import date, datetime, timedelta
from datetime import timezone as dt_timezone
from unittest import mock
from zoneinfo import ZoneInfo

from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import RefreshToken

from core.models import (
    Gym, Location, Member, Membership, MembershipPlan, RenewalReminder,
    StaffProfile, User,
)
from core.utils import gym_today

API = "/api/v1"


class RenewalWorklistTestCase(APITestCase):
    """
    Part A — GET /members/expiring/. Built on get_queryset()'s existing
    .visible().with_status(self.today), never a parallel query — these
    tests exercise the 7-day rule and visibility rule through the real
    thing, not a reimplementation of it.
    """

    def setUp(self):
        self.gym_a = Gym.objects.create(name="Renewal Gym A", slug="renewal-gym-a")
        self.location_a = Location.objects.create(gym=self.gym_a, name="Main")

        self.owner_user = User.objects.create_user(
            email="renewalowner@example.com", password="StrongPass123!",
            full_name="Renewal Owner")
        self.owner = StaffProfile.objects.create(
            user=self.owner_user, gym=self.gym_a, role=StaffProfile.OWNER,
            default_location=self.location_a)

        self.member_token_user = User.objects.create_user(
            email="renewalmembertoken@example.com", password="StrongPass123!",
            full_name="Member Token")

        self.plan = MembershipPlan.objects.create(
            gym=self.gym_a, name="Monthly", category="Regular",
            duration_value=1, duration_unit=MembershipPlan.MONTH,
            price="1000.00",
        )

        self.gym_b = Gym.objects.create(name="Renewal Gym B", slug="renewal-gym-b")
        self.location_b = Location.objects.create(gym=self.gym_b, name="Main")
        self.owner_b_user = User.objects.create_user(
            email="renewalownerb@example.com", password="StrongPass123!",
            full_name="Owner B")
        StaffProfile.objects.create(
            user=self.owner_b_user, gym=self.gym_b, role=StaffProfile.OWNER,
            default_location=self.location_b)
        self.plan_b = MembershipPlan.objects.create(
            gym=self.gym_b, name="Monthly", category="Regular",
            duration_value=1, duration_unit=MembershipPlan.MONTH,
            price="1000.00",
        )

    # ---- helpers ----

    def _auth(self, user):
        token = RefreshToken.for_user(user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token.access_token}")

    def _member(self, gym, location, first_name="Test", member_type=Member.MEMBER,
                archived=False):
        return Member.objects.create(
            gym=gym, home_location=location, first_name=first_name,
            last_name="Member", email=f"{first_name.lower()}@example.com",
            member_type=member_type,
            archived_at=timezone.now() if archived else None,
        )

    def _membership(self, member, end_date, gym=None, plan=None):
        return Membership.objects.create(
            gym=gym or member.gym, member=member, plan=plan or self.plan,
            start_date=end_date - timedelta(days=29), end_date=end_date,
        )

    def _expiring(self):
        return self.client.get(f"{API}/members/expiring/")

    # ---- worklist membership ----

    def test_member_expiring_soon_appears_one_far_out_does_not(self):
        today = gym_today(self.gym_a)
        soon = self._member(self.gym_a, self.location_a, "Soon")
        self._membership(soon, today + timedelta(days=3))
        far = self._member(self.gym_a, self.location_a, "Far")
        self._membership(far, today + timedelta(days=10))

        self._auth(self.owner_user)
        resp = self._expiring()
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        ids = [row["id"] for row in resp.data]
        self.assertIn(str(soon.id), ids)
        self.assertNotIn(str(far.id), ids)

    def test_member_expiring_today_appears_inclusive_with_zero_days(self):
        today = gym_today(self.gym_a)
        member = self._member(self.gym_a, self.location_a, "Today")
        self._membership(member, today)

        self._auth(self.owner_user)
        resp = self._expiring()
        row = next(r for r in resp.data if r["id"] == str(member.id))
        self.assertEqual(row["days_remaining"], 0)

    def test_expired_member_does_not_appear(self):
        today = gym_today(self.gym_a)
        member = self._member(self.gym_a, self.location_a, "Expired")
        self._membership(member, today - timedelta(days=1))

        self._auth(self.owner_user)
        resp = self._expiring()
        ids = [row["id"] for row in resp.data]
        self.assertNotIn(str(member.id), ids)

    def test_archived_member_does_not_appear(self):
        today = gym_today(self.gym_a)
        member = self._member(self.gym_a, self.location_a, "Archived", archived=True)
        self._membership(member, today + timedelta(days=3))

        self._auth(self.owner_user)
        resp = self._expiring()
        ids = [row["id"] for row in resp.data]
        self.assertNotIn(str(member.id), ids)

    def test_prospect_does_not_appear(self):
        today = gym_today(self.gym_a)
        prospect = self._member(
            self.gym_a, self.location_a, "Prospect", member_type=Member.PROSPECT,
        )
        self._membership(prospect, today + timedelta(days=3))

        self._auth(self.owner_user)
        resp = self._expiring()
        ids = [row["id"] for row in resp.data]
        self.assertNotIn(str(prospect.id), ids)

    def test_ordering_by_end_date_then_id_tiebreaker(self):
        today = gym_today(self.gym_a)
        shared_end = today + timedelta(days=5)
        # Created in reverse-id-ish order on purpose — the assertion below
        # only holds if the view actually orders by id, not insertion order.
        m2 = self._member(self.gym_a, self.location_a, "Tie2")
        self._membership(m2, shared_end)
        m1 = self._member(self.gym_a, self.location_a, "Tie1")
        self._membership(m1, shared_end)

        expected_order = sorted([str(m1.id), str(m2.id)])

        self._auth(self.owner_user)
        resp = self._expiring()
        tied_ids = [row["id"] for row in resp.data if row["id"] in expected_order]
        self.assertEqual(tied_ids, expected_order)

    def test_gym_only_sees_own_members(self):
        today = gym_today(self.gym_a)
        member_a = self._member(self.gym_a, self.location_a, "OnlyA")
        self._membership(member_a, today + timedelta(days=3))
        member_b = self._member(self.gym_b, self.location_b, "OnlyB")
        self._membership(member_b, today + timedelta(days=3), gym=self.gym_b,
                          plan=self.plan_b)

        self._auth(self.owner_user)
        resp = self._expiring()
        ids = [row["id"] for row in resp.data]
        self.assertIn(str(member_a.id), ids)
        self.assertNotIn(str(member_b.id), ids)

    def test_window_boundary_uses_gym_timezone_not_utc(self):
        # Asia/Manila is UTC+8 with no DST — picking a UTC instant late
        # in the day (20:00 UTC) means Manila's calendar date has
        # already advanced to the next day (04:00 the following
        # morning) while a raw UTC .date() would still read the
        # earlier date. gym_today(gym) must follow Manila, not UTC —
        # this proves it by checking days_remaining, not just presence
        # (a raw-UTC bug would still often keep the row "expiring",
        # just with the wrong day count).
        fixed_utc = datetime(2026, 3, 10, 20, 0, tzinfo=dt_timezone.utc)
        manila_today = fixed_utc.astimezone(ZoneInfo("Asia/Manila")).date()
        self.assertEqual(manila_today, date(2026, 3, 11))
        self.assertNotEqual(manila_today, fixed_utc.date())

        member = self._member(self.gym_a, self.location_a, "TzBoundary")
        self._membership(member, manila_today)

        with mock.patch("django.utils.timezone.now", return_value=fixed_utc):
            self._auth(self.owner_user)
            resp = self._expiring()

        row = next(r for r in resp.data if r["id"] == str(member.id))
        self.assertEqual(row["days_remaining"], 0)

    # ---- permissions ----

    def test_member_token_forbidden(self):
        Member.objects.create(
            gym=self.gym_a, home_location=self.location_a, first_name="Self",
            last_name="Member", email="renewalmembertoken@example.com",
            member_type=Member.MEMBER, user=self.member_token_user,
        )
        self._auth(self.member_token_user)
        resp = self._expiring()
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_non_owner_staff_can_view_worklist(self):
        staff_user = User.objects.create_user(
            email="renewalstaff@example.com", password="StrongPass123!",
            full_name="Renewal Staff")
        StaffProfile.objects.create(
            user=staff_user, gym=self.gym_a, role=StaffProfile.STAFF,
            default_location=self.location_a)
        self._auth(staff_user)
        resp = self._expiring()
        self.assertEqual(resp.status_code, status.HTTP_200_OK)


class RenewalReminderTestCase(APITestCase):
    """Part A — POST /members/{id}/remind/."""

    def setUp(self):
        self.gym = Gym.objects.create(name="Reminder Gym", slug="reminder-gym")
        self.location = Location.objects.create(gym=self.gym, name="Main")

        self.owner_user = User.objects.create_user(
            email="reminderowner@example.com", password="StrongPass123!",
            full_name="Reminder Owner")
        StaffProfile.objects.create(
            user=self.owner_user, gym=self.gym, role=StaffProfile.OWNER,
            default_location=self.location)

        self.staff_user = User.objects.create_user(
            email="reminderstaff@example.com", password="StrongPass123!",
            full_name="Reminder Staff")
        StaffProfile.objects.create(
            user=self.staff_user, gym=self.gym, role=StaffProfile.STAFF,
            default_location=self.location)

        self.member_token_user = User.objects.create_user(
            email="remindermembertoken@example.com", password="StrongPass123!",
            full_name="Member Token")

        self.plan = MembershipPlan.objects.create(
            gym=self.gym, name="Monthly", category="Regular",
            duration_value=1, duration_unit=MembershipPlan.MONTH,
            price="1000.00",
        )

        today = gym_today(self.gym)

        self.expiring_member = Member.objects.create(
            gym=self.gym, home_location=self.location, first_name="Expiring",
            last_name="Member", email="expiring@example.com",
            member_type=Member.MEMBER,
        )
        self.expiring_membership = Membership.objects.create(
            gym=self.gym, member=self.expiring_member, plan=self.plan,
            start_date=today - timedelta(days=27),
            end_date=today + timedelta(days=3),
        )

        self.active_member = Member.objects.create(
            gym=self.gym, home_location=self.location, first_name="Active",
            last_name="Member", email="active@example.com",
            member_type=Member.MEMBER,
        )
        Membership.objects.create(
            gym=self.gym, member=self.active_member, plan=self.plan,
            start_date=today, end_date=today + timedelta(days=30),
        )

        self.no_membership_member = Member.objects.create(
            gym=self.gym, home_location=self.location, first_name="Bare",
            last_name="Member", email="bare@example.com",
            member_type=Member.MEMBER,
        )

    def _auth(self, user):
        token = RefreshToken.for_user(user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token.access_token}")

    def _remind(self, member, body=None):
        return self.client.post(
            f"{API}/members/{member.id}/remind/", body or {}, format="json",
        )

    def test_marking_contacted_creates_record_against_current_membership(self):
        self._auth(self.owner_user)
        resp = self._remind(self.expiring_member, {"note": "Called, no answer"})
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)

        reminder = RenewalReminder.objects.get(member=self.expiring_member)
        self.assertEqual(reminder.membership_id, self.expiring_membership.id)
        self.assertEqual(reminder.contacted_by_id, self.owner_user.id)
        self.assertEqual(reminder.note, "Called, no answer")
        self.assertEqual(resp.data["contacted_by_name"], self.owner_user.full_name)

    def test_reminder_attaches_to_the_membership_the_guard_validated(self):
        # Independently re-derives "the current membership" via the same
        # latest-non-canceled-by-end_date shape the guard's own
        # current_membership_id annotation uses, rather than trusting
        # self.expiring_membership by test-setup coincidence — this is
        # what actually pins the reminder to the SAME row the guard's
        # membership_status check ran against, one query resolving
        # both, not two separate resolutions that a renewal landing
        # in between could pull apart.
        self._auth(self.owner_user)
        resp = self._remind(self.expiring_member)
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)

        guard_would_see = (
            Membership.objects
            .filter(member=self.expiring_member, canceled_at__isnull=True)
            .order_by("-end_date")
            .first()
        )
        reminder = RenewalReminder.objects.get(member=self.expiring_member)
        self.assertEqual(reminder.membership_id, guard_would_see.id)

    def test_worklist_reflects_latest_reminder_not_first(self):
        self._auth(self.owner_user)
        first = timezone.now() - timedelta(days=1)
        second = timezone.now()
        RenewalReminder.objects.create(
            gym=self.gym, member=self.expiring_member,
            membership=self.expiring_membership,
            contacted_at=first, contacted_by=self.owner_user,
        )
        RenewalReminder.objects.create(
            gym=self.gym, member=self.expiring_member,
            membership=self.expiring_membership,
            contacted_at=second, contacted_by=self.staff_user,
        )

        resp = self.client.get(f"{API}/members/expiring/")
        row = next(
            r for r in resp.data if r["id"] == str(self.expiring_member.id)
        )
        self.assertIsNotNone(row["reminder"])
        self.assertEqual(row["reminder"]["contacted_by"], self.staff_user.full_name)

    def test_second_reminder_on_same_membership_creates_second_record(self):
        self._auth(self.owner_user)
        self._remind(self.expiring_member)
        self._remind(self.expiring_member)
        self.assertEqual(
            RenewalReminder.objects.filter(
                membership=self.expiring_membership
            ).count(),
            2,
        )

    def test_member_with_no_current_membership_returns_400(self):
        self._auth(self.owner_user)
        resp = self._remind(self.no_membership_member)
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(
            RenewalReminder.objects.filter(member=self.no_membership_member).count(),
            0,
        )

    def test_member_not_in_expiring_window_returns_400(self):
        self._auth(self.owner_user)
        resp = self._remind(self.active_member)
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_renewal_starts_a_fresh_reminder_cycle(self):
        # A1's whole point: after renewal, the old reminder stays
        # attached to the old (now-superseded) membership, the member
        # leaves the worklist, and the new membership starts clean.
        self._auth(self.owner_user)
        self._remind(self.expiring_member)
        self.assertEqual(
            RenewalReminder.objects.filter(
                membership=self.expiring_membership
            ).count(),
            1,
        )

        new_membership = Membership.renew(
            self.expiring_member, self.plan, gym_today(self.gym),
            created_by=self.owner_user,
        )

        resp = self.client.get(f"{API}/members/expiring/")
        ids = [row["id"] for row in resp.data]
        self.assertNotIn(str(self.expiring_member.id), ids)
        self.assertEqual(new_membership.renewal_reminders.count(), 0)

    def test_duplicate_client_id_returns_400_not_a_second_record(self):
        self._auth(self.owner_user)
        fixed_id = str(uuid.uuid4())
        first = self._remind(self.expiring_member, {"id": fixed_id})
        self.assertEqual(first.status_code, status.HTTP_201_CREATED)

        second = self._remind(self.expiring_member, {"id": fixed_id})
        self.assertEqual(second.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("id", second.data)

        self.assertEqual(
            RenewalReminder.objects.filter(
                membership=self.expiring_membership
            ).count(),
            1,
        )

    # ---- permissions ----

    def test_member_token_forbidden(self):
        Member.objects.create(
            gym=self.gym, home_location=self.location, first_name="Self",
            last_name="Member", email="remindermembertoken@example.com",
            member_type=Member.MEMBER, user=self.member_token_user,
        )
        self._auth(self.member_token_user)
        resp = self._remind(self.expiring_member)
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_non_owner_staff_can_mark_contacted(self):
        self._auth(self.staff_user)
        resp = self._remind(self.expiring_member)
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
