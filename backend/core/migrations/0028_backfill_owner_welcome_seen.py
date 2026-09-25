from django.db import migrations


def mark_existing_owners_as_seen(apps, schema_editor):
    """
    0027 added has_seen_owner_welcome with default False, which would send
    every pre-existing owner through the post-signup welcome flow on their
    next login. Anyone who already has a gym (an owner StaffProfile) has
    been through signup, so mark them as having seen it.

    Rule is data-based, not date-based, so it behaves the same on every
    database. New signups after this migration are unaffected: their flag
    starts False and their gym is created in the same request, so they
    aren't matched here (this only runs once, at migrate time).
    """
    User = apps.get_model("core", "User")
    User.objects.filter(
        staff_profile__role="owner", has_seen_owner_welcome=False
    ).update(has_seen_owner_welcome=True)


class Migration(migrations.Migration):

    dependencies = [
        ("core", "0027_user_has_seen_owner_welcome"),
    ]

    operations = [
        # Nothing to undo: once seen, we can't know who was really new.
        migrations.RunPython(mark_existing_owners_as_seen, migrations.RunPython.noop),
    ]
