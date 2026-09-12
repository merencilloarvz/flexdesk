from rest_framework import viewsets
from .permissions import IsGymStaff, SubscriptionActive
from .utils import gym_today


class GymScopedViewSet(viewsets.ModelViewSet):
    permission_classes = [IsGymStaff]

    def get_permissions(self):
        # Appended here rather than baked into permission_classes so it
        # still applies no matter what a subclass (or an @action's own
        # permission_classes=[...]) overrides that list to. Safe even for
        # viewsets members also read from (Announcement/Event) — see
        # SubscriptionActive's own docstring for why a member request
        # always passes regardless.
        return [p() for p in self.permission_classes] + [SubscriptionActive()]

    @property
    def gym(self):
        return self.request.user.gym

    @property
    def today(self):
        return gym_today(self.gym)

    def get_queryset(self):
        return super().get_queryset().filter(gym=self.gym)

    def perform_create(self, serializer):
        serializer.save(gym=self.gym)

    def get_serializer_context(self):
        ctx = super().get_serializer_context()
        ctx["gym"] = self.gym
        ctx["today"] = self.today
        return ctx