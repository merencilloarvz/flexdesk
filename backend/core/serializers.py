from django.db import transaction, IntegrityError
from datetime import timedelta
from django.utils import timezone
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from .models import Announcement, Event, EventRegistration, EventResult
from .models import CheckIn, Location, Member, Membership, MembershipPlan
from django.contrib.auth.password_validation import validate_password
from django.utils.text import slugify
from .models import Gym, Location, MembershipPlan, StaffProfile, Subscription, User
from .utils import generate_claim_code
from .models import Booking, TimeSlot
from django.db.models import Count
from .utils import gym_today
from .models import Product, Sale, SaleItem, StockAdjustment

from .models import Location, Member, Membership, MembershipPlan
class MeSerializer(serializers.Serializer):
    id = serializers.UUIDField(read_only=True)
    email = serializers.EmailField(read_only=True)
    full_name = serializers.CharField(read_only=True)
    role = serializers.SerializerMethodField()
    account_type = serializers.SerializerMethodField()
    gym = serializers.SerializerMethodField()
    default_location_id = serializers.SerializerMethodField()
    must_change_password = serializers.BooleanField(read_only=True)

    def get_role(self, obj):
        return obj.role

    def get_account_type(self, obj):
        return obj.account_type

    def get_gym(self, obj):
        g = obj.gym
        if not g:
            return None
        sub = getattr(g, "subscription", None)
        return {
            "id": str(g.id),
            "name": g.name,
            "timezone": g.timezone,
            "currency": g.currency,
            "classes_enabled": g.classes_enabled,
            "needs_setup": not MembershipPlan.objects.filter(gym=g, price__gt=0).exists(),
            # The router's redirect decision reads subscription_blocked
            # straight off this payload on every navigation — see
            # app_router.dart — so it has to be here, not just on
            # GET /subscription/.
            "subscription_status": sub.status if sub else None,
            "subscription_blocked": sub.is_blocked if sub else False,
            "trial_ends_at": sub.trial_ends_at if sub else None,
        }
    def get_default_location_id(self, obj):
        p = getattr(obj, "staff_profile", None)
        return str(p.default_location_id) if p and p.default_location_id else None

class GymSettingsSerializer(serializers.ModelSerializer):
    class Meta:
        model = Gym
        fields = ["classes_enabled"]


class SubscriptionSerializer(serializers.Serializer):
    status = serializers.CharField(read_only=True)
    trial_ends_at = serializers.DateTimeField(read_only=True)
    is_blocked = serializers.SerializerMethodField()
    days_remaining = serializers.SerializerMethodField()

    def get_is_blocked(self, obj):
        return obj.is_blocked

    def get_days_remaining(self, obj):
        # Display only — trial countdown. None once the trial is no
        # longer the operative state (active/past_due/canceled); the
        # actual block decision always comes from is_blocked, never this.
        if obj.status != obj.TRIALING:
            return None
        return max((obj.trial_ends_at - timezone.now()).days, 0)

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
                  "is_day_pass", "is_active", "sort_order",'updated_at']

    def validate(self, attrs):
        gym = self.context.get("gym")
        name = attrs.get("name", getattr(self.instance, "name", None))
        category = attrs.get("category", getattr(self.instance, "category", ""))

        if gym and name is not None:
            qs = MembershipPlan.objects.filter(gym=gym, name=name, category=category)
            if self.instance:
                qs = qs.exclude(pk=self.instance.pk)
            if qs.exists():
                raise serializers.ValidationError(
                    {"name": f'A plan named "{name}" already exists for this category.'}
                )
        return attrs

class TimeSlotSerializer(serializers.ModelSerializer):
    # Not every action annotates booked_count (create/update instances
    # won't have it), so this is a method field rather than a plain
    # IntegerField — it just returns None when the annotation isn't there.
    booked_count = serializers.SerializerMethodField()

    class Meta:
        model = TimeSlot
        fields = ["id", "label", "start_time", "end_time", "capacity",
                  "days_of_week", "is_active", "booked_count", "coach_name",
                  "created_at", "updated_at"]
        read_only_fields = ["id", "created_at", "updated_at"]

    def get_booked_count(self, obj):
        return getattr(obj, "booked_count", None)

    def validate(self, attrs):
        # Find the worst case across every future date this slot is booked
        # for. Lowering below that would leave a date over-subscribed, and
        # nothing downstream would ever notice — the capacity check only
        # runs when someone new tries to book.
        if self.instance and "capacity" in attrs:
            worst = (Booking.objects
                     .filter(time_slot=self.instance,
                             canceled_at__isnull=True,
                             date__gte=gym_today(self.context["gym"]))
                     .values("date")
                     .annotate(n=Count("id"))
                     .order_by("-n")
                     .first())
            if worst and attrs["capacity"] < worst["n"]:
                raise serializers.ValidationError({
                    "capacity": f"{worst['n']} members are already booked on "
                                f"{worst['date']}. Cancel some bookings first, "
                                f"or set capacity to at least {worst['n']}."
                })
        return attrs


