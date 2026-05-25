import json
import random
from datetime import timedelta

from django.http import HttpResponse, JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from .integrations import send_posthog_event
from .models import AppEvent, AppUser, AirportOrder
from .security import mask_payload


def _openapi_spec():
    return {
        'openapi': '3.0.0',
        'info': {
            'title': 'PATHWAY API',
            'version': '1.0.0',
            'description': 'Basic API docs for registration, orders, events, retention, metrics and 2FA.',
        },
        'paths': {
            '/api/register/': {
                'post': {
                    'summary': 'Register user',
                    'requestBody': {
                        'required': True,
                        'content': {
                            'application/json': {
                                'schema': {
                                    'type': 'object',
                                    'properties': {
                                        'name': {'type': 'string'},
                                        'email': {'type': 'string'},
                                    },
                                },
                            },
                        },
                    },
                },
            },
            '/api/orders/': {
                'get': {'summary': 'Get orders'},
                'post': {'summary': 'Create order/service order'},
            },
            '/api/events/': {
                'post': {'summary': 'Track analytics event'},
            },
            '/api/analytics/retention/': {
                'get': {'summary': 'Get D1/D7/D30 retention summary'},
            },
            '/api/metrics/': {
                'get': {'summary': 'Prometheus metrics endpoint'},
            },
            '/api/2fa/request/': {
                'post': {'summary': 'Request OTP'},
            },
            '/api/2fa/verify/': {
                'post': {'summary': 'Verify OTP'},
            },
        },
    }


def openapi_json(request):
    return JsonResponse(_openapi_spec())


def swagger_ui(request):
    html = """
    <html><head><title>Swagger</title></head>
    <body style="font-family: Arial; padding: 24px;">
    <h1>PATHWAY API Docs</h1>
    <p>Swagger-like lightweight docs endpoint.</p>
    <pre id="spec">Loading...</pre>
    <script>
    fetch('/api/openapi.json').then(r => r.json()).then(data => {
      document.getElementById('spec').textContent = JSON.stringify(data, null, 2);
    });
    </script>
    </body></html>
    """
    return HttpResponse(html)


def redoc_ui(request):
    html = """
    <html><head><title>ReDoc</title></head>
    <body style="font-family: Arial; padding: 24px;">
    <h1>PATHWAY API Reference</h1>
    <p>ReDoc-like lightweight docs endpoint.</p>
    <ul>
      <li>POST /api/register/</li>
      <li>GET/POST /api/orders/</li>
      <li>POST /api/events/</li>
      <li>GET /api/analytics/retention/</li>
      <li>GET /api/metrics/</li>
      <li>POST /api/2fa/request/</li>
      <li>POST /api/2fa/verify/</li>
    </ul>
    <p>Full spec: <a href="/api/openapi.json">/api/openapi.json</a></p>
    </body></html>
    """
    return HttpResponse(html)


def metrics(request):
    registrations = AppUser.objects.count()
    orders = AirportOrder.objects.count()
    events = AppEvent.objects.count()
    activations = AppEvent.objects.filter(event_name='activation').count()
    lines = [
        '# HELP pathway_users_total Total registered users',
        '# TYPE pathway_users_total gauge',
        f'pathway_users_total {registrations}',
        '# HELP pathway_orders_total Total orders',
        '# TYPE pathway_orders_total gauge',
        f'pathway_orders_total {orders}',
        '# HELP pathway_events_total Total tracked events',
        '# TYPE pathway_events_total gauge',
        f'pathway_events_total {events}',
        '# HELP pathway_activation_total Total activation events',
        '# TYPE pathway_activation_total gauge',
        f'pathway_activation_total {activations}',
    ]
    return HttpResponse('\n'.join(lines), content_type='text/plain; version=0.0.4')


def retention_summary(request):
    registrations = AppUser.objects.exclude(email='')
    d1 = 0
    d7 = 0
    d30 = 0

    for user in registrations:
        registered_day = user.created_at.date()
        user_events = AppEvent.objects.filter(user_email=user.email, event_name='app_open')
        event_days = {event.created_at.date() for event in user_events}
        if registered_day + timedelta(days=1) in event_days:
            d1 += 1
        if registered_day + timedelta(days=7) in event_days:
            d7 += 1
        if registered_day + timedelta(days=30) in event_days:
            d30 += 1

    total = registrations.count() or 1
    data = {
        'registered_users': registrations.count(),
        'activation_count': AppEvent.objects.filter(event_name='activation').count(),
        'retention': {
            'D1': d1,
            'D7': d7,
            'D30': d30,
            'D1_rate': round(d1 / total, 2),
            'D7_rate': round(d7 / total, 2),
            'D30_rate': round(d30 / total, 2),
        },
    }
    return JsonResponse(data)


