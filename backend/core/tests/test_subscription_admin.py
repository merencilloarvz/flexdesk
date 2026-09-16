from datetime import timedelta

from dateutil.relativedelta import relativedelta
from django.contrib.auth import get_user_model
from django.test import TestCase
from django.urls import reverse
from django.utils import timezone

from core.models import Gym, Subscription

CHANGELIST_URL = reverse("admin:core_subscription_changelist")


class SubscriptionAdminExtendActionsTestCase(TestCase):
    def setUp(self):
        self.admin_user = get_user_model().objects.create_superuser(
            email="admin@example.com", password="StrongPass123!", full_name="Admin")
        self.client.force_login(self.admin_user)

    def _sub(self, **kwargs):
        gym = Gym.objects.create(name="Gym", slug=f"gym-{Gym.objects.count()}")
        defaults = {"trial_ends_at": timezone.now() + timedelta(days=14)}
        defaults.update(kwargs)
        return Subscription.objects.create(gym=gym, **defaults)

    def _run_action(self, action, sub):
        self.client.post(CHANGELIST_URL, {
            "action": action,
            "_selected_action": [str(sub.pk)],
        })
        sub.refresh_from_db()
        return sub

    def test_extend_one_month_from_null_current_period_end(self):
        sub = self._sub(status=Subscription.TRIALING, current_period_end=None)
        before = timezone.now()
        sub = self._run_action("extend_one_month", sub)
        self.assertEqual(sub.status, Subscription.ACTIVE)
        self.assertAlmostEqual(
            sub.current_period_end, before + relativedelta(months=1),
            delta=timedelta(seconds=10))

    def test_extend_one_month_from_past_current_period_end_uses_now(self):
        sub = self._sub(status=Subscription.ACTIVE,
                         current_period_end=timezone.now() - timedelta(days=5))
        before = timezone.now()
        sub = self._run_action("extend_one_month", sub)
        self.assertEqual(sub.status, Subscription.ACTIVE)
        self.assertAlmostEqual(
            sub.current_period_end, before + relativedelta(months=1),
            delta=timedelta(seconds=10))

    def test_extend_one_year_from_future_current_period_end_stacks(self):
        original_end = timezone.now() + timedelta(days=10)
        sub = self._sub(status=Subscription.ACTIVE, current_period_end=original_end)
        sub = self._run_action("extend_one_year", sub)
        self.assertEqual(sub.status, Subscription.ACTIVE)
        self.assertAlmostEqual(
            sub.current_period_end, original_end + relativedelta(years=1),
            delta=timedelta(seconds=10))