class BookingSerializer(serializers.ModelSerializer):
    time_slot_label = serializers.CharField(source="time_slot.label", read_only=True)

    class Meta:
        model = Booking
        fields = ["id", "time_slot", "time_slot_label", "date",
                  "canceled_at", "created_at"]
        read_only_fields = fields


class BookingCreateSerializer(serializers.Serializer):
    """
    Deliberately only these two fields exist on this serializer — that's
    what guarantees a client-supplied `member` in the POST body can never
    reach the database. All real validation (slot exists/active, weekday,
    date range, membership status, capacity) happens in
    views.create_booking(), not here.
    """
    time_slot = serializers.UUIDField()
    date = serializers.DateField()


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
    current_plan_category = serializers.CharField(read_only=True)
    days_remaining = serializers.SerializerMethodField()
    has_account = serializers.SerializerMethodField()

    class Meta:
        model = Member
        fields = ["id", "first_name", "last_name", "full_name", "phone", "email",
                  "member_code", "member_type", "home_location", "date_of_birth",
                  "notes", "membership_status", "current_end_date",
                  "current_plan_category", "days_remaining", "has_account",
                  "created_at", "updated_at",'archived_at']

    def get_days_remaining(self, obj):
        end = getattr(obj, "current_end_date", None)
        if not end:
            return None
        return (end - self.context["today"]).days

    def get_has_account(self, obj):
        return obj.user_id is not None


class MemberWriteSerializer(serializers.ModelSerializer):
    id = serializers.UUIDField(required=False)
    plan_id = serializers.UUIDField(write_only=True, required=False, allow_null=True)
    start_date = serializers.DateField(write_only=True, required=False)
    claim_code = serializers.CharField(read_only=True)

    class Meta:
        model = Member
        fields = ["id", "first_name", "last_name", "phone", "email", "date_of_birth",
                  "member_type", "notes", "home_location", "plan_id", "start_date",
                  "claim_code"]
        extra_kwargs = {"home_location": {"required": False}}

    def validate_home_location(self, value):
        if value and value.gym_id != self.context["gym"].id:
            raise serializers.ValidationError("Location does not belong to your gym.")
        return value

    def validate(self, attrs):
        gym = self.context["gym"]

        # Required only when creating a MEMBER (not PROSPECT, not on
        # update) — a walk-in prospect shouldn't need one, and an
        # existing legacy row with a blank email must stay editable
        # (archive/renew/edit all call Member.save(), which would
        # otherwise fail full_clean() on every write to that row).
        # The claim flow is still guaranteed an email for every member
        # created from here on, which is the actual thing that needed
        # fixing.
        member_type = attrs.get("member_type", Member.MEMBER)
        if (
            self.instance is None
            and member_type == Member.MEMBER
            and not attrs.get("email")
        ):
            raise serializers.ValidationError(
                {"email": "Email is required for a member (not needed for prospects)."}
            )

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

        if validated_data.get("member_type", Member.MEMBER) == Member.MEMBER:
            # Retry loop: claim_code is unique per gym, and a collision — while
            # rare — is possible. Django's full_clean() can't validate this
            # constraint in Python (it's conditional, only applies when
            # claim_code isn't blank), so a collision only surfaces as an
            # IntegrityError from the database on save. A savepoint per
            # attempt keeps the retry isolated within the outer transaction.
            member = None
            last_error = None
            for _ in range(3):
                validated_data["claim_code"] = generate_claim_code()
                validated_data["claim_code_expires_at"] = (
                    timezone.now() + timedelta(days=30)
                )
                try:
                    with transaction.atomic():
                        member = super().create(validated_data)
                    break
                except IntegrityError as e:
                    last_error = e
                    continue
            if member is None:
                raise last_error
        else:
            member = super().create(validated_data)

        if plan:
            Membership.objects.create(
                gym=member.gym, member=member, plan=plan, start_date=start,
                created_by=self.context["request"].user,
            )
        return member

