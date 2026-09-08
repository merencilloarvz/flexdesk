import threading

from decimal import Decimal
from django.db import connections
from django.test import TransactionTestCase
from rest_framework import status
from rest_framework.test import APIClient, APITestCase

from core.models import (Gym, Location, Member, MembershipPlan, Product,
                         Sale, StaffProfile, StockAdjustment, User)
from core.views import create_sale


def make_gym(name="Gym A"):
    return Gym.objects.create(name=name, slug=name.lower().replace(" ", "-"))


def make_location(gym, name="Main"):
    return Location.objects.create(gym=gym, name=name)


def make_staff_user(gym, email, role=StaffProfile.STAFF, location=None):
    user = User.objects.create_user(email=email, password="testpass123", full_name=email)
    StaffProfile.objects.create(user=user, gym=gym, role=role, default_location=location)
    return user


def make_member_user(gym, location, email="member@test.com"):
    user = User.objects.create_user(email=email, password="testpass123", full_name="Member")
    Member.objects.create(
        gym=gym, home_location=location, first_name="Test", last_name="Member",
        email=email, user=user,
    )
    return user


def make_product(gym, name="Protein Shake", price="150.00", stock=10, threshold=5):
    return Product.objects.create(
        gym=gym, name=name, category="Supplements",
        price=Decimal(price), stock_quantity=stock, low_stock_threshold=threshold,
    )


class POSBaseTestCase(APITestCase):
    def setUp(self):
        self.gym = make_gym()
        self.location = make_location(self.gym)
        self.owner = make_staff_user(self.gym, "owner@test.com",
                                     role=StaffProfile.OWNER, location=self.location)
        self.staff = make_staff_user(self.gym, "staff@test.com",
                                     role=StaffProfile.STAFF, location=self.location)

        other_gym = make_gym("Gym B")
        other_location = make_location(other_gym)
        self.other_owner = make_staff_user(other_gym, "otherowner@test.com",
                                           role=StaffProfile.OWNER,
                                           location=other_location)
        self.other_staff = make_staff_user(other_gym, "otherstaff@test.com",
                                           role=StaffProfile.STAFF,
                                           location=other_location)

        self.member_user = make_member_user(self.gym, self.location)

        self.product = make_product(self.gym, stock=10, threshold=5)

    def as_owner(self):
        c = APIClient()
        c.force_authenticate(user=self.owner)
        return c

    def as_staff(self):
        c = APIClient()
        c.force_authenticate(user=self.staff)
        return c

    def as_member(self):
        c = APIClient()
        c.force_authenticate(user=self.member_user)
        return c

    def as_other_staff(self):
        c = APIClient()
        c.force_authenticate(user=self.other_staff)
        return c