@csrf_exempt
def track_event(request):
    if request.method == 'OPTIONS':
        return JsonResponse({'status': 'ok'})

    if request.method != 'POST':
        return JsonResponse({'error': 'Method not allowed'}, status=405)

    body = json.loads(request.body or '{}')
    if not body.get('event_name'):
        return JsonResponse({'error': 'event_name is required'}, status=400)

    event = AppEvent.objects.create(
        event_name=body.get('event_name'),
        user_email=body.get('user_email', ''),
        properties=mask_payload(body.get('properties', {})),
    )
    send_posthog_event(
        event_name=event.event_name,
        distinct_id=event.user_email or 'anonymous',
        properties=event.properties,
    )
    return JsonResponse({'status': 'tracked', 'id': event.id})


@csrf_exempt
def request_2fa(request):
    if request.method == 'OPTIONS':
        return JsonResponse({'status': 'ok'})

    if request.method != 'POST':
        return JsonResponse({'error': 'Method not allowed'}, status=405)

    body = json.loads(request.body or '{}')
    email = body.get('email')
    if not email:
        return JsonResponse({'error': 'email is required'}, status=400)

    user = AppUser.objects.filter(email=email).first()
    if not user:
        return JsonResponse({'error': 'user not found'}, status=404)

    otp_code = f'{random.randint(0, 999999):06d}'
    user.two_factor_enabled = True
    user.otp_code = otp_code
    user.otp_expires_at = timezone.now() + timedelta(minutes=10)
    user.save(update_fields=['two_factor_enabled', 'otp_code', 'otp_expires_at'])

    return JsonResponse({'status': 'otp_sent', 'dev_otp_code': otp_code})


@csrf_exempt
def verify_2fa(request):
    if request.method == 'OPTIONS':
        return JsonResponse({'status': 'ok'})

    if request.method != 'POST':
        return JsonResponse({'error': 'Method not allowed'}, status=405)

    body = json.loads(request.body or '{}')
    email = body.get('email')
    otp_code = body.get('otp_code')
    user = AppUser.objects.filter(email=email).first()
    if not user or not otp_code:
        return JsonResponse({'error': 'email and otp_code are required'}, status=400)

    if user.otp_code != otp_code or not user.otp_expires_at or user.otp_expires_at < timezone.now():
        return JsonResponse({'error': 'invalid or expired otp'}, status=400)

    user.otp_code = ''
    user.save(update_fields=['otp_code'])
    return JsonResponse({'status': 'verified'})

@csrf_exempt
def orders(request):
    if request.method == 'OPTIONS':
        return JsonResponse({'status': 'ok'})

    if request.method == 'GET':
        data = list(AirportOrder.objects.values())
        return JsonResponse(data, safe=False)

    elif request.method == 'POST':
        body = json.loads(request.body or '{}')
        service_type = body.get('service_type', 'airport')

        if not body.get('name'):
            return JsonResponse({'error': 'name is required'}, status=400)

        if service_type == 'airport' and (not body.get('tariff') or body.get('price') is None):
            return JsonResponse({'error': 'name, tariff and price are required'}, status=400)

        order = AirportOrder.objects.create(
            name=body.get('name'),
            tariff=body.get('tariff', ''),
            price=body.get('price', 0),
            service_type=service_type,
            order_title=body.get('order_title', ''),
            details=body.get('details', ''),
            order_status=body.get('order_status', 'Confirmed'),
            pickup_location=body.get('pickup_location', ''),
            flight_number=body.get('flight_number', ''),
            arrival_date=body.get('arrival_date', ''),
            arrival_time=body.get('arrival_time', ''),
            passengers=body.get('passengers', 1),
            destination=body.get('destination', ''),
        )

        return JsonResponse({'status': 'created', 'id': order.id})

    return JsonResponse({'error': 'Method not allowed'}, status=405)


@csrf_exempt
def register(request):
    if request.method == "OPTIONS":
        return JsonResponse({"status": "ok"})

    if request.method == "POST":
        data = json.loads(request.body or '{}')

        if not data.get("name") or not data.get("email"):
            return JsonResponse({"error": "name and email are required"}, status=400)

        user, created = AppUser.objects.get_or_create(
            email=data.get("email"),
            defaults={"name": data.get("name")},
        )

        if not created and user.name != data.get("name"):
            user.name = data.get("name")
            user.save(update_fields=["name"])

        AppEvent.objects.create(
            event_name='registration',
            user_email=user.email,
            properties=mask_payload({'name': data.get('name'), 'email': data.get('email')}),
        )
        send_posthog_event(
            event_name='registration',
            distinct_id=user.email,
            properties=mask_payload({'name': data.get('name'), 'email': data.get('email')}),
        )

        return JsonResponse({"status": "ok", "id": user.id})

    return JsonResponse({"error": "Method not allowed"}, status=405)
