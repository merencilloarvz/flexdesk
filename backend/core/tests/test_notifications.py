import json
import threading
from datetime import date, datetime, timedelta, timezone as dt_timezone
from decimal import Decimal
from types import SimpleNamespace
from unittest import mock
from zoneinfo import ZoneInfo

from django.core.management import call_command
from django.db import connections
from django.test import TestCase, TransactionTestCase, override_settings
from django.utils import timezone
from firebase_admin import exceptions as fb_exceptions
from firebase_admin import messaging
from rest_framework import status
from rest_framework.test import APIClient, APITestCase
from rest_framework_simplejwt.tokens import RefreshToken

from core import notifications
from core.models import (Announcement, CheckIn, Comment, DeviceToken, Event,
                         EventRegistration, Gym, Location, Member,
                         Membership, MembershipPlan, NotificationSend,
                         Product, Sale, StaffProfile, Subscription, User)
from core.tests.test_pos import (make_gym, make_location, make_member_user,
                                 make_product, make_staff_user)
from core.utils import gym_today
from core.views import _notify_announcement, create_sale

API = "/api/v1"


def _run_thread_inline():
    """
    Every new notification trigger fires on a real background thread
    (threading.Thread(..., daemon=True).start()) the same way
    _notify_announcement does, so the create/action response doesn't
    wait on FCM. This patches threading.Thread to run inline instead —
    same approach as AnnouncementNotificationTests._run_announcement_
    thread_inline, generalized for reuse across every trigger below.
    """
    class ImmediateThread:
        def __init__(self, target=None, args=(), daemon=None):
            self._target = target
            self._args = args

        def start(self):
            self._target(*self._args)

        def join(self):
            pass

    return mock.patch("core.views.threading.Thread", ImmediateThread)

# Shape-valid but entirely fake — never a real credential. Enough for
# firebase_admin.credentials.Certificate to parse locally; no network
# call happens unless something actually sends, which every test here
# mocks out.
FAKE_SERVICE_ACCOUNT_JSON = json.dumps({
    "type": "service_account",
    "project_id": "flexdesk-test",
    "private_key_id": "test",
    "private_key": (
        "-----BEGIN PRIVATE KEY-----\n"
        "MC4CAQAwBQYDK2VwBCIEIBflsQOhcuUKp95VkkNMSXX+i8jHY9AB3DKVDrGnBTt3\n"
        "-----END PRIVATE KEY-----\n"
    ),
    "client_email": "fake@flexdesk-test.iam.gserviceaccount.com",
    "client_id": "123",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
})


def _multicast_response(outcomes):
    """outcomes: list of True (success) or an exception instance (failure)."""
    responses = []
    for outcome in outcomes:
        if outcome is True:
            responses.append(SimpleNamespace(success=True, exception=None))
        else:
            responses.append(SimpleNamespace(success=False, exception=outcome))
    return SimpleNamespace(responses=responses)


class FirebaseAppCleanupMixin:
    """
    firebase_admin's app registry is process-global, not per-test —
    without this, whichever test initialises the default app first
    leaks it into every test after it in the process.
    """

    def setUp(self):
        super().setUp()
        self._clear_firebase_apps()
        self.addCleanup(self._clear_firebase_apps)

    def _clear_firebase_apps(self):
        import firebase_admin
        for name in list(firebase_admin._apps.keys()):
            firebase_admin.delete_app(firebase_admin.get_app(name))


def _auth(client, user):
    token = RefreshToken.for_user(user)
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {token.access_token}")


class DeviceTokenEndpointTests(APITestCase):
    def setUp(self):
        self.gym = Gym.objects.create(name="Notif Gym", slug="notif-gym")
        self.location = Location.objects.create(gym=self.gym, name="Main")
        self.member_user = User.objects.create_user(
            email="notifmember@example.com", password="StrongPass123!")
        Member.objects.create(
            gym=self.gym, home_location=self.location, first_name="Notif",
            last_name="Member", member_type=Member.MEMBER, user=self.member_user,
        )
        self.other_user = User.objects.create_user(
            email="notifother@example.com", password="StrongPass123!")

    def test_registering_same_token_twice_creates_one_row_and_updates_user(self):
        _auth(self.client, self.member_user)
        resp1 = self.client.post(f"{API}/devices/",
                                 {"token": "tok-1", "platform": "android"}, format="json")
        self.assertEqual(resp1.status_code, status.HTTP_204_NO_CONTENT)

        _auth(self.client, self.other_user)
        resp2 = self.client.post(f"{API}/devices/",
                                 {"token": "tok-1", "platform": "android"}, format="json")
        self.assertEqual(resp2.status_code, status.HTTP_204_NO_CONTENT)

        self.assertEqual(DeviceToken.objects.filter(token="tok-1").count(), 1)
        row = DeviceToken.objects.get(token="tok-1")
        self.assertEqual(row.user_id, self.other_user.id)

    def test_delete_removes_token(self):
        _auth(self.client, self.member_user)
        self.client.post(f"{API}/devices/",
                         {"token": "tok-2", "platform": "ios"}, format="json")
        self.assertTrue(DeviceToken.objects.filter(token="tok-2").exists())

        resp = self.client.delete(f"{API}/devices/", {"token": "tok-2"}, format="json")
        self.assertEqual(resp.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(DeviceToken.objects.filter(token="tok-2").exists())


class DeviceTokenTestEndpointTests(FirebaseAppCleanupMixin, APITestCase):
    """
    Auth/plumbing only — the type picker's own behavior (audience
    filtering, per-type channel/sample, own-devices-only scoping) is
    covered by DeviceTokenTestPickerTests below, against the real
    TYPE_CATALOG rather than a placeholder "test" type.
    """
    def setUp(self):
        self.user = User.objects.create_user(
            email="selftestuser@example.com", password="StrongPass123!")

    def test_requires_authentication(self):
        resp = self.client.post(f"{API}/devices/test/", {"type": "out_of_stock"},
                                format="json")
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_no_devices_registered_reports_zero_sent(self):
        _auth(self.client, self.user)
        with override_settings(FIREBASE_SERVICE_ACCOUNT_JSON=FAKE_SERVICE_ACCOUNT_JSON):
            resp = self.client.post(f"{API}/devices/test/", {"type": "out_of_stock"},
                                    format="json")

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data, {"sent": 0, "pruned": 0})


