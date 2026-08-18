from rest_framework.routers import DefaultRouter
from .views import OwnerViewSet

router = DefaultRouter()
router.register('owners', OwnerViewSet)

urlpatterns = router.urls