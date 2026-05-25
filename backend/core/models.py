from django.db import models


class AppUser(models.Model):
    name = models.CharField(max_length=100)
    email = models.EmailField(unique=True)
    two_factor_enabled = models.BooleanField(default=False)
    otp_code = models.CharField(max_length=6, blank=True)
    otp_expires_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.name} <{self.email}>"


class AppEvent(models.Model):
    event_name = models.CharField(max_length=100)
    user_email = models.EmailField(blank=True)
    properties = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.event_name} - {self.user_email or 'anonymous'}"


class AirportOrder(models.Model):
    name = models.CharField(max_length=100)
    tariff = models.CharField(max_length=100)
    price = models.IntegerField()
    service_type = models.CharField(max_length=50, default='airport')
    order_title = models.CharField(max_length=255, blank=True)
    details = models.TextField(blank=True)
    order_status = models.CharField(max_length=50, default='Confirmed')
    pickup_location = models.CharField(max_length=255, blank=True)
    flight_number = models.CharField(max_length=50, blank=True)
    arrival_date = models.CharField(max_length=20, blank=True)
    arrival_time = models.CharField(max_length=20, blank=True)
    passengers = models.IntegerField(default=1)
    destination = models.CharField(max_length=255, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.name} - {self.tariff}"
