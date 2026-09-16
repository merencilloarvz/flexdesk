from dateutil.relativedelta import relativedelta
from django.contrib import admin
from django.utils import timezone

from .models import (Gym, Location, Member, Membership, MembershipPlan,
                     StaffProfile, Subscription, User)


@admin.register(Gym)
class GymAdmin(admin.ModelAdmin):
    list_display = ["name", "slug", "timezone", "currency"]
    search_fields = ["name", "slug"]


@admin.register(Location)
class LocationAdmin(admin.ModelAdmin):
    list_display = ["name", "gym", "is_active"]
    list_filter = ["gym", "is_active"]


@admin.register(MembershipPlan)
class MembershipPlanAdmin(admin.ModelAdmin):
    list_display = [
        "name", "category", "gym", "price",
        "duration_value", "duration_unit", "is_active",
    ]
    list_filter = ["gym", "is_active"]


@admin.action(description="Archive selected members")
def archive_members(modeladmin, request, queryset):
    queryset.update(archived_at=timezone.now(), archived_by=request.user)


@admin.register(Member)
class MemberAdmin(admin.ModelAdmin):
    list_display = ["full_name", "gym", "member_type", "archived_at", "created_at"]
    list_filter = ["gym", "member_type"]
    search_fields = ["first_name", "last_name", "email", "phone"]
    actions = [archive_members]


@admin.register(Membership)
class MembershipAdmin(admin.ModelAdmin):
    # end_date is editable here — set one to today's date to see the
    # "Expires today" label render on the members list screen.
    list_display = ["member", "plan_name", "start_date", "end_date", "gym"]
    list_filter = ["gym"]
    search_fields = ["member__first_name", "member__last_name"]


@admin.register(StaffProfile)
class StaffProfileAdmin(admin.ModelAdmin):
    list_display = ["user", "gym", "role"]
    list_filter = ["gym", "role"]


@admin.register(User)
class UserAdmin(admin.ModelAdmin):
    list_display = ["email", "full_name", "is_active", "is_staff"]
    search_fields = ["email", "full_name"]


class ExpiringWithinFilter(admin.SimpleListFilter):
    title = "expiring soon"
    parameter_name = "expiring_soon"

    def lookups(self, request, model_admin):
        return [("yes", f"Within {Subscription.EXPIRING_SOON_DAYS} days")]

    def queryset(self, request, queryset):
        if self.value() != "yes":
            return queryset
        matching_ids = [
            sub.pk for sub in queryset
            if sub.days_remaining is not None and sub.days_remaining <= Subscription.EXPIRING_SOON_DAYS
        ]
        return queryset.filter(pk__in=matching_ids)


def _extend(modeladmin, request, queryset, delta):
    now = timezone.now()
    updated = 0
    for sub in queryset:
        base = sub.current_period_end if sub.current_period_end and sub.current_period_end > now else now
        sub.current_period_end = base + delta
        sub.status = Subscription.ACTIVE
        sub.save(update_fields=["status", "current_period_end", "updated_at"])
        updated += 1
    modeladmin.message_user(request, f"Extended {updated} subscription(s).")


@admin.action(description="Extend 1 month")
def extend_one_month(modeladmin, request, queryset):
    _extend(modeladmin, request, queryset, relativedelta(months=1))


@admin.action(description="Extend 1 year")
def extend_one_year(modeladmin, request, queryset):
    _extend(modeladmin, request, queryset, relativedelta(years=1))


@admin.register(Subscription)
class SubscriptionAdmin(admin.ModelAdmin):
    list_display = [
        "gym", "status", "billing_state", "days_remaining",
        "trial_ends_at", "current_period_end",
    ]
    list_filter = ["status", ExpiringWithinFilter]
    search_fields = ["gym__name"]
    actions = [extend_one_month, extend_one_year]

    @admin.display(description="Billing state")
    def billing_state(self, obj):
        return obj.billing_state

    @admin.display(description="Days remaining")
    def days_remaining(self, obj):
        return obj.days_remaining