class CheckInSerializer(serializers.ModelSerializer):
    member_name = serializers.SerializerMethodField()
    member_code = serializers.SerializerMethodField()
    display_name = serializers.SerializerMethodField()

    class Meta:
        model = CheckIn
        fields = ["id", "visit_type", "member", "member_name", "member_code",
                  "visitor_name", "display_name", "category", "amount_charged",
                  "location", "checked_in_at", "membership_status",
                  "membership_end_date", "voided_at", "created_at", "updated_at"]
        read_only_fields = fields

    def get_member_name(self, obj):
        return obj.member.full_name if obj.member_id else None

    def get_member_code(self, obj):
        return obj.member.member_code if obj.member_id else None

    def get_display_name(self, obj):
        # Whichever the today-list should show at a glance — member's real
        # name, or the typed walk-in name.
        return obj.member.full_name if obj.member_id else obj.visitor_name


class CheckInWriteSerializer(serializers.ModelSerializer):
    id = serializers.UUIDField(required=False)

    class Meta:
        model = CheckIn
        fields = ["id", "visit_type", "member", "visitor_name", "category",
                  "amount_charged", "location", "checked_in_at",
                  "membership_status", "membership_end_date"]
        extra_kwargs = {"location": {"required": False}}

    def validate_location(self, value):
        if value and value.gym_id != self.context["gym"].id:
            raise serializers.ValidationError("Location does not belong to your gym.")
        return value

    def validate_member(self, value):
        if value and value.gym_id != self.context["gym"].id:
            raise serializers.ValidationError("Member does not belong to your gym.")
        if value and value.archived_at:
            raise serializers.ValidationError("This member has been archived.")
        return value

    def validate(self, attrs):
        gym = self.context["gym"]
        if not attrs.get("location"):
            profile = getattr(self.context["request"].user, "staff_profile", None)
            loc = (profile.default_location if profile else None) or \
                Location.objects.filter(gym=gym, is_active=True).first()
            if not loc:
                raise serializers.ValidationError(
                    {"location": "No location available for this gym."})
            attrs["location"] = loc

        visit_type = attrs.get("visit_type")
        if visit_type == CheckIn.MEMBER:
            if not attrs.get("member"):
                raise serializers.ValidationError(
                    {"member": "Required for a member check-in."})
            # A member row never carries walk-in fields, even if the client sent them.
            attrs["visitor_name"] = ""
            attrs["category"] = ""
            attrs["amount_charged"] = None
        elif visit_type == CheckIn.WALKIN:
            if attrs.get("member"):
                raise serializers.ValidationError(
                    {"member": "Walk-in check-ins must not include a member."})
            if not (attrs.get("visitor_name") or "").strip():
                raise serializers.ValidationError(
                    {"visitor_name": "Required for a walk-in check-in."})
            if not attrs.get("category"):
                raise serializers.ValidationError(
                    {"category": "Required for a walk-in check-in."})
            attrs["member"] = None
            attrs["membership_status"] = ""
            attrs["membership_end_date"] = None
        else:
            raise serializers.ValidationError(
                {"visit_type": "Must be MEMBER or WALKIN."})
        return attrs

    def create(self, validated_data):
        # "gym" is already in validated_data here — GymScopedViewSet.perform_create
        # injects it via serializer.save(gym=self.gym) before this runs.
        if validated_data["visit_type"] == CheckIn.MEMBER:
            valid_statuses = {"active", "expiring", "expired", "no_membership"}
            if validated_data.get("membership_status") not in valid_statuses:
                member = validated_data["member"]
                annotated = (Member.objects
                            .filter(gym=validated_data["gym"], pk=member.pk)
                            .with_status(self.context["today"]).first())
                validated_data["membership_status"] = annotated.membership_status
                validated_data["membership_end_date"] = annotated.current_end_date

        validated_data["checked_in_by"] = self.context["request"].user
        return CheckIn.objects.create(**validated_data)


TRIAL_DAYS = 14

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
        Subscription.objects.create(
            gym=gym, trial_ends_at=timezone.now() + timedelta(days=TRIAL_DAYS))
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


from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.exceptions import TokenError


