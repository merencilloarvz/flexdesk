import threading
from datetime import timedelta

from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import IntegrityError, connections
from django.test import TransactionTestCase
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from core.models import (Announcement, Comment, Event, EventRegistration,
                         EventResult, Gym, Like, Location, Member, Membership,
                         MembershipPlan, StaffProfile, Subscription, User)
from core.utils import gym_today

API = "/api/v1/"


def auth_client(user):
    client = APIClient()
    token = RefreshToken.for_user(user).access_token
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
    return client


class EventsTestBase(TransactionTestCase):
    def setUp(self):
        self.gym = Gym.objects.create(name="Iron Works", slug="iron-works-events")
        self.location = Location.objects.create(gym=self.gym, name="Main")
        self.today = gym_today(self.gym)

        self.owner_user = User.objects.create_user(
            email="owner@events.test", password="testpass123", full_name="Owner")
        StaffProfile.objects.create(
            user=self.owner_user, gym=self.gym, role=StaffProfile.OWNER,
            default_location=self.location)
        self.owner = auth_client(self.owner_user)

        self.staff_user = User.objects.create_user(
            email="staff@events.test", password="testpass123", full_name="Staff")
        StaffProfile.objects.create(
            user=self.staff_user, gym=self.gym, role=StaffProfile.STAFF,
            default_location=self.location)
        self.staff = auth_client(self.staff_user)

        self.plan = MembershipPlan.objects.create(
            gym=self.gym, name="Monthly", category="Regular",
            duration_value=1, duration_unit="MONTH", price=1000)

        self.member1_user, self.member1 = self._make_member_with_login(
            "m1@events.test", "Ana", "Cruz")
        self.member1_client = auth_client(self.member1_user)

        self.member2_user, self.member2 = self._make_member_with_login(
            "m2@events.test", "Ben", "Reyes")
        self.member2_client = auth_client(self.member2_user)

        self.event = Event.objects.create(
            gym=self.gym, title="Fall Classic",
            event_date=self.today + timedelta(days=7),
            registration_fee=500, capacity=1,
        )

    def _make_member_with_login(self, email, first, last, with_membership=True,
                                membership_status="active", archived=False):
        member = Member.objects.create(
            gym=self.gym, home_location=self.location, first_name=first,
            last_name=last, email=email, member_type=Member.MEMBER)
        if with_membership:
            if membership_status == "expired":
                start = self.today - timedelta(days=60)
            else:
                start = self.today - timedelta(days=1)
            Membership.objects.create(
                gym=self.gym, member=member, plan=self.plan, start_date=start)
        user = User.objects.create_user(
            email=email, password="testpass123", full_name=member.full_name)
        member.user = user
        member.save(update_fields=["user"])
        if archived:
            member.archived_at = timezone.now()
            member.save(update_fields=["archived_at"])
        return user, member

    def register(self, client, event_id):
        return client.post(f"{API}events/{event_id}/register/")


class AccessControlTests(EventsTestBase):
    def test_get_announcements_member_200(self):
        r = self.member1_client.get(f"{API}announcements/")
        self.assertEqual(r.status_code, 200)

    def test_post_announcements_member_403(self):
        r = self.member1_client.post(f"{API}announcements/",
                                     {"title": "Hi", "body": "Test"}, format="json")
        self.assertEqual(r.status_code, 403)

    def test_patch_announcement_member_403(self):
        ann = Announcement.objects.create(gym=self.gym, title="X", body="Y")
        r = self.member1_client.patch(f"{API}announcements/{ann.id}/",
                                      {"title": "Z"}, format="json")
        self.assertEqual(r.status_code, 403)

    def test_get_events_member_200(self):
        r = self.member1_client.get(f"{API}events/")
        self.assertEqual(r.status_code, 200)

    def test_post_events_member_403(self):
        r = self.member1_client.post(f"{API}events/", {
            "title": "New", "event_date": str(self.today + timedelta(days=10)),
        }, format="json")
        self.assertEqual(r.status_code, 403)

    def test_get_event_registrations_member_403(self):
        r = self.member1_client.get(f"{API}event-registrations/")
        self.assertEqual(r.status_code, 403)

    def test_mark_paid_member_403(self):
        reg = EventRegistration.objects.create(
            gym=self.gym, event=self.event, member=self.member1, amount_due=500)
        r = self.member1_client.post(f"{API}event-registrations/{reg.id}/mark-paid/")
        self.assertEqual(r.status_code, 403)

    def test_post_results_member_403(self):
        r = self.member1_client.post(
            f"{API}events/{self.event.id}/results/",
            [{"rank": 1, "display_name": "Ana"}], format="json")
        self.assertEqual(r.status_code, 403)

    def test_get_results_member_200(self):
        r = self.member1_client.get(f"{API}events/{self.event.id}/results/")
        self.assertEqual(r.status_code, 200)

    def test_verify_results_member_403(self):
        r = self.member1_client.post(
            f"{API}events/{self.event.id}/verify-results/")
        self.assertEqual(r.status_code, 403)

    def test_unverify_results_member_403(self):
        r = self.member1_client.post(
            f"{API}events/{self.event.id}/unverify-results/")
        self.assertEqual(r.status_code, 403)

    def test_register_staff_403(self):
        r = self.register(self.staff, self.event.id)
        self.assertEqual(r.status_code, 403)


