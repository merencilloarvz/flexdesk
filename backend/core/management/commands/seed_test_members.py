import random

from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone

from core.models import Gym, Location, Member, Membership, MembershipPlan, StaffProfile


FIRST_NAMES = [
    "Juan", "Maria", "Jose", "Ana", "Pedro", "Rosa", "Carlos", "Elena",
    "Miguel", "Sofia", "Luis", "Carmen", "Antonio", "Isabel", "Ricardo",
]
LAST_NAMES = [
    "Dela Cruz", "Santos", "Reyes", "Garcia", "Ramos", "Torres", "Flores",
    "Mendoza", "Castillo", "Villanueva", "Aquino", "Bautista", "Cruz",
]


class Command(BaseCommand):
    help = (
        "Seeds N test members (each with an active membership) for a gym. "
        "Built for the 3.6 pagination check — needs 60+ to catch the "
        "silent-truncation bug at PAGE_SIZE=50."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--gym-slug", required=True, help="Gym.slug to seed members into"
        )
        parser.add_argument("--count", type=int, default=60)
        # Member.member_type choices are MEMBER / PROSPECT (core/models.py).
        parser.add_argument("--member-type", default="MEMBER")

    def handle(self, *args, **options):
        try:
            gym = Gym.objects.get(slug=options["gym_slug"])
        except Gym.DoesNotExist:
            raise CommandError(f"No gym with slug '{options['gym_slug']}'")

        location = Location.objects.filter(gym=gym).first()
        if not location:
            raise CommandError(f"Gym '{gym.name}' has no Location")

        plan = (
            MembershipPlan.objects.filter(gym=gym, is_active=True, price__gt=0)
            .first()
        )
        if not plan:
            self.stdout.write(self.style.WARNING(
                "No priced, active plan found for this gym — members will be "
                "created without a membership (no current_end_date)."
            ))

        owner_profile = StaffProfile.objects.filter(
            gym=gym, role=StaffProfile.OWNER
        ).first()
        created_by = owner_profile.user if owner_profile else None

        count = options["count"]
        member_type = options["member_type"]
        created = 0

        for i in range(count):
            first = random.choice(FIRST_NAMES)
            last = random.choice(LAST_NAMES)
            member = Member.objects.create(
                gym=gym,
                home_location=location,
                first_name=first,
                # Numbered so they're easy to eyeball/count in the list.
                last_name=f"{last} {i + 1}",
                member_type=member_type,
                phone=f"09{random.randint(100000000, 999999999)}",
                email=f"testmember{i + 1}.{gym.slug}@example.com",
            )
            if plan:
                Membership.objects.create(
                    gym=gym,
                    member=member,
                    plan=plan,
                    start_date=timezone.now().date(),
                    created_by=created_by,
                )
            created += 1

        self.stdout.write(self.style.SUCCESS(
            f"Created {created} test members for '{gym.name}' ({gym.slug})."
        ))