class LogoutSerializer(serializers.Serializer):
    """
    Blacklists the submitted refresh token. Deliberately never raises —
    logout must never fail in a way that leaves someone stuck on a
    screen they're trying to leave. An already-blacklisted, expired, or
    malformed token still results in a successful logout from the
    caller's point of view; see LogoutView, which returns 204
    regardless of what happens here.
    """
    refresh = serializers.CharField()

    def save(self):
        try:
            token = RefreshToken(self.validated_data["refresh"])
            token.blacklist()
        except TokenError:
            # Already blacklisted, expired, or malformed — treat as a
            # no-op. The client's goal (this token no longer works) is
            # already achieved either way.
            pass

class ClaimAccountSerializer(serializers.Serializer):
    """
    Lets a member turn their staff-issued one-time code into a real login.
    All failures from the member-lookup step return the SAME generic
    message on purpose — see the docstring on validate() below. Never
    change that without re-reading why.
    """
    email = serializers.EmailField()
    claim_code = serializers.CharField()
    password = serializers.CharField(write_only=True)

    GENERIC_ERROR = "That email and code don't match, or the code has expired."

    def validate_password(self, value):
        validate_password(value)
        return value

    def validate(self, attrs):
        # Step 1: normalize, same as User.save() does.
        email = attrs["email"].strip().lower()
        # Step 2: uppercase — someone typing a printed code will often use
        # lowercase, and the alphabet the code is generated from is all caps.
        code = attrs["claim_code"].strip().upper()

        # Step 3: find the matching, still-unclaimed, still-valid member.
        member = (
            Member.objects.filter(
                email__iexact=email,
                claim_code=code,
                user__isnull=True,
                archived_at__isnull=True,
                claim_code_expires_at__gt=timezone.now(),
            ).first()
        )
        if not member:
            # Deliberately identical whether the email doesn't exist, the
            # code is wrong, the code expired, or it was already used.
            # Distinguishing these turns this endpoint into a way to test
            # which emails belong to a gym member.
            raise serializers.ValidationError(self.GENERIC_ERROR)

        # Step 4: a DIFFERENT check — does a login already exist for this
        # email? (e.g. this person is staff elsewhere, or a member at
        # another gym.) This gets its own distinct message on purpose —
        # it's not part of the "don't leak which email is a member" secrecy
        # above, since by this point we've already confirmed the code
        # matched a real member.
        if User.objects.filter(email=email).exists():
            raise serializers.ValidationError(
                "An account already exists for this email. Please sign in instead."
            )

        attrs["member"] = member
        attrs["email"] = email
        attrs["claim_code"] = code
        return attrs

    @transaction.atomic
    def create(self, validated_data):
        member = validated_data["member"]
        user = User.objects.create_user(
            email=validated_data["email"],
            password=validated_data["password"],
            full_name=member.full_name,
        )
        member.user = user
        member.claim_code = ""
        member.claim_code_expires_at = None
        member.save(update_fields=["user", "claim_code", "claim_code_expires_at","updated_at"])
        return user
class MeMemberSummarySerializer(serializers.Serializer):
    """
    Deliberately NOT a ModelSerializer, and deliberately NOT a reuse of
    MemberSerializer. MemberSerializer exposes `notes` — the gym's private
    notes about the member — and `archived_at`/`member_type`, none of
    which a member should ever see about themselves. Explicit fields here
    mean nothing gets added to this response by accident when Member
    grows new fields later.

    Expects the Member instance passed in to already be annotated via
    .with_status() (for membership_status/current_end_date/
    current_plan_category), and to have check_ins_this_month and
    last_check_in_at set as plain attributes by the view before
    serializing — see MeSummaryView.
    """
    id = serializers.UUIDField()
    full_name = serializers.CharField()
    member_code = serializers.CharField()
    membership_status = serializers.CharField()
    current_end_date = serializers.DateField(allow_null=True)
    days_remaining = serializers.SerializerMethodField()
    current_plan_category = serializers.CharField(allow_null=True)
    is_archived = serializers.SerializerMethodField()
    gym = serializers.SerializerMethodField()
    check_ins_this_month = serializers.IntegerField()
    last_check_in_at = serializers.DateTimeField(allow_null=True)
    rest_days = serializers.CharField()

    def get_days_remaining(self, obj):
        end = getattr(obj, "current_end_date", None)
        if not end:
            return None
        return (end - self.context["today"]).days

    def get_is_archived(self, obj):
        return obj.archived_at is not None

    def get_gym(self, obj):
        g = obj.gym
        # Deliberately no needs_setup — that's an owner-onboarding concern
        # and means nothing to a member.
        return {
            "name": g.name,
            "timezone": g.timezone,
            "currency": g.currency,
        }


