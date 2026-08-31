import uuid
from django.conf import settings
from django.contrib.auth.models import AbstractBaseUser, PermissionsMixin, BaseUserManager
from django.core.exceptions import ValidationError
from django.db import models
from django.db.models.functions import Lower
from datetime import timedelta
from dateutil.relativedelta import relativedelta
from django.db.models import Case, CharField, OuterRef, Q, Subquery, Value, When




class UserManager(BaseUserManager):
    def create_user(self, email, password=None, **extra):
        if not email:
            raise ValueError("Email is required")
        user = self.model(email=self.normalize_email(email), **extra)
        user.set_password(password)
        user.save(using=self._db)
        return user
    
    def create_superuser(self, email, password=None, **extra):
        extra.setdefault("is_staff", True)
        extra.setdefault("is_superuser", True)
        if extra.get("is_staff") is not True:
            raise ValueError("Superuser must have is_staff=True.")
        if extra.get("is_superuser") is not True:
            raise ValueError("Superuser must have is_superuser=True.")
        return self.create_user(email, password, **extra)


class User(AbstractBaseUser, PermissionsMixin):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email = models.EmailField(unique=True)
    full_name = models.CharField(max_length=120, blank=True)
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)   # Django admin access, NOT gym staff
    date_joined = models.DateTimeField(auto_now_add=True)
    must_change_password = models.BooleanField(default=False)
    
    objects = UserManager()
    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = []

    @property
    def gym(self):
        profile = getattr(self, "staff_profile", None)
        return profile.gym if profile else None

    @property
    def role(self):
        profile = getattr(self, "staff_profile", None)
        return profile.role if profile else None

    @property
    def is_owner(self):
        return self.role == StaffProfile.OWNER

    def __str__(self):
        return self.email
    
    def save(self, *args, **kwargs):
        self.email = (self.email or "").strip().lower()
        return super().save(*args, **kwargs)
    
    def get_full_name(self):
        return self.full_name or self.email

    def get_short_name(self):
        return self.full_name.split(" ")[0] if self.full_name else self.email

    class Meta:
        constraints = [
            models.UniqueConstraint(Lower("email"), name="uniq_user_email_ci"),
        ]


class Gym(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=255)
    slug = models.SlugField(unique=True)  # human-readable identifier, not routing
    timezone = models.CharField(max_length=64, default="Asia/Manila")
    currency = models.CharField(max_length=8, default="PHP")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.name

