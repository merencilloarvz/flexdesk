import uuid
from django.conf import settings
from django.contrib.auth.models import AbstractBaseUser, PermissionsMixin, BaseUserManager
from django.core.exceptions import ValidationError
from django.db import models
from django.db.models.functions import Lower
from datetime import timedelta
from dateutil.relativedelta import relativedelta
from django.db.models import Case, CharField, OuterRef, Q, Subquery, Value, When
from django.utils import timezone



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
        staff = getattr(self, "staff_profile", None)
        if staff:
            return staff.gym
        member = getattr(self, "member_profile", None)
        return member.gym if member else None

    @property
    def role(self):
        profile = getattr(self, "staff_profile", None)
        return profile.role if profile else None

    @property
    def account_type(self):
        if getattr(self, "staff_profile", None):
            return "staff"
        if getattr(self, "member_profile", None):
            return "member"
        return None

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
    classes_enabled = models.BooleanField(default=False)
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
        
class Subscription(models.Model):
    TRIALING, ACTIVE, PAST_DUE, CANCELED = "trialing", "active", "past_due", "canceled"
    STATUS_CHOICES = [
        (TRIALING, "Trialing"), (ACTIVE, "Active"),
        (PAST_DUE, "Past due"), (CANCELED, "Canceled"),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    gym = models.OneToOneField(Gym, on_delete=models.CASCADE, related_name="subscription")
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default=TRIALING)
    trial_ends_at = models.DateTimeField()
    paymongo_customer_id = models.CharField(max_length=100, blank=True)
    paymongo_subscription_id = models.CharField(max_length=100, blank=True)
    current_period_end = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    @property
    def is_blocked(self):
        if self.status == self.ACTIVE:
            return False
        if self.status == self.TRIALING:
            return timezone.now() > self.trial_ends_at
        return True  # past_due, canceled

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
        ordering = ["sort_order","category", "name", "id"]
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
    # Comma-separated weekday numbers (1=Mon..7=Sun), e.g. "6,7" for
    # Sat/Sun. Empty means none configured.
    rest_days = models.CharField(max_length=20, blank=True)
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="member_profile",
    )
    claim_code = models.CharField(max_length=8, blank=True)
    claim_code_expires_at = models.DateTimeField(null=True, blank=True)

    objects = MemberQuerySet.as_manager()

    class Meta(TenantScopedModel.Meta):
        ordering = ["first_name", "last_name","id"]
        constraints = [
            models.UniqueConstraint(
                fields=["gym", "member_code"],
                condition=~Q(member_code=""),
                name="uniq_member_code_per_gym",
            ),
            models.UniqueConstraint(
                fields=["gym", "claim_code"],
                condition=~Q(claim_code=""),
                name="uniq_claim_code_per_gym",
            ),
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
        ordering = ["-end_date","id"]
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

class CheckIn(TenantScopedModel):
    MEMBER, WALKIN = "MEMBER", "WALKIN"
    VISIT_TYPE_CHOICES = [(MEMBER, "Member"), (WALKIN, "Walk-in")]

    REGULAR, STUDENT = "regular", "student"
    CATEGORY_CHOICES = [(REGULAR, "Regular"), (STUDENT, "Student")]

    visit_type = models.CharField(max_length=10, choices=VISIT_TYPE_CHOICES)

    # --- member check-ins ---
    member = models.ForeignKey(Member, null=True, blank=True, on_delete=models.PROTECT,
                               related_name="check_ins")
    membership_status = models.CharField(max_length=20, blank=True)
    membership_end_date = models.DateField(null=True, blank=True)

    # --- walk-in check-ins ---
    visitor_name = models.CharField(max_length=120, blank=True)
    category = models.CharField(max_length=50, blank=True)
    amount_charged = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)

    location = models.ForeignKey(Location, on_delete=models.PROTECT, related_name="check_ins")
    checked_in_at = models.DateTimeField()
    checked_in_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True,
                                      on_delete=models.SET_NULL, related_name="+")
    voided_at = models.DateTimeField(null=True, blank=True)
    voided_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True,
                                  on_delete=models.SET_NULL, related_name="+")

    class Meta(TenantScopedModel.Meta):
        ordering = ["-checked_in_at", "id"]
        indexes = [
            models.Index(fields=["gym", "-checked_in_at"]),
            models.Index(fields=["member", "-checked_in_at"]),
        ]

    def __str__(self):
        who = self.member.full_name if self.member_id else self.visitor_name
        return f"{who} @ {self.checked_in_at:%Y-%m-%d %H:%M}"

    def clean(self):
        if self.location_id and self.location.gym_id != self.gym_id:
            raise ValidationError({"location": "Location must belong to the same gym."})
        if self.visit_type == self.MEMBER:
            if not self.member_id:
                raise ValidationError({"member": "Member check-in requires a member."})
            if self.member.gym_id != self.gym_id:
                raise ValidationError({"member": "Member must belong to the same gym."})
        elif self.visit_type == self.WALKIN:
            if self.member_id:
                raise ValidationError({"member": "Walk-in check-in must not reference a member."})
            if not self.visitor_name.strip():
                raise ValidationError({"visitor_name": "Walk-in check-in requires a name."})
            if not self.category:
                raise ValidationError({"category": "Walk-in check-in requires a category."})

        future_limit = timezone.now() + timedelta(hours=1)
        if self.checked_in_at and self.checked_in_at > future_limit:
            raise ValidationError({"checked_in_at": "Check-in time can't be in the future."})

    def save(self, *args, **kwargs):
        self.full_clean()
        return super().save(*args, **kwargs)


