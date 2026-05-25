from django.urls import path
from .views import (
    metrics,
<<<<<<< HEAD
    openapi_json,
    orders,
=======
    login,
    openapi_json,
    orders,
    pay_order,
>>>>>>> ada3666a7ae7021d50248364e83e0eda6abf2950
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
<<<<<<< HEAD
    path('register/', register),
=======
    path('orders/<int:order_id>/pay/', pay_order),
    path('register/', register),
    path('login/', login),
>>>>>>> ada3666a7ae7021d50248364e83e0eda6abf2950
    path('events/', track_event),
    path('analytics/retention/', retention_summary),
    path('metrics/', metrics),
    path('openapi.json', openapi_json),
    path('docs/swagger/', swagger_ui),
    path('docs/redoc/', redoc_ui),
    path('2fa/request/', request_2fa),
    path('2fa/verify/', verify_2fa),
]
