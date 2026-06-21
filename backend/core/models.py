from django.db import models


class AppUser(models.Model):
    ROLE_USER = 'user'
    ROLE_ADMIN = 'admin'

    ROLE_CHOICES = [
        (ROLE_USER, 'User'),
        (ROLE_ADMIN, 'Admin'),
    ]

    name = models.CharField(max_length=100)
    email = models.EmailField(unique=True)
    plan = models.CharField(max_length=20, default='free')
    role = models.CharField(max_length=20, choices=ROLE_CHOICES, default=ROLE_USER)
    password_hash = models.CharField(max_length=255, blank=True)
    google_id = models.CharField(max_length=255, blank=True)
    two_factor_enabled = models.BooleanField(default=False)
    otp_code = models.CharField(max_length=6, blank=True)
    otp_expires_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    company = models.CharField(max_length=100, blank=True, default='')
    utm_source = models.CharField(max_length=100, blank=True, default='')
    utm_medium = models.CharField(max_length=100, blank=True, default='')
    utm_campaign = models.CharField(max_length=100, blank=True, default='')

    def __str__(self):
        return f"{self.name} <{self.email}>"

    class Meta:
        indexes = [
            models.Index(fields=['email'], name='appuser_email_idx'),
            models.Index(fields=['created_at'], name='appuser_created_idx'),
        ]


class AppEvent(models.Model):
    event_name = models.CharField(max_length=100)
    user_email = models.EmailField(blank=True)
    properties = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.event_name} - {self.user_email or 'anonymous'}"

    class Meta:
        indexes = [
            models.Index(fields=['user_email', 'event_name'], name='event_user_name_idx'),
            models.Index(fields=['created_at'], name='event_created_idx'),
        ]


class AirportOrder(models.Model):
    STATUS_PENDING = 'pending'
    STATUS_DONE = 'done'
    STATUS_CANCELLED = 'cancelled'

    STATUS_CHOICES = [
        (STATUS_PENDING, 'Pending'),
        (STATUS_DONE, 'Done'),
        (STATUS_CANCELLED, 'Cancelled'),
    ]

    user = models.ForeignKey(
        AppUser,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name='orders',
    )
    user_email = models.EmailField(blank=True)
    name = models.CharField(max_length=100)
    tariff = models.CharField(max_length=100)
    price = models.IntegerField()
    service_type = models.CharField(max_length=50, default='airport')
    order_title = models.CharField(max_length=255, blank=True)
    details = models.TextField(blank=True)
    order_status = models.CharField(
        max_length=50,
        choices=STATUS_CHOICES,
        default=STATUS_PENDING,
    )
    pickup_location = models.CharField(max_length=255, blank=True)
    flight_number = models.CharField(max_length=50, blank=True)
    arrival_date = models.CharField(max_length=20, blank=True)
    arrival_time = models.CharField(max_length=20, blank=True)
    passengers = models.IntegerField(default=1)
    destination = models.CharField(max_length=255, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.name} - {self.tariff}"

    class Meta:
        indexes = [
            models.Index(fields=['user_email'], name='order_user_email_idx'),
            models.Index(fields=['created_at'], name='order_created_idx'),
            models.Index(fields=['order_status'], name='order_status_idx'),
        ]
import uuid

class Order(models.Model):
    order_id = models.CharField(max_length=100, unique=True)
    user_email = models.EmailField(blank=True, default='')
    amount = models.IntegerField()
    status = models.CharField(max_length=20, default='created')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Order {self.order_id} - {self.user_email} - {self.status}"