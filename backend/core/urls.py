from django.urls import path
from .views import (
    metrics,
    openapi_json,
    orders,
    redoc_ui,
    register,
    request_2fa,
    retention_summary,
    swagger_ui,
    track_event,
    verify_2fa,
)

urlpatterns = [
    path('orders/', orders),
    path('register/', register),
    path('events/', track_event),
    path('analytics/retention/', retention_summary),
    path('metrics/', metrics),
    path('openapi.json', openapi_json),
    path('docs/swagger/', swagger_ui),
    path('docs/redoc/', redoc_ui),
    path('2fa/request/', request_2fa),
    path('2fa/verify/', verify_2fa),
]