class SendToUsersTests(FirebaseAppCleanupMixin, TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email="pushtarget@example.com", password="StrongPass123!")

    def test_no_tokens_sends_nothing_and_does_not_error(self):
        with override_settings(FIREBASE_SERVICE_ACCOUNT_JSON=FAKE_SERVICE_ACCOUNT_JSON):
            sent, pruned = notifications.send_to_users([self.user], "Title", "Body")
        self.assertEqual((sent, pruned), (0, 0))

    def test_unset_config_is_a_noop(self):
        DeviceToken.objects.create(user=self.user, token="tok-a", platform="android")
        with override_settings(FIREBASE_SERVICE_ACCOUNT_JSON=""):
            with mock.patch.object(messaging, "send_each_for_multicast") as send_mock:
                sent, pruned = notifications.send_to_users([self.user], "Title", "Body")
        self.assertEqual((sent, pruned), (0, 0))
        send_mock.assert_not_called()

    def test_unregistered_token_is_pruned(self):
        DeviceToken.objects.create(user=self.user, token="dead-tok", platform="android")
        response = _multicast_response([messaging.UnregisteredError("gone")])
        with override_settings(FIREBASE_SERVICE_ACCOUNT_JSON=FAKE_SERVICE_ACCOUNT_JSON):
            with mock.patch.object(messaging, "send_each_for_multicast",
                                   return_value=response) as send_mock:
                sent, pruned = notifications.send_to_users([self.user], "Title", "Body")
        send_mock.assert_called_once()
        self.assertEqual((sent, pruned), (0, 1))
        self.assertFalse(DeviceToken.objects.filter(token="dead-tok").exists())

    def test_invalid_argument_token_is_pruned(self):
        DeviceToken.objects.create(user=self.user, token="bad-tok", platform="android")
        response = _multicast_response([fb_exceptions.InvalidArgumentError("bad token")])
        with override_settings(FIREBASE_SERVICE_ACCOUNT_JSON=FAKE_SERVICE_ACCOUNT_JSON):
            with mock.patch.object(messaging, "send_each_for_multicast",
                                   return_value=response):
                sent, pruned = notifications.send_to_users([self.user], "Title", "Body")
        self.assertEqual((sent, pruned), (0, 1))
        self.assertFalse(DeviceToken.objects.filter(token="bad-tok").exists())

    def test_fcm_raising_does_not_propagate(self):
        DeviceToken.objects.create(user=self.user, token="tok-b", platform="android")
        with override_settings(FIREBASE_SERVICE_ACCOUNT_JSON=FAKE_SERVICE_ACCOUNT_JSON):
            with mock.patch.object(messaging, "send_each_for_multicast",
                                   side_effect=RuntimeError("FCM is down")):
                sent, pruned = notifications.send_to_users([self.user], "Title", "Body")
        self.assertEqual((sent, pruned), (0, 0))
        # The token survives — a transport failure isn't evidence the
        # token itself is dead.
        self.assertTrue(DeviceToken.objects.filter(token="tok-b").exists())

    def test_successful_send_is_counted(self):
        DeviceToken.objects.create(user=self.user, token="tok-c", platform="android")
        response = _multicast_response([True])
        with override_settings(FIREBASE_SERVICE_ACCOUNT_JSON=FAKE_SERVICE_ACCOUNT_JSON):
            with mock.patch.object(messaging, "send_each_for_multicast",
                                   return_value=response):
                sent, pruned = notifications.send_to_users([self.user], "Title", "Body")
        self.assertEqual((sent, pruned), (1, 0))

    def test_send_sets_high_priority_android_channel(self):
        # Without this, a backgrounded/terminated app either doesn't get
        # a heads-up banner + sound, or falls back to a default channel
        # that doesn't match the one the app actually creates — see
        # PushNotificationService.ensureNotificationChannel in the
        # frontend and the default_notification_channel_id meta-data in
        # AndroidManifest.xml, which both must agree with this channel id.
        DeviceToken.objects.create(user=self.user, token="tok-d", platform="android")
        response = _multicast_response([True])
        with override_settings(FIREBASE_SERVICE_ACCOUNT_JSON=FAKE_SERVICE_ACCOUNT_JSON):
            with mock.patch.object(messaging, "send_each_for_multicast",
                                   return_value=response) as send_mock:
                notifications.send_to_users([self.user], "Title", "Body")

        message = send_mock.call_args.args[0]
        self.assertEqual(message.android.priority, "high")
        self.assertEqual(
            message.android.notification.channel_id, "high_importance_channel",
        )