class SaleCreationTests(POSBaseTestCase):
    def test_sell_within_stock_reduces_quantity(self):
        c = self.as_staff()
        resp = c.post("/api/v1/sales/", {
            "items": [{"product_id": str(self.product.id), "quantity": 3}]
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED, resp.data)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 7)
        self.assertEqual(Decimal(resp.data["total_amount"]), Decimal("450.00"))

    def test_sell_more_than_stock_fails_and_stock_unchanged(self):
        c = self.as_staff()
        resp = c.post("/api/v1/sales/", {
            "items": [{"product_id": str(self.product.id), "quantity": 11}]
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 10)

    def test_multi_item_sale_fails_atomically(self):
        product2 = make_product(self.gym, name="Gym Towel", price="80.00", stock=2)
        c = self.as_staff()
        resp = c.post("/api/v1/sales/", {
            "items": [
                {"product_id": str(self.product.id), "quantity": 5},
                {"product_id": str(product2.id), "quantity": 10},  # insufficient
            ]
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.product.refresh_from_db()
        product2.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 10)  # untouched
        self.assertEqual(product2.stock_quantity, 2)        # untouched

    def test_same_product_twice_sums_quantities(self):
        c = self.as_staff()
        resp = c.post("/api/v1/sales/", {
            "items": [
                {"product_id": str(self.product.id), "quantity": 6},
                {"product_id": str(self.product.id), "quantity": 6},  # 12 total > 10
            ]
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 10)

    def test_zero_or_negative_quantity_rejected(self):
        c = self.as_staff()
        resp = c.post("/api/v1/sales/", {
            "items": [{"product_id": str(self.product.id), "quantity": 0}]
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

        resp = c.post("/api/v1/sales/", {
            "items": [{"product_id": str(self.product.id), "quantity": -1}]
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_empty_items_rejected(self):
        c = self.as_staff()
        resp = c.post("/api/v1/sales/", {"items": []}, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)


class ConcurrentSaleTests(TransactionTestCase):
    def setUp(self):
        self.gym = make_gym()
        self.location = make_location(self.gym)
        self.staff = make_staff_user(self.gym, "staff@test.com",
                                     role=StaffProfile.STAFF, location=self.location)
        self.product = make_product(self.gym, stock=1)

    def test_two_threads_selling_last_unit(self):
        results = []

        def sell():
            connections.close_all()
            try:
                create_sale(
                    gym=self.gym,
                    items=[{"product_id": self.product.id, "quantity": 1}],
                    user=self.staff,
                )
                results.append("ok")
            except Exception:
                results.append("fail")
            finally:
                connections.close_all()

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


class VoidTests(POSBaseTestCase):
    def _make_sale(self, qty=3):
        c = self.as_staff()
        resp = c.post("/api/v1/sales/", {
            "items": [{"product_id": str(self.product.id), "quantity": qty}]
        }, format="json")
        return resp.data["id"]

    def test_void_restores_stock_exactly(self):
        sale_id = self._make_sale(qty=3)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 7)

        c = self.as_owner()
        resp = c.post(f"/api/v1/sales/{sale_id}/void/")
        self.assertEqual(resp.status_code, status.HTTP_204_NO_CONTENT)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 10)

    def test_voiding_twice_restores_once(self):
        sale_id = self._make_sale(qty=3)
        c = self.as_owner()
        c.post(f"/api/v1/sales/{sale_id}/void/")
        self.product.refresh_from_db()
        after_first = self.product.stock_quantity

        c.post(f"/api/v1/sales/{sale_id}/void/")
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, after_first)

    def test_voided_sale_excluded_from_analytics(self):
        sale_id = self._make_sale(qty=2)
        c = self.as_owner()
        c.post(f"/api/v1/sales/{sale_id}/void/")

        resp = c.get("/api/v1/analytics/?range=1D")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        merch = next(b for b in resp.data["revenue"]["breakdown"]
                    if b["category"] == "merch")
        self.assertEqual(Decimal(merch["amount"]), Decimal("0.00"))

    def test_staff_cannot_void(self):
        sale_id = self._make_sale(qty=1)
        c = self.as_staff()
        resp = c.post(f"/api/v1/sales/{sale_id}/void/")
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)


class SnapshotTests(POSBaseTestCase):
    def test_price_change_does_not_affect_past_sale(self):
        c = self.as_staff()
        resp = c.post("/api/v1/sales/", {
            "items": [{"product_id": str(self.product.id), "quantity": 1}]
        }, format="json")
        sale_id = resp.data["id"]

        self.product.price = Decimal("999.00")
        self.product.save(update_fields=["price", "updated_at"])

        resp = c.get(f"/api/v1/sales/{sale_id}/")
        item = resp.data["items"][0]
        self.assertEqual(Decimal(item["unit_price"]), Decimal("150.00"))
        self.assertEqual(Decimal(item["line_total"]), Decimal("150.00"))

    def test_deactivated_product_keeps_past_sale_details(self):
        c = self.as_staff()
        resp = c.post("/api/v1/sales/", {
            "items": [{"product_id": str(self.product.id), "quantity": 1}]
        }, format="json")
        sale_id = resp.data["id"]

        self.product.is_active = False
        self.product.save(update_fields=["is_active", "updated_at"])

        resp = c.get(f"/api/v1/sales/{sale_id}/")
        item = resp.data["items"][0]
        self.assertEqual(item["product_name"], "Protein Shake")


class AdjustmentTests(POSBaseTestCase):
    def test_positive_adjustment_raises_stock_and_logs(self):
        c = self.as_staff()
        resp = c.post(f"/api/v1/products/{self.product.id}/adjust/",
                      {"delta": 10, "reason": "Received"}, format="json")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 20)
        self.assertEqual(StockAdjustment.objects.filter(product=self.product).count(), 1)

    def test_adjustment_that_would_go_negative_rejected(self):
        c = self.as_staff()
        resp = c.post(f"/api/v1/products/{self.product.id}/adjust/",
                      {"delta": -50, "reason": "Damaged"}, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 10)
        self.assertEqual(StockAdjustment.objects.filter(product=self.product).count(), 0)

    def test_zero_delta_rejected(self):
        c = self.as_staff()
        resp = c.post(f"/api/v1/products/{self.product.id}/adjust/",
                      {"delta": 0, "reason": "Count correction"}, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)


class AccessControlTests(POSBaseTestCase):
    def test_member_gets_403_on_all_pos_endpoints(self):
        c = self.as_member()
        self.assertEqual(c.get("/api/v1/products/").status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(c.get("/api/v1/sales/").status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(c.get("/api/v1/inventory/alerts/").status_code,
                         status.HTTP_403_FORBIDDEN)

    def test_non_owner_staff_cannot_create_product(self):
        c = self.as_staff()
        resp = c.post("/api/v1/products/", {
            "name": "New Item", "category": "Merch", "price": "50.00",
            "stock_quantity": 5, "low_stock_threshold": 2,
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_non_owner_staff_can_record_sale(self):
        c = self.as_staff()
        resp = c.post("/api/v1/sales/", {
            "items": [{"product_id": str(self.product.id), "quantity": 1}]
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)

    def test_other_gyms_staff_selling_this_products_gives_404(self):
        c = self.as_other_staff()
        resp = c.post("/api/v1/sales/", {
            "items": [{"product_id": str(self.product.id), "quantity": 1}]
        }, format="json")
        self.assertEqual(resp.status_code, status.HTTP_404_NOT_FOUND)


class AlertsTests(POSBaseTestCase):
    def test_thresholds(self):
        low = make_product(self.gym, name="Low Item", stock=5, threshold=5)
        not_low = make_product(self.gym, name="Fine Item", stock=6, threshold=5)
        out = make_product(self.gym, name="Out Item", stock=0, threshold=5)

        c = self.as_staff()
        resp = c.get("/api/v1/inventory/alerts/")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

        names_low = [i["name"] for i in resp.data["items"] if i["state"] == "low"]
        names_out = [i["name"] for i in resp.data["items"] if i["state"] == "critical"]
        self.assertIn("Low Item", names_low)
        self.assertNotIn("Fine Item", names_low)
        self.assertNotIn("Fine Item", names_out)
        self.assertIn("Out Item", names_out)

    def test_items_capped_at_five_worst_first(self):
        for i in range(8):
            make_product(self.gym, name=f"Product {i}", stock=0, threshold=5)

        c = self.as_staff()
        resp = c.get("/api/v1/inventory/alerts/")
        self.assertLessEqual(len(resp.data["items"]), 5)
        self.assertTrue(all(i["state"] == "critical" for i in resp.data["items"]))
