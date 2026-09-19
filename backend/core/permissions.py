from rest_framework.exceptions import APIException
from rest_framework.permissions import SAFE_METHODS, BasePermission


class SubscriptionRequired(APIException):
    """
    Raised (not just a 403) so a blocked owner's app can tell "you're
    blocked, go subscribe" apart from every other permission failure.
    """
    status_code = 402
    default_detail = "Your gym's subscription has expired. Please subscribe to continue."
    default_code = "subscription_required"


class SubscriptionActive(BasePermission):
    """
    Blocks a WRITE on an owner/staff endpoint once the trial or paid
    period has expired with no manual payment recorded. Reads are never
    blocked here — the agreed design is read-only-with-export, never a
    full lockout: a lapsed gym must still be able to read its own
    members, run a report, or export its data. The client already
    handles the rest on its own (subscription_blocked comes down on
    every /auth/me/, which is what drives the banner and disables write
    actions in the UI), so this only has to hold the write boundary
    server-side.

    A member request is ALWAYS let through here, regardless of which
    view it hit — this is what lets it sit on shared viewsets like
    AnnouncementViewSet (IsGymUser + IsGymStaffOrReadOnly, read by
    members, written by staff) without also blocking the member's read.
    That's the actual boundary from the spec: block the owner's tools,
    never the gym's existence to its members.

    Deliberately its own permission class rather than folded into
    IsGymStaff: the subscription endpoints themselves (status read,
    checkout) are also IsGymStaff-gated and must keep working while
    blocked — that's the only way an owner gets unblocked.
    """

    def has_permission(self, request, view):
        user = request.user
        if getattr(user, "member_profile", None) is not None:
            return True
        if request.method in SAFE_METHODS:
            return True
        gym = getattr(user, "gym", None)
        subscription = getattr(gym, "subscription", None) if gym else None
        if subscription is not None and subscription.is_blocked:
            raise SubscriptionRequired()
        return True


class IsGymStaff(BasePermission):
    message = "This account is not linked to a gym."

    def has_permission(self, request, view):
        user = request.user
        return bool(
            user
            and user.is_authenticated
            and getattr(user, "staff_profile", None) is not None
        )


class IsGymMember(BasePermission):
    message = "This account is not a gym member account."

    def has_permission(self, request, view):
        user = request.user
        return bool(
            user
            and user.is_authenticated
            and getattr(user, "member_profile", None) is not None
        )


class IsOwner(BasePermission):
    message = "Only the gym owner can do this."

    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and user.is_owner)


class IsOwnerOrReadOnly(BasePermission):
    message = "Only the gym owner can change this."

    def has_permission(self, request, view):
        user = request.user
        if not (user and user.is_authenticated):
            return False
        if request.method in SAFE_METHODS:
            return True
        return bool(user.is_owner)

class IsGymUser(BasePermission):
    """Anyone attached to a gym — staff or member."""
    message = "This account is not attached to a gym."

    def has_permission(self, request, view):
        user = request.user
        return bool(
            user
            and user.is_authenticated
            and (getattr(user, "staff_profile", None) is not None
                 or getattr(user, "member_profile", None) is not None)
        )


class IsGymStaffOrReadOnly(BasePermission):
    """Reads for any gym user; writes require a staff profile."""
    message = "Only gym staff can change this."

    def has_permission(self, request, view):
        user = request.user
        if not (user and user.is_authenticated):
            return False
        if request.method in SAFE_METHODS:
            return True
        return getattr(user, "staff_profile", None) is not None


class ClassesEnabled(BasePermission):
    """
    Scheduling is off for most gyms. Hiding the UI isn't enough — the
    endpoints have to refuse too, or a member with a URL can book against
    a gym that doesn't run classes.
    """
    message = "This gym does not use class bookings."

    def has_permission(self, request, view):
        gym = getattr(request.user, "gym", None)
        return bool(gym and gym.classes_enabled)

class CanEngage(IsGymUser):
    """
    Like / comment endpoints. Any gym user may read; writing additionally
    excludes an archived member — same rule as booking and event
    registration (a member removed from the gym shouldn't be posting
    under its name), but enforced here as a permission so it's a 403
    before any lookup happens.
    """
    message = "Your membership record is no longer active at this gym."

    def has_permission(self, request, view):
        if not super().has_permission(request, view):
            return False
        if request.method in SAFE_METHODS:
            return True
        member = getattr(request.user, "member_profile", None)
        return member is None or member.archived_at is None