class MemberRestDaysSerializer(serializers.Serializer):
    """
    Lets a member set which weekdays are excused from breaking their
    streak. Free text validated into a clean comma-separated set of
    1-7 ints — never trusts the client's exact formatting.
    """
    rest_days = serializers.CharField(allow_blank=True)

    def validate_rest_days(self, value):
        if not value.strip():
            return ""
        try:
            days = {int(d.strip()) for d in value.split(",") if d.strip()}
        except ValueError:
            raise serializers.ValidationError(
                "Must be comma-separated numbers 1 (Mon) through 7 (Sun)."
            )
        if not days.issubset(set(range(1, 8))):
            raise serializers.ValidationError("Days must be between 1 and 7.")
        return ",".join(str(d) for d in sorted(days))

class MeCheckInSerializer(serializers.ModelSerializer):
    """
    Narrow, member-facing view of a check-in. Deliberately excludes
    location, amount_charged, voided_at, and who checked them in —
    the member doesn't need any of that, and voided rows are filtered
    out entirely before they ever reach this serializer (see
    MeCheckInsView), not just hidden here.
    """
    class Meta:
        model = CheckIn
        fields = ["id", "checked_in_at", "visit_type", "membership_status"]
        read_only_fields = fields


class AnnouncementSerializer(serializers.ModelSerializer):
    class Meta:
        model = Announcement
        fields = ["id", "title", "body", "is_pinned", "created_at", "updated_at"]
        read_only_fields = ["id", "created_at", "updated_at"]
        # created_by deliberately absent — not just hidden, never sent.


class EventSerializer(serializers.ModelSerializer):
    is_canceled = serializers.SerializerMethodField()
    registration_count = serializers.SerializerMethodField()
    spots_left = serializers.SerializerMethodField()
    my_registration = serializers.SerializerMethodField()

    class Meta:
        model = Event
        fields = ["id", "title", "description", "event_date", "start_time",
                  "location_text", "registration_fee", "prize_description",
                  "capacity", "registration_closes_on", "canceled_at",
                  "is_canceled", "registration_count", "spots_left",
                  "my_registration", "created_at", "updated_at"]
        read_only_fields = ["id", "is_canceled", "registration_count",
                           "spots_left", "my_registration", "created_at",
                           "updated_at"]

    def get_is_canceled(self, obj):
        return obj.canceled_at is not None

    def get_registration_count(self, obj):
        count = getattr(obj, "registration_count", None)
        if count is None:
            count = obj.registrations.filter(canceled_at__isnull=True).count()
        return count

    def get_spots_left(self, obj):
        if obj.capacity is None:
            return None
        return max(obj.capacity - self.get_registration_count(obj), 0)

    def get_my_registration(self, obj):
        # Deliberately does NOT expose the full registrations list —
        # only ever the caller's own row, same pattern as my_booking_id
        # on /schedule/.
        request = self.context.get("request")
        member = getattr(request.user, "member_profile", None) if request else None
        if not member:
            return None
        reg = obj.registrations.filter(member=member, canceled_at__isnull=True).first()
        if not reg:
            return None
        return {
            "id": str(reg.id),
            "payment_status": reg.payment_status,
            "amount_due": str(reg.amount_due),
        }


class MemberEventRegistrationSerializer(serializers.ModelSerializer):
    """
    The member's own view of a registration — used for /me/event-registrations/
    and the register()/unregister() action responses. Deliberately excludes
    member_name/member_code/marked_paid_by; it's always the caller's own row.
    """
    event_title = serializers.CharField(source="event.title", read_only=True)
    event_date = serializers.DateField(source="event.event_date", read_only=True)

    class Meta:
        model = EventRegistration
        fields = ["id", "event", "event_title", "event_date", "payment_status",
                  "amount_due", "canceled_at", "created_at"]
        read_only_fields = fields


