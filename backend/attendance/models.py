from django.db import models
from members.models import Member

class CheckIn(models.Model):
    member = models.ForeignKey(Member, on_delete=models.CASCADE, null=True, blank=True)
    walk_in_name = models.CharField(max_length=255, blank=True)
    checked_in_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        if self.member:
            return f"{self.member.full_name} - {self.checked_in_at}"
        return f"Walk-in: {self.walk_in_name} - {self.checked_in_at}"