from django.contrib import admin
from .models import AppEvent, AppUser, AirportOrder

admin.site.register(AppUser)
admin.site.register(AppEvent)
admin.site.register(AirportOrder)
