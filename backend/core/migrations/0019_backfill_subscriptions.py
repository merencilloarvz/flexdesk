from django.db import migrations
from django.utils import timezone


def backfill_subscriptions(apps, schema_editor):
    # Gyms that signed up before Stage 10 never went through a trial —
    # they're grandfathered in as already-active subscribers rather than
    # being retroactively dropped into a 14-day countdown they never
    # agreed to. trial_ends_at is set to "now" purely to satisfy the
    # NOT NULL column; status=active means is_blocked never reads it.
    Gym = apps.get_model("core", "Gym")
    Subscription = apps.get_model("core", "Subscription")
    now = timezone.now()
    Subscription.objects.bulk_create([
        Subscription(gym=gym, status="active", trial_ends_at=now)
        for gym in Gym.objects.filter(subscription__isnull=True)
    ])


def noop_reverse(apps, schema_editor):
    pass


class Migration(migrations.Migration):

    dependencies = [
        ('core', '0018_subscription'),
    ]

    operations = [
        migrations.RunPython(backfill_subscriptions, noop_reverse),
    ]