class DailyNotificationsCommandTests(TestCase):
    def setUp(self):
        self.gym = Gym.objects.create(name="Renewal Gym", slug="renewal-gym",
                                      timezone="Asia/Manila")
        self.location = Location.objects.create(gym=self.gym, name="Main")
        self.plan = MembershipPlan.objects.create(
            gym=self.gym, name="Monthly", category="Standard",
            duration_value=1, duration_unit=MembershipPlan.MONTH, price=1000,
        )
        self.owner_user = User.objects.create_user(
            email="renewalowner@example.com", password="StrongPass123!")
        StaffProfile.objects.create(
            user=self.owner_user, gym=self.gym, role=StaffProfile.OWNER,
            default_location=self.location,
        )

    def _member(self, gym, location, plan, email, end_date):
        user = User.objects.create_user(email=email, password="StrongPass123!")
        member = Member.objects.create(
            gym=gym, home_location=location, first_name="Test", last_name="Member",
            member_type=Member.MEMBER, user=user,
        )
        Membership.objects.create(
            gym=gym, member=member, plan=plan,
            start_date=end_date - timedelta(days=29), end_date=end_date,
        )
        return member

    def test_sends_renewal_3day_exactly_3_days_out_not_4_days(self):
        today = gym_today(self.gym)
        three_out = self._member(self.gym, self.location, self.plan,
                                 "threeout@example.com", today + timedelta(days=3))
        four_out = self._member(self.gym, self.location, self.plan,
                                "fourout@example.com", today + timedelta(days=4))

        with mock.patch(
            "core.management.commands.send_daily_notifications.send_to_users"
        ) as send_mock:
            call_command("send_daily_notifications")

        sent_to_users = [call.args[0][0] for call in send_mock.call_args_list]
        self.assertIn(three_out.user, sent_to_users)
        self.assertNotIn(four_out.user, sent_to_users)
        self.assertTrue(
            NotificationSend.objects.filter(
                user=three_out.user, kind="renewal_3day").exists()
        )
        self.assertFalse(
            NotificationSend.objects.filter(
                user=four_out.user, kind="renewal_3day").exists()
        )

    def test_running_twice_sends_once(self):
        today = gym_today(self.gym)
        member = self._member(self.gym, self.location, self.plan,
                              "twice@example.com", today + timedelta(days=3))

        with mock.patch(
            "core.management.commands.send_daily_notifications.send_to_users"
        ) as send_mock:
            call_command("send_daily_notifications")
            call_command("send_daily_notifications")

        calls_for_member = [
            call for call in send_mock.call_args_list if call.args[0] == [member.user]
        ]
        self.assertEqual(len(calls_for_member), 1)
        self.assertEqual(
            NotificationSend.objects.filter(user=member.user, kind="renewal_3day").count(),
            1,
        )

    def test_one_gym_raising_does_not_block_other_gyms(self):
        today = gym_today(self.gym)
        gym_b = Gym.objects.create(name="Working Gym", slug="working-gym",
                                   timezone="Asia/Manila")
        location_b = Location.objects.create(gym=gym_b, name="Main")
        plan_b = MembershipPlan.objects.create(
            gym=gym_b, name="Monthly", category="Standard",
            duration_value=1, duration_unit=MembershipPlan.MONTH, price=1000,
        )
        StaffProfile.objects.create(
            user=User.objects.create_user(email="workingowner@example.com",
                                          password="StrongPass123!"),
            gym=gym_b, role=StaffProfile.OWNER, default_location=location_b,
        )
        broken_member = self._member(self.gym, self.location, self.plan,
                                     "broken@example.com", today + timedelta(days=3))
        working_member = self._member(gym_b, location_b, plan_b,
                                      "working@example.com", today + timedelta(days=3))

        def send_side_effect(users, **kwargs):
            if users == [broken_member.user]:
                raise RuntimeError("boom")
            return (1, 0)

        # Gym has no defined ordering, so force self.gym (the one that
        # raises) to be processed first — otherwise this test could pass
        # by accident regardless of whether the loop actually recovers.
        with mock.patch.object(Gym.objects, "all", return_value=[self.gym, gym_b]):
            with mock.patch(
                "core.management.commands.send_daily_notifications.send_to_users",
                side_effect=send_side_effect,
            ):
                call_command("send_daily_notifications")

        self.assertTrue(
            NotificationSend.objects.filter(
                user=working_member.user, kind="renewal_3day").exists()
        )

    def test_send_to_users_raising_leaves_no_notification_send_row(self):
        today = gym_today(self.gym)
        member = self._member(self.gym, self.location, self.plan,
                              "retry@example.com", today + timedelta(days=3))

        with mock.patch(
            "core.management.commands.send_daily_notifications.send_to_users",
            side_effect=RuntimeError("boom"),
        ):
            call_command("send_daily_notifications")

        self.assertFalse(
            NotificationSend.objects.filter(
                user=member.user, kind="renewal_3day").exists()
        )

        # A later run (send_to_users healthy again) must still attempt
        # the send — nothing about the earlier failed attempt should
        # have marked this member as already notified.
        with mock.patch(
            "core.management.commands.send_daily_notifications.send_to_users"
        ) as send_mock:
            call_command("send_daily_notifications")

        send_mock.assert_called_once()
        self.assertTrue(
            NotificationSend.objects.filter(
                user=member.user, kind="renewal_3day").exists()
        )

    def test_member_in_one_gym_never_receives_another_gyms_notification(self):
        today = gym_today(self.gym)
        gym_b = Gym.objects.create(name="Other Gym", slug="other-gym")
        location_b = Location.objects.create(gym=gym_b, name="Main")
        plan_b = MembershipPlan.objects.create(
            gym=gym_b, name="Monthly", category="Standard",
            duration_value=1, duration_unit=MembershipPlan.MONTH, price=1000,
        )
        StaffProfile.objects.create(
            user=User.objects.create_user(email="ownerb@example.com",
                                          password="StrongPass123!"),
            gym=gym_b, role=StaffProfile.OWNER, default_location=location_b,
        )
        member_a = self._member(self.gym, self.location, self.plan,
                                "membera@example.com", today + timedelta(days=3))
        member_b = self._member(gym_b, location_b, plan_b,
                                "memberb@example.com", today + timedelta(days=3))

        with mock.patch(
            "core.management.commands.send_daily_notifications.send_to_users"
        ) as send_mock:
            call_command("send_daily_notifications")

        sent_to_users = [call.args[0][0] for call in send_mock.call_args_list]
        self.assertIn(member_a.user, sent_to_users)
        self.assertIn(member_b.user, sent_to_users)

        for call in send_mock.call_args_list:
            recipient = call.args[0][0]
            body = call.kwargs["body"]
            if recipient == member_a.user:
                self.assertIn(self.gym.name, body)
                self.assertNotIn(gym_b.name, body)
            elif recipient == member_b.user:
                self.assertIn(gym_b.name, body)
                self.assertNotIn(self.gym.name, body)

    def test_expiry_uses_gym_local_date_not_utc(self):
        # 2026-09-15 22:00 UTC is already 2026-09-16 06:00 in Manila
        # (UTC+8, no DST). A member 3 days out from the Manila date
        # (Sep 19) must be picked up even though the UTC calendar date
        # is still Sep 15 — with_status(gym_today(gym)) must be driving
        # this, not a naive timezone.now().date().
        fixed_utc_now = datetime(2026, 9, 15, 22, 0, tzinfo=dt_timezone.utc)
        manila_today = date(2026, 9, 16)
        member = self._member(self.gym, self.location, self.plan,
                              "manila@example.com", manila_today + timedelta(days=3))

        with mock.patch("django.utils.timezone.now", return_value=fixed_utc_now):
            with mock.patch(
                "core.management.commands.send_daily_notifications.send_to_users"
            ) as send_mock:
                call_command("send_daily_notifications")

        sent_to_users = [call.args[0][0] for call in send_mock.call_args_list]
        self.assertIn(member.user, sent_to_users)


