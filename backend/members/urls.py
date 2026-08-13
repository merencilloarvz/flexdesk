from rest_framework .routers import DefaultRouter
from .views import MembershipPlanViewSet, MemberViewSet

router = DefaultRouter()
router.register('plans', MembershipPlanViewSet)
router.register('members', MemberViewSet)

urlpatterns = router.urls