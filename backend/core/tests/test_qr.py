import threading
import uuid

from django.db import connections
from django.test import SimpleTestCase, TransactionTestCase
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient, APITestCase
from rest_framework_simplejwt.tokens import RefreshToken

from core import qr as qr_lib
from core.models import CheckIn, Gym, Location, Member, StaffProfile, User

API = "/api/v1"


def _auth_client(user):
    client = APIClient()
    token = RefreshToken.for_user(user)
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {token.access_token}")
    return client


class QrAlgorithmVectorTestCase(SimpleTestCase):
    """
    A2.1 — cross-implementation test vectors, hard-coded here exactly as
    given in the spec. These were computed independently of this
    codebase; the Dart side (Phase 3b Part B, not built yet) asserts the
    same three against the same constants. Do not regenerate these from
    core.qr itself — a test that checks an implementation against itself
    proves nothing.
    """

    def test_vector_1(self):
        secret = "AAAQEAYEAUDAOCAJBIFQYDIOB4IBCEQTCQKRMFYYDENBWHA5DYPQ===="
        step = qr_lib.time_step(1767225600)
        self.assertEqual(step, 29453760)
        self.assertEqual(qr_lib.compute_code(secret, step), "42081074")

    def test_vector_2_has_leading_zero(self):
        # Catches an integer-vs-string formatting bug: '09458587' as an
        # int would lose the leading zero and fail this assertion.
        secret = "IFAUCQKBIFAUCQKBIFAUCQKBIFAUCQKBIFAUCQKBIFAUCQKBIFAQ===="
        step = qr_lib.time_step(1767225660)
        self.assertEqual(step, 29453761)
        code = qr_lib.compute_code(secret, step)
        self.assertEqual(code, "09458587")
        self.assertEqual(len(code), 8)

    def test_vector_3(self):
        secret = "777777777777777777777777777777777777777777777777777Q===="
        step = qr_lib.time_step(1767312000)
        self.assertEqual(step, 29455200)
        self.assertEqual(qr_lib.compute_code(secret, step), "99002962")