class AnnouncementNotificationTests(APITestCase):
    def setUp(self):
        self.gym = make_gym()
        self.location = make_location(self.gym)
        self.owner = make_staff_user(self.gym, "annowner@test.com",
                                     role=StaffProfile.OWNER, location=self.location)
        self.member_user = make_member_user(self.gym, self.location, "annmember@test.com")

        self.other_gym = make_gym("Other Ann Gym")
        self.other_location = make_location(self.other_gym)
        self.other_member_user = make_member_user(
            self.other_gym, self.other_location, "otherannmember@test.com")

    def as_owner(self):
        c = APIClient()
        c.force_authenticate(user=self.owner)
        return c

    def _post_announcement(self):
        return self.as_owner().post(f"{API}/announcements/", {
            "title": "Gym closed Sunday", "body": "We're closed this Sunday for cleaning.",
        }, format="json")

    def _run_announcement_thread_inline(self):
        """
        The view fires _notify_announcement on a real background thread
        (see AnnouncementViewSet.perform_create) so the create response
        doesn't wait on it. Tests need the thread's work done before they
        assert, so this patches threading.Thread to run the target inline
        and returns a dummy object with a no-op start/join, capturing the
        real thread for the caller to join instead.
        """
        started = []

        class ImmediateThread:
            def __init__(self, target=None, args=(), daemon=None):
                self._target = target
                self._args = args

            def start(self):
                self._target(*self._args)
                started.append(True)

            def join(self):
                pass

        return mock.patch("core.views.threading.Thread", ImmediateThread)

    def test_announcement_notifies_members_of_same_gym_only(self):
        with self._run_announcement_thread_inline():
            with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
                resp = self._post_announcement()

        self.assertIn(resp.status_code, (200, 201))
        send_mock.assert_called_once()
        recipients = send_mock.call_args.args[0]
        self.assertIn(self.member_user, recipients)
        self.assertNotIn(self.other_member_user, recipients)
        self.assertNotIn(self.owner, recipients)

    def test_announcement_creates_notification_send_row_per_member(self):
        with self._run_announcement_thread_inline():
            with mock.patch("core.views.send_to_users", return_value=(0, 0)):
                resp = self._post_announcement()

        announcement_id = resp.data["id"]
        self.assertTrue(
            NotificationSend.objects.filter(
                user=self.member_user, kind="announcement", subject_id=announcement_id,
            ).exists()
        )

    def test_announcement_send_failure_does_not_fail_the_create_request(self):
        with self._run_announcement_thread_inline():
            with mock.patch("core.views.send_to_users", side_effect=RuntimeError("boom")):
                resp = self._post_announcement()

        self.assertIn(resp.status_code, (200, 201))
        self.assertEqual(Announcement.objects.count(), 1)

    def test_announcement_hands_the_send_to_a_daemon_background_thread(self):
        # Confirms the view really defers to a background thread (rather
        # than running notify inline) without actually letting a second
        # thread touch this test's uncommitted transaction — a real
        # second thread would use its own DB connection and couldn't see
        # the gym/member rows created in setUp, which are never committed
        # under APITestCase. core.views.notifications lives in the same
        # process, so asserting on the Thread construction is enough.
        with mock.patch("core.views.threading.Thread") as thread_cls:
            thread_cls.return_value = mock.Mock()
            resp = self._post_announcement()

        self.assertIn(resp.status_code, (200, 201))
        thread_cls.assert_called_once()
        _, kwargs = thread_cls.call_args
        self.assertEqual(kwargs["target"], _notify_announcement)
        self.assertTrue(kwargs["daemon"])
        thread_cls.return_value.start.assert_called_once()


