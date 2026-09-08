import threading
from datetime import timedelta

from django.db import connections
from django.test import TransactionTestCase
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from core.models import (Booking, Gym, Location, Member, Membership,
                         MembershipPlan, StaffProfile, TimeSlot, User)
from core.utils import gym_today

API = "/api/v1/"


def auth_client(user):
    client = APIClient()
    token = RefreshToken.for_user(user).access_token
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
    return client


class SchedulingTestBase(TransactionTestCase):
    def setUp(self):
        self.gym = Gym.objects.create(
            name="Iron Works", slug="iron-works-sched", classes_enabled=True)
        self.location = Location.objects.create(gym=self.gym, name="Main")
        self.today = gym_today(self.gym)

        self.owner_user = User.objects.create_user(
            email="owner@sched.test", password="testpass123", full_name="Owner")
        StaffProfile.objects.create(
            user=self.owner_user, gym=self.gym, role=StaffProfile.OWNER,
            default_location=self.location)
        self.owner = auth_client(self.owner_user)

        self.staff_user = User.objects.create_user(
            email="staff@sched.test", password="testpass123", full_name="Staff")
        StaffProfile.objects.create(
            user=self.staff_user, gym=self.gym, role=StaffProfile.STAFF,
            default_location=self.location)
        self.staff = auth_client(self.staff_user)

        self.plan = MembershipPlan.objects.create(
            gym=self.gym, name="Monthly", category="Regular",
            duration_value=1, duration_unit="MONTH", price=1000)

        self.member1_user, self.member1 = self._make_member_with_login(
            "m1@sched.test", "Ana", "Cruz")
        self.member1_client = auth_client(self.member1_user)

        self.member2_user, self.member2 = self._make_member_with_login(
            "m2@sched.test", "Ben", "Reyes")
        self.member2_client = auth_client(self.member2_user)

        # runs every day, capacity 1
        self.slot = TimeSlot.objects.create(
            gym=self.gym, label="Morning", start_time="06:00", end_time="07:00",
            capacity=1, days_of_week="1,2,3,4,5,6,7")

    def _make_member_with_login(self, email, first, last, with_membership=True,
                                membership_status="active"):
        member = Member.objects.create(
            gym=self.gym, home_location=self.location, first_name=first,
            last_name=last, email=email, member_type=Member.MEMBER)
        if with_membership:
            if membership_status == "expired":
                start = self.today - timedelta(days=60)
                Membership.objects.create(
                    gym=self.gym, member=member, plan=self.plan, start_date=start)
            else:
                start = self.today - timedelta(days=1)
                Membership.objects.create(
                    gym=self.gym, member=member, plan=self.plan, start_date=start)
        user = User.objects.create_user(
            email=email, password="testpass123", full_name=member.full_name)
        member.user = user
        member.save(update_fields=["user"])
        return user, member

    def book(self, client, slot_id, date_, extra=None):
        body = {"time_slot": str(slot_id), "date": str(date_)}
        if extra:
            body.update(extra)
        return client.post(f"{API}bookings/", body, format="json")


class CapacityTests(SchedulingTestBase):
    def test_capacity_one_second_booking_rejected(self):
        r1 = self.book(self.member1_client, self.slot.id, self.today)
        self.assertEqual(r1.status_code, 201)
        r2 = self.book(self.member2_client, self.slot.id, self.today)
        self.assertEqual(r2.status_code, 400)

    def test_concurrent_booking_last_spot(self):
        results = []

        def attempt(user):
            try:
                client = auth_client(user)
                resp = self.book(client, self.slot.id, self.today)
                results.append(resp.status_code)
            finally:
                connections.close_all()

        t1 = threading.Thread(target=attempt, args=(self.member1_user,))
        t2 = threading.Thread(target=attempt, args=(self.member2_user,))
        t1.start(); t2.start()
        t1.join(); t2.join()

        self.assertEqual(sorted(results), [201, 400])
        self.assertEqual(
            Booking.objects.filter(
                time_slot=self.slot, date=self.today, canceled_at__isnull=True
            ).count(), 1)

    def test_cancel_frees_spot(self):
        r1 = self.book(self.member1_client, self.slot.id, self.today)
        booking_id = r1.data["id"]
        cancel = self.member1_client.post(f"{API}bookings/{booking_id}/cancel/")
        self.assertEqual(cancel.status_code, 200)
        r2 = self.book(self.member2_client, self.slot.id, self.today)
        self.assertEqual(r2.status_code, 201)


