from django.urls import path
from .views import (
    health,
    metrics,
    login,
    openapi_json,
    orders,
    pay_order,
    redoc_ui,
    register,
    request_2fa,
    retention_summary,
    swagger_ui,
    track_event,
    verify_2fa,
)

urlpatterns = [
    path('health/', health),
    path('orders/', orders),
    path('orders/<int:order_id>/pay/', pay_order),
    path('register/', register),
    path('login/', login),
    path('events/', track_event),
    path('analytics/retention/', retention_summary),
    path('metrics/', metrics),
    path('openapi.json', openapi_json),
    path('docs/swagger/', swagger_ui),
    path('docs/redoc/', redoc_ui),
    path('2fa/request/', request_2fa),
    path('2fa/verify/', verify_2fa),
]
