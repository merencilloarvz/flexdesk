from datetime import timedelta
from unittest import mock

from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from core.google_auth import GoogleTokenError, verify_google_id_token
from core.models import Gym, Location, Member, StaffProfile, User

API = "/api/v1"


def _google_payload(sub="google-sub-1", email="person@example.com",
                    email_verified=True, full_name="Person Test"):
    return (sub, email, email_verified, full_name)


class VerifyGoogleIdTokenTests(TestCase):
    """
    Exercises the real (unmocked) verification function — everything
    else in this file mocks it out, so this is the only coverage that
    the function itself actually rejects what it should.
    """

    @override_settings(GOOGLE_OAUTH_CLIENT_ID="")
    def test_unconfigured_client_id_refuses(self):
        with self.assertRaises(GoogleTokenError):
            verify_google_id_token("anything")

    @override_settings(GOOGLE_OAUTH_CLIENT_ID="some-client-id")
    def test_malformed_token_is_rejected(self):
        # Never reaches the network — the library rejects a token that
        # isn't even well-formed JWT before fetching Google's certs.
        with self.assertRaises(GoogleTokenError):
            verify_google_id_token("not-a-real-token")


@mock.patch("core.serializers.verify_google_id_token")
class GoogleLoginViewTests(APITestCase):
    def setUp(self):
        self.gym = Gym.objects.create(name="Google Gym", slug="google-gym")
        self.location = Location.objects.create(gym=self.gym, name="Main")

        self.owner_user = User.objects.create_user(
            email="owner@example.com", password="StrongPass123!", full_name="Owner")
        StaffProfile.objects.create(
            user=self.owner_user, gym=self.gym, role=StaffProfile.OWNER,
            default_location=self.location)

        self.member_user = User.objects.create_user(
            email="member@example.com", password="StrongPass123!", full_name="Claimed Member")
        Member.objects.create(
            gym=self.gym, home_location=self.location, first_name="Claimed",
            last_name="Member", email="member@example.com",
            member_type=Member.MEMBER, user=self.member_user)

    def test_unverified_email_is_refused(self, mock_verify):
        mock_verify.return_value = _google_payload(
            email="owner@example.com", email_verified=False)
        resp = self.client.post(f"{API}/auth/google/login/",
                                {"id_token": "tok"}, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("verified", str(resp.data).lower())

    def test_rejected_token_returns_400(self, mock_verify):
        mock_verify.side_effect = GoogleTokenError("That Google sign-in couldn't be verified.")
        resp = self.client.post(f"{API}/auth/google/login/",
                                {"id_token": "bad"}, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_existing_owner_matched_by_email_logs_in_and_links(self, mock_verify):
        mock_verify.return_value = _google_payload(
            sub="owner-sub", email="owner@example.com")
        resp = self.client.post(f"{API}/auth/google/login/",
                                {"id_token": "tok"}, format="json")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertIn("access", resp.data)
        self.assertEqual(resp.data["user"]["email"], "owner@example.com")
        self.owner_user.refresh_from_db()
        self.assertEqual(self.owner_user.google_sub, "owner-sub")
        # Linking Google must not disturb the existing password.
        self.assertTrue(self.owner_user.has_usable_password())
        self.assertTrue(self.owner_user.check_password("StrongPass123!"))

    def test_existing_claimed_member_logs_in(self, mock_verify):
        mock_verify.return_value = _google_payload(
            sub="member-sub", email="member@example.com")
        resp = self.client.post(f"{API}/auth/google/login/",
                                {"id_token": "tok"}, format="json")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data["user"]["account_type"], "member")

    def test_already_linked_google_sub_logs_in_without_relinking(self, mock_verify):
        self.owner_user.google_sub = "owner-sub"
        self.owner_user.save(update_fields=["google_sub"])
        mock_verify.return_value = _google_payload(
            sub="owner-sub", email="owner@example.com")
        resp = self.client.post(f"{API}/auth/google/login/",
                                {"id_token": "tok"}, format="json")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

    def test_no_matching_account_returns_404(self, mock_verify):
        mock_verify.return_value = _google_payload(
            sub="new-sub", email="nobody@example.com")
        resp = self.client.post(f"{API}/auth/google/login/",
                                {"id_token": "tok"}, format="json")
        self.assertEqual(resp.status_code, status.HTTP_404_NOT_FOUND)

    def test_google_account_linked_to_different_user_is_refused(self, mock_verify):
        # owner_user is linked to a different Google sub than the one
        # signing in now, but shares the same email.
        self.owner_user.google_sub = "someone-elses-sub"
        self.owner_user.save(update_fields=["google_sub"])
        mock_verify.return_value = _google_payload(
            sub="this-attempt-sub", email="owner@example.com")
        resp = self.client.post(f"{API}/auth/google/login/",
                                {"id_token": "tok"}, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("different", str(resp.data).lower())
        self.owner_user.refresh_from_db()
        # Never silently reassigned.
        self.assertEqual(self.owner_user.google_sub, "someone-elses-sub")


@mock.patch("core.serializers.verify_google_id_token")
class GoogleSignupViewTests(APITestCase):
    def test_creates_gym_and_owner_without_password(self, mock_verify):
        mock_verify.return_value = _google_payload(
            sub="new-owner-sub", email="neverdergym@example.com", full_name="New Owner")
        resp = self.client.post(f"{API}/auth/google/signup/", {
            "id_token": "tok", "gym_name": "Never Der Gym",
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data["user"]["role"], "owner")

        user = User.objects.get(email="neverdergym@example.com")
        self.assertEqual(user.google_sub, "new-owner-sub")
        self.assertFalse(user.has_usable_password())
        self.assertEqual(user.full_name, "New Owner")
        self.assertTrue(Gym.objects.filter(name="Never Der Gym").exists())

    def test_existing_email_is_refused(self, mock_verify):
        User.objects.create_user(
            email="taken@example.com", password="StrongPass123!", full_name="Taken")
        mock_verify.return_value = _google_payload(
            sub="dup-sub", email="taken@example.com")
        resp = self.client.post(f"{API}/auth/google/signup/", {
            "id_token": "tok", "gym_name": "Some Gym",
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("already exists", str(resp.data).lower())

    def test_unverified_email_is_refused(self, mock_verify):
        mock_verify.return_value = _google_payload(
            email="unverified@example.com", email_verified=False)
        resp = self.client.post(f"{API}/auth/google/signup/", {
            "id_token": "tok", "gym_name": "Some Gym",
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)


@mock.patch("core.serializers.verify_google_id_token")
class GoogleClaimViewTests(APITestCase):
    def setUp(self):
        self.gym = Gym.objects.create(name="Claim Gym", slug="google-claim-gym")
        self.location = Location.objects.create(gym=self.gym, name="Main")
        self.claim_code = "ABCD2345"
        self.unclaimed_member = Member.objects.create(
            gym=self.gym, home_location=self.location, first_name="Unclaimed",
            last_name="Member", email="unclaimed@example.com",
            member_type=Member.MEMBER, claim_code=self.claim_code,
            claim_code_expires_at=timezone.now() + timedelta(days=30),
        )

    def test_valid_code_links_google_account_without_password(self, mock_verify):
        mock_verify.return_value = _google_payload(
            sub="member-sub", email="unclaimed@example.com")
        resp = self.client.post(f"{API}/auth/google/claim/", {
            "id_token": "tok", "claim_code": self.claim_code,
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)

        self.unclaimed_member.refresh_from_db()
        self.assertIsNotNone(self.unclaimed_member.user)
        user = self.unclaimed_member.user
        self.assertEqual(user.google_sub, "member-sub")
        self.assertFalse(user.has_usable_password())
        self.assertEqual(self.unclaimed_member.claim_code, "")
        self.assertIsNone(self.unclaimed_member.claim_code_expires_at)

    def test_wrong_code_gives_generic_error(self, mock_verify):
        mock_verify.return_value = _google_payload(email="unclaimed@example.com")
        resp = self.client.post(f"{API}/auth/google/claim/", {
            "id_token": "tok", "claim_code": "WRONGCODE",
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("don't match", str(resp.data))

    def test_email_not_matching_any_unclaimed_member_gives_generic_error(self, mock_verify):
        mock_verify.return_value = _google_payload(email="someoneelse@example.com")
        resp = self.client.post(f"{API}/auth/google/claim/", {
            "id_token": "tok", "claim_code": self.claim_code,
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("don't match", str(resp.data))

    def test_expired_code_gives_generic_error(self, mock_verify):
        expired = Member.objects.create(
            gym=self.gym, home_location=self.location, first_name="Expired",
            last_name="Code", email="expired@example.com",
            member_type=Member.MEMBER, claim_code="EXPI1234",
            claim_code_expires_at=timezone.now() - timedelta(days=1),
        )
        mock_verify.return_value = _google_payload(email="expired@example.com")
        resp = self.client.post(f"{API}/auth/google/claim/", {
            "id_token": "tok", "claim_code": "EXPI1234",
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("don't match", str(resp.data))

    def test_archived_member_gives_generic_error(self, mock_verify):
        Member.objects.create(
            gym=self.gym, home_location=self.location, first_name="Archived",
            last_name="Member", email="archived@example.com",
            member_type=Member.MEMBER, claim_code="ARCH1234",
            claim_code_expires_at=timezone.now() + timedelta(days=30),
            archived_at=timezone.now(),
        )
        mock_verify.return_value = _google_payload(email="archived@example.com")
        resp = self.client.post(f"{API}/auth/google/claim/", {
            "id_token": "tok", "claim_code": "ARCH1234",
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("don't match", str(resp.data))

    def test_email_already_has_an_account_is_refused(self, mock_verify):
        User.objects.create_user(
            email="unclaimed@example.com", password="StrongPass123!", full_name="Existing")
        mock_verify.return_value = _google_payload(email="unclaimed@example.com")
        resp = self.client.post(f"{API}/auth/google/claim/", {
            "id_token": "tok", "claim_code": self.claim_code,
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("already exists", str(resp.data).lower())

    def test_unverified_email_is_refused(self, mock_verify):
        mock_verify.return_value = _google_payload(
            email="unclaimed@example.com", email_verified=False)
        resp = self.client.post(f"{API}/auth/google/claim/", {
            "id_token": "tok", "claim_code": self.claim_code,
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_claim_code_is_case_and_space_normalized(self, mock_verify):
        mock_verify.return_value = _google_payload(email="unclaimed@example.com")
        resp = self.client.post(f"{API}/auth/google/claim/", {
            "id_token": "tok", "claim_code": " abcd2345 ",
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
