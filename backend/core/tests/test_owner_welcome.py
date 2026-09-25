from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import RefreshToken

from core.models import Gym, Location, StaffProfile, User

API = "/api/v1"

SIGNUP_PAYLOAD = {
    "gym_name": "Welcome Gym",
    "full_name": "Welcome Owner",
    "email": "welcomeowner@example.com",
    "password": "StrongPass123!",
}


def _auth(client, user):
    token = RefreshToken.for_user(user)
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {token.access_token}")


class OwnerWelcomeSignupTests(APITestCase):
    """A brand-new owner must start out never having seen the welcome
    flow — confirmed from both the signup response and a fresh login,
    the same two places every other session-state field is checked."""

    def test_new_owner_has_not_seen_welcome(self):
        resp = self.client.post(f"{API}/auth/signup/", SIGNUP_PAYLOAD, format="json")
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertFalse(resp.data["user"]["has_seen_owner_welcome"])

    def test_login_after_signup_still_reports_unseen(self):
        self.client.post(f"{API}/auth/signup/", SIGNUP_PAYLOAD, format="json")
        resp = self.client.post(f"{API}/auth/login/", {
            "email": SIGNUP_PAYLOAD["email"], "password": SIGNUP_PAYLOAD["password"],
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertFalse(resp.data["user"]["has_seen_owner_welcome"])


class OwnerWelcomeSeenViewTests(APITestCase):
    def setUp(self):
        self.gym = Gym.objects.create(name="Seen Gym", slug="seen-gym")
        self.location = Location.objects.create(gym=self.gym, name="Main")

        self.owner_user = User.objects.create_user(
            email="owner@example.com", password="StrongPass123!", full_name="Owner")
        StaffProfile.objects.create(
            user=self.owner_user, gym=self.gym, role=StaffProfile.OWNER,
            default_location=self.location)

        self.staff_user = User.objects.create_user(
            email="staff@example.com", password="StrongPass123!", full_name="Staff")
        StaffProfile.objects.create(
            user=self.staff_user, gym=self.gym, role=StaffProfile.STAFF,
            default_location=self.location)

    def test_owner_can_mark_it_seen(self):
        _auth(self.client, self.owner_user)
        resp = self.client.post(f"{API}/auth/owner-welcome-seen/")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertTrue(resp.data["has_seen_owner_welcome"])

        self.owner_user.refresh_from_db()
        self.assertTrue(self.owner_user.has_seen_owner_welcome)

    def test_it_sticks_across_requests(self):
        _auth(self.client, self.owner_user)
        self.client.post(f"{API}/auth/owner-welcome-seen/")

        resp = self.client.get(f"{API}/auth/me/")
        self.assertTrue(resp.data["has_seen_owner_welcome"])

    def test_cannot_be_unset(self):
        # There is no "unsee" endpoint at all — the only way to flip the
        # column is direct DB access, which this proves stays put even
        # across repeated calls to the one endpoint that exists.
        _auth(self.client, self.owner_user)
        self.client.post(f"{API}/auth/owner-welcome-seen/")
        self.owner_user.refresh_from_db()
        self.assertTrue(self.owner_user.has_seen_owner_welcome)

        second = self.client.post(f"{API}/auth/owner-welcome-seen/")
        self.assertEqual(second.status_code, status.HTTP_200_OK)
        self.assertTrue(second.data["has_seen_owner_welcome"])
        self.owner_user.refresh_from_db()
        self.assertTrue(self.owner_user.has_seen_owner_welcome)

    def test_staff_cannot_mark_it_seen(self):
        _auth(self.client, self.staff_user)
        resp = self.client.post(f"{API}/auth/owner-welcome-seen/")
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_requires_authentication(self):
        resp = self.client.post(f"{API}/auth/owner-welcome-seen/")
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_second_owner_of_a_different_gym_still_sees_it(self):
        # One owner marking theirs seen must never affect another.
        _auth(self.client, self.owner_user)
        self.client.post(f"{API}/auth/owner-welcome-seen/")

        other_gym = Gym.objects.create(name="Other Gym", slug="other-welcome-gym")
        other_location = Location.objects.create(gym=other_gym, name="Main")
        other_owner = User.objects.create_user(
            email="otherowner@example.com", password="StrongPass123!", full_name="Other Owner")
        StaffProfile.objects.create(
            user=other_owner, gym=other_gym, role=StaffProfile.OWNER,
            default_location=other_location)

        self.assertFalse(other_owner.has_seen_owner_welcome)

        resp = self.client.get(f"{API}/auth/me/")  # still owner_user's session
        self.assertTrue(resp.data["has_seen_owner_welcome"])

    def test_a_second_signup_for_a_different_owner_still_sees_it(self):
        # Same guarantee, via the real signup path rather than ORM setup.
        _auth(self.client, self.owner_user)
        self.client.post(f"{API}/auth/owner-welcome-seen/")

        resp = self.client.post(f"{API}/auth/signup/", {
            "gym_name": "Second New Gym", "full_name": "Second Owner",
            "email": "secondowner@example.com", "password": "StrongPass123!",
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertFalse(resp.data["user"]["has_seen_owner_welcome"])


class BackfillMigrationTests(APITestCase):
    """0028: owners who already have a gym are marked as having seen the
    welcome flow; staff and gym-less users are left alone."""

    def _run_backfill(self):
        import importlib
        from django.apps import apps

        mod = importlib.import_module("core.migrations.0028_backfill_owner_welcome_seen")
        mod.mark_existing_owners_as_seen(apps, None)

    def test_existing_owner_marked_seen_but_staff_and_gymless_untouched(self):
        gym = Gym.objects.create(name="Old Gym")
        owner = User.objects.create_user(email="old@example.com", password="StrongPass123!", full_name="Old")
        StaffProfile.objects.create(user=owner, gym=gym, role=StaffProfile.OWNER)
        staff = User.objects.create_user(email="staff@example.com", password="StrongPass123!", full_name="S")
        StaffProfile.objects.create(user=staff, gym=gym, role=StaffProfile.STAFF)
        gymless = User.objects.create_user(email="none@example.com", password="StrongPass123!", full_name="N")

        self._run_backfill()

        for u in (owner, staff, gymless):
            u.refresh_from_db()
        self.assertTrue(owner.has_seen_owner_welcome)
        self.assertFalse(staff.has_seen_owner_welcome)
        self.assertFalse(gymless.has_seen_owner_welcome)

    def test_signup_after_backfill_still_sees_welcome(self):
        self._run_backfill()  # runs at migrate time only, before this signup
        resp = self.client.post(f"{API}/auth/signup/", SIGNUP_PAYLOAD, format="json")
        self.assertFalse(resp.data["user"]["has_seen_owner_welcome"])


class StaffCreatedAccountsSkipWelcomeTests(APITestCase):
    """A person added through Add staff (either role) was not just signed
    up for a gym, so the owner welcome flow must not be sent to them."""

    def setUp(self):
        self.gym = Gym.objects.create(name="Team Gym", slug="team-gym")
        self.location = Location.objects.create(gym=self.gym, name="Main")
        self.owner = User.objects.create_user(
            email="boss@example.com", password="StrongPass123!", full_name="Boss")
        StaffProfile.objects.create(
            user=self.owner, gym=self.gym, role=StaffProfile.OWNER,
            default_location=self.location)
        _auth(self.client, self.owner)

    def _add(self, email, role):
        return self.client.post(f"{API}/staff/", {
            "full_name": "New Person", "email": email,
            "password": "StrongPass123!", "role": role,
        }, format="json")

    def test_staff_role_created_via_add_staff_has_seen_welcome(self):
        resp = self._add("desk@example.com", "staff")
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertTrue(User.objects.get(email="desk@example.com").has_seen_owner_welcome)

    def test_second_owner_created_via_add_staff_has_seen_welcome(self):
        resp = self._add("coowner@example.com", "owner")
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertTrue(User.objects.get(email="coowner@example.com").has_seen_owner_welcome)

    def test_login_of_added_owner_reports_seen(self):
        self._add("coowner2@example.com", "owner")
        self.client.credentials()
        resp = self.client.post(f"{API}/auth/login/", {
            "email": "coowner2@example.com", "password": "StrongPass123!",
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertTrue(resp.data["user"]["has_seen_owner_welcome"])