class ConstraintTests(SchedulingTestBase):
    def test_book_cancel_rebook_succeeds(self):
        r1 = self.book(self.member1_client, self.slot.id, self.today)
        self.assertEqual(r1.status_code, 201)
        booking_id = r1.data["id"]
        self.member1_client.post(f"{API}bookings/{booking_id}/cancel/")
        r2 = self.book(self.member1_client, self.slot.id, self.today)
        self.assertEqual(r2.status_code, 201)

    def test_book_twice_without_cancel_fails(self):
        r1 = self.book(self.member1_client, self.slot.id, self.today)
        self.assertEqual(r1.status_code, 201)
        r2 = self.book(self.member1_client, self.slot.id, self.today)
        self.assertEqual(r2.status_code, 400)

    def test_two_different_members_both_succeed_within_capacity(self):
        self.slot.capacity = 2
        self.slot.save()
        r1 = self.book(self.member1_client, self.slot.id, self.today)
        r2 = self.book(self.member2_client, self.slot.id, self.today)
        self.assertEqual(r1.status_code, 201)
        self.assertEqual(r2.status_code, 201)
    def test_lowering_capacity_below_future_bookings_rejected(self):
        self.slot.capacity = 3
        self.slot.save()
        r1 = self.book(self.member1_client, self.slot.id, self.today)
        r2 = self.book(self.member2_client, self.slot.id, self.today)
        self.assertEqual(r1.status_code, 201)
        self.assertEqual(r2.status_code, 201)

        r = self.owner.patch(f"{API}time-slots/{self.slot.id}/",
                             {"capacity": 1}, format="json")
        self.assertEqual(r.status_code, 400)
        self.assertIn("2", str(r.data))
        self.assertIn(str(self.today), str(r.data))

    def test_lowering_capacity_below_past_bookings_succeeds(self):
        past_date = self.today - timedelta(days=1)
        Booking.objects.create(
            gym=self.gym, member=self.member1, time_slot=self.slot,
            date=past_date)
        Booking.objects.create(
            gym=self.gym, member=self.member2, time_slot=self.slot,
            date=past_date)

        r = self.owner.patch(f"{API}time-slots/{self.slot.id}/",
                             {"capacity": 1}, format="json")
        self.assertEqual(r.status_code, 200)


class ValidationTests(SchedulingTestBase):
    def test_wrong_weekday(self):
        self.slot.days_of_week = str(self.today.isoweekday() % 7 + 1)  # a day it's NOT
        self.slot.save()
        r = self.book(self.member1_client, self.slot.id, self.today)
        self.assertEqual(r.status_code, 400)

    def test_past_date(self):
        r = self.book(self.member1_client, self.slot.id, self.today - timedelta(days=1))
        self.assertEqual(r.status_code, 400)

    def test_horizon(self):
        r_over = self.book(self.member1_client, self.slot.id,
                           self.today + timedelta(days=15))
        self.assertEqual(r_over.status_code, 400)
        r_ok = self.book(self.member2_client, self.slot.id,
                         self.today + timedelta(days=14))
        self.assertEqual(r_ok.status_code, 201)

    def test_inactive_slot(self):
        self.slot.is_active = False
        self.slot.save()
        r = self.book(self.member1_client, self.slot.id, self.today)
        self.assertEqual(r.status_code, 404)

    def test_expired_member(self):
        user, member = self._make_member_with_login(
            "expired@sched.test", "Ex", "Pired", membership_status="expired")
        client = auth_client(user)
        r = self.book(client, self.slot.id, self.today)
        self.assertEqual(r.status_code, 400)

    def test_no_membership_member(self):
        user, member = self._make_member_with_login(
            "nomem@sched.test", "No", "Mem", with_membership=False)
        client = auth_client(user)
        r = self.book(client, self.slot.id, self.today)
        self.assertEqual(r.status_code, 400)

    def test_archived_member_cannot_book(self):
        user, member = self._make_member_with_login(
            "archived@sched.test", "Ar", "Chived")
        member.archived_at = timezone.now()
        member.save(update_fields=["archived_at"])
        client = auth_client(user)
        r = self.book(client, self.slot.id, self.today)
        self.assertEqual(r.status_code, 400)