class CrossTenantTests(EventsTestBase):
    def test_announcements_isolated_by_gym(self):
        Announcement.objects.create(gym=self.gym, title="Gym A news", body="...")
        other_gym = Gym.objects.create(name="Other Gym", slug="other-gym-events")
        other_location = Location.objects.create(gym=other_gym, name="Main")
        other_plan = MembershipPlan.objects.create(
            gym=other_gym, name="Monthly", category="Regular",
            duration_value=1, duration_unit="MONTH", price=1000)
        other_member = Member.objects.create(
            gym=other_gym, home_location=other_location, first_name="Cid",
            email="cid@other.test", member_type=Member.MEMBER)
        Membership.objects.create(
            gym=other_gym, member=other_member, plan=other_plan,
            start_date=self.today - timedelta(days=1))
        other_user = User.objects.create_user(
            email="cid@other.test", password="testpass123", full_name="Cid")
        other_member.user = other_user
        other_member.save(update_fields=["user"])
        other_client = auth_client(other_user)

        r = other_client.get(f"{API}announcements/")
        self.assertEqual(r.status_code, 200)
        results = r.data["results"] if isinstance(r.data, dict) and "results" in r.data else r.data
        self.assertEqual(results, [])

    def test_register_other_gyms_event_404(self):
        other_gym = Gym.objects.create(name="Other Gym 2", slug="other-gym-events-2")
        other_event = Event.objects.create(
            gym=other_gym, title="Other Event",
            event_date=self.today + timedelta(days=5))
        r = self.register(self.member1_client, other_event.id)
        self.assertEqual(r.status_code, 404)

    def test_mark_paid_other_gyms_registration_404(self):
        other_gym = Gym.objects.create(name="Other Gym 3", slug="other-gym-events-3")
        other_location = Location.objects.create(gym=other_gym, name="Main")
        other_member = Member.objects.create(
            gym=other_gym, home_location=other_location, first_name="Dee",
            email="dee@other.test", member_type=Member.MEMBER)
        other_event = Event.objects.create(
            gym=other_gym, title="Other Event",
            event_date=self.today + timedelta(days=5))
        other_reg = EventRegistration.objects.create(
            gym=other_gym, event=other_event, member=other_member, amount_due=0)

        r = self.owner.post(f"{API}event-registrations/{other_reg.id}/mark-paid/")
        self.assertEqual(r.status_code, 404)