class OutOfStockNotificationTests(APITestCase):
    def setUp(self):
        self.gym = make_gym("Stock Gym")
        self.location = make_location(self.gym)
        self.owner = make_staff_user(self.gym, "stockowner@test.com",
                                     role=StaffProfile.OWNER, location=self.location)
        self.staff = make_staff_user(self.gym, "stockstaff@test.com",
                                     role=StaffProfile.STAFF, location=self.location)
        self.member_user = make_member_user(self.gym, self.location, "stockmember@test.com")
        self.product = make_product(self.gym, stock=1)

    def as_staff(self):
        c = APIClient()
        c.force_authenticate(user=self.staff)
        return c

    def as_owner(self):
        c = APIClient()
        c.force_authenticate(user=self.owner)
        return c

    def test_stock_hitting_exactly_zero_sends_once_to_owner_and_staff(self):
        with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
            with self.captureOnCommitCallbacks(execute=True):
                create_sale(
                    gym=self.gym,
                    items=[{"product_id": self.product.id, "quantity": 1}],
                    user=self.staff,
                )

        send_mock.assert_called_once()
        recipients = send_mock.call_args.args[0]
        self.assertIn(self.owner, recipients)
        self.assertIn(self.staff, recipients)
        self.assertNotIn(self.member_user, recipients)
        self.assertEqual(send_mock.call_args.kwargs["data"]["type"], "out_of_stock")
        self.assertEqual(send_mock.call_args.kwargs["data"]["id"], str(self.product.id))

    def test_selling_already_zero_stock_does_not_notify_again(self):
        self.product.stock_quantity = 0
        self.product.save(update_fields=["stock_quantity"])

        with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
            with self.captureOnCommitCallbacks(execute=True):
                with self.assertRaises(Exception):
                    create_sale(
                        gym=self.gym,
                        items=[{"product_id": self.product.id, "quantity": 1}],
                        user=self.staff,
                    )

        send_mock.assert_not_called()

    def test_partial_stock_not_hitting_zero_does_not_notify(self):
        self.product.stock_quantity = 5
        self.product.save(update_fields=["stock_quantity"])

        with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
            with self.captureOnCommitCallbacks(execute=True):
                create_sale(
                    gym=self.gym,
                    items=[{"product_id": self.product.id, "quantity": 2}],
                    user=self.staff,
                )

        send_mock.assert_not_called()

    def test_restock_then_zero_again_notifies_twice_with_distinct_kinds(self):
        with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
            with self.captureOnCommitCallbacks(execute=True):
                create_sale(
                    gym=self.gym,
                    items=[{"product_id": self.product.id, "quantity": 1}],
                    user=self.staff,
                )

            self.product.stock_quantity = 3
            self.product.save(update_fields=["stock_quantity"])

            with self.captureOnCommitCallbacks(execute=True):
                create_sale(
                    gym=self.gym,
                    items=[{"product_id": self.product.id, "quantity": 3}],
                    user=self.staff,
                )

        self.assertEqual(send_mock.call_count, 2)
        rows = NotificationSend.objects.filter(
            user=self.owner, subject_id=self.product.id, kind__startswith="out_of_stock",
        )
        self.assertEqual(rows.count(), 2)
        kinds = set(rows.values_list("kind", flat=True))
        self.assertEqual(len(kinds), 2)

    def test_stock_adjustment_hitting_zero_notifies(self):
        with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
            with self.captureOnCommitCallbacks(execute=True):
                resp = self.as_owner().post(
                    f"{API}/products/{self.product.id}/adjust/",
                    {"delta": -1, "reason": "damaged"}, format="json",
                )

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        send_mock.assert_called_once()

    def test_out_of_stock_send_failure_does_not_fail_the_sale(self):
        with mock.patch("core.views.send_to_users", side_effect=RuntimeError("boom")):
            with self.captureOnCommitCallbacks(execute=True):
                sale = create_sale(
                    gym=self.gym,
                    items=[{"product_id": self.product.id, "quantity": 1}],
                    user=self.staff,
                )
        self.assertIsNotNone(sale)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 0)


class ConcurrentOutOfStockNotificationTests(TransactionTestCase):
    def setUp(self):
        self.gym = make_gym("Concurrent Stock Gym")
        self.location = make_location(self.gym)
        self.owner = make_staff_user(self.gym, "concurrentowner@test.com",
                                     role=StaffProfile.OWNER, location=self.location)
        self.product = make_product(self.gym, stock=1)

    def test_two_concurrent_sales_of_last_unit_notify_exactly_once(self):
        results = []

        def sell():
            connections.close_all()
            try:
                create_sale(
                    gym=self.gym,
                    items=[{"product_id": self.product.id, "quantity": 1}],
                    user=self.owner,
                )
                results.append("ok")
            except Exception:
                results.append("fail")
            finally:
                connections.close_all()

        with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
            t1 = threading.Thread(target=sell)
            t2 = threading.Thread(target=sell)
            t1.start()
            t2.start()
            t1.join()
            t2.join()

        self.assertEqual(results.count("ok"), 1)
        self.assertEqual(results.count("fail"), 1)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 0)
        # on_commit callbacks run for real in TransactionTestCase (each
        # thread's transaction actually commits), so the notification for
        # the one successful sale should have fired exactly once.
        self.assertEqual(send_mock.call_count, 1)


