from django.urls import include, path
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView, TokenVerifyView

from .views import (AnnouncementViewSet, AnalyticsView, BookingCancelView, BookingCreateView,
                    CheckInViewSet, ClaimAccountView, EventRegistrationViewSet,
                    EventResultsView, EventViewSet, FlexTokenObtainPairView, GymSettingsView,
                    InventoryAlertsView, LogoutView, MeCheckInsView, MeEventRegistrationsView,
                    MeMembershipView, MeSummaryView, MeView, MemberViewSet,
                    MembershipPlanViewSet, MyBookingsView, ProductViewSet,
                    SaleViewSet, ScheduleView, TimeSlotViewSet)
from .views import SignupView
from .views import ChangePasswordView, StaffViewSet
from .views import MeRestDaysView  # add to the existing .views import block
router = DefaultRouter()
router.register("members", MemberViewSet, basename="member")
router.register("check-ins", CheckInViewSet, basename="check-in")
router.register("plans", MembershipPlanViewSet, basename="plan")
router.register("staff", StaffViewSet, basename="staff")
router.register("time-slots", TimeSlotViewSet, basename="time-slot")
router.register("announcements", AnnouncementViewSet, basename="announcement")
router.register("events", EventViewSet, basename="event")
router.register("event-registrations", EventRegistrationViewSet,
                basename="event-registration")
router.register("products", ProductViewSet, basename="product")
router.register("sales", SaleViewSet, basename="sale")


urlpatterns = [
    path("auth/login/", FlexTokenObtainPairView.as_view(), name="login"),
    path("auth/refresh/", TokenRefreshView.as_view(), name="token-refresh"),
    path("auth/verify/", TokenVerifyView.as_view(), name="token-verify"),
    path("auth/me/", MeView.as_view(), name="me"),
    path("auth/signup/", SignupView.as_view(), name="signup"),
    path("auth/claim/", ClaimAccountView.as_view(), name="claim"),
    path("auth/change-password/", ChangePasswordView.as_view(), name="change-password"),
    path("me/summary/", MeSummaryView.as_view(), name="me-summary"),
    path("analytics/", AnalyticsView.as_view(), name="analytics"),
    path("me/membership/", MeMembershipView.as_view(), name="me-membership"),
    path("me/check-ins/", MeCheckInsView.as_view(), name="me-check-ins"),
    path("me/bookings/", MyBookingsView.as_view(), name="me-bookings"),
    path("me/event-registrations/", MeEventRegistrationsView.as_view(),
        name="me-event-registrations"),
    path("schedule/", ScheduleView.as_view(), name="schedule"),
    path("bookings/", BookingCreateView.as_view(), name="booking-create"),
    path("bookings/<uuid:pk>/cancel/", BookingCancelView.as_view(), name="booking-cancel"),
    path("gym/settings/", GymSettingsView.as_view(), name="gym-settings"),
    path("events/<uuid:event_id>/results/", EventResultsView.as_view(),
        name="event-results"),
    path("inventory/alerts/", InventoryAlertsView.as_view(), name="inventory-alerts"),
    path("me/rest-days/", MeRestDaysView.as_view(), name="me-rest-days"),
    path("auth/logout/", LogoutView.as_view(), name="auth-logout"),
    path("", include(router.urls)),
    
]