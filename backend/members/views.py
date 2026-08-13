from rest_framework import viewsets
from .models import MembershipPlan, Member  
from .serializers import MembershipPlanSerializer, MemberSerializer

class MembershipPlanViewSet(viewsets.ModelViewSet):
    queryset = MembershipPlan.objects.all()
    serializer_class = MembershipPlanSerializer

class MemberViewSet(viewsets.ModelViewSet):
    queryset = Member.objects.all()
    serializer_class = MemberSerializer