# Scheduling (TimeSlot/Booking below) is fully built and tested but off
# by default — gated behind Gym.classes_enabled, which defaults to False.
# Neighbourhood gyms (the primary market) have no scarce slots to
# allocate; boutique studios do, and for them it's a settings toggle,
# not a missing feature. See core/permissions.py: ClassesEnabled, and
# the "Class scheduling" section in the README. Do not read the absence
# of a Schedule tab as this code being unfinished.
class TimeSlot(TenantScopedModel):
    label = models.CharField(max_length=100)
    start_time = models.TimeField()
    end_time = models.TimeField()
    coach_name = models.CharField(max_length=120, blank=True)
    capacity = models.PositiveIntegerField()
    # ISO weekdays this slot runs, comma-separated: Mon=1 ... Sun=7.
    days_of_week = models.CharField(max_length=20)
    is_active = models.BooleanField(default=True)

    class Meta(TenantScopedModel.Meta):
        ordering = ["start_time", "label", "id"]
        constraints = [
            models.UniqueConstraint(fields=["gym", "label"],
                                    name="uniq_slot_label_per_gym"),
        ]

    def __str__(self):
        return f"{self.label} ({self.start_time}-{self.end_time})"

    def days_of_week_set(self):
        return {int(p) for p in self.days_of_week.split(",") if p}

    def clean(self):
        if self.start_time and self.end_time and self.end_time <= self.start_time:
            raise ValidationError({"end_time": "End time must be after start time."})

        if self.capacity is not None and self.capacity < 1:
            raise ValidationError({"capacity": "Capacity must be at least 1."})

        raw = (self.days_of_week or "").strip()
        if not raw:
            raise ValidationError({"days_of_week": "At least one day is required."})
        try:
            days = [int(p.strip()) for p in raw.split(",") if p.strip() != ""]
        except ValueError:
            raise ValidationError(
                {"days_of_week": "Use comma-separated ISO weekday numbers (1-7)."})
        if not days:
            raise ValidationError({"days_of_week": "At least one day is required."})
        if any(d < 1 or d > 7 for d in days):
            raise ValidationError(
                {"days_of_week": "Days must be between 1 (Mon) and 7 (Sun)."})
        if len(set(days)) != len(days):
            raise ValidationError({"days_of_week": "Duplicate days are not allowed."})

    def save(self, *args, **kwargs):
        # Normalise BEFORE full_clean() so clean() parses the clean string,
        # and so "3,1,1" and "1,3" are stored identically.
        if self.days_of_week:
            days = sorted({int(p.strip()) for p in self.days_of_week.split(",")
                          if p.strip() != ""})
            self.days_of_week = ",".join(str(d) for d in days)
        self.full_clean()
        return super().save(*args, **kwargs)


