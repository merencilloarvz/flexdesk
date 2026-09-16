from datetime import timedelta

from django.test import override_settings
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import RefreshToken

from core.models import Gym, Location, StaffProfile, Subscription, User

API = "/api/v1"


class SubscriptionIsBlockedTestCase(APITestCase):
    """
    Manual-payment model: `status` only says which regime applies —
    the actual expiry math lives in is_blocked/days_remaining/billing_state.
    """

    def _sub(self, **kwargs):
        gym = Gym.objects.create(name="Gym", slug=f"gym-{Gym.objects.count()}")
        defaults = {"trial_ends_at": timezone.now() + timedelta(days=14)}
        defaults.update(kwargs)
        return Subscription.objects.create(gym=gym, **defaults)

    def test_trialing_within_window_is_not_blocked(self):
        sub = self._sub(status=Subscription.TRIALING,
                         trial_ends_at=timezone.now() + timedelta(days=5))
        self.assertFalse(sub.is_blocked)

    def test_trialing_past_end_is_blocked(self):
        sub = self._sub(status=Subscription.TRIALING,
                         trial_ends_at=timezone.now() - timedelta(hours=1))
        self.assertTrue(sub.is_blocked)

    def test_active_with_no_current_period_end_is_not_blocked(self):
        # e.g. the 0019 backfill — active gyms with nothing stamped yet.
        sub = self._sub(status=Subscription.ACTIVE, current_period_end=None)
        self.assertFalse(sub.is_blocked)

    def test_active_with_future_current_period_end_is_not_blocked(self):
        sub = self._sub(status=Subscription.ACTIVE,
                         current_period_end=timezone.now() + timedelta(days=10))
        self.assertFalse(sub.is_blocked)

    def test_active_past_current_period_end_is_blocked(self):
        sub = self._sub(status=Subscription.ACTIVE,
                         current_period_end=timezone.now() - timedelta(hours=1))
        self.assertTrue(sub.is_blocked)

    def test_past_due_is_always_blocked(self):
        sub = self._sub(status=Subscription.PAST_DUE)
        self.assertTrue(sub.is_blocked)

    def test_canceled_is_always_blocked(self):
        sub = self._sub(status=Subscription.CANCELED)
        self.assertTrue(sub.is_blocked)


class SubscriptionDaysRemainingTestCase(APITestCase):
    def _sub(self, **kwargs):
        gym = Gym.objects.create(name="Gym", slug=f"gym-{Gym.objects.count()}")
        defaults = {"trial_ends_at": timezone.now() + timedelta(days=14)}
        defaults.update(kwargs)
        return Subscription.objects.create(gym=gym, **defaults)

    def test_trialing_counts_down_to_trial_ends_at(self):
        sub = self._sub(status=Subscription.TRIALING,
                         trial_ends_at=timezone.now() + timedelta(days=5))
        self.assertEqual(sub.days_remaining, 4)  # timedelta.days floors

    def test_trialing_never_negative(self):
        sub = self._sub(status=Subscription.TRIALING,
                         trial_ends_at=timezone.now() - timedelta(days=5))
        self.assertEqual(sub.days_remaining, 0)

    def test_active_counts_down_to_current_period_end(self):
        sub = self._sub(status=Subscription.ACTIVE,
                         current_period_end=timezone.now() + timedelta(days=10))
        self.assertEqual(sub.days_remaining, 9)

    def test_active_with_no_current_period_end_is_none(self):
        sub = self._sub(status=Subscription.ACTIVE, current_period_end=None)
        self.assertIsNone(sub.days_remaining)

    def test_canceled_is_none(self):
        sub = self._sub(status=Subscription.CANCELED)
        self.assertIsNone(sub.days_remaining)


class SubscriptionBillingStateTestCase(APITestCase):
    def _sub(self, **kwargs):
        gym = Gym.objects.create(name="Gym", slug=f"gym-{Gym.objects.count()}")
        defaults = {"trial_ends_at": timezone.now() + timedelta(days=14)}
        defaults.update(kwargs)
        return Subscription.objects.create(gym=gym, **defaults)

    def test_trial_active(self):
        sub = self._sub(status=Subscription.TRIALING,
                         trial_ends_at=timezone.now() + timedelta(days=10))
        self.assertEqual(sub.billing_state, "trial_active")

    def test_trial_expiring_at_threshold(self):
        sub = self._sub(status=Subscription.TRIALING,
                         trial_ends_at=timezone.now() + timedelta(days=3))
        self.assertEqual(sub.billing_state, "trial_expiring")

    def test_trial_expired(self):
        sub = self._sub(status=Subscription.TRIALING,
                         trial_ends_at=timezone.now() - timedelta(hours=1))
        self.assertEqual(sub.billing_state, "trial_expired")

    def test_active(self):
        sub = self._sub(status=Subscription.ACTIVE,
                         current_period_end=timezone.now() + timedelta(days=20))
        self.assertEqual(sub.billing_state, "active")

    def test_active_expiring(self):
        sub = self._sub(status=Subscription.ACTIVE,
                         current_period_end=timezone.now() + timedelta(days=2))
        self.assertEqual(sub.billing_state, "active_expiring")

    def test_active_with_no_current_period_end_is_plain_active(self):
        sub = self._sub(status=Subscription.ACTIVE, current_period_end=None)
        self.assertEqual(sub.billing_state, "active")

    def test_active_expired(self):
        sub = self._sub(status=Subscription.ACTIVE,
                         current_period_end=timezone.now() - timedelta(hours=1))
        self.assertEqual(sub.billing_state, "expired")

    def test_past_due(self):
        sub = self._sub(status=Subscription.PAST_DUE)
        self.assertEqual(sub.billing_state, "expired")

    def test_canceled(self):
        sub = self._sub(status=Subscription.CANCELED)
        self.assertEqual(sub.billing_state, "canceled")


class SubscriptionPaymentInfoViewTestCase(APITestCase):
    def setUp(self):
        self.gym = Gym.objects.create(name="Gym", slug="gym")
        self.location = Location.objects.create(gym=self.gym, name="Main")
        Subscription.objects.create(
            gym=self.gym, trial_ends_at=timezone.now() + timedelta(days=14))
        self.owner = User.objects.create_user(
            email="owner@example.com", password="StrongPass123!",
            full_name="Owner")
        StaffProfile.objects.create(
            user=self.owner, gym=self.gym, role=StaffProfile.OWNER,
            default_location=self.location)
        token = RefreshToken.for_user(self.owner)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token.access_token}")

    @override_settings(
        SUBSCRIPTION_PRICE_MONTHLY_CENTAVOS=79900,
        SUBSCRIPTION_PRICE_YEARLY_CENTAVOS=799000,
        SUBSCRIPTION_PAYMENT_INSTRUCTIONS="GCash: 0917-000-0000",
        SUBSCRIPTION_CONTACT_INFO="Message us on Messenger",
    )
    def test_returns_configured_payment_info(self):
        resp = self.client.get(f"{API}/subscription/payment-info/")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data, {
            "price_monthly_centavos": 79900,
            "price_yearly_centavos": 799000,
            "payment_instructions": "GCash: 0917-000-0000",
            "contact_info": "Message us on Messenger",
        })

    def test_reachable_even_when_blocked(self):
        self.gym.subscription.status = Subscription.PAST_DUE
        self.gym.subscription.save()
        resp = self.client.get(f"{API}/subscription/payment-info/")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