class CapacityConstraintTests(EventsTestBase):
    def test_capacity_one_second_registration_rejected(self):
        r1 = self.register(self.member1_client, self.event.id)
        self.assertEqual(r1.status_code, 201)
        r2 = self.register(self.member2_client, self.event.id)
        self.assertEqual(r2.status_code, 400)

    def test_concurrent_registration_last_spot(self):
        results = []

        def attempt(user):
            try:
                client = auth_client(user)
                resp = self.register(client, self.event.id)
                results.append(resp.status_code)
            finally:
                connections.close_all()

        t1 = threading.Thread(target=attempt, args=(self.member1_user,))
        t2 = threading.Thread(target=attempt, args=(self.member2_user,))
        t1.start(); t2.start()
        t1.join(); t2.join()

        self.assertEqual(sorted(results), [201, 400])
        self.assertEqual(
            EventRegistration.objects.filter(
                event=self.event, canceled_at__isnull=True).count(), 1)

    def test_register_cancel_reregister_succeeds(self):
        r1 = self.register(self.member1_client, self.event.id)
        self.assertEqual(r1.status_code, 201)
        cancel = self.member1_client.post(f"{API}events/{self.event.id}/unregister/")
        self.assertEqual(cancel.status_code, 200)
        r2 = self.register(self.member1_client, self.event.id)
        self.assertEqual(r2.status_code, 201)

    def test_register_twice_without_cancel_fails(self):
        r1 = self.register(self.member1_client, self.event.id)
        self.assertEqual(r1.status_code, 201)
        r2 = self.register(self.member1_client, self.event.id)
        self.assertEqual(r2.status_code, 400)

    def test_capacity_null_allows_many(self):
        self.event.capacity = None
        self.event.save()
        r1 = self.register(self.member1_client, self.event.id)
        r2 = self.register(self.member2_client, self.event.id)
        self.assertEqual(r1.status_code, 201)
        self.assertEqual(r2.status_code, 201)