class NewEventNotificationTests(APITestCase):
    def setUp(self):
        self.gym = make_gym("Event Gym")
        self.location = make_location(self.gym)
        self.owner = make_staff_user(self.gym, "eventowner@test.com",
                                     role=StaffProfile.OWNER, location=self.location)
        self.member_user = make_member_user(self.gym, self.location, "eventmember@test.com")

        self.other_gym = make_gym("Other Event Gym")
        self.other_location = make_location(self.other_gym)
        self.other_member_user = make_member_user(
            self.other_gym, self.other_location, "othereventmember@test.com")

    def as_owner(self):
        c = APIClient()
        c.force_authenticate(user=self.owner)
        return c

    def _post_event(self, **overrides):
        payload = {
            "title": "Summer Showdown",
            "event_date": "2026-10-12",
            "registration_fee": "200.00",
        }
        payload.update(overrides)
        return self.as_owner().post(f"{API}/events/", payload, format="json")

    def test_new_event_notifies_members_of_same_gym_only(self):
        with _run_thread_inline():
            with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
                resp = self._post_event()

        self.assertIn(resp.status_code, (200, 201))
        send_mock.assert_called_once()
        recipients = send_mock.call_args.args[0]
        self.assertIn(self.member_user, recipients)
        self.assertNotIn(self.other_member_user, recipients)
        self.assertNotIn(self.owner, recipients)
        self.assertEqual(send_mock.call_args.kwargs["notif_type"], "new_event")

    def test_title_and_fee_in_body(self):
        with _run_thread_inline():
            with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
                self._post_event(title="Summer Showdown", **{"registration_fee": "200.00"})

        title = send_mock.call_args.kwargs.get("title") or send_mock.call_args.args[1]
        body = send_mock.call_args.kwargs.get("body") or send_mock.call_args.args[2]
        self.assertIn("Summer Showdown", title)
        self.assertIn("₱200", body)

    def test_free_event_says_free(self):
        with _run_thread_inline():
            with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
                self._post_event(registration_fee="0")

        body = send_mock.call_args.kwargs.get("body") or send_mock.call_args.args[2]
        self.assertIn("Free", body)

    def test_creates_notification_send_row_per_member(self):
        with _run_thread_inline():
            with mock.patch("core.views.send_to_users", return_value=(0, 0)):
                resp = self._post_event()

        event_id = resp.data["id"]
        self.assertTrue(
            NotificationSend.objects.filter(
                user=self.member_user, kind="new_event", subject_id=event_id).exists()
        )

    def test_send_failure_does_not_fail_the_create_request(self):
        with _run_thread_inline():
            with mock.patch("core.views.send_to_users", side_effect=RuntimeError("boom")):
                resp = self._post_event()

        self.assertIn(resp.status_code, (200, 201))
        self.assertEqual(Event.objects.count(), 1)


class CommentNotificationTests(APITestCase):
    def setUp(self):
        self.gym = make_gym("Comment Gym")
        self.location = make_location(self.gym)
        self.owner = make_staff_user(self.gym, "commentowner@test.com",
                                     role=StaffProfile.OWNER, location=self.location)
        self.staff = make_staff_user(self.gym, "commentstaff@test.com",
                                     role=StaffProfile.STAFF, location=self.location)
        self.member_user = make_member_user(self.gym, self.location, "commentmember@test.com")
        self.announcement = Announcement.objects.create(
            gym=self.gym, created_by=self.owner, title="Gym closed Sunday",
            body="We're closed this Sunday.")
        self.event = Event.objects.create(
            gym=self.gym, title="Summer Showdown", event_date="2026-10-12")

    def as_(self, user):
        c = APIClient()
        c.force_authenticate(user=user)
        return c

    def test_staff_comment_notifies_owner_but_not_the_commenter(self):
        with _run_thread_inline():
            with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
                resp = self.as_(self.staff).post(
                    f"{API}/announcements/{self.announcement.id}/comments/",
                    {"body": "Noted, thanks!"}, format="json")

        self.assertIn(resp.status_code, (200, 201))
        send_mock.assert_called_once()
        recipients = send_mock.call_args.args[0]
        self.assertIn(self.owner, recipients)
        self.assertNotIn(self.staff, recipients)

    def test_member_comment_notifies_all_staff(self):
        with _run_thread_inline():
            with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
                resp = self.as_(self.member_user).post(
                    f"{API}/announcements/{self.announcement.id}/comments/",
                    {"body": "What time do you reopen?"}, format="json")

        self.assertIn(resp.status_code, (200, 201))
        recipients = send_mock.call_args.args[0]
        self.assertIn(self.owner, recipients)
        self.assertIn(self.staff, recipients)
        self.assertNotIn(self.member_user, recipients)

    def test_title_and_quoted_body_preview(self):
        with _run_thread_inline():
            with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
                self.as_(self.member_user).post(
                    f"{API}/announcements/{self.announcement.id}/comments/",
                    {"body": "What time do you reopen?"}, format="json")

        title = send_mock.call_args.kwargs.get("title") or send_mock.call_args.args[1]
        body = send_mock.call_args.kwargs.get("body") or send_mock.call_args.args[2]
        self.assertIn("Gym closed Sunday", title)
        self.assertIn('"What time do you reopen?"', body)

    def test_comment_on_event_uses_event_title_and_target_type(self):
        with _run_thread_inline():
            with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
                self.as_(self.member_user).post(
                    f"{API}/events/{self.event.id}/comments/",
                    {"body": "Can't wait!"}, format="json")

        title = send_mock.call_args.kwargs.get("title") or send_mock.call_args.args[1]
        self.assertIn("Summer Showdown", title)
        data = send_mock.call_args.kwargs["data"]
        self.assertEqual(data["target_type"], "event")
        self.assertEqual(data["id"], str(self.event.id))

    def test_creates_notification_send_row(self):
        with _run_thread_inline():
            with mock.patch("core.views.send_to_users", return_value=(0, 0)):
                self.as_(self.member_user).post(
                    f"{API}/announcements/{self.announcement.id}/comments/",
                    {"body": "Noted"}, format="json")

        comment = Comment.objects.get(announcement=self.announcement)
        self.assertTrue(
            NotificationSend.objects.filter(
                user=self.owner, kind="comment", subject_id=comment.id).exists()
        )

    def test_like_sends_no_notification(self):
        with _run_thread_inline():
            with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
                resp = self.as_(self.member_user).post(
                    f"{API}/announcements/{self.announcement.id}/like/")

        self.assertEqual(resp.status_code, 200)
        send_mock.assert_not_called()


