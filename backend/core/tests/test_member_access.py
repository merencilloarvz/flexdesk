from datetime import timedelta

from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import RefreshToken
from core.models import CheckIn, Membership, MembershipPlan

from core.models import Gym, Location, Member, StaffProfile, User

API = "/api/v1"


class MemberAccessTestCase(APITestCase):
    """
    Stage 4.1 — the highest-value tests in this project. These prove a
    member cannot read staff-only data, cannot read another gym's data,
    and that the claim flow can't be used to fish for which emails
    belong to a gym member.
    """

    def setUp(self):
        # --- Gym A: owner, staff, one claimed member, one unclaimed member ---
        self.gym_a = Gym.objects.create(name="Gym A", slug="gym-a")
        self.location_a = Location.objects.create(gym=self.gym_a, name="Main")

        self.owner_a_user = User.objects.create_user(
            email="ownera@example.com", password="StrongPass123!", full_name="Owner A"
        )
        self.owner_a = StaffProfile.objects.create(
            user=self.owner_a_user, gym=self.gym_a, role=StaffProfile.OWNER,
            default_location=self.location_a,
        )

        self.staff_a_user = User.objects.create_user(
            email="staffa@example.com", password="StrongPass123!", full_name="Staff A"
        )
        self.staff_a = StaffProfile.objects.create(
            user=self.staff_a_user, gym=self.gym_a, role=StaffProfile.STAFF,
            default_location=self.location_a,
        )

        # Claimed member — has a User attached.
        self.member_a_user = User.objects.create_user(
            email="membera@example.com", password="StrongPass123!", full_name="Member A"
        )
        self.member_a = Member.objects.create(
            gym=self.gym_a, home_location=self.location_a,
            first_name="Member", last_name="A", email="membera@example.com",
            member_type=Member.MEMBER, user=self.member_a_user,
        )

        # Unclaimed member — has a valid, unexpired claim code, no User yet.
        self.unclaimed_code = "ABCD2345"
        self.unclaimed_member = Member.objects.create(
            gym=self.gym_a, home_location=self.location_a,
            first_name="Unclaimed", last_name="Member", email="unclaimed@example.com",
            member_type=Member.MEMBER, claim_code=self.unclaimed_code,
            claim_code_expires_at=timezone.now() + timedelta(days=30),
        )

        # Archived member — should never be claimable.
        self.archived_code = "WXYZ6789"
        self.archived_member = Member.objects.create(
            gym=self.gym_a, home_location=self.location_a,
            first_name="Archived", last_name="Member", email="archived@example.com",
            member_type=Member.MEMBER, claim_code=self.archived_code,
            claim_code_expires_at=timezone.now() + timedelta(days=30),
            archived_at=timezone.now(),
        )

        # Expired-code member.
        self.expired_code = "EXPI1234"
        self.expired_member = Member.objects.create(
            gym=self.gym_a, home_location=self.location_a,
            first_name="Expired", last_name="Code", email="expiredcode@example.com",
            member_type=Member.MEMBER, claim_code=self.expired_code,
            claim_code_expires_at=timezone.now() - timedelta(days=1),
        )

        # --- Gym B: owner, one claimed member ---
        self.gym_b = Gym.objects.create(name="Gym B", slug="gym-b")
        self.location_b = Location.objects.create(gym=self.gym_b, name="Main")

        self.owner_b_user = User.objects.create_user(
            email="ownerb@example.com", password="StrongPass123!", full_name="Owner B"
        )
        self.owner_b = StaffProfile.objects.create(
            user=self.owner_b_user, gym=self.gym_b, role=StaffProfile.OWNER,
            default_location=self.location_b,
        )

        self.member_b_user = User.objects.create_user(
            email="memberb@example.com", password="StrongPass123!", full_name="Member B"
        )
        self.member_b = Member.objects.create(
            gym=self.gym_b, home_location=self.location_b,
            first_name="Member", last_name="B", email="memberb@example.com",
            member_type=Member.MEMBER, user=self.member_b_user,
        )

    # ---- helpers ----

    def _auth(self, user):
        token = RefreshToken.for_user(user)
        self.client.credentials(
            HTTP_AUTHORIZATION=f"Bearer {token.access_token}"
        )

    def _clear_auth(self):
        self.client.credentials()

    # ======================================================================
    # Access control: a member's token against staff endpoints.
    # Every one of these must be non-2xx.
    # ======================================================================

    def test_member_cannot_list_members(self):
        self._auth(self.member_a_user)
        resp = self.client.get(f"{API}/members/")
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_member_cannot_retrieve_own_member_row_via_staff_endpoint(self):
        # Deliberately in this list: a member reading their own row through
        # the staff endpoint is still the staff endpoint. Their own data
        # comes from /me/ routes in 4.2, not here.
        self._auth(self.member_a_user)
        resp = self.client.get(f"{API}/members/{self.member_a.id}/")
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_member_cannot_retrieve_other_member_in_own_gym(self):
        self._auth(self.member_a_user)
        resp = self.client.get(f"{API}/members/{self.unclaimed_member.id}/")
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_member_cannot_create_member(self):
        self._auth(self.member_a_user)
        resp = self.client.post(f"{API}/members/", {
            "first_name": "New", "last_name": "Person",
        })
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_member_cannot_list_staff(self):
        self._auth(self.member_a_user)
        resp = self.client.get(f"{API}/staff/")
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_member_cannot_create_staff(self):
        self._auth(self.member_a_user)
        resp = self.client.post(f"{API}/staff/", {
            "full_name": "New Staff", "email": "newstaff@example.com",
            "password": "StrongPass123!",
        })
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_member_cannot_list_plans(self):
        self._auth(self.member_a_user)
        resp = self.client.get(f"{API}/plans/")
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_member_cannot_create_plan(self):
        self._auth(self.member_a_user)
        resp = self.client.post(f"{API}/plans/", {
            "name": "New Plan", "duration_value": 1, "duration_unit": "MONTH",
            "price": "1000.00",
        })
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_member_cannot_list_check_ins(self):
        self._auth(self.member_a_user)
        resp = self.client.get(f"{API}/check-ins/")
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_member_cannot_create_check_in(self):
        self._auth(self.member_a_user)
        resp = self.client.post(f"{API}/check-ins/", {
            "visit_type": "MEMBER", "member": str(self.member_a.id),
        })
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_member_cannot_issue_claim_code(self):
        self._auth(self.member_a_user)
        resp = self.client.post(f"{API}/members/{self.unclaimed_member.id}/claim-code/")
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    # ======================================================================
    # Cross-tenant
    # ======================================================================

    def test_gym_b_member_cannot_access_gym_a_member(self):
        self._auth(self.member_b_user)
        resp = self.client.get(f"{API}/members/{self.member_a.id}/")
        self.assertIn(
            resp.status_code,
            (status.HTTP_403_FORBIDDEN, status.HTTP_404_NOT_FOUND),
        )
        self.assertNotEqual(resp.status_code, status.HTTP_200_OK)

    def test_gym_a_staff_cannot_access_gym_b_member(self):
        self._auth(self.staff_a_user)
        resp = self.client.get(f"{API}/members/{self.member_b.id}/")
        self.assertEqual(resp.status_code, status.HTTP_404_NOT_FOUND)

    # ======================================================================
    # Claim flow
    # ======================================================================

    def test_claim_with_valid_code_succeeds(self):
        resp = self.client.post(f"{API}/auth/claim/", {
            "email": "unclaimed@example.com",
            "claim_code": self.unclaimed_code,
            "password": "AnotherStrongPass123!",
        })
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertIn("access", resp.data)
        self.assertIn("refresh", resp.data)
        self.assertIn("user", resp.data)

        self.unclaimed_member.refresh_from_db()
        self.assertIsNotNone(self.unclaimed_member.user_id)
        self.assertEqual(self.unclaimed_member.claim_code, "")
        self.assertIsNone(self.unclaimed_member.claim_code_expires_at)

    def test_claim_code_cannot_be_reused(self):
        first = self.client.post(f"{API}/auth/claim/", {
            "email": "unclaimed@example.com",
            "claim_code": self.unclaimed_code,
            "password": "AnotherStrongPass123!",
        })
        self.assertEqual(first.status_code, status.HTTP_201_CREATED)

        second = self.client.post(f"{API}/auth/claim/", {
            "email": "unclaimed@example.com",
            "claim_code": self.unclaimed_code,
            "password": "YetAnotherStrongPass123!",
        })
        self.assertEqual(second.status_code, status.HTTP_400_BAD_REQUEST)

    def test_wrong_code_and_unknown_email_return_identical_response(self):
        wrong_code_resp = self.client.post(f"{API}/auth/claim/", {
            "email": "unclaimed@example.com",
            "claim_code": "WRONGCOD",
            "password": "StrongPass123!",
        })
        unknown_email_resp = self.client.post(f"{API}/auth/claim/", {
            "email": "doesnotexist@example.com",
            "claim_code": self.unclaimed_code,
            "password": "StrongPass123!",
        })

        self.assertEqual(wrong_code_resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(unknown_email_resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(wrong_code_resp.data, unknown_email_resp.data)

    def test_expired_code_rejected(self):
        resp = self.client.post(f"{API}/auth/claim/", {
            "email": "expiredcode@example.com",
            "claim_code": self.expired_code,
            "password": "StrongPass123!",
        })
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_weak_password_rejected(self):
        resp = self.client.post(f"{API}/auth/claim/", {
            "email": "unclaimed@example.com",
            "claim_code": self.unclaimed_code,
            "password": "123",
        })
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("password", resp.data)

    def test_claim_with_email_already_belonging_to_existing_user(self):
        clashing_member = Member.objects.create(
            gym=self.gym_a, home_location=self.location_a,
            first_name="Clash", last_name="Test", email="membera@example.com",
            member_type=Member.MEMBER, claim_code="CLASH123",
            claim_code_expires_at=timezone.now() + timedelta(days=30),
        )
        resp = self.client.post(f"{API}/auth/claim/", {
            "email": "membera@example.com",
            "claim_code": "CLASH123",
            "password": "StrongPass123!",
        })
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("already exists", str(resp.data).lower())

    def test_archived_member_code_rejected(self):
        resp = self.client.post(f"{API}/auth/claim/", {
            "email": "archived@example.com",
            "claim_code": self.archived_code,
            "password": "StrongPass123!",
        })
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    # ======================================================================
    # Auth shape
    # ======================================================================

    def test_me_as_member(self):
        self._auth(self.member_a_user)
        resp = self.client.get(f"{API}/auth/me/")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data["account_type"], "member")
        self.assertIsNone(resp.data["role"])
        self.assertIsNotNone(resp.data["gym"])
        self.assertEqual(resp.data["gym"]["id"], str(self.gym_a.id))

    def test_me_as_staff(self):
        self._auth(self.staff_a_user)
        resp = self.client.get(f"{API}/auth/me/")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data["account_type"], "staff")
        self.assertEqual(resp.data["role"], "staff")
        self.assertIsNotNone(resp.data["gym"])

    # ======================================================================
    # Stage 4.2 — /me/ endpoints
    # ======================================================================

    # ---- Access control ----

    def test_me_summary_staff_forbidden(self):
        self._auth(self.staff_a_user)
        resp = self.client.get(f"{API}/me/summary/")
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_me_membership_staff_forbidden(self):
        self._auth(self.staff_a_user)
        resp = self.client.get(f"{API}/me/membership/")
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_me_check_ins_staff_forbidden(self):
        self._auth(self.staff_a_user)
        resp = self.client.get(f"{API}/me/check-ins/")
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_me_summary_owner_forbidden(self):
        self._auth(self.owner_a_user)
        resp = self.client.get(f"{API}/me/summary/")
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_me_membership_owner_forbidden(self):
        self._auth(self.owner_a_user)
        resp = self.client.get(f"{API}/me/membership/")
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_me_check_ins_owner_forbidden(self):
        self._auth(self.owner_a_user)
        resp = self.client.get(f"{API}/me/check-ins/")
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_me_summary_unauthenticated(self):
        self._clear_auth()
        resp = self.client.get(f"{API}/me/summary/")
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_me_membership_unauthenticated(self):
        self._clear_auth()
        resp = self.client.get(f"{API}/me/membership/")
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_me_check_ins_unauthenticated(self):
        self._clear_auth()
        resp = self.client.get(f"{API}/me/check-ins/")
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_me_summary_member_ok(self):
        self._auth(self.member_a_user)
        resp = self.client.get(f"{API}/me/summary/")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

    def test_me_membership_member_ok(self):
        self._auth(self.member_a_user)
        resp = self.client.get(f"{API}/me/membership/")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

    def test_me_check_ins_member_ok(self):
        self._auth(self.member_a_user)
        resp = self.client.get(f"{API}/me/check-ins/")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

    # ---- Isolation ----

    def test_me_check_ins_isolated_between_gyms(self):
        loc_a = self.location_a
        loc_b = self.location_b

        checkin_a = CheckIn.objects.create(
            gym=self.gym_a, member=self.member_a, visit_type=CheckIn.MEMBER,
            location=loc_a, checked_in_at=timezone.now(),
            membership_status="no_membership",
        )
        checkin_b = CheckIn.objects.create(
            gym=self.gym_b, member=self.member_b, visit_type=CheckIn.MEMBER,
            location=loc_b, checked_in_at=timezone.now(),
            membership_status="no_membership",
        )

        self._auth(self.member_a_user)
        resp_a = self.client.get(f"{API}/me/check-ins/")
        ids_a = {row["id"] for row in resp_a.data["results"]}
        self.assertIn(str(checkin_a.id), ids_a)
        self.assertNotIn(str(checkin_b.id), ids_a)

        self._auth(self.member_b_user)
        resp_b = self.client.get(f"{API}/me/check-ins/")
        ids_b = {row["id"] for row in resp_b.data["results"]}
        self.assertIn(str(checkin_b.id), ids_b)
        self.assertNotIn(str(checkin_a.id), ids_b)

    def test_me_check_ins_isolated_between_members_same_gym(self):
        # Give member_a's "sibling" (a second claimed member in gym A) a
        # check-in on the same day, then confirm member_a's own list
        # contains none of it.
        second_member_user = User.objects.create_user(
            email="secondmember@example.com", password="StrongPass123!",
            full_name="Second Member",
        )
        second_member = Member.objects.create(
            gym=self.gym_a, home_location=self.location_a,
            first_name="Second", last_name="Member",
            email="secondmember@example.com", member_type=Member.MEMBER,
            user=second_member_user,
        )

        own_checkin = CheckIn.objects.create(
            gym=self.gym_a, member=self.member_a, visit_type=CheckIn.MEMBER,
            location=self.location_a, checked_in_at=timezone.now(),
            membership_status="no_membership",
        )
        other_checkin = CheckIn.objects.create(
            gym=self.gym_a, member=second_member, visit_type=CheckIn.MEMBER,
            location=self.location_a, checked_in_at=timezone.now(),
            membership_status="no_membership",
        )

        self._auth(self.member_a_user)
        resp = self.client.get(f"{API}/me/check-ins/")
        ids = {row["id"] for row in resp.data["results"]}
        self.assertIn(str(own_checkin.id), ids)
        self.assertNotIn(str(other_checkin.id), ids)

    def test_me_summary_no_membership_returns_clean_defaults(self):
        # member_a has no Membership row at all in the fixture.
        self._auth(self.member_a_user)
        resp = self.client.get(f"{API}/me/summary/")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data["membership_status"], "no_membership")
        self.assertIsNone(resp.data["current_end_date"])
        self.assertIsNone(resp.data["days_remaining"])

    # ---- Correctness ----

    def test_voided_check_in_excluded_from_me_check_ins_and_summary(self):
        voided = CheckIn.objects.create(
            gym=self.gym_a, member=self.member_a, visit_type=CheckIn.MEMBER,
            location=self.location_a, checked_in_at=timezone.now(),
            membership_status="no_membership", voided_at=timezone.now(),
        )

        self._auth(self.member_a_user)

        list_resp = self.client.get(f"{API}/me/check-ins/")
        ids = {row["id"] for row in list_resp.data["results"]}
        self.assertNotIn(str(voided.id), ids)

        summary_resp = self.client.get(f"{API}/me/summary/")
        self.assertEqual(summary_resp.data["check_ins_this_month"], 0)
        self.assertIsNone(summary_resp.data["last_check_in_at"])

    def test_member_summary_status_matches_owner_view(self):
        # Give member_a an active membership, then compare the status
        # the member sees about themselves against the status the owner
        # sees for the same member via the staff endpoint. Same
        # with_status() code path on both sides — this test is what
        # proves that, rather than assuming it.
        plan = MembershipPlan.objects.create(
            gym=self.gym_a, name="Monthly", category="Regular",
            duration_value=1, duration_unit=MembershipPlan.MONTH,
            price="1000.00",
        )
        Membership.objects.create(
            gym=self.gym_a, member=self.member_a, plan=plan,
            start_date=timezone.now().date(),
            created_by=self.owner_a_user,
        )

        self._auth(self.member_a_user)
        member_resp = self.client.get(f"{API}/me/summary/")
        self.assertEqual(member_resp.status_code, status.HTTP_200_OK)

        self._auth(self.owner_a_user)
        owner_detail_resp = self.client.get(f"{API}/members/{self.member_a.id}/")
        self.assertEqual(owner_detail_resp.status_code, status.HTTP_200_OK)

        self.assertEqual(
            member_resp.data["membership_status"],
            owner_detail_resp.data["membership_status"],
        )

    def test_archived_member_gets_200_with_is_archived_true(self):
        self.member_a.archived_at = timezone.now()
        self.member_a.save(update_fields=["archived_at"])

        self._auth(self.member_a_user)
        resp = self.client.get(f"{API}/me/summary/")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertTrue(resp.data["is_archived"])

    # ---- Privacy ----

    def test_me_summary_never_contains_notes_key(self):
        self._auth(self.member_a_user)
        resp = self.client.get(f"{API}/me/summary/")
        self.assertNotIn("notes", resp.data)