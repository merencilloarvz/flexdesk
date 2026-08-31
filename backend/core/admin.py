from django.contrib import admin
from django.utils import timezone

from .models import Gym, Location, Member, Membership, MembershipPlan, StaffProfile, User


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