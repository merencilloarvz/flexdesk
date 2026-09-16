from django.contrib.admin.models import CHANGE, LogEntry
from rest_framework import status
from rest_framework.test import APITestCase

from core.models import Gym, Location, Member, StaffProfile, User
from core.utils import CLAIM_ALPHABET

API = "/api/v1"


class MemberPasswordResetTestCase(APITestCase):
    """
    Front-desk "forgot password" — staff or owner reset a member's
    password in person and read the new temp password out to them. See
    qr_secret_reset (test_qr.py) for the sibling front-desk reset action
    this one is modelled on; the key difference is this one is open to
    plain staff too, not owner-only.
    """

    def setUp(self):
        self.gym_a = Gym.objects.create(name="Gym A", slug="pwreset-gym-a")
        self.location_a = Location.objects.create(gym=self.gym_a, name="Main")

        self.owner_user = User.objects.create_user(
            email="pwowner@example.com", password="StrongPass123!", full_name="Owner")
        self.owner = StaffProfile.objects.create(
            user=self.owner_user, gym=self.gym_a, role=StaffProfile.OWNER,
            default_location=self.location_a)

        self.staff_user = User.objects.create_user(
            email="pwstaff@example.com", password="StrongPass123!", full_name="Staff")
        self.staff = StaffProfile.objects.create(
            user=self.staff_user, gym=self.gym_a, role=StaffProfile.STAFF,
            default_location=self.location_a)

        self.member_user = User.objects.create_user(
            email="pwmember@example.com", password="StrongPass123!", full_name="PW Member")
        self.member = Member.objects.create(
            gym=self.gym_a, home_location=self.location_a, first_name="PW",
            last_name="Member", email="pwmember@example.com",
            member_type=Member.MEMBER, user=self.member_user,
        )

        self.unclaimed_member = Member.objects.create(
            gym=self.gym_a, home_location=self.location_a, first_name="Unclaimed",
            last_name="Member", email="pwunclaimed@example.com",
            member_type=Member.MEMBER,
        )

        self.gym_b = Gym.objects.create(name="Gym B", slug="pwreset-gym-b")
        self.location_b = Location.objects.create(gym=self.gym_b, name="Main")
        self.owner_b_user = User.objects.create_user(
            email="pwownerb@example.com", password="StrongPass123!", full_name="Owner B")
        StaffProfile.objects.create(
            user=self.owner_b_user, gym=self.gym_b, role=StaffProfile.OWNER,
            default_location=self.location_b)
        self.member_b_user = User.objects.create_user(
            email="pwmemberb@example.com", password="StrongPass123!", full_name="Member B")
        self.member_b = Member.objects.create(
            gym=self.gym_b, home_location=self.location_b, first_name="Member",
            last_name="B", email="pwmemberb@example.com",
            member_type=Member.MEMBER, user=self.member_b_user,
        )

    # ---- helpers ----

    def _auth(self, user):
        from rest_framework_simplejwt.tokens import RefreshToken
        token = RefreshToken.for_user(user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token.access_token}")

    def _reset(self, member):
        return self.client.post(f"{API}/members/{member.id}/reset-password/")

    # ======================================================================

    def test_staff_can_reset_member_password(self):
        self._auth(self.staff_user)
        resp = self._reset(self.member)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

        temp_password = resp.data["temp_password"]
        self.assertTrue(temp_password)
        self.assertTrue(all(c in CLAIM_ALPHABET for c in temp_password))

        self.member_user.refresh_from_db()
        self.assertTrue(self.member_user.must_change_password)
        self.assertTrue(self.member_user.check_password(temp_password))

    def test_owner_can_reset_member_password(self):
        self._auth(self.owner_user)
        resp = self._reset(self.member)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

    def test_member_forbidden_from_reset(self):
        self._auth(self.member_user)
        resp = self._reset(self.member)
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_unclaimed_member_returns_400(self):
        self._auth(self.staff_user)
        resp = self._reset(self.unclaimed_member)
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_cross_gym_member_returns_404(self):
        self._auth(self.staff_user)
        resp = self._reset(self.member_b)
        self.assertEqual(resp.status_code, status.HTTP_404_NOT_FOUND)

    def test_temp_password_is_never_reused(self):
        # Not a real collision check — just confirms two resets in a row
        # generate independent passwords rather than something derived
        # from a fixed seed.
        self._auth(self.staff_user)
        first = self._reset(self.member).data["temp_password"]
        second = self._reset(self.member).data["temp_password"]
        self.assertNotEqual(first, second)

    def test_reset_writes_admin_log_entry(self):
        self._auth(self.staff_user)
        self._reset(self.member)

        entry = LogEntry.objects.filter(
            user_id=self.staff_user.pk, action_flag=CHANGE,
            object_id=str(self.member.pk),
        ).first()
        self.assertIsNotNone(entry)
        self.assertEqual(entry.object_repr, str(self.member))
