from django.db import models
from members.models import Member

class CheckIn(models.Model):
    WALK_IN_TYPE_CHOICES = [
        ('student', 'Student'),
        ('regular', 'Regular'),
    ]

    member = models.ForeignKey(Member, on_delete=models.CASCADE, null=True, blank=True)
    walk_in_name = models.CharField(max_length=255, blank=True)
    walk_in_type = models.CharField(max_length=10, choices=WALK_IN_TYPE_CHOICES, blank=True)
    amount_paid = models.DecimalField(max_digits=8, decimal_places=2, null=True, blank=True)
    check_in_time = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.member.full_name if self.member else self.walk_in_name or "Walk-in"