class CheckInNotificationTests(APITestCase):
    def setUp(self):
        self.gym = make_gym("CheckIn Gym")
        self.location = make_location(self.gym)
        self.staff = make_staff_user(self.gym, "checkinstaff@test.com",
                                     role=StaffProfile.STAFF, location=self.location)
        self.member_user = make_member_user(self.gym, self.location, "checkinmember@test.com")
        self.member = self.member_user.member_profile

    def as_staff(self):
        c = APIClient()
        c.force_authenticate(user=self.staff)
        return c

    def _post_checkin(self, member_id, checked_in_at):
        return self.as_staff().post(f"{API}/check-ins/", {
            "visit_type": "MEMBER", "member": str(member_id),
            "checked_in_at": checked_in_at.isoformat(),
        }, format="json")

    def test_fresh_checkin_notifies_the_member(self):
        with _run_thread_inline():
            with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
                resp = self._post_checkin(self.member.id, timezone.now())

        self.assertIn(resp.status_code, (200, 201))
        send_mock.assert_called_once()
        self.assertEqual(send_mock.call_args.args[0], [self.member_user])
        self.assertEqual(send_mock.call_args.kwargs["notif_type"], "checkin")

    def test_checkin_more_than_an_hour_old_does_not_notify(self):
        with _run_thread_inline():
            with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
                resp = self._post_checkin(
                    self.member.id, timezone.now() - timedelta(hours=2))

        self.assertIn(resp.status_code, (200, 201))
        send_mock.assert_not_called()

    def test_checkin_just_under_an_hour_old_still_notifies(self):
        with _run_thread_inline():
            with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
                resp = self._post_checkin(
                    self.member.id, timezone.now() - timedelta(minutes=59))

        self.assertIn(resp.status_code, (200, 201))
        send_mock.assert_called_once()

    def test_unclaimed_member_checkin_does_not_notify(self):
        unclaimed = Member.objects.create(
            gym=self.gym, home_location=self.location, first_name="No",
            last_name="Account", member_type=Member.MEMBER)

        with _run_thread_inline():
            with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
                resp = self._post_checkin(unclaimed.id, timezone.now())

        self.assertIn(resp.status_code, (200, 201))
        send_mock.assert_not_called()

    def test_walkin_checkin_does_not_notify(self):
        with _run_thread_inline():
            with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
                resp = self.as_staff().post(f"{API}/check-ins/", {
                    "visit_type": "WALKIN", "visitor_name": "Drop-in Dave",
                    "category": "regular", "checked_in_at": timezone.now().isoformat(),
                }, format="json")

        self.assertIn(resp.status_code, (200, 201))
        send_mock.assert_not_called()


class EventRegistrationNotificationTests(APITestCase):
    def setUp(self):
        self.gym = make_gym("Registration Gym")
        self.location = make_location(self.gym)
        self.owner = make_staff_user(self.gym, "regowner@test.com",
                                     role=StaffProfile.OWNER, location=self.location)
        self.staff = make_staff_user(self.gym, "regstaff@test.com",
                                     role=StaffProfile.STAFF, location=self.location)
        self.member_user = make_member_user(self.gym, self.location, "regmember@test.com")
        self.event = Event.objects.create(
            gym=self.gym, title="Summer Showdown", event_date="2026-10-12")

    def as_(self, user):
        c = APIClient()
        c.force_authenticate(user=user)
        return c

    def test_registration_notifies_owner_and_staff(self):
        with _run_thread_inline():
            with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
                resp = self.as_(self.member_user).post(
                    f"{API}/events/{self.event.id}/register/")

        self.assertIn(resp.status_code, (200, 201))
        send_mock.assert_called_once()
        recipients = send_mock.call_args.args[0]
        self.assertIn(self.owner, recipients)
        self.assertIn(self.staff, recipients)
        self.assertNotIn(self.member_user, recipients)
        self.assertEqual(send_mock.call_args.kwargs["notif_type"], "event_registration")

    def test_body_includes_member_name_event_and_count(self):
        with _run_thread_inline():
            with mock.patch("core.views.send_to_users", return_value=(0, 0)) as send_mock:
                self.as_(self.member_user).post(f"{API}/events/{self.event.id}/register/")

        body = send_mock.call_args.kwargs.get("body") or send_mock.call_args.args[2]
        self.assertIn("Test Member", body)
        self.assertIn("Summer Showdown", body)
        self.assertIn("1 registered", body)

    def test_creates_notification_send_row_per_recipient(self):
        with _run_thread_inline():
            with mock.patch("core.views.send_to_users", return_value=(0, 0)):
                resp = self.as_(self.member_user).post(
                    f"{API}/events/{self.event.id}/register/")

        registration = EventRegistration.objects.get(event=self.event)
        self.assertTrue(
            NotificationSend.objects.filter(
                user=self.owner, kind="event_registration",
                subject_id=registration.id).exists()
        )


class TrialReminderCommandTests(TestCase):
    def setUp(self):
        self.gym = make_gym("Trial Gym")
        self.location = make_location(self.gym)
        self.owner = make_staff_user(self.gym, "trialowner@test.com",
                                     role=StaffProfile.OWNER, location=self.location)

    def _sub(self, **kwargs):
        defaults = {"gym": self.gym, "status": Subscription.TRIALING}
        defaults.update(kwargs)
        return Subscription.objects.create(**defaults)

    def test_sends_3day_and_lastday_reminders(self):
        today = gym_today(self.gym)
        self._sub(trial_ends_at=timezone.now() + timedelta(days=3))

        with mock.patch(
            "core.management.commands.send_daily_notifications.send_to_users"
        ) as send_mock:
            call_command("send_daily_notifications")

        send_mock.assert_called_once()
        self.assertEqual(send_mock.call_args.args[0], [self.owner])
        self.assertEqual(send_mock.call_args.kwargs["data"]["type"], "trial_ending")
        self.assertTrue(
            NotificationSend.objects.filter(
                user=self.owner, kind="trial_3day").exists()
        )

    def test_active_subscription_is_never_reminded(self):
        self._sub(status=Subscription.ACTIVE,
                  trial_ends_at=timezone.now() + timedelta(days=3),
                  current_period_end=timezone.now() + timedelta(days=3))

        with mock.patch(
            "core.management.commands.send_daily_notifications.send_to_users"
        ) as send_mock:
            call_command("send_daily_notifications")

        send_mock.assert_not_called()

    def test_running_twice_sends_once(self):
        self._sub(trial_ends_at=timezone.now())  # ends today

        with mock.patch(
            "core.management.commands.send_daily_notifications.send_to_users"
        ) as send_mock:
            call_command("send_daily_notifications")
            call_command("send_daily_notifications")

        self.assertEqual(send_mock.call_count, 1)
        self.assertEqual(
            NotificationSend.objects.filter(
                user=self.owner, kind="trial_lastday").count(),
            1,
        )


