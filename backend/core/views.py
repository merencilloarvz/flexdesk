from django.db import IntegrityError
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.generics import RetrieveAPIView
from rest_framework.response import Response
from rest_framework.exceptions import MethodNotAllowed, ValidationError
from rest_framework_simplejwt.views import TokenObtainPairView
from django.utils import timezone

from .mixins import GymScopedViewSet
from .models import Member, Membership, MembershipPlan
from .permissions import IsGymStaff, IsOwner, IsOwnerOrReadOnly
from .serializers import (FlexTokenObtainPairSerializer, MeSerializer,
                          MemberSerializer, MembershipPlanSerializer,
                          MembershipSerializer, MemberWriteSerializer)

from rest_framework.permissions import AllowAny
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from .serializers import SignupSerializer

from .serializers import (ChangePasswordSerializer, StaffCreateSerializer,
                          StaffMemberSerializer)
from .models import StaffProfile

class FlexTokenObtainPairView(TokenObtainPairView):
    serializer_class = FlexTokenObtainPairSerializer


class MeView(RetrieveAPIView):
    serializer_class = MeSerializer

    def get_object(self):
        return self.request.user


class MembershipPlanViewSet(GymScopedViewSet):
    queryset = MembershipPlan.objects.all()
    serializer_class = MembershipPlanSerializer
    permission_classes = [IsGymStaff, IsOwnerOrReadOnly]

    def create(self, request, *args, **kwargs):
        try:
            return super().create(request, *args, **kwargs)
        except IntegrityError:
            raise ValidationError(
                {"name": "A plan with this name and category already exists."}
            )


class MemberViewSet(GymScopedViewSet):
    queryset = Member.objects.all()
    search_fields = ["first_name", "last_name", "phone", "member_code"]
    ordering_fields = ["first_name", "last_name", "created_at"]

    def get_serializer_class(self):
        if self.action in ("create", "update", "partial_update"):
            return MemberWriteSerializer
        return MemberSerializer

    def get_queryset(self):
        qs = Member.objects.filter(gym=self.gym).visible().with_status(self.today)
        mtype = self.request.query_params.get("type")
        if mtype == "prospect":
            qs = qs.prospects()
        elif mtype == "member":
            qs = qs.members()
        status_filter = self.request.query_params.get("status")
        if status_filter:
            qs = qs.filter(membership_status=status_filter)
        return qs.select_related("home_location")

    def create(self, request, *args, **kwargs):
        try:
            return super().create(request, *args, **kwargs)
        except IntegrityError:
            raise ValidationError({"id": "A member with this id already exists."})

    def destroy(self, request, *args, **kwargs):
        raise MethodNotAllowed("DELETE", detail="Use POST /members/{id}/archive/ instead.")

    @action(detail=True, methods=["get"])
    def memberships(self, request, pk=None):
        member = self.get_object()
        qs = member.memberships.all()
        return Response(MembershipSerializer(qs, many=True).data)

    @action(detail=True, methods=["post"])
    def renew(self, request, pk=None):
        member = self.get_object()
        plan_id = request.data.get("plan_id")
        if not plan_id:
            raise ValidationError({"plan_id": "This field is required."})
        try:
            plan = MembershipPlan.objects.get(id=plan_id, gym=self.gym, is_active=True)
        except (MembershipPlan.DoesNotExist, ValueError, TypeError):
            raise ValidationError({"plan_id": "Plan not found for your gym."})
        ms = Membership.renew(member, plan, self.today, created_by=request.user)
        return Response(MembershipSerializer(ms).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"], permission_classes=[IsGymStaff, IsOwner])
    def archive(self, request, pk=None):
        member = self.get_object()
        member.archived_at = timezone.now()
        member.archived_by = request.user
        member.save()
        return Response(status=status.HTTP_204_NO_CONTENT)

class SignupView(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_scope = "signup"

    def post(self, request):
        s = SignupSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        user = s.save()
        refresh = RefreshToken.for_user(user)
        return Response({
            "access": str(refresh.access_token),
            "refresh": str(refresh),
            "user": MeSerializer(user).data,
        }, status=status.HTTP_201_CREATED)


class ChangePasswordView(APIView):
    def post(self, request):
        s = ChangePasswordSerializer(data=request.data, context={"request": request})
        s.is_valid(raise_exception=True)
        user = request.user
        user.set_password(s.validated_data["new_password"])
        user.must_change_password = False
        user.save(update_fields=["password", "must_change_password"])
        return Response(status=status.HTTP_204_NO_CONTENT)


class StaffViewSet(viewsets.ModelViewSet):
    permission_classes = [IsGymStaff, IsOwner]
    http_method_names = ["get", "post", "patch", "head", "options"]

    def get_queryset(self):
        return (StaffProfile.objects.filter(gym=self.request.user.gym)
                .select_related("user", "default_location"))

    def get_serializer_class(self):
        return StaffCreateSerializer if self.action == "create" else StaffMemberSerializer

    def get_serializer_context(self):
        ctx = super().get_serializer_context()
        ctx["gym"] = self.request.user.gym
        return ctx

    def create(self, request, *args, **kwargs):
        s = self.get_serializer(data=request.data)
        s.is_valid(raise_exception=True)
        profile = s.save()
        return Response(StaffMemberSerializer(profile).data,
                        status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"])
    def deactivate(self, request, pk=None):
        profile = self.get_object()
        if profile.user_id == request.user.id:
            raise ValidationError({"detail": "You cannot deactivate your own account."})
        profile.user.is_active = False
        profile.user.save(update_fields=["is_active"])
        return Response(status=status.HTTP_204_NO_CONTENT)