from zoneinfo import ZoneInfo
from django.utils import timezone
import secrets


def gym_today(gym):
    return timezone.now().astimezone(ZoneInfo(gym.timezone)).date()


# No O/0 or I/1 — these get read aloud and written down at a counter.
CLAIM_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def generate_claim_code(length=8):
    return "".join(secrets.choice(CLAIM_ALPHABET) for _ in range(length))