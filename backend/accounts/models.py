from django.db import models
from django.contrib.auth.models import User

class Owner(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE)
    gym_name = models.CharField(max_length=255)
    phone_number = models.CharField(max_length=20, blank=True)
    student_rate = models.DecimalField(max_digits=8, decimal_places=2, default=0)
    regular_rate = models.DecimalField(max_digits=8, decimal_places=2, default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.gym_name