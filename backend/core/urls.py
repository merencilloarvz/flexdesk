from django.urls import include, path
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView, TokenVerifyView

from .views import (ActivityLogView, AnnouncementViewSet, AnalyticsView, BookingCancelView, BookingCreateView,
                    SalesHistoryView,
                    CheckInViewSet, ClaimAccountView, EventRegistrationViewSet,
                    EventResultsView, EventUnverifyResultsView, EventVerifyResultsView,
                    EventViewSet, FlexTokenObtainPairView, GymSettingsView,
                    InventoryAlertsView, LogoutView, MeCheckInsView, MeEventRegistrationsView,
                    MeMembershipView, MeSummaryView, MeView, MemberViewSet,
                    MembershipPlanViewSet, MyBookingsView, ProductViewSet,
                    SaleViewSet, ScheduleView, TimeSlotViewSet)
from .views import SignupView
from .views import ChangePasswordView, StaffViewSet
from .views import MeRestDaysView  # add to the existing .views import block
from .views import SubscriptionPaymentInfoView, SubscriptionView
from .views import MeQrSecretView
from .views import DeviceTokenView, DeviceTokenTestView
from .views import CommentDeleteView, CommentListCreateView, LikeToggleView
from .models import Announcement, Event
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


# Likes and comments serve two targets with the same views; each URL binds
# a view to one (model, FK field). Listed ahead of the router include, like
# the events/<id>/results/ routes.
engagement_urls = []
for _prefix, _model, _field in [("announcements", Announcement, "announcement"),
                                ("events", Event, "event")]:
    _bind = {"item_model": _model, "item_field": _field}
    engagement_urls += [
        path(f"{_prefix}/<uuid:item_id>/like/",
             LikeToggleView.as_view(**_bind), name=f"{_field}-like"),
        path(f"{_prefix}/<uuid:item_id>/comments/",
             CommentListCreateView.as_view(**_bind), name=f"{_field}-comments"),
        path(f"{_prefix}/<uuid:item_id>/comments/<uuid:comment_id>/",
             CommentDeleteView.as_view(**_bind), name=f"{_field}-comment-detail"),
    ]

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
    path("analytics/activity-log/", ActivityLogView.as_view(), name="activity-log"),
    path("analytics/sales-history/", SalesHistoryView.as_view(), name="sales-history"),
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
    path("events/<uuid:event_id>/verify-results/", EventVerifyResultsView.as_view(),
        name="event-verify-results"),
    path("events/<uuid:event_id>/unverify-results/", EventUnverifyResultsView.as_view(),
        name="event-unverify-results"),
    path("inventory/alerts/", InventoryAlertsView.as_view(), name="inventory-alerts"),
    path("me/rest-days/", MeRestDaysView.as_view(), name="me-rest-days"),
    path("me/qr-secret/", MeQrSecretView.as_view(), name="me-qr-secret"),
    path("devices/", DeviceTokenView.as_view(), name="devices"),
    path("devices/test/", DeviceTokenTestView.as_view(), name="devices-test"),
    path("auth/logout/", LogoutView.as_view(), name="auth-logout"),
    path("subscription/", SubscriptionView.as_view(), name="subscription"),
    path("subscription/payment-info/", SubscriptionPaymentInfoView.as_view(),
        name="subscription-payment-info"),
    *engagement_urls,
    path("", include(router.urls)),
    
]