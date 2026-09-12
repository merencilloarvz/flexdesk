from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import RefreshToken

from core.models import (Announcement, Gym, Location, Member, StaffProfile,
                         Subscription, User)

API = "/api/v1"


class SubscriptionActiveSafeMethodsTestCase(APITestCase):
    """
    SubscriptionActive's design is read-only-with-export, never lockout:
    a lapsed gym must still be able to read its own data. It must only
    ever block a WRITE. /plans/ is the target for the GET/POST pair
    below because MembershipPlanViewSet's own permission_classes
    (IsGymStaff, IsOwnerOrReadOnly) already let an owner do both, so
    SubscriptionActive is the only thing that could still say no.
    """

    def setUp(self):
        self.blocked_gym = Gym.objects.create(name="Blocked Gym", slug="blocked-gym")
        self.blocked_location = Location.objects.create(
            gym=self.blocked_gym, name="Main")
        Subscription.objects.create(
            gym=self.blocked_gym, status=Subscription.PAST_DUE,
            trial_ends_at=timezone.now())

        self.blocked_owner_user = User.objects.create_user(
            email="blockedowner@example.com", password="StrongPass123!",
            full_name="Blocked Owner")
        StaffProfile.objects.create(
            user=self.blocked_owner_user, gym=self.blocked_gym,
            role=StaffProfile.OWNER, default_location=self.blocked_location)

        self.blocked_member_user = User.objects.create_user(
            email="blockedmember@example.com", password="StrongPass123!",
            full_name="Blocked Member")
        Member.objects.create(
            gym=self.blocked_gym, home_location=self.blocked_location,
            first_name="Blocked", last_name="Member",
            email="blockedmember@example.com", member_type=Member.MEMBER,
            user=self.blocked_member_user)
        Announcement.objects.create(
            gym=self.blocked_gym, title="Notice", body="Something happened.")

        self.active_gym = Gym.objects.create(name="Active Gym", slug="active-gym")
        self.active_location = Location.objects.create(
            gym=self.active_gym, name="Main")
        Subscription.objects.create(
            gym=self.active_gym, status=Subscription.ACTIVE,
            trial_ends_at=timezone.now())
        self.active_owner_user = User.objects.create_user(
            email="activeowner@example.com", password="StrongPass123!",
            full_name="Active Owner")
        StaffProfile.objects.create(
            user=self.active_owner_user, gym=self.active_gym,
            role=StaffProfile.OWNER, default_location=self.active_location)

    def _auth(self, user):
        token = RefreshToken.for_user(user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token.access_token}")

    def test_blocked_gym_staff_get_on_staff_endpoint_succeeds(self):
        self._auth(self.blocked_owner_user)
        resp = self.client.get(f"{API}/plans/")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

    def test_blocked_gym_staff_post_on_same_endpoint_is_blocked(self):
        self._auth(self.blocked_owner_user)
        resp = self.client.post(f"{API}/plans/", {
            "name": "New Plan", "duration_value": 1, "duration_unit": "MONTH",
            "price": "1000.00",
        })
        self.assertEqual(resp.status_code, status.HTTP_402_PAYMENT_REQUIRED)

    def test_unblocked_gym_staff_post_behaves_normally(self):
        self._auth(self.active_owner_user)
        resp = self.client.post(f"{API}/plans/", {
            "name": "New Plan", "duration_value": 1, "duration_unit": "MONTH",
            "price": "1000.00",
        })
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)

    def test_member_token_on_blocked_gym_unaffected(self):
        # AnnouncementViewSet: IsGymUser + IsGymStaffOrReadOnly, with
        # SubscriptionActive appended by GymScopedViewSet — the one
        # place the member bypass and an actually-blocked subscription
        # meet in the same request.
        self._auth(self.blocked_member_user)
        resp = self.client.get(f"{API}/announcements/")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