class EventRegistrationSerializer(serializers.ModelSerializer):
    """
    Staff-only view — includes member_name/member_code, which is exactly
    what must never reach a member. See EventRegistrationViewSet's
    permission_classes.
    """
    member_name = serializers.CharField(source="member.full_name", read_only=True)
    member_code = serializers.CharField(source="member.member_code", read_only=True)
    event_title = serializers.CharField(source="event.title", read_only=True)

    class Meta:
        model = EventRegistration
        fields = ["id", "event", "event_title", "member", "member_name",
                  "member_code", "payment_status", "amount_due", "paid_at",
                  "canceled_at", "created_at"]
        read_only_fields = fields


class EventResultInputSerializer(serializers.Serializer):
    """
    Input shape for POST /events/{id}/results/ — a plain Serializer used
    with many=True, not a ModelSerializer, since the whole set is replaced
    in one go rather than mapped item-by-item onto existing rows.
    """
    member = serializers.UUIDField(required=False, allow_null=True)
    display_name = serializers.CharField(required=False, allow_blank=True,
                                         max_length=120)
    rank = serializers.IntegerField(min_value=1)
    score_text = serializers.CharField(required=False, allow_blank=True,
                                       max_length=60)
    note = serializers.CharField(required=False, allow_blank=True, max_length=200)

    def validate(self, attrs):
        if not attrs.get("member") and not (attrs.get("display_name") or "").strip():
            raise serializers.ValidationError(
                {"display_name": "Required when no member is linked."})
        return attrs


class EventResultSerializer(serializers.ModelSerializer):
    class Meta:
        model = EventResult
        fields = ["id", "member", "display_name", "rank", "score_text", "note"]
        read_only_fields = fields


class ProductSerializer(serializers.ModelSerializer):
    class Meta:
        model = Product
        fields = ["id", "name", "category", "price", "stock_quantity",
                  "low_stock_threshold", "is_active", "created_at", "updated_at"]
        read_only_fields = ["id", "created_at", "updated_at"]

    def validate(self, attrs):
        gym = self.context.get("gym")
        name = attrs.get("name", getattr(self.instance, "name", None))
        if gym and name is not None:
            qs = Product.objects.filter(gym=gym, name=name)
            if self.instance:
                qs = qs.exclude(pk=self.instance.pk)
            if qs.exists():
                raise serializers.ValidationError(
                    {"name": f'A product named "{name}" already exists.'})
        return attrs

    def update(self, instance, validated_data):
        # Stock changes only ever go through /products/{id}/adjust/, so
        # every change gets a StockAdjustment row. Silently dropping it
        # here (rather than erroring) keeps a stray "stock_quantity" in a
        # PATCH body from doing anything unexpected.
        validated_data.pop("stock_quantity", None)
        return super().update(instance, validated_data)


class SaleItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = SaleItem
        fields = ["id", "product", "product_name", "unit_price",
                  "quantity", "line_total"]
        read_only_fields = fields


class SaleSerializer(serializers.ModelSerializer):
    items = SaleItemSerializer(many=True, read_only=True)
    member_name = serializers.SerializerMethodField()
    sold_by_name = serializers.SerializerMethodField()

    class Meta:
        model = Sale
        fields = ["id", "member", "member_name", "total_amount", "sold_at",
                  "sold_by_name", "voided_at", "items", "created_at"]
        read_only_fields = fields

    def get_member_name(self, obj):
        return obj.member.full_name if obj.member_id else None

    def get_sold_by_name(self, obj):
        return obj.sold_by.get_full_name() if obj.sold_by_id else None


class SaleItemInputSerializer(serializers.Serializer):
    product_id = serializers.UUIDField()
    quantity = serializers.IntegerField(min_value=1)


class SaleCreateSerializer(serializers.Serializer):
    """
    Deliberately a plain Serializer, same reasoning as
    BookingCreateSerializer — all the real validation (stock, gym
    ownership, atomicity) happens in views.create_sale(), not here.
    """
    member = serializers.UUIDField(required=False, allow_null=True)
    items = SaleItemInputSerializer(many=True)

    def validate_items(self, value):
        if not value:
            raise serializers.ValidationError("At least one item is required.")
        return value


class StockAdjustmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = StockAdjustment
        fields = ["id", "delta", "reason", "created_by", "created_at"]
        read_only_fields = fields


class StockAdjustmentInputSerializer(serializers.Serializer):
    delta = serializers.IntegerField()
    reason = serializers.CharField(required=False, allow_blank=True, max_length=120)

    def validate_delta(self, value):
        if value == 0:
            raise serializers.ValidationError("Delta cannot be zero.")
        return value