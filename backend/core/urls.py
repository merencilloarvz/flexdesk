from django.urls import include, path
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView, TokenVerifyView

from .views import (FlexTokenObtainPairView, MeView, MemberViewSet,
                    MembershipPlanViewSet)
from .views import SignupView   
from .views import ChangePasswordView, StaffViewSet

router = DefaultRouter()
router.register("members", MemberViewSet, basename="member")
router.register("plans", MembershipPlanViewSet, basename="plan")
router.register("staff", StaffViewSet, basename="staff")


urlpatterns = [
    path("auth/login/", FlexTokenObtainPairView.as_view(), name="login"),
    path("auth/refresh/", TokenRefreshView.as_view(), name="token-refresh"),
    path("auth/verify/", TokenVerifyView.as_view(), name="token-verify"),
    path("auth/me/", MeView.as_view(), name="me"),
    path("auth/signup/", SignupView.as_view(), name="signup"),
    path("auth/change-password/", ChangePasswordView.as_view(), name="change-password"),
    path("", include(router.urls)),
]