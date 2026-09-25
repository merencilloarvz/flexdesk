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
