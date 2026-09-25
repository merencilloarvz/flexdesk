from datetime import timedelta

from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from core.models import Gym, Subscription

API = "/api/v1"

SIGNUP_PAYLOAD = {
    "gym_name": "Trial Gym",
    "full_name": "Trial Owner",
    "email": "trialowner@example.com",
    "password": "StrongPass123!",
}


class SignupTrialTestCase(APITestCase):
    """A gym created through signup must land in a valid 14-day trial."""

    def _signup(self, **overrides):
        return self.client.post(
            f"{API}/auth/signup/", {**SIGNUP_PAYLOAD, **overrides}, format="json")

    def test_new_gym_gets_14_day_trial(self):
        before = timezone.now()
        response = self._signup()
        after = timezone.now()
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

        sub = Subscription.objects.get(gym__name="Trial Gym")
        self.assertEqual(sub.status, Subscription.TRIALING)
        self.assertGreaterEqual(sub.trial_ends_at, before + timedelta(days=14))
        self.assertLessEqual(sub.trial_ends_at, after + timedelta(days=14))
        self.assertFalse(sub.is_blocked)
        self.assertEqual(sub.billing_state, "trial_active")

    def test_signup_response_reports_valid_trial(self):
        response = self._signup()
        gym = response.data["user"]["gym"]
        self.assertEqual(gym["subscription_status"], "trialing")
        self.assertFalse(gym["subscription_blocked"])
        self.assertIsNotNone(gym["trial_ends_at"])
        self.assertEqual(gym["billing_state"], "trial_active")
        self.assertIn(gym["days_remaining"], (13, 14))

    def test_login_after_signup_still_reports_valid_trial(self):
        self._signup()
        response = self.client.post(
            f"{API}/auth/login/",
            {"email": SIGNUP_PAYLOAD["email"],
             "password": SIGNUP_PAYLOAD["password"]},
            format="json")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        gym = response.data["user"]["gym"]
        self.assertEqual(gym["subscription_status"], "trialing")
        self.assertFalse(gym["subscription_blocked"])

    def test_trialing_gym_can_write_data(self):
        response = self._signup()
        self.client.credentials(
            HTTP_AUTHORIZATION=f"Bearer {response.data['access']}")

        # /plans/ POST is gated only by SubscriptionActive beyond owner
        # role, so a 201 here proves the trial is not read-only.
        created = self.client.post(
            f"{API}/plans/",
            {"name": "Monthly Test", "category": "Regular",
             "duration_value": 1, "duration_unit": "MONTH", "price": "500.00"},
            format="json")
        self.assertEqual(created.status_code, status.HTTP_201_CREATED, created.data)

    def test_expired_trial_gym_is_read_only(self):
        response = self._signup()
        Subscription.objects.filter(gym__name="Trial Gym").update(
            trial_ends_at=timezone.now() - timedelta(days=1))
        self.client.credentials(
            HTTP_AUTHORIZATION=f"Bearer {response.data['access']}")

        listed = self.client.get(f"{API}/plans/")
        self.assertEqual(listed.status_code, status.HTTP_200_OK)
        blocked = self.client.post(
            f"{API}/plans/",
            {"name": "Blocked", "category": "Regular", "duration_value": 1,
             "duration_unit": "MONTH", "price": "500.00"},
            format="json")
        self.assertEqual(blocked.status_code, status.HTTP_402_PAYMENT_REQUIRED)


class UnpricedPlansTestCase(APITestCase):
    """
    Signup no longer forces a pricing step, so a fresh owner can reach
    add-member / renew / check-in while every seeded plan is still ₱0.
    None of those may crash or refuse because of the zero price.
    """

    def setUp(self):
        response = self.client.post(
            f"{API}/auth/signup/", SIGNUP_PAYLOAD, format="json")
        self.client.credentials(
            HTTP_AUTHORIZATION=f"Bearer {response.data['access']}")
        self.assertTrue(response.data["user"]["gym"]["needs_setup"])
        self.plans = self.client.get(f"{API}/plans/").data
        self.plans = self.plans["results"] if "results" in self.plans else self.plans
        self.plan = next(p for p in self.plans if not p["is_day_pass"])
        self.assertEqual(float(self.plan["price"]), 0)

    def _create_member(self, **extra):
        return self.client.post(
            f"{API}/members/",
            {"first_name": "Zero", "last_name": "Price",
             "email": "zero@example.com", "member_type": "MEMBER", **extra},
            format="json")

    def test_add_member_with_unpriced_plan(self):
        response = self._create_member(plan_id=self.plan["id"])
        self.assertEqual(response.status_code, status.HTTP_201_CREATED, response.data)

    def test_renew_with_unpriced_plan(self):
        member = self._create_member().data
        response = self.client.post(
            f"{API}/members/{member['id']}/renew/",
            {"plan_id": self.plan["id"]}, format="json")
        self.assertEqual(response.status_code, status.HTTP_201_CREATED, response.data)
        self.assertEqual(float(response.data["price_paid"]), 0)

    def test_member_check_in_with_unpriced_plan(self):
        member = self._create_member(plan_id=self.plan["id"]).data
        response = self.client.post(
            f"{API}/check-ins/",
            {"visit_type": "MEMBER", "member": member["id"],
             "checked_in_at": timezone.now().isoformat()},
            format="json")
        self.assertEqual(response.status_code, status.HTTP_201_CREATED, response.data)