class Booking(TenantScopedModel):
    member = models.ForeignKey(Member, on_delete=models.PROTECT,
                               related_name="bookings")
    time_slot = models.ForeignKey(TimeSlot, on_delete=models.PROTECT,
                                  related_name="bookings")
    date = models.DateField()   # gym-local calendar date
    canceled_at = models.DateTimeField(null=True, blank=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True,
                                   blank=True, on_delete=models.SET_NULL,
                                   related_name="+")

    class Meta(TenantScopedModel.Meta):
        ordering = ["-date", "time_slot__start_time", "id"]
        constraints = [
            models.UniqueConstraint(
                fields=["member", "time_slot", "date"],
                condition=Q(canceled_at__isnull=True),
                name="uniq_active_booking",
            ),
        ]
        indexes = [
            models.Index(fields=["time_slot", "date"]),
            models.Index(fields=["member", "-date"]),
        ]

    def __str__(self):
        return f"{self.member.full_name} — {self.time_slot.label} on {self.date}"

    def clean(self):
        if self.member_id and self.member.gym_id != self.gym_id:
            raise ValidationError({"member": "Member must belong to the same gym."})
        if self.time_slot_id and self.time_slot.gym_id != self.gym_id:
            raise ValidationError({"time_slot": "Time slot must belong to the same gym."})

    def save(self, *args, **kwargs):
        self.full_clean()
        return super().save(*args, **kwargs)

class Announcement(TenantScopedModel):
    title = models.CharField(max_length=200)
    body = models.TextField()
    is_pinned = models.BooleanField(default=False)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True,
                                   blank=True, on_delete=models.SET_NULL,
                                   related_name="+")

    class Meta(TenantScopedModel.Meta):
        ordering = ["-is_pinned", "-created_at", "id"]

    def __str__(self):
        return self.title


class Event(TenantScopedModel):
    title = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    event_date = models.DateField()
    start_time = models.TimeField(null=True, blank=True)
    location_text = models.CharField(max_length=255, blank=True)
    registration_fee = models.DecimalField(max_digits=12, decimal_places=2,
                                           default=0)
    prize_description = models.TextField(blank=True)
    capacity = models.PositiveIntegerField(null=True, blank=True)  # null = no limit
    registration_closes_on = models.DateField(null=True, blank=True)
    canceled_at = models.DateTimeField(null=True, blank=True)

    class Meta(TenantScopedModel.Meta):
        ordering = ["-event_date", "id"]

    def __str__(self):
        return f"{self.title} ({self.event_date})"

    @property
    def effective_registration_deadline(self):
        # Computed, never stored — changing event_date later can't leave
        # a stale registration_closes_on behind it.
        return self.registration_closes_on or self.event_date

    def clean(self):
        if self.capacity is not None and self.capacity < 1:
            raise ValidationError({"capacity": "Capacity must be at least 1."})
        if (self.registration_closes_on and self.event_date
                and self.registration_closes_on > self.event_date):
            raise ValidationError({
                "registration_closes_on":
                    "Registration can't close after the event date."
            })

    def save(self, *args, **kwargs):
        self.full_clean()
        return super().save(*args, **kwargs)


class EventRegistration(TenantScopedModel):
    UNPAID, PAID = "unpaid", "paid"
    PAYMENT_CHOICES = [(UNPAID, "Unpaid"), (PAID, "Paid")]

    event = models.ForeignKey(Event, on_delete=models.PROTECT,
                              related_name="registrations")
    member = models.ForeignKey(Member, on_delete=models.PROTECT,
                               related_name="event_registrations")
    payment_status = models.CharField(max_length=10, choices=PAYMENT_CHOICES,
                                      default=UNPAID)
    amount_due = models.DecimalField(max_digits=12, decimal_places=2)
    paid_at = models.DateTimeField(null=True, blank=True)
    marked_paid_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True,
                                       blank=True, on_delete=models.SET_NULL,
                                       related_name="+")
    canceled_at = models.DateTimeField(null=True, blank=True)

    class Meta(TenantScopedModel.Meta):
        ordering = ["-created_at", "id"]
        constraints = [
            models.UniqueConstraint(
                fields=["event", "member"],
                condition=Q(canceled_at__isnull=True),
                name="uniq_active_event_registration",
            ),
        ]

    def __str__(self):
        return f"{self.member.full_name} — {self.event.title}"

    def clean(self):
        if self.event_id and self.event.gym_id != self.gym_id:
            raise ValidationError({"event": "Event must belong to the same gym."})
        if self.member_id and self.member.gym_id != self.gym_id:
            raise ValidationError({"member": "Member must belong to the same gym."})

    def save(self, *args, **kwargs):
        self.full_clean()
        return super().save(*args, **kwargs)


