from rest_framework import viewsets
from .permissions import IsGymStaff
from .utils import gym_today


class GymScopedViewSet(viewsets.ModelViewSet):
    permission_classes = [IsGymStaff]

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