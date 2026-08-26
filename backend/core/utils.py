from zoneinfo import ZoneInfo
from django.utils import timezone


def gym_today(gym):
    return timezone.now().astimezone(ZoneInfo(gym.timezone)).date()