class EventResult(TenantScopedModel):
    event = models.ForeignKey(Event, on_delete=models.CASCADE,
                              related_name="results")
    member = models.ForeignKey(Member, null=True, blank=True,
                               on_delete=models.SET_NULL, related_name="+")
    display_name = models.CharField(max_length=120)
    rank = models.PositiveIntegerField()
    score_text = models.CharField(max_length=60, blank=True)
    note = models.CharField(max_length=200, blank=True)

    class Meta(TenantScopedModel.Meta):
        ordering = ["rank"]
        constraints = [
            models.UniqueConstraint(fields=["event", "rank"],
                                    name="uniq_result_rank_per_event"),
        ]

    def __str__(self):
        return f"#{self.rank} {self.display_name} — {self.event.title}"

    def clean(self):
        if self.event_id and self.event.gym_id != self.gym_id:
            raise ValidationError({"event": "Event must belong to the same gym."})
        if self.member_id and self.member.gym_id != self.gym_id:
            raise ValidationError({"member": "Member must belong to the same gym."})
        if self.rank is not None and self.rank < 1:
            raise ValidationError({"rank": "Rank must be at least 1."})

    def save(self, *args, **kwargs):
        self.full_clean()
        return super().save(*args, **kwargs)


class Product(TenantScopedModel):
    name = models.CharField(max_length=120)
    category = models.CharField(max_length=50, blank=True)
    price = models.DecimalField(max_digits=12, decimal_places=2)
    stock_quantity = models.IntegerField(default=0)
    low_stock_threshold = models.PositiveIntegerField(default=5)
    is_active = models.BooleanField(default=True)

    class Meta(TenantScopedModel.Meta):
        ordering = ["category", "name", "id"]
        constraints = [
            models.UniqueConstraint(fields=["gym", "name"],
                                    name="uniq_product_name_per_gym"),
        ]

    def __str__(self):
        return self.name


class Sale(TenantScopedModel):
    member = models.ForeignKey(Member, null=True, blank=True,
                               on_delete=models.SET_NULL, related_name="+")
    total_amount = models.DecimalField(max_digits=12, decimal_places=2)
    sold_at = models.DateTimeField()
    sold_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True,
                                on_delete=models.SET_NULL, related_name="+")
    voided_at = models.DateTimeField(null=True, blank=True)
    voided_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True,
                                  on_delete=models.SET_NULL, related_name="+")

    class Meta(TenantScopedModel.Meta):
        ordering = ["-sold_at", "id"]

    def __str__(self):
        return f"Sale {self.id} — {self.total_amount}"

    def clean(self):
        if self.member_id and self.member.gym_id != self.gym_id:
            raise ValidationError({"member": "Member must belong to the same gym."})

    def save(self, *args, **kwargs):
        self.full_clean()
        return super().save(*args, **kwargs)


class SaleItem(TenantScopedModel):
    sale = models.ForeignKey(Sale, on_delete=models.CASCADE, related_name="items")
    product = models.ForeignKey(Product, on_delete=models.PROTECT, related_name="+")
    product_name = models.CharField(max_length=120)
    unit_price = models.DecimalField(max_digits=12, decimal_places=2)
    quantity = models.PositiveIntegerField()
    line_total = models.DecimalField(max_digits=12, decimal_places=2)

    class Meta(TenantScopedModel.Meta):
        ordering = ["id"]

    def __str__(self):
        return f"{self.quantity} x {self.product_name}"

    def clean(self):
        if self.sale_id and self.sale.gym_id != self.gym_id:
            raise ValidationError({"sale": "Sale must belong to the same gym."})
        if self.product_id and self.product.gym_id != self.gym_id:
            raise ValidationError({"product": "Product must belong to the same gym."})

    def save(self, *args, **kwargs):
        self.full_clean()
        return super().save(*args, **kwargs)


class StockAdjustment(TenantScopedModel):
    product = models.ForeignKey(Product, on_delete=models.CASCADE,
                                related_name="adjustments")
    delta = models.IntegerField()          # +10 received, -3 damaged
    reason = models.CharField(max_length=120, blank=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True,
                                   blank=True, on_delete=models.SET_NULL,
                                   related_name="+")

    class Meta(TenantScopedModel.Meta):
        ordering = ["-created_at", "id"]

    def __str__(self):
        return f"{self.product.name} {self.delta:+d}"

    def clean(self):
        if self.product_id and self.product.gym_id != self.gym_id:
            raise ValidationError({"product": "Product must belong to the same gym."})

    def save(self, *args, **kwargs):
        self.full_clean()
        return super().save(*args, **kwargs)

    