class CorrectnessTests(EventsTestBase):
    def test_amount_due_snapshotted(self):
        r1 = self.register(self.member1_client, self.event.id)
        self.assertEqual(r1.status_code, 201)
        reg = EventRegistration.objects.get(id=r1.data["id"])
        self.assertEqual(str(reg.amount_due), "500.00")

        self.event.registration_fee = 999
        self.event.save()

        reg.refresh_from_db()
        self.assertEqual(str(reg.amount_due), "500.00")

    def test_registration_after_deadline_rejected(self):
        self.event.registration_closes_on = self.today - timedelta(days=1)
        self.event.save()
        r = self.register(self.member1_client, self.event.id)
        self.assertEqual(r.status_code, 400)

    def test_registration_for_canceled_event_rejected(self):
        self.event.canceled_at = timezone.now()
        self.event.save()
        r = self.register(self.member1_client, self.event.id)
        self.assertEqual(r.status_code, 400)

    def test_archived_member_cannot_register(self):
        user, member = self._make_member_with_login(
            "archived@events.test", "Ar", "Chived", archived=True)
        client = auth_client(user)
        r = self.register(client, self.event.id)
        self.assertEqual(r.status_code, 400)

    def test_expired_member_can_register(self):
        user, member = self._make_member_with_login(
            "expired@events.test", "Ex", "Pired", membership_status="expired")
        client = auth_client(user)
        r = self.register(client, self.event.id)
        self.assertEqual(r.status_code, 201)

    def test_mark_paid_then_unpaid(self):
        r1 = self.register(self.member1_client, self.event.id)
        reg_id = r1.data["id"]

        paid = self.owner.post(f"{API}event-registrations/{reg_id}/mark-paid/")
        self.assertEqual(paid.status_code, 200)
        self.assertEqual(paid.data["payment_status"], "paid")

        unpaid = self.owner.post(f"{API}event-registrations/{reg_id}/mark-unpaid/")
        self.assertEqual(unpaid.status_code, 200)
        self.assertEqual(unpaid.data["payment_status"], "unpaid")
        self.assertIsNone(unpaid.data["paid_at"])

    def test_duplicate_ranks_rejected_nothing_written(self):
        r = self.owner.post(f"{API}events/{self.event.id}/results/", [
            {"rank": 1, "display_name": "Ana"},
            {"rank": 1, "display_name": "Ben"},
        ], format="json")
        self.assertEqual(r.status_code, 400)
        self.assertEqual(EventResult.objects.filter(event=self.event).count(), 0)

    def test_result_display_name_survives_member_archive(self):
        r = self.owner.post(f"{API}events/{self.event.id}/results/", [
            {"rank": 1, "member": str(self.member1.id)},
        ], format="json")
        self.assertEqual(r.status_code, 201)

        self.member1.archived_at = timezone.now()
        self.member1.save(update_fields=["archived_at"])

        result = EventResult.objects.get(event=self.event, rank=1)
        self.assertEqual(result.display_name, "Ana Cruz")

    def test_registration_fee_serializes_as_string(self):
        r = self.owner.get(f"{API}events/{self.event.id}/")
        self.assertEqual(r.status_code, 200)
        self.assertIsInstance(r.data["registration_fee"], str)

    def test_guidelines_saved_and_returned_on_create(self):
        r = self.owner.post(f"{API}events/", {
            "title": "Guidelines Cup",
            "event_date": str(self.today + timedelta(days=14)),
            "guidelines": "No open shoes. Weigh-ins start at 7am.",
        }, format="json")
        self.assertEqual(r.status_code, 201)
        self.assertEqual(r.data["guidelines"], "No open shoes. Weigh-ins start at 7am.")
        event = Event.objects.get(id=r.data["id"])
        self.assertEqual(event.guidelines, "No open shoes. Weigh-ins start at 7am.")

    def test_guidelines_saved_and_returned_on_update(self):
        r = self.owner.patch(f"{API}events/{self.event.id}/", {
            "guidelines": "Bring your own gear.",
        }, format="json")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["guidelines"], "Bring your own gear.")
        self.event.refresh_from_db()
        self.assertEqual(self.event.guidelines, "Bring your own gear.")

    def test_guidelines_blank_by_default(self):
        r = self.owner.get(f"{API}events/{self.event.id}/")
        self.assertEqual(r.status_code, 200)
        self.assertIn(r.data["guidelines"], (None, ""))

    def test_verify_results_sets_verified_and_timestamp(self):
        self.owner.post(f"{API}events/{self.event.id}/results/", [
            {"rank": 1, "display_name": "Ana"},
        ], format="json")

        r = self.owner.post(f"{API}events/{self.event.id}/verify-results/")
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.data["results_verified"])
        self.assertIsNotNone(r.data["results_verified_at"])

        self.event.refresh_from_db()
        self.assertTrue(self.event.results_verified)
        self.assertIsNotNone(self.event.results_verified_at)

    def test_verify_results_rejected_with_no_results(self):
        r = self.owner.post(f"{API}events/{self.event.id}/verify-results/")
        self.assertEqual(r.status_code, 400)
        self.event.refresh_from_db()
        self.assertFalse(self.event.results_verified)

    def test_unverify_results_resets_verified_and_timestamp(self):
        self.owner.post(f"{API}events/{self.event.id}/results/", [
            {"rank": 1, "display_name": "Ana"},
        ], format="json")
        self.owner.post(f"{API}events/{self.event.id}/verify-results/")

        r = self.owner.post(f"{API}events/{self.event.id}/unverify-results/")
        self.assertEqual(r.status_code, 200)
        self.assertFalse(r.data["results_verified"])
        self.assertIsNone(r.data["results_verified_at"])

        self.event.refresh_from_db()
        self.assertFalse(self.event.results_verified)
        self.assertIsNone(self.event.results_verified_at)


class PrivacyTests(EventsTestBase):
    def test_event_detail_hides_other_registrations(self):
        self.register(self.member1_client, self.event.id)
        r = self.member2_client.get(f"{API}events/{self.event.id}/")
        self.assertEqual(r.status_code, 200)
        self.assertNotIn("registrations", r.data)
        self.assertNotIn("Ana", str(r.data))
        self.assertNotIn("Cruz", str(r.data))