class Location(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    gym = models.ForeignKey(Gym, on_delete=models.CASCADE, related_name="locations")
    name = models.CharField(max_length=255)
    address = models.CharField(max_length=500, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)


    def __str__(self):
        return f"{self.gym.name} — {self.name}"

    class Meta:
        ordering = ["name"]
        constraints = [
            models.UniqueConstraint(fields=["gym", "name"], name="uniq_location_name_per_gym")
        ]

class TenantScopedModel(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    gym = models.ForeignKey(Gym, on_delete=models.CASCADE, related_name="%(class)ss")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class StaffProfile(models.Model):
    OWNER = "owner"
    STAFF = "staff"
    ROLE_CHOICES = [(OWNER, "Owner"), (STAFF, "Staff")]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="staff_profile")
    gym = models.ForeignKey(Gym, on_delete=models.CASCADE, related_name="staff")
    role = models.CharField(max_length=10, choices=ROLE_CHOICES, default=STAFF)
    default_location = models.ForeignKey(
        Location, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    

    def __str__(self):
        return f"{self.user.email} ({self.get_role_display()} @ {self.gym.name})"
    
    def clean(self):
        if self.default_location_id and self.default_location.gym_id != self.gym_id:
            raise ValidationError(
                {"default_location": "Location must belong to the same gym."}
            )

    def save(self, *args, **kwargs):
        self.full_clean()
        return super().save(*args, **kwargs)


DURATION_UNITS = {"DAY": "days", "WEEK": "weeks", "MONTH": "months", "YEAR": "years"}


class MembershipPlan(TenantScopedModel):
    DAY, WEEK, MONTH, YEAR = "DAY", "WEEK", "MONTH", "YEAR"
    UNIT_CHOICES = [(DAY, "Day"), (WEEK, "Week"), (MONTH, "Month"), (YEAR, "Year")]

    name = models.CharField(max_length=100)
    category = models.CharField(max_length=50, blank=True)
    duration_value = models.PositiveIntegerField(default=1)
    duration_unit = models.CharField(max_length=10, choices=UNIT_CHOICES, default=MONTH)
    price = models.DecimalField(max_digits=12, decimal_places=2)
    is_day_pass = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveIntegerField(default=0)

    class Meta(TenantScopedModel.Meta):
        ordering = ["sort_order","category", "name"]
        constraints = [
            models.UniqueConstraint(fields=["gym", "name","category"], name="uniq_plan_name_per_gym")
        ]

    def __str__(self):
        return f"{self.name} ({self.duration_value} {self.get_duration_unit_display().lower()})"

    def end_date_from(self, start_date):
        delta = relativedelta(**{DURATION_UNITS[self.duration_unit]: self.duration_value})
        return start_date + delta - timedelta(days=1)


class MemberQuerySet(models.QuerySet):
    def visible(self):
        return self.filter(archived_at__isnull=True)

    def members(self):
        return self.filter(member_type=Member.MEMBER)

    def prospects(self):
        return self.filter(member_type=Member.PROSPECT)

    def with_status(self, today, expiring_within_days=7):
        # Both current_end_date and current_plan_category come from the
        # same "latest non-canceled membership" row, so they share one
        # base subquery rather than each re-filtering/re-ordering from
        # scratch — keeps the two guaranteed to describe the same
        # Membership row, not two different ones if timing ever mattered.
        latest_membership = (
            Membership.objects
            .filter(member=OuterRef("pk"), canceled_at__isnull=True)
            .order_by("-end_date")
        )
        return self.annotate(
            current_end_date=Subquery(latest_membership.values("end_date")[:1]),
            current_plan_category=Subquery(
                latest_membership.values("plan__category")[:1]
            ),
        ).annotate(
            membership_status=Case(
                When(current_end_date__isnull=True, then=Value("no_membership")),
                When(current_end_date__lt=today, then=Value("expired")),
                When(current_end_date__lte=today + timedelta(days=expiring_within_days),
                     then=Value("expiring")),
                default=Value("active"),
                output_field=CharField(),
            )
        )


class Member(TenantScopedModel):
    MEMBER, PROSPECT = "MEMBER", "PROSPECT"
    TYPE_CHOICES = [(MEMBER, "Member"), (PROSPECT, "Walk-in / prospect")]

    home_location = models.ForeignKey(Location, on_delete=models.PROTECT, related_name="members")
    member_code = models.CharField(max_length=20, blank=True)
    first_name = models.CharField(max_length=80)
    last_name = models.CharField(max_length=80, blank=True)
    phone = models.CharField(max_length=32, blank=True)
    email = models.EmailField(blank=True)
    photo = models.ImageField(upload_to="members/", null=True, blank=True)
    date_of_birth = models.DateField(null=True, blank=True)
    member_type = models.CharField(max_length=10, choices=TYPE_CHOICES, default=MEMBER)
    notes = models.TextField(blank=True)
    archived_at = models.DateTimeField(null=True, blank=True)
    archived_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True,
                                    on_delete=models.SET_NULL, related_name="+")

    objects = MemberQuerySet.as_manager()

    class Meta(TenantScopedModel.Meta):
        ordering = ["first_name", "last_name"]
        constraints = [
            models.UniqueConstraint(
                fields=["gym", "member_code"],
                condition=~Q(member_code=""),
                name="uniq_member_code_per_gym",
            )
        ]
        indexes = [
            models.Index(fields=["gym", "member_type", "archived_at"]),
            models.Index(fields=["gym", "last_name", "first_name"]),
        ]

    def __str__(self):
        return self.full_name

    @property
    def full_name(self):
        return f"{self.first_name} {self.last_name}".strip()

    @property
    def current_membership(self):
        return (self.memberships
                .filter(canceled_at__isnull=True)
                .order_by("-end_date")
                .first())

    def clean(self):
        if self.home_location_id and self.home_location.gym_id != self.gym_id:
            raise ValidationError({"home_location": "Location must belong to the same gym."})

    def save(self, *args, **kwargs):
        self.full_clean()
        return super().save(*args, **kwargs)

class Membership(TenantScopedModel):
    member = models.ForeignKey(Member, on_delete=models.CASCADE, related_name="memberships")
    plan = models.ForeignKey(MembershipPlan, on_delete=models.PROTECT, related_name="memberships")

    plan_name = models.CharField(max_length=100, blank=True)
    price_paid = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    duration_value = models.PositiveIntegerField(null=True, blank=True)
    duration_unit = models.CharField(max_length=10, blank=True)

    start_date = models.DateField()
    end_date = models.DateField(blank=True)
    previous = models.ForeignKey("self", null=True, blank=True,
                                 on_delete=models.SET_NULL, related_name="renewals")
    canceled_at = models.DateTimeField(null=True, blank=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True,
                                   on_delete=models.SET_NULL, related_name="+")

    class Meta(TenantScopedModel.Meta):
        ordering = ["-end_date"]
        indexes = [
            models.Index(fields=["gym", "end_date"]),
            models.Index(fields=["member", "-end_date"]),
        ]

    def __str__(self):
        return f"{self.member.full_name} — {self.plan_name} to {self.end_date}"

    def clean(self):
        if self.member_id and self.member.gym_id != self.gym_id:
            raise ValidationError({"member": "Member must belong to the same gym."})
        if self.plan_id and self.plan.gym_id != self.gym_id:
            raise ValidationError({"plan": "Plan must belong to the same gym."})

    def save(self, *args, **kwargs):
        if self.plan_id:
            if not self.plan_name:
                self.plan_name = self.plan.name
            if self.price_paid is None:
                self.price_paid = self.plan.price
            if self.duration_value is None:
                self.duration_value = self.plan.duration_value
            if not self.duration_unit:
                self.duration_unit = self.plan.duration_unit
        if not self.end_date:
            delta = relativedelta(**{DURATION_UNITS[self.duration_unit]: self.duration_value})
            self.end_date = self.start_date + delta - timedelta(days=1)

        self.full_clean()  
        return super().save(*args, **kwargs)

    @classmethod
    def renew(cls, member, plan, today, created_by=None):
        current = member.current_membership
        start = max(today, current.end_date + timedelta(days=1)) if current else today
        return cls.objects.create(
            gym=member.gym, member=member, plan=plan,
            start_date=start, previous=current, created_by=created_by,
        )