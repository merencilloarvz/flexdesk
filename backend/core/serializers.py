from django.db import transaction
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

from .models import Location, Member, Membership, MembershipPlan
from django.contrib.auth.password_validation import validate_password
from django.utils.text import slugify
from .models import Gym, Location, MembershipPlan, StaffProfile, User


class MeSerializer(serializers.Serializer):
    id = serializers.UUIDField(read_only=True)
    email = serializers.EmailField(read_only=True)
    full_name = serializers.CharField(read_only=True)
    role = serializers.SerializerMethodField()
    gym = serializers.SerializerMethodField()
    default_location_id = serializers.SerializerMethodField()
    must_change_password = serializers.BooleanField(read_only=True)

    def get_role(self, obj):
        return obj.role

    def get_gym(self, obj):
        g = obj.gym
        if not g:
            return None
        return {
            "id": str(g.id),
            "name": g.name,
            "timezone": g.timezone,
            "currency": g.currency,
            "needs_setup": not MembershipPlan.objects.filter(gym=g, price__gt=0).exists(),
        }
    def get_default_location_id(self, obj):
        p = getattr(obj, "staff_profile", None)
        return str(p.default_location_id) if p and p.default_location_id else None


class FlexTokenObtainPairSerializer(TokenObtainPairSerializer):
    def validate(self, attrs):
        attrs[self.username_field] = (attrs.get(self.username_field) or "").strip().lower()
        data = super().validate(attrs)
        data["user"] = MeSerializer(self.user).data
        return data


class MembershipPlanSerializer(serializers.ModelSerializer):
    class Meta:
        model = MembershipPlan
        fields = ["id", "name","category", "duration_value", "duration_unit", "price",
                  "is_day_pass", "is_active", "sort_order"]


class MembershipSerializer(serializers.ModelSerializer):
    class Meta:
        model = Membership
        fields = ["id", "plan", "plan_name", "price_paid", "duration_value",
                  "duration_unit", "start_date", "end_date", "canceled_at", "created_at"]
        read_only_fields = fields


class MemberSerializer(serializers.ModelSerializer):
    full_name = serializers.CharField(read_only=True)
    membership_status = serializers.CharField(read_only=True)
    current_end_date = serializers.DateField(read_only=True)
    days_remaining = serializers.SerializerMethodField()

    class Meta:
        model = Member
        fields = ["id", "first_name", "last_name", "full_name", "phone", "email",
                  "member_code", "member_type", "home_location", "date_of_birth",
                  "notes", "membership_status", "current_end_date", "days_remaining",
                  "created_at", "updated_at"]

    def get_days_remaining(self, obj):
        end = getattr(obj, "current_end_date", None)
        if not end:
            return None
        return (end - self.context["today"]).days


class MemberWriteSerializer(serializers.ModelSerializer):
    id = serializers.UUIDField(required=False)
    plan_id = serializers.UUIDField(write_only=True, required=False, allow_null=True)
    start_date = serializers.DateField(write_only=True, required=False)

    class Meta:
        model = Member
        fields = ["id", "first_name", "last_name", "phone", "email", "date_of_birth",
                  "member_type", "notes", "home_location", "plan_id", "start_date"]
        extra_kwargs = {"home_location": {"required": False}}

    def validate_home_location(self, value):
        if value and value.gym_id != self.context["gym"].id:
            raise serializers.ValidationError("Location does not belong to your gym.")
        return value

    def validate(self, attrs):
        gym = self.context["gym"]
        if not attrs.get("home_location"):
            profile = self.context["request"].user.staff_profile
            loc = profile.default_location or Location.objects.filter(
                gym=gym, is_active=True).first()
            if not loc:
                raise serializers.ValidationError(
                    {"home_location": "No location available for this gym."})
            attrs["home_location"] = loc

        plan_id = attrs.pop("plan_id", None)
        if plan_id:
            try:
                attrs["_plan"] = MembershipPlan.objects.get(
                    id=plan_id, gym=gym, is_active=True)
            except MembershipPlan.DoesNotExist:
                raise serializers.ValidationError(
                    {"plan_id": "Plan not found for your gym."})
        return attrs

    @transaction.atomic
    def create(self, validated_data):
        plan = validated_data.pop("_plan", None)
        start = validated_data.pop("start_date", None) or self.context["today"]
        member = super().create(validated_data)
        if plan:
            Membership.objects.create(
                gym=member.gym, member=member, plan=plan, start_date=start,
                created_by=self.context["request"].user,
            )
        return member

