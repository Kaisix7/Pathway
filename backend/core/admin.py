from django.contrib import admin
from .models import AppEvent, AppUser, AirportOrder


@admin.register(AppUser)
class AppUserAdmin(admin.ModelAdmin):
    list_display = ('email', 'name', 'role', 'plan', 'created_at')
    search_fields = ('email', 'name')
    list_filter = ('role', 'plan')


@admin.register(AppEvent)
class AppEventAdmin(admin.ModelAdmin):
    list_display = ('event_name', 'user_email', 'created_at')
    search_fields = ('event_name', 'user_email')


@admin.register(AirportOrder)
class AirportOrderAdmin(admin.ModelAdmin):
    list_display = ('id', 'user_email', 'name', 'order_status', 'created_at')
    search_fields = ('user_email', 'name', 'order_title')
    list_filter = ('order_status', 'service_type')