class QrCheckInTestCase(APITestCase):
    """
    Part A — verify-qr, /me/qr-secret/, and the owner-only reset action.
    """

    def setUp(self):
        self.gym_a = Gym.objects.create(name="Gym A", slug="qr-gym-a")
        self.location_a = Location.objects.create(gym=self.gym_a, name="Main")

        self.owner_user = User.objects.create_user(
            email="qrowner@example.com", password="StrongPass123!", full_name="Owner")
        self.owner = StaffProfile.objects.create(
            user=self.owner_user, gym=self.gym_a, role=StaffProfile.OWNER,
            default_location=self.location_a)

        self.staff_user = User.objects.create_user(
            email="qrstaff@example.com", password="StrongPass123!", full_name="Staff")
        self.staff = StaffProfile.objects.create(
            user=self.staff_user, gym=self.gym_a, role=StaffProfile.STAFF,
            default_location=self.location_a)

        # A claimed member with a secret already issued — the common case
        # for the verification tests below.
        self.member_user = User.objects.create_user(
            email="qrmember@example.com", password="StrongPass123!", full_name="QR Member")
        self.member = Member.objects.create(
            gym=self.gym_a, home_location=self.location_a, first_name="QR",
            last_name="Member", email="qrmember@example.com",
            member_type=Member.MEMBER, user=self.member_user,
            qr_secret=qr_lib.generate_secret(),
        )

        # Claimed, but has never opened their card — qr_secret is still
        # blank. This is the A3 / S6 case.
        self.unclaimed_member_user = User.objects.create_user(
            email="qrunclaimed@example.com", password="StrongPass123!",
            full_name="Unclaimed QR")
        self.unclaimed_qr_member = Member.objects.create(
            gym=self.gym_a, home_location=self.location_a, first_name="Unclaimed",
            last_name="QR", email="qrunclaimed@example.com",
            member_type=Member.MEMBER, user=self.unclaimed_member_user,
        )

        self.archived_member = Member.objects.create(
            gym=self.gym_a, home_location=self.location_a, first_name="Archived",
            last_name="QR", email="qrarchived@example.com",
            member_type=Member.MEMBER, qr_secret=qr_lib.generate_secret(),
            archived_at=timezone.now(),
        )

        self.gym_b = Gym.objects.create(name="Gym B", slug="qr-gym-b")
        self.location_b = Location.objects.create(gym=self.gym_b, name="Main")
        self.member_b_user = User.objects.create_user(
            email="qrmemberb@example.com", password="StrongPass123!", full_name="Member B")
        self.member_b = Member.objects.create(
            gym=self.gym_b, home_location=self.location_b, first_name="Member",
            last_name="B", email="qrmemberb@example.com",
            member_type=Member.MEMBER, user=self.member_b_user,
            qr_secret=qr_lib.generate_secret(),
        )

    # ---- helpers ----

    def _auth(self, user):
        token = RefreshToken.for_user(user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token.access_token}")

    def _clear_auth(self):
        self.client.credentials()

    def _current_step(self):
        return qr_lib.time_step(timezone.now().timestamp())

    def _payload_for(self, member, step_offset=0, secret=None):
        step = self._current_step() + step_offset
        code = qr_lib.compute_code(secret if secret is not None else member.qr_secret, step)
        return f"{qr_lib.CHECKIN_PREFIX}|{member.id}|{code}"

    def _verify(self, payload):
        return self.client.post(f"{API}/check-ins/verify-qr/", {"payload": payload},
                                format="json")

    # ======================================================================
    # Verification
    # ======================================================================

    def test_valid_code_verifies_and_returns_correct_member_data(self):
        self._auth(self.owner_user)
        resp = self._verify(self._payload_for(self.member))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data["id"], str(self.member.id))
        self.assertEqual(resp.data["full_name"], self.member.full_name)
        self.assertEqual(resp.data["member_code"], self.member.member_code)
        self.assertEqual(resp.data["membership_status"], "no_membership")
        self.assertIsNone(resp.data["current_end_date"])
        self.assertIsNone(resp.data["days_remaining"])
        self.assertFalse(resp.data["already_checked_in_today"])

    def test_code_one_step_ago_accepted(self):
        self._auth(self.owner_user)
        resp = self._verify(self._payload_for(self.member, step_offset=-1))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

    def test_code_two_steps_ago_rejected(self):
        self._auth(self.owner_user)
        resp = self._verify(self._payload_for(self.member, step_offset=-2))
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(
            resp.data["detail"],
            "That code has expired — ask them to reopen their card",
        )

    def test_code_one_step_ahead_accepted(self):
        self._auth(self.owner_user)
        resp = self._verify(self._payload_for(self.member, step_offset=1))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

    def test_same_code_twice_second_is_already_used(self):
        self._auth(self.owner_user)
        payload = self._payload_for(self.member)
        first = self._verify(payload)
        self.assertEqual(first.status_code, status.HTTP_200_OK)

        second = self._verify(payload)
        self.assertEqual(second.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(second.data["detail"], "That code has already been used")

    def test_empty_secret_with_correctly_computed_code_still_rejected(self):
        # S6 / A3: the unclaimed member's qr_secret is "" — compute the
        # code from that EXACT empty key (what anyone holding their UUID
        # and nothing else could produce themselves) at every step the
        # server would otherwise accept, and confirm every one is still
        # rejected with the SAME message as an expired code, never a
        # distinct "unclaimed" message that would leak claim status to
        # whoever is holding the scanner.
        #
        # base64.b32decode("") is zero-length bytes, and HMAC with a
        # zero-length key is a perfectly valid, deterministic
        # computation — a code forged from a 32-BYTE key of zeros (or
        # anything else non-empty) would fail for the mundane reason
        # that the keys don't match, proving nothing about this guard.
        # Only "" is the actual attack: anyone holding this member's
        # UUID and nothing else can compute exactly this.
        self._auth(self.owner_user)
        expired_message = "That code has expired — ask them to reopen their card"

        for step_offset in (-1, 0, 1):
            payload = self._payload_for(
                self.unclaimed_qr_member, step_offset=step_offset, secret="")
            resp = self._verify(payload)
            self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
            self.assertEqual(resp.data["detail"], expired_message)

        # A rejected attempt must never consume a step. This member has
        # never verified anything, so qr_last_step must still be null —
        # not just unchanged, since a bug that set it to some value
        # derived from the empty-key computation would also "pass" a
        # weaker assertNotEqual-from-before check.
        self.unclaimed_qr_member.refresh_from_db()
        self.assertIsNone(self.unclaimed_qr_member.qr_last_step)

    def test_another_gyms_member_and_nonexistent_member_return_identical_message(self):
        self._auth(self.owner_user)

        cross_gym_payload = self._payload_for(self.member_b)
        cross_gym_resp = self._verify(cross_gym_payload)

        fake_id = uuid.uuid4()
        fake_code = qr_lib.compute_code(self.member.qr_secret, self._current_step())
        not_found_resp = self._verify(f"{qr_lib.CHECKIN_PREFIX}|{fake_id}|{fake_code}")

        self.assertEqual(cross_gym_resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(not_found_resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(cross_gym_resp.data, not_found_resp.data)
        self.assertEqual(cross_gym_resp.data["detail"], "This card isn't from your gym")

    def test_archived_member_rejected(self):
        self._auth(self.owner_user)
        resp = self._verify(self._payload_for(self.archived_member))
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(
            resp.data["detail"], "This membership is no longer active at your gym")

    def test_claim_payload_at_verify_qr_gets_specific_message(self):
        self._auth(self.owner_user)
        resp = self._verify(f"{qr_lib.CLAIM_PREFIX}|SOMECODE")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(
            resp.data["detail"],
            "That's an account setup code, not a membership card",
        )

    def test_malformed_payload_no_separator(self):
        self._auth(self.owner_user)
        resp = self._verify("not-a-real-payload")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(resp.data["detail"], "Couldn't read that code")

    def test_malformed_payload_wrong_prefix(self):
        self._auth(self.owner_user)
        code = qr_lib.compute_code(self.member.qr_secret, self._current_step())
        resp = self._verify(f"NOTAREALPREFIX|{self.member.id}|{code}")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(resp.data["detail"], "Couldn't read that code")

    def test_malformed_payload_extra_fields(self):
        self._auth(self.owner_user)
        code = qr_lib.compute_code(self.member.qr_secret, self._current_step())
        resp = self._verify(f"{qr_lib.CHECKIN_PREFIX}|{self.member.id}|{code}|extra")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(resp.data["detail"], "Couldn't read that code")

    def test_malformed_payload_invalid_uuid(self):
        self._auth(self.owner_user)
        resp = self._verify(f"{qr_lib.CHECKIN_PREFIX}|not-a-uuid|12345678")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(resp.data["detail"], "Couldn't read that code")

    def test_already_checked_in_today_reflected(self):
        CheckIn.objects.create(
            gym=self.gym_a, member=self.member, visit_type=CheckIn.MEMBER,
            location=self.location_a, checked_in_at=timezone.now(),
            membership_status="no_membership",
        )
        self._auth(self.owner_user)
        resp = self._verify(self._payload_for(self.member))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertTrue(resp.data["already_checked_in_today"])

    # ======================================================================
    # Permissions and lifecycle
    # ======================================================================

    def test_member_forbidden_from_verify_qr(self):
        self._auth(self.member_user)
        resp = self._verify(self._payload_for(self.member))
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_staff_forbidden_from_me_qr_secret(self):
        self._auth(self.owner_user)
        resp = self.client.get(f"{API}/me/qr-secret/")
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_non_owner_staff_forbidden_from_reset(self):
        self._auth(self.staff_user)
        resp = self.client.post(f"{API}/members/{self.member.id}/qr-secret/reset/")
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_first_qr_secret_call_generates_and_persists(self):
        self._auth(self.unclaimed_member_user)
        self.assertEqual(self.unclaimed_qr_member.qr_secret, "")

        resp = self.client.get(f"{API}/me/qr-secret/")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertTrue(resp.data["secret"])
        self.assertEqual(resp.data["period"], 60)
        self.assertEqual(resp.data["digits"], 8)
        self.assertIn("server_time", resp.data)

        self.unclaimed_qr_member.refresh_from_db()
        self.assertEqual(self.unclaimed_qr_member.qr_secret, resp.data["secret"])

    def test_second_qr_secret_call_returns_same_secret(self):
        self._auth(self.member_user)
        first = self.client.get(f"{API}/me/qr-secret/")
        second = self.client.get(f"{API}/me/qr-secret/")
        self.assertEqual(first.data["secret"], second.data["secret"])
        self.assertEqual(first.data["secret"], self.member.qr_secret)

    def test_reset_invalidates_old_secret_and_nulls_last_step(self):
        old_secret = self.member.qr_secret
        self._auth(self.owner_user)

        # Establish a non-null qr_last_step first.
        verify_resp = self._verify(self._payload_for(self.member))
        self.assertEqual(verify_resp.status_code, status.HTTP_200_OK)
        self.member.refresh_from_db()
        self.assertIsNotNone(self.member.qr_last_step)

        reset_resp = self.client.post(f"{API}/members/{self.member.id}/qr-secret/reset/")
        self.assertEqual(reset_resp.status_code, status.HTTP_204_NO_CONTENT)

        self.member.refresh_from_db()
        self.assertNotEqual(self.member.qr_secret, old_secret)
        self.assertIsNone(self.member.qr_last_step)

        # The old secret's code no longer verifies.
        stale_code = qr_lib.compute_code(old_secret, self._current_step())
        stale_resp = self._verify(f"{qr_lib.CHECKIN_PREFIX}|{self.member.id}|{stale_code}")
        self.assertEqual(stale_resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_me_qr_secret_honours_throttle(self):
        self._auth(self.member_user)
        for _ in range(10):
            resp = self.client.get(f"{API}/me/qr-secret/")
            self.assertEqual(resp.status_code, status.HTTP_200_OK)

        throttled = self.client.get(f"{API}/me/qr-secret/")
        self.assertEqual(throttled.status_code, status.HTTP_429_TOO_MANY_REQUESTS)


class QrVerifyRaceTestCase(TransactionTestCase):
    """
    The bug: verify_qr's old replay guard read qr_last_step, then wrote it
    in a separate statement. Two concurrent requests carrying the same
    code could both read it as not-yet-set and both write success. A
    same-thread "call twice" test can't exercise this at all — the two
    calls never overlap — so this needs real threads and, per the
    convention already established for exactly this kind of bug
    elsewhere in this suite (ConcurrentSaleTests in test_pos.py,
    test_concurrent_booking_last_spot in test_scheduling.py),
    TransactionTestCase rather than the transaction-wrapped, single-
    connection APITestCase the rest of this module uses.
    """

    def setUp(self):
        self.gym = Gym.objects.create(name="Race Gym", slug="qr-race-gym")
        self.location = Location.objects.create(gym=self.gym, name="Main")
        self.owner_user = User.objects.create_user(
            email="qrraceowner@example.com", password="StrongPass123!",
            full_name="Owner")
        StaffProfile.objects.create(
            user=self.owner_user, gym=self.gym, role=StaffProfile.OWNER,
            default_location=self.location)
        self.member_user = User.objects.create_user(
            email="qrracemember@example.com", password="StrongPass123!",
            full_name="Race Member")
        self.member = Member.objects.create(
            gym=self.gym, home_location=self.location, first_name="Race",
            last_name="Member", email="qrracemember@example.com",
            member_type=Member.MEMBER, user=self.member_user,
            qr_secret=qr_lib.generate_secret(),
        )

    def test_concurrent_verify_same_code_only_one_succeeds(self):
        step = qr_lib.time_step(timezone.now().timestamp())
        code = qr_lib.compute_code(self.member.qr_secret, step)
        payload = f"{qr_lib.CHECKIN_PREFIX}|{self.member.id}|{code}"

        results = []

        def attempt():
            try:
                client = _auth_client(self.owner_user)
                resp = client.post(f"{API}/check-ins/verify-qr/",
                                   {"payload": payload}, format="json")
                results.append(resp.status_code)
            finally:
                connections.close_all()

        t1 = threading.Thread(target=attempt)
        t2 = threading.Thread(target=attempt)
        t1.start()
        t2.start()
        t1.join()
        t2.join()

        self.assertEqual(sorted(results), [200, 400])

        # Exactly one winner reached the DB, and it recorded the step
        # this code actually maps to — not a partial or doubled write.
        self.member.refresh_from_db()
        self.assertEqual(self.member.qr_last_step, step)
