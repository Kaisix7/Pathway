from django.db import models


class AppUser(models.Model):
    name = models.CharField(max_length=100)
    email = models.EmailField(unique=True)
<<<<<<< HEAD
=======
    plan = models.CharField(max_length=20, default='free')
>>>>>>> ada3666a7ae7021d50248364e83e0eda6abf2950
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
<<<<<<< HEAD
=======
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
>>>>>>> ada3666a7ae7021d50248364e83e0eda6abf2950
    name = models.CharField(max_length=100)
    tariff = models.CharField(max_length=100)
    price = models.IntegerField()
    service_type = models.CharField(max_length=50, default='airport')
    order_title = models.CharField(max_length=255, blank=True)
    details = models.TextField(blank=True)
<<<<<<< HEAD
    order_status = models.CharField(max_length=50, default='Confirmed')
=======
    order_status = models.CharField(
        max_length=50,
        choices=STATUS_CHOICES,
        default=STATUS_PENDING,
    )
>>>>>>> ada3666a7ae7021d50248364e83e0eda6abf2950
    pickup_location = models.CharField(max_length=255, blank=True)
    flight_number = models.CharField(max_length=50, blank=True)
    arrival_date = models.CharField(max_length=20, blank=True)
    arrival_time = models.CharField(max_length=20, blank=True)
    passengers = models.IntegerField(default=1)
    destination = models.CharField(max_length=255, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.name} - {self.tariff}"
