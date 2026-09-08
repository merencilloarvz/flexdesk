from django.db import migrations
from django.core.cache import caches


def create_cache_table(apps, schema_editor):
    from django.core.management import call_command
    call_command("createcachetable")


def drop_cache_table(apps, schema_editor):
    with schema_editor.connection.cursor() as cursor:
        cursor.execute("DROP TABLE IF EXISTS flexdesk_cache")


class Migration(migrations.Migration):

    dependencies = [
        ("core", "0016_gym_classes_enabled"),
    ]

    operations = [
        migrations.RunPython(create_cache_table, drop_cache_table),
    ]