class EngagementTestsMixin:
    """
    Likes and comments behave identically on announcements and events, so
    the tests are written once here and run against both — see
    EventLikeCommentTests below and AnnouncementLikeCommentTests in
    test_announcements.py. Subclasses set `kind` (the URL prefix) and
    `make_item`.
    """
    kind = None

    def make_item(self, gym):
        raise NotImplementedError

    @property
    def item_field(self):
        return "event" if self.kind == "events" else "announcement"

    def setUp(self):
        super().setUp()
        self.item = self.make_item(self.gym)

    def url(self, suffix="", item=None):
        return f"{API}{self.kind}/{(item or self.item).id}/{suffix}"

    def like(self, client, item=None):
        return client.post(self.url("like/", item))

    def comment(self, client, body="Great!", item=None):
        return client.post(self.url("comments/", item), {"body": body}, format="json")

    def listed(self, client):
        r = client.get(f"{API}{self.kind}/")
        self.assertEqual(r.status_code, 200)
        return next(row for row in r.data["results"]
                    if row["id"] == str(self.item.id))

    def other_gym(self):
        gym = Gym.objects.create(name="Elsewhere", slug=f"elsewhere-{self.kind}")
        location = Location.objects.create(gym=gym, name="Main")
        member = Member.objects.create(
            gym=gym, home_location=location, first_name="Cid",
            email=f"cid@{self.kind}.test", member_type=Member.MEMBER)
        user = User.objects.create_user(
            email=f"cid@{self.kind}.test", password="testpass123", full_name="Cid")
        member.user = user
        member.save(update_fields=["user"])
        return gym, auth_client(user), self.make_item(gym)

    # ---- likes ----

    def test_like_toggles_on_and_off(self):
        r = self.like(self.member1_client)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data, {"like_count": 1, "liked_by_me": True})
        self.assertEqual(Like.objects.count(), 1)

        r = self.like(self.member1_client)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data, {"like_count": 0, "liked_by_me": False})
        self.assertEqual(Like.objects.count(), 0)

    def test_repeated_likes_never_double_count(self):
        for _ in range(5):
            self.like(self.member1_client)
        # Five taps is on/off/on/off/on — one like, not five.
        self.assertEqual(Like.objects.filter(user=self.member1_user).count(), 1)
        self.assertEqual(self.listed(self.member1_client)["like_count"], 1)

    def test_duplicate_like_rejected_by_database(self):
        Like.objects.create(gym=self.gym, user=self.member1_user,
                            **{self.item_field: self.item})
        with self.assertRaises(IntegrityError):
            Like.objects.bulk_create([Like(gym=self.gym, user=self.member1_user,
                                           **{self.item_field: self.item})])

    def test_duplicate_like_rejected_by_model_validation(self):
        Like.objects.create(gym=self.gym, user=self.member1_user,
                            **{self.item_field: self.item})
        with self.assertRaises(DjangoValidationError):
            Like.objects.create(gym=self.gym, user=self.member1_user,
                                **{self.item_field: self.item})

    def test_like_count_and_liked_by_me_are_per_viewer(self):
        self.like(self.member1_client)
        self.like(self.member2_client)
        self.like(self.staff)

        row = self.listed(self.member1_client)
        self.assertEqual(row["like_count"], 3)
        self.assertTrue(row["liked_by_me"])

        # The owner hasn't liked it: sees the same count, not their own like.
        row = self.listed(self.owner)
        self.assertEqual(row["like_count"], 3)
        self.assertFalse(row["liked_by_me"])

    def test_unliking_only_removes_own_like(self):
        self.like(self.member1_client)
        self.like(self.member2_client)
        self.like(self.member1_client)   # member1 un-likes
        row = self.listed(self.member2_client)
        self.assertEqual(row["like_count"], 1)
        self.assertTrue(row["liked_by_me"])

    def test_like_state_on_detail(self):
        self.like(self.member1_client)
        r = self.member1_client.get(f"{API}{self.kind}/{self.item.id}/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["like_count"], 1)
        self.assertTrue(r.data["liked_by_me"])

    def test_like_fields_are_read_only(self):
        r = self.owner.patch(f"{API}{self.kind}/{self.item.id}/",
                             {"like_count": 99, "liked_by_me": True}, format="json")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["like_count"], 0)
        self.assertFalse(r.data["liked_by_me"])

    def test_staff_and_owner_can_like(self):
        self.assertEqual(self.like(self.staff).status_code, 200)
        self.assertEqual(self.like(self.owner).status_code, 200)
        self.assertEqual(Like.objects.count(), 2)

    def test_racing_duplicate_insert_is_a_noop(self):
        # The loser of a double-tap race hits the unique constraint; the
        # view inserts with ignore_conflicts so that's a no-op, not a 500.
        Like.objects.bulk_create(
            [Like(gym=self.gym, user=self.member1_user, **{self.item_field: self.item})])
        Like.objects.bulk_create(
            [Like(gym=self.gym, user=self.member1_user, **{self.item_field: self.item})],
            ignore_conflicts=True)
        self.assertEqual(Like.objects.count(), 1)

    # ---- comments ----

    def test_comment_create_and_list(self):
        r = self.comment(self.member1_client, "  Can't wait!  ")
        self.assertEqual(r.status_code, 201)
        self.assertEqual(r.data["body"], "Can't wait!")
        self.assertEqual(r.data["author_name"], "Ana Cruz")
        self.assertEqual(r.data["author_role"], "member")
        self.assertTrue(r.data["is_mine"])

        r = self.member2_client.get(self.url("comments/"))
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["count"], 1)
        row = r.data["results"][0]
        self.assertEqual(row["body"], "Can't wait!")
        self.assertFalse(row["is_mine"])
        self.assertFalse(row["can_delete"])

    def test_staff_comment_shows_staff_role(self):
        r = self.comment(self.owner, "See you there")
        self.assertEqual(r.status_code, 201)
        self.assertEqual(r.data["author_role"], "owner")
        self.assertEqual(r.data["author_name"], "Owner")
        r = self.comment(self.staff, "Me too")
        self.assertEqual(r.data["author_role"], "staff")

    def test_comment_does_not_leak_identity(self):
        self.comment(self.member1_client)
        r = self.member2_client.get(self.url("comments/"))
        row = r.data["results"][0]
        self.assertEqual(
            set(row), {"id", "body", "author_name", "author_role", "is_mine",
                       "can_delete", "created_at"})
        self.assertNotIn("m1@events.test", str(r.data))

    def test_comments_listed_oldest_first_and_reorderable(self):
        for body in ("first", "second", "third"):
            self.comment(self.member1_client, body)
        r = self.member1_client.get(self.url("comments/"))
        self.assertEqual([c["body"] for c in r.data["results"]],
                         ["first", "second", "third"])
        r = self.member1_client.get(self.url("comments/") + "?ordering=-created_at")
        self.assertEqual([c["body"] for c in r.data["results"]],
                         ["third", "second", "first"])

    def test_comments_are_paginated(self):
        Comment.objects.bulk_create([
            Comment(gym=self.gym, user=self.member1_user, body=f"c{i}",
                    **{self.item_field: self.item})
            for i in range(51)])
        r = self.member1_client.get(self.url("comments/"))
        self.assertEqual(r.data["count"], 51)
        self.assertEqual(len(r.data["results"]), 50)
        self.assertIsNotNone(r.data["next"])
        r = self.member1_client.get(self.url("comments/") + "?page=2")
        self.assertEqual(len(r.data["results"]), 1)

    def test_comments_scoped_to_their_own_item(self):
        other_item = self.make_item(self.gym)
        self.comment(self.member1_client, "on the first")
        self.comment(self.member1_client, "on the second", item=other_item)
        r = self.member1_client.get(self.url("comments/"))
        self.assertEqual([c["body"] for c in r.data["results"]], ["on the first"])

    def test_blank_and_oversized_comment_rejected(self):
        self.assertEqual(self.comment(self.member1_client, "   ").status_code, 400)
        self.assertEqual(self.comment(self.member1_client, "x" * 1001).status_code, 400)
        r = self.member1_client.post(self.url("comments/"), {}, format="json")
        self.assertEqual(r.status_code, 400)
        self.assertEqual(Comment.objects.count(), 0)

    def test_cannot_forge_comment_author_or_gym(self):
        r = self.member1_client.post(self.url("comments/"), {
            "body": "hi", "user": str(self.member2_user.id),
            "gym": str(self.gym.id)}, format="json")
        self.assertEqual(r.status_code, 201)
        self.assertEqual(Comment.objects.get().user_id, self.member1_user.id)

    def test_delete_own_comment(self):
        cid = self.comment(self.member1_client).data["id"]
        r = self.member1_client.delete(self.url(f"comments/{cid}/"))
        self.assertEqual(r.status_code, 204)
        self.assertEqual(Comment.objects.count(), 0)

    def test_cannot_delete_someone_elses_comment(self):
        cid = self.comment(self.member1_client).data["id"]
        r = self.member2_client.delete(self.url(f"comments/{cid}/"))
        self.assertEqual(r.status_code, 403)
        self.assertEqual(Comment.objects.count(), 1)

    def test_staff_can_delete_any_comment_for_moderation(self):
        cid = self.comment(self.member1_client).data["id"]
        row = self.staff.get(self.url("comments/")).data["results"][0]
        self.assertTrue(row["can_delete"])
        self.assertFalse(row["is_mine"])
        self.assertEqual(self.staff.delete(self.url(f"comments/{cid}/")).status_code, 204)
        cid = self.comment(self.member1_client).data["id"]
        self.assertEqual(self.owner.delete(self.url(f"comments/{cid}/")).status_code, 204)
        self.assertEqual(Comment.objects.count(), 0)

    def test_delete_comment_via_wrong_item_404(self):
        other_item = self.make_item(self.gym)
        cid = self.comment(self.member1_client).data["id"]
        r = self.member1_client.delete(self.url(f"comments/{cid}/", item=other_item))
        self.assertEqual(r.status_code, 404)
        self.assertEqual(Comment.objects.count(), 1)

    def test_delete_missing_comment_404(self):
        r = self.member1_client.delete(
            self.url("comments/00000000-0000-0000-0000-000000000000/"))
        self.assertEqual(r.status_code, 404)

    def test_comment_edit_not_supported(self):
        cid = self.comment(self.member1_client).data["id"]
        r = self.member1_client.patch(self.url(f"comments/{cid}/"),
                                      {"body": "changed"}, format="json")
        self.assertEqual(r.status_code, 405)
        self.assertEqual(Comment.objects.get().body, "Great!")

    def test_deleting_the_item_removes_its_likes_and_comments(self):
        self.like(self.member1_client)
        self.comment(self.member1_client)
        self.item.delete()
        self.assertEqual(Like.objects.count(), 0)
        self.assertEqual(Comment.objects.count(), 0)

    # ---- cross-tenant ----

    def test_cross_gym_like_404(self):
        _, client, _ = self.other_gym()
        self.assertEqual(self.like(client).status_code, 404)
        self.assertEqual(Like.objects.count(), 0)

    def test_cross_gym_comment_list_and_create_404(self):
        self.comment(self.member1_client)
        _, client, _ = self.other_gym()
        self.assertEqual(client.get(self.url("comments/")).status_code, 404)
        self.assertEqual(self.comment(client).status_code, 404)
        self.assertEqual(Comment.objects.count(), 1)

    def test_cross_gym_comment_delete_404(self):
        cid = self.comment(self.member1_client).data["id"]
        _, client, _ = self.other_gym()
        self.assertEqual(client.delete(self.url(f"comments/{cid}/")).status_code, 404)
        self.assertEqual(Comment.objects.count(), 1)

    def test_cross_gym_owner_blocked_too(self):
        # Staff of another gym get the same 404 — moderation rights stop
        # at the gym boundary.
        gym, _, other_item = self.other_gym()
        boss = User.objects.create_user(
            email=f"boss@{self.kind}.test", password="testpass123")
        StaffProfile.objects.create(user=boss, gym=gym, role=StaffProfile.OWNER)
        client = auth_client(boss)
        cid = self.comment(self.member1_client).data["id"]
        self.assertEqual(self.like(client, other_item).status_code, 200)
        self.assertEqual(self.like(client).status_code, 404)
        self.assertEqual(client.delete(self.url(f"comments/{cid}/")).status_code, 404)
        self.assertEqual(Comment.objects.count(), 1)

    def test_likes_do_not_cross_gyms_in_lists(self):
        self.like(self.member1_client)
        _, client, _ = self.other_gym()
        r = client.get(f"{API}{self.kind}/")
        self.assertEqual([row["like_count"] for row in r.data["results"]], [0])

    # ---- authentication / permissions ----

    def test_unauthenticated_blocked(self):
        anon = APIClient()
        cid = self.comment(self.member1_client).data["id"]
        self.assertEqual(anon.post(self.url("like/")).status_code, 401)
        self.assertEqual(anon.get(self.url("comments/")).status_code, 401)
        self.assertEqual(
            anon.post(self.url("comments/"), {"body": "x"}, format="json").status_code, 401)
        self.assertEqual(anon.delete(self.url(f"comments/{cid}/")).status_code, 401)

    def test_user_without_gym_blocked(self):
        drifter = User.objects.create_user(email="nogym@x.test", password="testpass123")
        client = auth_client(drifter)
        self.assertEqual(self.like(client).status_code, 403)
        self.assertEqual(client.get(self.url("comments/")).status_code, 403)

    def test_archived_member_can_read_but_not_engage(self):
        cid = self.comment(self.member1_client).data["id"]
        self.member1.archived_at = timezone.now()
        self.member1.save(update_fields=["archived_at"])
        self.assertEqual(self.like(self.member1_client).status_code, 403)
        self.assertEqual(self.comment(self.member1_client).status_code, 403)
        self.assertEqual(
            self.member1_client.delete(self.url(f"comments/{cid}/")).status_code, 403)
        self.assertEqual(self.member1_client.get(self.url("comments/")).status_code, 200)

    def test_lapsed_subscription_blocks_staff_writes_but_not_members(self):
        Subscription.objects.create(
            gym=self.gym, status=Subscription.PAST_DUE,
            trial_ends_at=timezone.now())
        self.assertEqual(self.like(self.owner).status_code, 402)
        self.assertEqual(self.comment(self.owner).status_code, 402)
        self.assertEqual(self.owner.get(self.url("comments/")).status_code, 200)
        self.assertEqual(self.like(self.member1_client).status_code, 200)
        self.assertEqual(self.comment(self.member1_client).status_code, 201)

    # ---- model invariants ----

    def test_like_and_comment_must_target_exactly_one_item(self):
        with self.assertRaises(DjangoValidationError):
            Like.objects.create(gym=self.gym, user=self.member1_user)
        with self.assertRaises(DjangoValidationError):
            Comment.objects.create(gym=self.gym, user=self.member1_user, body="x")
        announcement = Announcement.objects.create(gym=self.gym, title="A", body="B")
        event = Event.objects.create(
            gym=self.gym, title="E", event_date=self.today + timedelta(days=3))
        with self.assertRaises(DjangoValidationError):
            Like.objects.create(gym=self.gym, user=self.member1_user,
                                announcement=announcement, event=event)

    def test_like_and_comment_reject_cross_gym_target_or_user(self):
        other_gym, _, other_item = self.other_gym()
        with self.assertRaises(DjangoValidationError):
            Like.objects.create(gym=self.gym, user=self.member1_user,
                                **{self.item_field: other_item})
        with self.assertRaises(DjangoValidationError):
            Comment.objects.create(gym=other_gym, user=self.member1_user,
                                   body="x", **{self.item_field: other_item})


class EventLikeCommentTests(EngagementTestsMixin, EventsTestBase):
    kind = "events"

    def make_item(self, gym):
        return Event.objects.create(
            gym=gym, title="Fall Classic",
            event_date=self.today + timedelta(days=7))

    def test_likes_do_not_inflate_registration_count(self):
        # registration_count and like_count come from the same queryset; a
        # join-based like count would multiply the registration rows.
        # Three likes x one registration must still be one registration.
        self.register(self.member1_client, self.item.id)
        self.like(self.member1_client)
        self.like(self.member2_client)
        self.like(self.staff)
        row = self.listed(self.member1_client)
        self.assertEqual(row["registration_count"], 1)
        self.assertEqual(row["like_count"], 3)

    def test_like_state_present_on_verify_results_response(self):
        # Views that serialize an un-annotated Event fall back to querying.
        self.like(self.member1_client)
        EventResult.objects.create(gym=self.gym, event=self.item, rank=1,
                                   display_name="Ana")
        r = self.owner.post(f"{API}events/{self.item.id}/verify-results/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["like_count"], 1)
        self.assertFalse(r.data["liked_by_me"])
