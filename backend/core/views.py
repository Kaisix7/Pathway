import json
import logging
import random
from datetime import timedelta

from django.db import connection
from django.conf import settings
from django.http import HttpResponse, JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from .cache import cache_delete, cache_get, cache_set, cache_status
from .integrations import send_posthog_event
from .models import AppEvent, AppUser, AirportOrder
from .security import mask_payload
from .tasks import send_welcome_event


logger = logging.getLogger(__name__)

RATE_LIMITS = {
    'login': {'limit': 5, 'window': 60},
    'register': {'limit': 3, 'window': 3600},
}


def _client_ip(request):
    forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
    if forwarded_for:
        return forwarded_for.split(',')[0].strip()
    return request.META.get('REMOTE_ADDR', 'unknown')


def _is_rate_limited(request, action):
    config = RATE_LIMITS[action]
    key = f'rate:{action}:{_client_ip(request)}'
    attempts = cache_get(key) or 0
    if attempts >= config['limit']:
        return True
    cache_set(key, attempts + 1, ttl=config['window'])
    return False


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
            '/api/login/': {
                'post': {'summary': 'Passwordless login by email'},
            },
            '/api/orders/': {
                'get': {'summary': 'Get orders'},
                'post': {'summary': 'Create order/service order'},
            },
            '/api/orders/{id}/pay/': {
                'post': {'summary': 'Mark order as paid/done'},
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
            '/health/': {
                'get': {'summary': 'Health check with database and cache status'},
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
      <li>POST /api/login/</li>
      <li>GET/POST /api/orders/</li>
      <li>POST /api/orders/&lt;id&gt;/pay/</li>
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
    cached = cache_get('metrics:v1')
    if cached is not None:
        response = HttpResponse(cached, content_type='text/plain; version=0.0.4')
        response['X-Cache'] = 'HIT'
        return response

    registrations = AppUser.objects.count()
    orders = AirportOrder.objects.count()
    events = AppEvent.objects.count()
    activations = AppEvent.objects.filter(event_name='activation').count()
    paid_orders = AirportOrder.objects.filter(order_status=AirportOrder.STATUS_DONE).count()
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
        '# HELP pathway_paid_orders_total Total paid/done orders',
        '# TYPE pathway_paid_orders_total gauge',
        f'pathway_paid_orders_total {paid_orders}',
    ]
    payload = '\n'.join(lines)
    cache_set('metrics:v1', payload, ttl=60)
    response = HttpResponse(payload, content_type='text/plain; version=0.0.4')
    response['X-Cache'] = 'MISS'
    return response


def _order_payload(order):
    return {
        'id': order.id,
        'user_id': order.user_id,
        'user_email': order.user_email,
        'name': order.name,
        'tariff': order.tariff,
        'price': order.price,
        'service_type': order.service_type,
        'order_title': order.order_title,
        'details': order.details,
        'order_status': order.order_status,
        'pickup_location': order.pickup_location,
        'flight_number': order.flight_number,
        'arrival_date': order.arrival_date,
        'arrival_time': order.arrival_time,
        'passengers': order.passengers,
        'destination': order.destination,
        'created_at': order.created_at.isoformat(),
    }


def retention_summary(request):
    cached = cache_get('analytics:retention:v1')
    if cached is not None:
        response = JsonResponse(cached)
        response['X-Cache'] = 'HIT'
        return response

    registrations = list(AppUser.objects.exclude(email=''))
    d1 = 0
    d7 = 0
    d30 = 0
    emails = [user.email for user in registrations]
    events_by_email = {email: set() for email in emails}

    app_open_events = AppEvent.objects.filter(user_email__in=emails, event_name='app_open')
    for event in app_open_events:
        events_by_email.setdefault(event.user_email, set()).add(event.created_at.date())

    for user in registrations:
        registered_day = user.created_at.date()
        event_days = events_by_email.get(user.email, set())
        if registered_day + timedelta(days=1) in event_days:
            d1 += 1
        if registered_day + timedelta(days=7) in event_days:
            d7 += 1
        if registered_day + timedelta(days=30) in event_days:
            d30 += 1

    total = len(registrations) or 1
    data = {
        'registered_users': len(registrations),
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
    cache_set('analytics:retention:v1', data, ttl=120)
    response = JsonResponse(data)
    response['X-Cache'] = 'MISS'
    return response


def health(request):
    database_status = 'ok'
    try:
        with connection.cursor() as cursor:
            cursor.execute('SELECT 1')
            cursor.fetchone()
    except Exception:
        database_status = 'error'

    cache_state = cache_status()
    status_code = 200 if database_status == 'ok' and cache_state in {'ok', 'memory-fallback'} else 503

    return JsonResponse(
        {
            'status': 'ok' if status_code == 200 else 'error',
            'database': database_status,
            'cache': cache_state,
            'version': 'week2-reliability',
        },
        status=status_code,
    )


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
        user_email = request.GET.get('user_email', '').strip()
        cache_key = f'orders:v1:{user_email or "all"}'
        cached = cache_get(cache_key)
        if cached is not None:
            response = JsonResponse(cached, safe=False)
            response['X-Cache'] = 'HIT'
            return response

        queryset = AirportOrder.objects.select_related('user').order_by('-created_at')
        if user_email:
            queryset = queryset.filter(user_email=user_email)
        data = [_order_payload(order) for order in queryset]
        cache_set(cache_key, data, ttl=90)
        response = JsonResponse(data, safe=False)
        response['X-Cache'] = 'MISS'
        return response

    elif request.method == 'POST':
        body = json.loads(request.body or '{}')
        service_type = body.get('service_type', 'airport')

        if not body.get('name'):
            return JsonResponse({'error': 'name is required'}, status=400)

        if service_type == 'airport' and (not body.get('tariff') or body.get('price') is None):
            return JsonResponse({'error': 'name, tariff and price are required'}, status=400)

        user_email = body.get('user_email', '').strip()
        user = AppUser.objects.filter(email=user_email).first() if user_email else None

        order = AirportOrder.objects.create(
            user=user,
            user_email=user_email,
            name=body.get('name'),
            tariff=body.get('tariff', ''),
            price=body.get('price', 0),
            service_type=service_type,
            order_title=body.get('order_title', ''),
            details=body.get('details', ''),
            order_status=body.get('order_status', AirportOrder.STATUS_PENDING),
            pickup_location=body.get('pickup_location', ''),
            flight_number=body.get('flight_number', ''),
            arrival_date=body.get('arrival_date', ''),
            arrival_time=body.get('arrival_time', ''),
            passengers=body.get('passengers', 1),
            destination=body.get('destination', ''),
        )

        AppEvent.objects.create(
            event_name='order_created',
            user_email=order.user_email,
            properties=mask_payload({'order_id': order.id, 'service_type': order.service_type}),
        )
        cache_delete('orders:v1:all')
        if order.user_email:
            cache_delete(f'orders:v1:{order.user_email}')
        cache_delete('metrics:v1')

        return JsonResponse({'status': 'created', 'id': order.id, 'order': _order_payload(order)})

    return JsonResponse({'error': 'Method not allowed'}, status=405)


@csrf_exempt
def pay_order(request, order_id):
    if request.method == 'OPTIONS':
        return JsonResponse({'status': 'ok'})

    if request.method != 'POST':
        return JsonResponse({'error': 'Method not allowed'}, status=405)

    order = AirportOrder.objects.filter(id=order_id).first()
    if not order:
        return JsonResponse({'error': 'order not found'}, status=404)

    order.order_status = AirportOrder.STATUS_DONE
    order.save(update_fields=['order_status'])

    AppEvent.objects.create(
        event_name='order_paid',
        user_email=order.user_email,
        properties=mask_payload({'order_id': order.id, 'amount': order.price}),
    )
    cache_delete('orders:v1:all')
    if order.user_email:
        cache_delete(f'orders:v1:{order.user_email}')
    cache_delete('metrics:v1')

    return JsonResponse({'status': 'done', 'order': _order_payload(order)})


@csrf_exempt
def login(request):
    if request.method == "OPTIONS":
        return JsonResponse({"status": "ok"})

    if request.method != "POST":
        return JsonResponse({"error": "Method not allowed"}, status=405)

    data = json.loads(request.body or '{}')
    email = data.get('email', '').strip()
    if not email:
        return JsonResponse({'error': 'email is required'}, status=400)

    if _is_rate_limited(request, 'login'):
        return JsonResponse({'error': 'rate limit exceeded'}, status=429)

    user = AppUser.objects.filter(email=email).first()
    if not user:
        return JsonResponse({'error': 'user not found'}, status=404)

    AppEvent.objects.create(
        event_name='login',
        user_email=user.email,
        properties={},
    )

    return JsonResponse({
        'status': 'ok',
        'user': {
            'id': user.id,
            'name': user.name,
            'email': user.email,
            'plan': user.plan,
        },
    })


@csrf_exempt
def register(request):
    if request.method == "OPTIONS":
        return JsonResponse({"status": "ok"})

    if request.method == "POST":
        data = json.loads(request.body or '{}')

        if not data.get("name") or not data.get("email"):
            return JsonResponse({"error": "name and email are required"}, status=400)

        if _is_rate_limited(request, 'register'):
            return JsonResponse({'error': 'rate limit exceeded'}, status=429)

        user, created = AppUser.objects.get_or_create(
            email=data.get("email"),
            defaults={"name": data.get("name"), "plan": data.get("plan", "free")},
        )

        if not created and (user.name != data.get("name") or user.plan != data.get("plan", user.plan)):
            user.name = data.get("name")
            user.plan = data.get("plan", user.plan)
            user.save(update_fields=["name", "plan"])

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
        cache_delete('metrics:v1')
        try:
            if getattr(settings, 'CELERY_TASK_ALWAYS_EAGER', False):
                send_welcome_event.apply(args=[user.email, user.name])
            else:
                send_welcome_event.delay(user.email, user.name)
        except Exception as exc:
            logger.warning('celery_welcome_task_failed email=%s error=%s', user.email, exc)

        return JsonResponse({
            "status": "ok",
            "id": user.id,
            "user": {
                "id": user.id,
                "name": user.name,
                "email": user.email,
                "plan": user.plan,
            },
        })

    return JsonResponse({"error": "Method not allowed"}, status=405)