class AccessControlTests(SchedulingTestBase):
    def test_staff_post_bookings_403(self):
        r = self.book(self.staff, self.slot.id, self.today)
        self.assertEqual(r.status_code, 403)

    def test_staff_get_schedule_403(self):
        r = self.staff.get(f"{API}schedule/")
        self.assertEqual(r.status_code, 403)

    def test_member_post_timeslots_403(self):
        r = self.member1_client.post(f"{API}time-slots/", {
            "label": "Evening", "start_time": "18:00", "end_time": "19:00",
            "capacity": 5, "days_of_week": "1,2,3,4,5",
        }, format="json")
        self.assertEqual(r.status_code, 403)

    def test_member_get_timeslot_bookings_403(self):
        r = self.member1_client.get(f"{API}time-slots/{self.slot.id}/bookings/")
        self.assertEqual(r.status_code, 403)

    def test_cross_gym_slot_404(self):
        other_gym = Gym.objects.create(name="Other Gym", slug="other-gym-sched")
        other_slot = TimeSlot.objects.create(
            gym=other_gym, label="Other", start_time="06:00", end_time="07:00",
            capacity=5, days_of_week="1,2,3,4,5,6,7")
        r = self.book(self.member1_client, other_slot.id, self.today)
        self.assertEqual(r.status_code, 404)

    def test_cancel_other_members_booking_404(self):
        r1 = self.book(self.member1_client, self.slot.id, self.today)
        booking_id = r1.data["id"]
        r2 = self.member2_client.post(f"{API}bookings/{booking_id}/cancel/")
        self.assertEqual(r2.status_code, 404)

    def test_member_field_in_body_ignored(self):
        r = self.book(self.member1_client, self.slot.id, self.today,
                      extra={"member": str(self.member2.id)})
        self.assertEqual(r.status_code, 201)
        booking = Booking.objects.get(id=r.data["id"])
        self.assertEqual(booking.member_id, self.member1.id)


class ClassesToggleTests(SchedulingTestBase):
    def test_disabled_owner_403_on_timeslots(self):
        self.gym.classes_enabled = False
        self.gym.save(update_fields=["classes_enabled"])
        r = self.owner.get(f"{API}time-slots/")
        self.assertEqual(r.status_code, 403)

    def test_disabled_member_403_on_schedule(self):
        self.gym.classes_enabled = False
        self.gym.save(update_fields=["classes_enabled"])
        r = self.member1_client.get(f"{API}schedule/")
        self.assertEqual(r.status_code, 403)

    def test_disabled_member_403_on_booking_post(self):
        self.gym.classes_enabled = False
        self.gym.save(update_fields=["classes_enabled"])
        r = self.book(self.member1_client, self.slot.id, self.today)
        self.assertEqual(r.status_code, 403)

    def test_disabled_member_403_on_my_bookings(self):
        self.gym.classes_enabled = False
        self.gym.save(update_fields=["classes_enabled"])
        r = self.member1_client.get(f"{API}me/bookings/")
        self.assertEqual(r.status_code, 403)

    def test_disabled_member_403_on_cancel(self):
        r1 = self.book(self.member1_client, self.slot.id, self.today)
        booking_id = r1.data["id"]
        self.gym.classes_enabled = False
        self.gym.save(update_fields=["classes_enabled"])
        r2 = self.member1_client.post(f"{API}bookings/{booking_id}/cancel/")
        self.assertEqual(r2.status_code, 403)

    def test_me_returns_classes_enabled_for_owner(self):
        r = self.owner.get(f"{API}auth/me/")
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.data["gym"]["classes_enabled"])

    def test_me_returns_classes_enabled_for_member(self):
        r = self.member1_client.get(f"{API}auth/me/")
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.data["gym"]["classes_enabled"])

    def test_toggle_off_then_on_leaves_bookings_intact(self):
        self.book(self.member1_client, self.slot.id, self.today)
        count_before = Booking.objects.filter(gym=self.gym).count()
        self.assertEqual(count_before, 1)

        self.gym.classes_enabled = False
        self.gym.save(update_fields=["classes_enabled"])
        self.assertEqual(Booking.objects.filter(gym=self.gym).count(), 1)

        self.gym.classes_enabled = True
        self.gym.save(update_fields=["classes_enabled"])
        self.assertEqual(Booking.objects.filter(gym=self.gym).count(), 1)

class CapacityTests(SchedulingTestBase):
    def test_capacity_one_second_booking_rejected(self):
        r1 = self.book(self.member1_client, self.slot.id, self.today)
        self.assertEqual(r1.status_code, 201)
        r2 = self.book(self.member2_client, self.slot.id, self.today)
        self.assertEqual(r2.status_code, 400)

    def test_concurrent_booking_last_spot(self):
        results = []

        def attempt(user):
            try:
                client = auth_client(user)
                resp = self.book(client, self.slot.id, self.today)
                results.append(resp.status_code)
            finally:
                connections.close_all()

        t1 = threading.Thread(target=attempt, args=(self.member1_user,))
        t2 = threading.Thread(target=attempt, args=(self.member2_user,))
        t1.start(); t2.start()
        t1.join(); t2.join()

        self.assertEqual(sorted(results), [201, 400])
        self.assertEqual(
            Booking.objects.filter(
                time_slot=self.slot, date=self.today, canceled_at__isnull=True
            ).count(), 1)

    def test_cancel_frees_spot(self):
        r1 = self.book(self.member1_client, self.slot.id, self.today)
        booking_id = r1.data["id"]
        cancel = self.member1_client.post(f"{API}bookings/{booking_id}/cancel/")
        self.assertEqual(cancel.status_code, 200)
        r2 = self.book(self.member2_client, self.slot.id, self.today)
        self.assertEqual(r2.status_code, 201)