class DailySummaryCommandTests(TestCase):
    def setUp(self):
        self.gym = make_gym("Summary Gym")
        self.location = make_location(self.gym)
        self.owner = make_staff_user(self.gym, "summaryowner@test.com",
                                     role=StaffProfile.OWNER, location=self.location)

    def _yesterday_range(self):
        today = gym_today(self.gym)
        yesterday = today - timedelta(days=1)
        tz = ZoneInfo(self.gym.timezone)
        start = datetime.combine(yesterday, datetime.min.time(), tzinfo=tz)
        return start + timedelta(hours=10)  # mid-morning yesterday

    def test_skips_when_zero_sales_and_zero_checkins(self):
        with mock.patch(
            "core.management.commands.send_daily_notifications.send_to_users"
        ) as send_mock:
            call_command("send_daily_notifications")

        send_mock.assert_not_called()

    def test_sends_with_totals_when_sales_present(self):
        member_user = make_member_user(self.gym, self.location, "summarymember@test.com")
        Sale.objects.create(
            gym=self.gym, member=member_user.member_profile,
            total_amount=Decimal("500.00"), sold_at=self._yesterday_range(),
            sold_by=self.owner,
        )

        with mock.patch(
            "core.management.commands.send_daily_notifications.send_to_users"
        ) as send_mock:
            call_command("send_daily_notifications")

        send_mock.assert_called_once()
        self.assertEqual(send_mock.call_args.args[0], [self.owner])
        body = send_mock.call_args.kwargs["body"]
        self.assertIn("500", body)
        self.assertEqual(send_mock.call_args.kwargs["data"]["type"], "daily_summary")

    def test_running_twice_sends_once(self):
        Sale.objects.create(
            gym=self.gym, total_amount=Decimal("100.00"),
            sold_at=self._yesterday_range(), sold_by=self.owner,
        )

        with mock.patch(
            "core.management.commands.send_daily_notifications.send_to_users"
        ) as send_mock:
            call_command("send_daily_notifications")
            call_command("send_daily_notifications")

        self.assertEqual(send_mock.call_count, 1)

    def test_voided_sale_does_not_count(self):
        Sale.objects.create(
            gym=self.gym, total_amount=Decimal("100.00"),
            sold_at=self._yesterday_range(), sold_by=self.owner,
            voided_at=timezone.now(),
        )

        with mock.patch(
            "core.management.commands.send_daily_notifications.send_to_users"
        ) as send_mock:
            call_command("send_daily_notifications")

        send_mock.assert_not_called()


class DeviceTokenTestPickerTests(APITestCase):
    def setUp(self):
        self.gym = make_gym("Picker Gym")
        self.location = make_location(self.gym)
        self.owner = make_staff_user(self.gym, "pickerowner@test.com",
                                     role=StaffProfile.OWNER, location=self.location)
        self.member_user = make_member_user(self.gym, self.location, "pickermember@test.com")

    def _auth(self, user):
        self.client.credentials(
            HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")

    def test_owner_sees_only_owner_facing_types(self):
        self._auth(self.owner)
        resp = self.client.get(f"{API}/devices/test/")

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        types = {t["type"] for t in resp.data["types"]}
        self.assertIn("out_of_stock", types)
        self.assertIn("daily_summary", types)
        self.assertNotIn("announcement", types)
        self.assertNotIn("checkin", types)

    def test_member_sees_only_member_facing_types(self):
        self._auth(self.member_user)
        resp = self.client.get(f"{API}/devices/test/")

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        types = {t["type"] for t in resp.data["types"]}
        self.assertIn("announcement", types)
        self.assertIn("checkin", types)
        self.assertNotIn("out_of_stock", types)

    def test_post_sends_sample_to_own_devices_only(self):
        other_user = make_staff_user(self.gym, "pickerother@test.com",
                                     role=StaffProfile.STAFF, location=self.location)
        DeviceToken.objects.create(user=self.owner, token="picker-own-tok", platform="android")
        DeviceToken.objects.create(user=other_user, token="picker-other-tok", platform="android")
        response = _multicast_response([True])

        self._auth(self.owner)
        with override_settings(FIREBASE_SERVICE_ACCOUNT_JSON=FAKE_SERVICE_ACCOUNT_JSON):
            with mock.patch.object(messaging, "send_each_for_multicast",
                                   return_value=response) as send_mock:
                resp = self.client.post(
                    f"{API}/devices/test/", {"type": "out_of_stock"}, format="json")

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        message = send_mock.call_args.args[0]
        self.assertEqual(message.tokens, ["picker-own-tok"])
        self.assertEqual(message.android.notification.channel_id, "channel_store")

    def test_post_rejects_type_for_wrong_role(self):
        self._auth(self.member_user)
        resp = self.client.post(
            f"{API}/devices/test/", {"type": "out_of_stock"}, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_post_rejects_unknown_type(self):
        self._auth(self.owner)
        resp = self.client.post(
            f"{API}/devices/test/", {"type": "not_a_real_type"}, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
