import threading
from datetime import timedelta

from django.db import connections
from django.test import TransactionTestCase
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from core.models import (Announcement, Event, EventRegistration, EventResult,
                         Gym, Location, Member, Membership, MembershipPlan,
                         StaffProfile, User)
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


class PrivacyTests(EventsTestBase):
    def test_event_detail_hides_other_registrations(self):
        self.register(self.member1_client, self.event.id)
        r = self.member2_client.get(f"{API}events/{self.event.id}/")
        self.assertEqual(r.status_code, 200)
        self.assertNotIn("registrations", r.data)
        self.assertNotIn("Ana", str(r.data))
        self.assertNotIn("Cruz", str(r.data))