class ConstraintTests(SchedulingTestBase):
    def test_book_cancel_rebook_succeeds(self):
        r1 = self.book(self.member1_client, self.slot.id, self.today)
        self.assertEqual(r1.status_code, 201)
        booking_id = r1.data["id"]
        self.member1_client.post(f"{API}bookings/{booking_id}/cancel/")
        r2 = self.book(self.member1_client, self.slot.id, self.today)
        self.assertEqual(r2.status_code, 201)

    def test_book_twice_without_cancel_fails(self):
        r1 = self.book(self.member1_client, self.slot.id, self.today)
        self.assertEqual(r1.status_code, 201)
        r2 = self.book(self.member1_client, self.slot.id, self.today)
        self.assertEqual(r2.status_code, 400)

    def test_two_different_members_both_succeed_within_capacity(self):
        self.slot.capacity = 2
        self.slot.save()
        r1 = self.book(self.member1_client, self.slot.id, self.today)
        r2 = self.book(self.member2_client, self.slot.id, self.today)
        self.assertEqual(r1.status_code, 201)
        self.assertEqual(r2.status_code, 201)
    def test_lowering_capacity_below_future_bookings_rejected(self):
        self.slot.capacity = 3
        self.slot.save()
        r1 = self.book(self.member1_client, self.slot.id, self.today)
        r2 = self.book(self.member2_client, self.slot.id, self.today)
        self.assertEqual(r1.status_code, 201)
        self.assertEqual(r2.status_code, 201)

        r = self.owner.patch(f"{API}time-slots/{self.slot.id}/",
                             {"capacity": 1}, format="json")
        self.assertEqual(r.status_code, 400)
        self.assertIn("2", str(r.data))
        self.assertIn(str(self.today), str(r.data))

    def test_lowering_capacity_below_past_bookings_succeeds(self):
        past_date = self.today - timedelta(days=1)
        Booking.objects.create(
            gym=self.gym, member=self.member1, time_slot=self.slot,
            date=past_date)
        Booking.objects.create(
            gym=self.gym, member=self.member2, time_slot=self.slot,
            date=past_date)

        r = self.owner.patch(f"{API}time-slots/{self.slot.id}/",
                             {"capacity": 1}, format="json")
        self.assertEqual(r.status_code, 200)


class ValidationTests(SchedulingTestBase):
    def test_wrong_weekday(self):
        self.slot.days_of_week = str(self.today.isoweekday() % 7 + 1)  # a day it's NOT
        self.slot.save()
        r = self.book(self.member1_client, self.slot.id, self.today)
        self.assertEqual(r.status_code, 400)

    def test_past_date(self):
        r = self.book(self.member1_client, self.slot.id, self.today - timedelta(days=1))
        self.assertEqual(r.status_code, 400)

    def test_horizon(self):
        r_over = self.book(self.member1_client, self.slot.id,
                           self.today + timedelta(days=15))
        self.assertEqual(r_over.status_code, 400)
        r_ok = self.book(self.member2_client, self.slot.id,
                         self.today + timedelta(days=14))
        self.assertEqual(r_ok.status_code, 201)

    def test_inactive_slot(self):
        self.slot.is_active = False
        self.slot.save()
        r = self.book(self.member1_client, self.slot.id, self.today)
        self.assertEqual(r.status_code, 404)

    def test_expired_member(self):
        user, member = self._make_member_with_login(
            "expired@sched.test", "Ex", "Pired", membership_status="expired")
        client = auth_client(user)
        r = self.book(client, self.slot.id, self.today)
        self.assertEqual(r.status_code, 400)

    def test_no_membership_member(self):
        user, member = self._make_member_with_login(
            "nomem@sched.test", "No", "Mem", with_membership=False)
        client = auth_client(user)
        r = self.book(client, self.slot.id, self.today)
        self.assertEqual(r.status_code, 400)

    def test_archived_member_cannot_book(self):
        user, member = self._make_member_with_login(
            "archived@sched.test", "Ar", "Chived")
        member.archived_at = timezone.now()
        member.save(update_fields=["archived_at"])
        client = auth_client(user)
        r = self.book(client, self.slot.id, self.today)
        self.assertEqual(r.status_code, 400)