# name, category, duration_value, unit, is_day_pass
DEFAULT_PLANS = [
    ("Walk-in", "Regular", 1, "DAY", True),
    ("Walk-in", "Student", 1, "DAY", True),
    ("Monthly", "Regular", 1, "MONTH", False),
    ("Monthly", "Student", 1, "MONTH", False),
]


def _unique_gym_slug(name):
    base = slugify(name)[:40] or "gym"
    slug, i = base, 2
    while Gym.objects.filter(slug=slug).exists():
        slug, i = f"{base}-{i}", i + 1
    return slug


class SignupSerializer(serializers.Serializer):
    gym_name = serializers.CharField(max_length=255)
    location_name = serializers.CharField(max_length=255, required=False, default="Main")
    full_name = serializers.CharField(max_length=120)
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True, min_length=8)

    def validate_email(self, value):
        value = value.strip().lower()
        if User.objects.filter(email=value).exists():
            raise serializers.ValidationError("An account with this email already exists.")
        return value

    def validate_password(self, value):
        validate_password(value)
        return value

    @transaction.atomic
    def create(self, data):
        gym = Gym.objects.create(
            name=data["gym_name"],
            slug=_unique_gym_slug(data["gym_name"]),
        )
        location = Location.objects.create(
            gym=gym, name=data.get("location_name") or "Main")
        user = User.objects.create_user(
            email=data["email"],
            password=data["password"],
            full_name=data["full_name"],
        )
        StaffProfile.objects.create(
            user=user, gym=gym, role=StaffProfile.OWNER, default_location=location)
        MembershipPlan.objects.bulk_create([
            MembershipPlan(gym=gym, name=n, category=c, duration_value=v,
                           duration_unit=u, price=0, is_day_pass=d, sort_order=i)
            for i, (n, c, v, u, d) in enumerate(DEFAULT_PLANS)
        ])
        return user

class StaffMemberSerializer(serializers.ModelSerializer):
    email = serializers.EmailField(source="user.email", read_only=True)
    full_name = serializers.CharField(source="user.full_name", read_only=True)
    is_active = serializers.BooleanField(source="user.is_active", read_only=True)

    class Meta:
        model = StaffProfile
        fields = ["id", "email", "full_name", "role", "is_active",
                  "default_location", "created_at"]


class StaffCreateSerializer(serializers.Serializer):
    full_name = serializers.CharField(max_length=120)
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True, min_length=8)
    role = serializers.ChoiceField(choices=StaffProfile.ROLE_CHOICES,
                                   default=StaffProfile.STAFF)
    default_location = serializers.UUIDField(required=False, allow_null=True)

    def validate_email(self, value):
        value = value.strip().lower()
        if User.objects.filter(email=value).exists():
            raise serializers.ValidationError("An account with this email already exists.")
        return value

    def validate_password(self, value):
        validate_password(value)
        return value

    def validate(self, attrs):
        gym = self.context["gym"]
        loc_id = attrs.pop("default_location", None)
        if loc_id:
            try:
                attrs["_location"] = Location.objects.get(id=loc_id, gym=gym)
            except (Location.DoesNotExist, ValueError, TypeError):
                raise serializers.ValidationError(
                    {"default_location": "Location not found for your gym."})
        return attrs

    @transaction.atomic
    def create(self, data):
        gym = self.context["gym"]
        owner_profile = self.context["request"].user.staff_profile
        location = data.get("_location") or owner_profile.default_location
        user = User.objects.create_user(
            email=data["email"], password=data["password"], full_name=data["full_name"])
        user.must_change_password = True
        user.save(update_fields=["must_change_password"])
        return StaffProfile.objects.create(
            user=user, gym=gym, role=data["role"], default_location=location)


class ChangePasswordSerializer(serializers.Serializer):
    current_password = serializers.CharField(write_only=True)
    new_password = serializers.CharField(write_only=True, min_length=8)

    def validate_current_password(self, value):
        if not self.context["request"].user.check_password(value):
            raise serializers.ValidationError("Current password is incorrect.")
        return value

    def validate_new_password(self, value):
        validate_password(value, self.context["request"].user)
        return value