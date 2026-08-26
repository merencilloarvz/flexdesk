from rest_framework.permissions import SAFE_METHODS, BasePermission


class IsGymStaff(BasePermission):
    message = "This account is not linked to a gym."

    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and user.gym is not None)


class IsOwner(BasePermission):
    message = "Only the gym owner can do this."

    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and user.is_owner)


class IsOwnerOrReadOnly(BasePermission):
    message = "Only the gym owner can change this."

    def has_permission(self, request, view):
        if request.method in SAFE_METHODS:
            return True
        return bool(request.user and request.user.is_owner)