class AccessControlTests(SchedulingTestBase):
    def test_staff_post_bookings_403(self):
        r = self.book(self.staff, self.slot.id, self.today)
        self.assertEqual(r.status_code, 403)

    def test_staff_get_schedule_403(self):
        r = self.staff.get(f"{API}schedule/")
        self.assertEqual(r.status_code, 403)

    def test_member_post_timeslots_403(self):
        r = self.member1_client.post(f"{API}time-slots/", {
            "label": "Evening", "start_time": "18:00", "end_time": "19:00",
            "capacity": 5, "days_of_week": "1,2,3,4,5",
        }, format="json")
        self.assertEqual(r.status_code, 403)

    def test_member_get_timeslot_bookings_403(self):
        r = self.member1_client.get(f"{API}time-slots/{self.slot.id}/bookings/")
        self.assertEqual(r.status_code, 403)

    def test_cross_gym_slot_404(self):
        other_gym = Gym.objects.create(name="Other Gym", slug="other-gym-sched")
        other_slot = TimeSlot.objects.create(
            gym=other_gym, label="Other", start_time="06:00", end_time="07:00",
            capacity=5, days_of_week="1,2,3,4,5,6,7")
        r = self.book(self.member1_client, other_slot.id, self.today)
        self.assertEqual(r.status_code, 404)

    def test_cancel_other_members_booking_404(self):
        r1 = self.book(self.member1_client, self.slot.id, self.today)
        booking_id = r1.data["id"]
        r2 = self.member2_client.post(f"{API}bookings/{booking_id}/cancel/")
        self.assertEqual(r2.status_code, 404)

    def test_member_field_in_body_ignored(self):
        r = self.book(self.member1_client, self.slot.id, self.today,
                      extra={"member": str(self.member2.id)})
        self.assertEqual(r.status_code, 201)
        booking = Booking.objects.get(id=r.data["id"])
        self.assertEqual(booking.member_id, self.member1.id)




class ClassesToggleTests(SchedulingTestBase):
    def test_disabled_owner_403_on_timeslots(self):
        self.gym.classes_enabled = False
        self.gym.save(update_fields=["classes_enabled"])
        r = self.owner.get(f"{API}time-slots/")
        self.assertEqual(r.status_code, 403)

    def test_disabled_member_403_on_schedule(self):
        self.gym.classes_enabled = False
        self.gym.save(update_fields=["classes_enabled"])
        r = self.member1_client.get(f"{API}schedule/")
        self.assertEqual(r.status_code, 403)

    def test_disabled_member_403_on_booking_post(self):
        self.gym.classes_enabled = False
        self.gym.save(update_fields=["classes_enabled"])
        r = self.book(self.member1_client, self.slot.id, self.today)
        self.assertEqual(r.status_code, 403)

    def test_disabled_member_403_on_my_bookings(self):
        self.gym.classes_enabled = False
        self.gym.save(update_fields=["classes_enabled"])
        r = self.member1_client.get(f"{API}me/bookings/")
        self.assertEqual(r.status_code, 403)

    def test_disabled_member_403_on_cancel(self):
        r1 = self.book(self.member1_client, self.slot.id, self.today)
        booking_id = r1.data["id"]
        self.gym.classes_enabled = False
        self.gym.save(update_fields=["classes_enabled"])
        r2 = self.member1_client.post(f"{API}bookings/{booking_id}/cancel/")
        self.assertEqual(r2.status_code, 403)

    def test_me_returns_classes_enabled_for_owner(self):
        r = self.owner.get(f"{API}auth/me/")
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.data["gym"]["classes_enabled"])

    def test_me_returns_classes_enabled_for_member(self):
        r = self.member1_client.get(f"{API}auth/me/")
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.data["gym"]["classes_enabled"])

    def test_toggle_off_then_on_leaves_bookings_intact(self):
        self.book(self.member1_client, self.slot.id, self.today)
        count_before = Booking.objects.filter(gym=self.gym).count()
        self.assertEqual(count_before, 1)

        self.gym.classes_enabled = False
        self.gym.save(update_fields=["classes_enabled"])
        self.assertEqual(Booking.objects.filter(gym=self.gym).count(), 1)

        self.gym.classes_enabled = True
        self.gym.save(update_fields=["classes_enabled"])
        self.assertEqual(Booking.objects.filter(gym=self.gym).count(), 1)