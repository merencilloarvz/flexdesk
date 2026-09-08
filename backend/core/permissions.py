from rest_framework.permissions import SAFE_METHODS, BasePermission


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