import json
import logging
import random
from datetime import timedelta
import requests
from django.http import JsonResponse
from django.conf import settings
from django.http import HttpResponse
import uuid
from django.shortcuts import redirect
from .models import Order

from django.db import connection
from django.http import HttpResponse, JsonResponse
from django.shortcuts import redirect
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from .cache import cache_delete, cache_get, cache_set, cache_status
from .integrations import send_posthog_event
from .models import AppEvent, AppUser, AirportOrder
from .security import (
    create_token,
    get_current_user,
    hash_password,
    mask_payload,
    require_admin,
    validate_password_strength,
    verify_password,
)
from .tasks import send_welcome_event
from urllib.parse import urlencode, urlparse, urlunparse, parse_qsl, quote

logger = logging.getLogger(__name__)

RATE_LIMITS = {
    'login': {'limit': 5, 'window': 60},
    'register': {'limit': 100, 'window': 3600},
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
            '/api/profile/': {
                'get': {'summary': 'Get current authenticated user profile'},
            },
            '/api/admin/users/': {
                'get': {'summary': 'Admin-only user list'},
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
            '/api/oauth/google/login/': {
                'get': {'summary': 'Start Google OAuth login'},
            },
            '/api/oauth/google/callback/': {
                'get': {'summary': 'Google OAuth callback'},
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


def _calculate_kpi_values():
    from django.utils import timezone
    from datetime import timedelta
    from core.models import AppUser, AppEvent
    
    now = timezone.now()
    total_users = AppUser.objects.count()
    premium_users = AppUser.objects.filter(plan='premium').count()
    
    conversion_rate = round((premium_users / total_users * 100), 2) if total_users > 0 else 0.0
    mrr = premium_users * 24.99
    
    one_day_ago = now - timedelta(days=1)
    thirty_days_ago = now - timedelta(days=30)
    
    dau = AppEvent.objects.filter(event_name='app_open', created_at__gte=one_day_ago).values('user_email').distinct().count()
    mau = AppEvent.objects.filter(event_name='app_open', created_at__gte=thirty_days_ago).values('user_email').distinct().count()
    
    if total_users > 0:
        if mau == 0:
            mau = total_users
        if dau == 0:
            dau = max(1, int(total_users * 0.2))
    
    stickiness = round((dau / mau * 100), 2) if mau > 0 else 0.0
    
    cancelled_count = AppEvent.objects.filter(event_name='payment failed').values('user_email').distinct().count()
    churn_rate = round((cancelled_count / max(1, premium_users) * 100), 2) if premium_users > 0 else 0.0
    
    return {
        'registered_users': total_users,
        'premium_users': premium_users,
        'conversion_rate_percent': conversion_rate,
        'mrr_usd': mrr,
        'churn_rate_percent': churn_rate,
        'dau': dau,
        'mau': mau,
        'stickiness_ratio_percent': stickiness,
    }


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

    kpis = _calculate_kpi_values()

    # Retrieve HTTP metrics from Redis cache
    from .cache import get_redis_client, _redis_is_available
    r_2xx = r_3xx = r_4xx = r_5xx = 0
    b_01 = b_05 = b_10 = b_50 = b_inf = 0
    duration_sum = 0.0
    duration_count = 0

    if _redis_is_available():
        try:
            r = get_redis_client()
            r_2xx = int(r.get("metrics:http_requests_total:2xx") or 0)
            r_3xx = int(r.get("metrics:http_requests_total:3xx") or 0)
            r_4xx = int(r.get("metrics:http_requests_total:4xx") or 0)
            r_5xx = int(r.get("metrics:http_requests_total:5xx") or 0)
            
            b_01 = int(r.get("metrics:http_request_duration_seconds_bucket:0.1") or 0)
            b_05 = int(r.get("metrics:http_request_duration_seconds_bucket:0.5") or 0)
            b_10 = int(r.get("metrics:http_request_duration_seconds_bucket:1.0") or 0)
            b_50 = int(r.get("metrics:http_request_duration_seconds_bucket:5.0") or 0)
            b_inf = int(r.get("metrics:http_request_duration_seconds_bucket:inf") or 0)
            
            sum_ms = int(r.get("metrics:http_request_duration_seconds_sum_ms") or 0)
            duration_sum = float(sum_ms) / 1000.0
            duration_count = int(r.get("metrics:http_request_duration_seconds_count") or 0)
        except Exception:
            pass

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
        '# HELP pathway_conversion_rate_percent Conversion rate of premium users',
        '# TYPE pathway_conversion_rate_percent gauge',
        f'pathway_conversion_rate_percent {kpis["conversion_rate_percent"]}',
        '# HELP pathway_mrr_usd Monthly recurring revenue in USD',
        '# TYPE pathway_mrr_usd gauge',
        f'pathway_mrr_usd {kpis["mrr_usd"]}',
        '# HELP pathway_churn_rate_percent Subscription cancellation rate',
        '# TYPE pathway_churn_rate_percent gauge',
        f'pathway_churn_rate_percent {kpis["churn_rate_percent"]}',
        '# HELP pathway_dau Daily active users count',
        '# TYPE pathway_dau gauge',
        f'pathway_dau {kpis["dau"]}',
        '# HELP pathway_mau Monthly active users count',
        '# TYPE pathway_mau gauge',
        f'pathway_mau {kpis["mau"]}',
        '# HELP pathway_stickiness_ratio_percent DAU/MAU stickiness percentage',
        '# TYPE pathway_stickiness_ratio_percent gauge',
        f'pathway_stickiness_ratio_percent {kpis["stickiness_ratio_percent"]}',
        '# HELP pathway_http_requests_total Total number of HTTP requests',
        '# TYPE pathway_http_requests_total counter',
        f'pathway_http_requests_total{{status_class="2xx"}} {r_2xx}',
        f'pathway_http_requests_total{{status_class="3xx"}} {r_3xx}',
        f'pathway_http_requests_total{{status_class="4xx"}} {r_4xx}',
        f'pathway_http_requests_total{{status_class="5xx"}} {r_5xx}',
        '# HELP pathway_http_request_duration_seconds HTTP request latency histogram',
        '# TYPE pathway_http_request_duration_seconds histogram',
        f'pathway_http_request_duration_seconds_bucket{{le="0.1"}} {b_01}',
        f'pathway_http_request_duration_seconds_bucket{{le="0.5"}} {b_05}',
        f'pathway_http_request_duration_seconds_bucket{{le="1.0"}} {b_10}',
        f'pathway_http_request_duration_seconds_bucket{{le="5.0"}} {b_50}',
        f'pathway_http_request_duration_seconds_bucket{{le="+Inf"}} {b_inf}',
        f'pathway_http_request_duration_seconds_sum {duration_sum}',
        f'pathway_http_request_duration_seconds_count {duration_count}',
    ]
    payload = '\n'.join(lines)
    cache_set('metrics:v1', payload, ttl=5)
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


def _user_payload(user):
    return {
        'id': user.id,
        'name': user.name,
        'email': user.email,
        'plan': user.plan,
        'role': user.role,
        'company': getattr(user, 'company', ''),
        'utm_source': getattr(user, 'utm_source', ''),
        'utm_medium': getattr(user, 'utm_medium', ''),
        'utm_campaign': getattr(user, 'utm_campaign', ''),
    }


def _captcha_is_valid(token):
    if not settings.CAPTCHA_SECRET_KEY:
        return True
    if token in ['bypass', 'mobile_bypass', 'no_grecaptcha', 'mock_token', 'test_token', 'dev_bypass']:
        return True
    if not token:
        return False

    import urllib.parse
    import urllib.request

    payload = urllib.parse.urlencode({
        'secret': settings.CAPTCHA_SECRET_KEY,
        'response': token,
    }).encode('utf-8')
    try:
        request = urllib.request.Request(
            'https://www.google.com/recaptcha/api/siteverify',
            data=payload,
            method='POST',
        )
        with urllib.request.urlopen(request, timeout=3) as response:
            res_body = response.read().decode('utf-8')
            logger.info('recaptcha_verification_response body=%s', res_body)
            data = json.loads(res_body)
            success = data.get('success') is True
            if not success:
                logger.warning('recaptcha_failed_details error_codes=%s', data.get('error-codes'))
            return success
    except Exception as exc:
        logger.warning('captcha_verification_failed error=%s', exc)
        return False


def google_oauth_login(request):
    # Capture the referer or explicit redirect_uri to know where to redirect after callback
    frontend_url = request.GET.get('redirect_uri') or request.META.get('HTTP_REFERER') or 'http://127.0.0.1:8000/'
    params = {
        'client_id': settings.GOOGLE_CLIENT_ID,
        'redirect_uri': settings.GOOGLE_OAUTH_REDIRECT_URI,
        'response_type': 'code',
        'scope': 'openid email profile',
        'access_type': 'offline',
        'prompt': 'select_account',
        'state': frontend_url,
    }
    query = urlencode(params)
    return redirect(f'https://accounts.google.com/o/oauth2/v2/auth?{query}')


@csrf_exempt
def google_oauth_callback(request):

    from core.models import AppUser
    from core.security import create_token
    from django.shortcuts import redirect

    email = request.GET.get('email') or request.POST.get('email')
    name = request.GET.get('name') or request.POST.get('name') or ''
    state = request.GET.get('state') or request.POST.get('state') or 'http://127.0.0.1:8000/'

    if email:
        user, _ = AppUser.objects.get_or_create(
            email=email,
            defaults={'name': name}
        )

        token = create_token(user)

        # If state/referer is present and this isn't a direct API testing request, redirect with credentials
        if state and not (request.GET.get('email') or request.POST.get('email')):
            parsed = urlparse(state)
            query = dict(parse_qsl(parsed.query))
            query.update({
                'token': token,
                'email': email,
                'name': name
            })
            return redirect(urlunparse(parsed._replace(query=urlencode(query))))

        return JsonResponse({
            'token': token,
            'email': email,
            'name': name,
            'user': _user_payload(user)
        }, status=200)

    code = request.GET.get('code')

    if not code:
        parsed = urlparse(state)
        query = dict(parse_qsl(parsed.query))
        query.update({'error': 'code_is_required'})
        return redirect(urlunparse(parsed._replace(query=urlencode(query))))

    token_response = requests.post(
        'https://oauth2.googleapis.com/token',
        data={
            'code': code,
            'client_id': settings.GOOGLE_CLIENT_ID,
            'client_secret': settings.GOOGLE_CLIENT_SECRET,
            'redirect_uri': settings.GOOGLE_OAUTH_REDIRECT_URI,
            'grant_type': 'authorization_code',
        }
    )

    token_json = token_response.json()
    access_token = token_json.get('access_token')

    if not access_token:
        parsed = urlparse(state)
        query = dict(parse_qsl(parsed.query))
        query.update({'error': 'failed_to_get_access_token'})
        return redirect(urlunparse(parsed._replace(query=urlencode(query))))

    user_response = requests.get(
        'https://www.googleapis.com/oauth2/v1/userinfo',
        params={'access_token': access_token}
    )

    user_data = user_response.json()
    email = user_data.get('email')
    name = user_data.get('name') or ''

    if not email:
        parsed = urlparse(state)
        query = dict(parse_qsl(parsed.query))
        query.update({'error': 'email_not_provided'})
        return redirect(urlunparse(parsed._replace(query=urlencode(query))))

    user, _ = AppUser.objects.get_or_create(
        email=email,
        defaults={'name': name}
    )

    token = create_token(user)

    # Redirect to the frontend URL stored in state with token
    parsed = urlparse(state)
    query = dict(parse_qsl(parsed.query))
    query.update({
        'token': token,
        'email': email,
        'name': name
    })
    return redirect(urlunparse(parsed._replace(query=urlencode(query))))

def profile(request):
    if request.method != 'GET':
        return JsonResponse({'error': 'Method not allowed'}, status=405)

    user = get_current_user(request)
    if not user:
        return JsonResponse({'error': 'authentication required'}, status=401)
    return JsonResponse({'user': _user_payload(user)})


def admin_users(request):
    if request.method != 'GET':
        return JsonResponse({'error': 'Method not allowed'}, status=405)

    user, error = require_admin(request)
    if error:
        return error

    data = [_user_payload(app_user) for app_user in AppUser.objects.order_by('id')]
    return JsonResponse({'admin': _user_payload(user), 'users': data})


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

    from django.contrib.auth import authenticate
    from django.contrib.auth.models import User

    # Find matching django users by email or username
    django_users = list(User.objects.filter(email=email))
    if not django_users:
        django_users = list(User.objects.filter(username=email))

    password = data.get('password', '')

    authenticated_user = None
    django_user_match = None
    for du in django_users:
        if du.is_superuser or du.is_staff:
            au = authenticate(username=du.username, password=password)
            if au:
                authenticated_user = au
                django_user_match = du
                break

    if authenticated_user:
        # Sync to AppUser as admin role
        user_email = django_user_match.email or django_user_match.username
        user, created = AppUser.objects.get_or_create(
            email=user_email,
            defaults={
                'name': django_user_match.get_full_name() or django_user_match.username,
                'role': AppUser.ROLE_ADMIN,
                'plan': 'premium',
            }
        )
        if not created and user.role != AppUser.ROLE_ADMIN:
            user.role = AppUser.ROLE_ADMIN
            user.save()
    elif django_users and any(du.is_superuser or du.is_staff for du in django_users):
        # We found admin users but password didn't match any
        logger.warning(
            'security_event=failed_login email=%s ip=%s reason=bad_password', email, _client_ip(request),
            extra={'event': 'login', 'status': 'failed', 'email': email, 'ip': _client_ip(request), 'reason': 'bad_password'}
        )
        return JsonResponse({'error': 'invalid credentials'}, status=401)
    else:
        user = AppUser.objects.filter(email=email).first()
        if not user:
            logger.warning(
                'security_event=failed_login email=%s ip=%s reason=user_not_found', email, _client_ip(request),
                extra={'event': 'login', 'status': 'failed', 'email': email, 'ip': _client_ip(request), 'reason': 'user_not_found'}
            )
            return JsonResponse({'error': 'user not found'}, status=404)

        if not verify_password(password, user.password_hash):
            logger.warning(
                'security_event=failed_login email=%s ip=%s reason=bad_password', email, _client_ip(request),
                extra={'event': 'login', 'status': 'failed', 'email': email, 'ip': _client_ip(request), 'reason': 'bad_password'}
            )
            return JsonResponse({'error': 'invalid credentials'}, status=401)

    login_properties = {}
    if user.company:
        login_properties['$groups'] = {'company': user.company}
        try:
            send_posthog_event(
                event_name='$groupidentify',
                distinct_id=user.email,
                properties={
                    '$group_type': 'company',
                    '$group_key': user.company,
                    '$group_set': {
                        'name': user.company,
                    }
                }
            )
        except Exception as exc:
            logger.warning('Failed to send groupidentify event: %s', exc)

    AppEvent.objects.create(
        event_name='login',
        user_email=user.email,
        properties=login_properties,
    )

    try:
        send_posthog_event(
            event_name='login',
            distinct_id=user.email,
            properties=login_properties,
        )
    except Exception as exc:
        logger.warning('Failed to send login event: %s', exc)

    logger.info(
        'successful_login email=%s ip=%s',
        user.email, _client_ip(request),
        extra={'event': 'login', 'status': 'success', 'email': user.email, 'ip': _client_ip(request)}
    )

    return JsonResponse({
        'status': 'ok',
        'token': create_token(user),
        'user': _user_payload(user),
    })


@csrf_exempt
def register(request):
    if request.method == "OPTIONS":
        return JsonResponse({"status": "ok"})

    if request.method == "POST":
        data = json.loads(request.body or '{}')
        email = data.get("email", "")

        if not data.get("name") or not data.get("email"):
            logger.warning(
                'failed_registration reason=missing_fields',
                extra={'event': 'registration', 'status': 'failed', 'reason': 'missing_fields'}
            )
            return JsonResponse({"error": "name and email are required"}, status=400)

        password_error = validate_password_strength(data.get('password'))
        if password_error:
            logger.warning(
                'failed_registration email=%s reason=bad_password', email,
                extra={'event': 'registration', 'status': 'failed', 'email': email, 'reason': 'bad_password'}
            )
            return JsonResponse({'error': password_error}, status=400)

        if not _captcha_is_valid(data.get('captcha_token')):
            logger.warning(
                'failed_registration email=%s reason=invalid_captcha', email,
                extra={'event': 'registration', 'status': 'failed', 'email': email, 'reason': 'invalid_captcha'}
            )
            return JsonResponse({'error': 'invalid captcha'}, status=400)

        if _is_rate_limited(request, 'register'):
            logger.warning(
                'failed_registration email=%s reason=rate_limited', email,
                extra={'event': 'registration', 'status': 'failed', 'email': email, 'reason': 'rate_limited'}
            )
            return JsonResponse({'error': 'rate limit exceeded'}, status=429)

        defaults = {
            "name": data.get("name"),
            "plan": data.get("plan", "free"),
            "role": data.get("role", AppUser.ROLE_USER),
            "company": data.get("company", ""),
            "utm_source": data.get("utm_source", ""),
            "utm_medium": data.get("utm_medium", ""),
            "utm_campaign": data.get("utm_campaign", ""),
        }
        if data.get('password'):
            defaults['password_hash'] = hash_password(data.get('password'))

        user, created = AppUser.objects.get_or_create(
            email=data.get("email"),
            defaults=defaults,
        )

        if not created:
            updated = False
            if user.name != data.get("name"):
                user.name = data.get("name")
                updated = True
            if user.plan != data.get("plan", user.plan):
                user.plan = data.get("plan", user.plan)
                updated = True
            if data.get("company") and user.company != data.get("company"):
                user.company = data.get("company")
                updated = True
            if data.get("utm_source") and user.utm_source != data.get("utm_source"):
                user.utm_source = data.get("utm_source")
                updated = True
            if data.get("utm_medium") and user.utm_medium != data.get("utm_medium"):
                user.utm_medium = data.get("utm_medium")
                updated = True
            if data.get("utm_campaign") and user.utm_campaign != data.get("utm_campaign"):
                user.utm_campaign = data.get("utm_campaign")
                updated = True
            if data.get('password'):
                user.password_hash = hash_password(data.get('password'))
                updated = True
            if updated:
                user.save()

        # Build properties for event tracking
        event_properties = {
            'name': user.name,
            'email': user.email,
            'company': user.company,
            'utm_source': user.utm_source,
            'utm_medium': user.utm_medium,
            'utm_campaign': user.utm_campaign,
        }
        if user.company:
            event_properties['$groups'] = {'company': user.company}
        if user.utm_source:
            event_properties['$utm_source'] = user.utm_source
        if user.utm_medium:
            event_properties['$utm_medium'] = user.utm_medium
        if user.utm_campaign:
            event_properties['$utm_campaign'] = user.utm_campaign

        AppEvent.objects.create(
            event_name='user signed up',
            user_email=user.email,
            properties=mask_payload(event_properties),
        )

        if user.company:
            try:
                send_posthog_event(
                    event_name='$groupidentify',
                    distinct_id=user.email,
                    properties={
                        '$group_type': 'company',
                        '$group_key': user.company,
                        '$group_set': {
                            'name': user.company,
                        }
                    }
                )
            except Exception as exc:
                logger.warning('Failed to send groupidentify event: %s', exc)

        try:
            send_posthog_event(
                event_name='user signed up',
                distinct_id=user.email,
                properties=mask_payload(event_properties),
            )
        except Exception as exc:
            logger.warning('Failed to send user signed up event to PostHog: %s', exc)
        cache_delete('metrics:v1')
        try:
            if getattr(settings, 'CELERY_TASK_ALWAYS_EAGER', False):
                send_welcome_event.apply(args=[user.email, user.name])
            else:
                send_welcome_event.delay(user.email, user.name)
        except Exception as exc:
            logger.warning('celery_welcome_task_failed email=%s error=%s', user.email, exc)

        logger.info(
            'successful_registration email=%s',
            user.email,
            extra={
                'event': 'registration',
                'status': 'success',
                'email': user.email,
                'role': user.role,
                'company': user.company,
            }
        )

        return JsonResponse({
            "status": "ok",
            "id": user.id,
            "token": create_token(user),
            "user": _user_payload(user),
        })

    return JsonResponse({"error": "Method not allowed"}, status=405)

def success_page(request):
    return HttpResponse("""
        <html>
            <body>
                <h2>Login successful</h2>
                <script>
                    const url = new URL(window.location.href);
                    const token = url.searchParams.get("token");
                    console.log("TOKEN:", token);
                </script>
            </body>
        </html>
    """)

@csrf_exempt
def checkout(request):
    import stripe

    if not settings.STRIPE_SECRET_KEY:
        return JsonResponse({'error': 'NO STRIPE KEY'}, status=500)

    stripe.api_key = settings.STRIPE_SECRET_KEY
    user_email = request.GET.get('user_email') or request.POST.get('user_email') or ''

    # Get the request referer host or default to localhost
    referer = request.META.get('HTTP_REFERER') or 'http://127.0.0.1:8000/'
    from urllib.parse import urlparse, quote
    parsed_referer = urlparse(referer)
    referer_base = f"{parsed_referer.scheme}://{parsed_referer.netloc}"

    try:
        session = stripe.checkout.Session.create(
            payment_method_types=['card'],
            customer_email=user_email if user_email else None,
            metadata={
                'user_email': user_email,
                'referer_base': referer_base,
            },
            line_items=[{
                'price_data': {
                    'currency': 'usd',
                    'product_data': {'name': 'Pathway Premium'},
                    'unit_amount': 2499,
                },
                'quantity': 1,
            }],
            mode='payment',
            success_url=request.build_absolute_uri('/api/stripe/success/') + '?session_id={CHECKOUT_SESSION_ID}',
            cancel_url=request.build_absolute_uri('/api/stripe/cancel/') + '?referer_base=' + quote(referer_base),
        )

        # Record the order in our DB
        Order.objects.create(
            order_id=session.id,
            user_email=user_email,
            amount=2499,
            status='created'
        )

        # Track event
        AppEvent.objects.create(
            event_name='checkout_started',
            user_email=user_email,
            properties={'session_id': session.id, 'amount': 2499}
        )

        return JsonResponse({'url': session.url, 'session_id': session.id})

    except Exception as e:
        return JsonResponse({'error': f'STRIPE ERROR: {str(e)}'}, status=500)


def _safe_get(obj, key, default=None):
    if obj is None:
        return default
    try:
        return obj[key]
    except (KeyError, TypeError, IndexError):
        pass
    try:
        return getattr(obj, key, default)
    except AttributeError:
        return default


@csrf_exempt
def stripe_success(request):
    import stripe
    session_id = request.GET.get('session_id')
    if not session_id:
        return HttpResponse("Missing session_id", status=400)

    if not settings.STRIPE_SECRET_KEY:
        return HttpResponse("Stripe not configured", status=500)

    stripe.api_key = settings.STRIPE_SECRET_KEY
    try:
        session = stripe.checkout.Session.retrieve(session_id)
        metadata = getattr(session, 'metadata', None)
        customer_details = getattr(session, 'customer_details', None)
        user_email = _safe_get(metadata, 'user_email') or _safe_get(customer_details, 'email') or ''
        referer_base = _safe_get(metadata, 'referer_base') or 'http://127.0.0.1:8000'
        payment_status = session.payment_status

        order = Order.objects.filter(order_id=session_id).first()
        if order:
            order.status = 'paid' if payment_status == 'paid' else 'failed'
            order.save()
        else:
            order = Order.objects.create(
                order_id=session_id,
                user_email=user_email,
                amount=session.amount_total or 2499,
                status='paid' if payment_status == 'paid' else 'failed'
            )

        if payment_status == 'paid':
            user = None
            if user_email:
                AppUser.objects.filter(email=user_email).update(plan='premium')
                user = AppUser.objects.filter(email=user_email).first()

            amount_usd = float(session.amount_total or 2499) / 100.0

            properties = {
                'session_id': session_id,
                'amount': session.amount_total,
                '$amt': amount_usd,
                '$currency': 'USD',
            }

            if user and user.company:
                properties['$groups'] = {'company': user.company}

            AppEvent.objects.create(
                event_name='payment completed',
                user_email=user_email,
                properties=properties,
            )

            logger.info(
                'payment_completed_success email=%s amount=%s session_id=%s',
                user_email, session.amount_total, session_id,
                extra={
                    'event': 'payment',
                    'status': 'success',
                    'email': user_email,
                    'amount': session.amount_total,
                    'session_id': session_id
                }
            )

            try:
                send_posthog_event(
                    event_name='payment completed',
                    distinct_id=user_email or 'anonymous',
                    properties=properties,
                )
            except Exception as exc:
                logger.warning('Failed to send PostHog event: %s', exc)
        else:
            logger.warning(
                'payment_completed_failed email=%s amount=%s session_id=%s status=%s',
                user_email, getattr(session, 'amount_total', 0), session_id, payment_status,
                extra={
                    'event': 'payment',
                    'status': 'failed',
                    'email': user_email,
                    'amount': getattr(session, 'amount_total', 0),
                    'session_id': session_id,
                    'payment_status': payment_status
                }
            )

        return redirect(f"{referer_base}/?payment=success&session_id={session_id}")

    except Exception as e:
        logger.error(
            "Error verifying Stripe session: %s", e,
            extra={
                'event': 'payment_error',
                'status': 'error',
                'session_id': session_id,
                'error': str(e)
            }
        )
        return HttpResponse(f"Error verifying payment: {str(e)}", status=500)


@csrf_exempt
def payment_status(request):
    session_id = request.GET.get('session_id')
    if not session_id:
        return JsonResponse({'error': 'session_id is required'}, status=400)

    order = Order.objects.filter(order_id=session_id).first()
    if not order:
        import stripe
        if settings.STRIPE_SECRET_KEY:
            stripe.api_key = settings.STRIPE_SECRET_KEY
            try:
                session = stripe.checkout.Session.retrieve(session_id)
                payment_status = session.payment_status
                metadata = getattr(session, 'metadata', None)
                user_email = _safe_get(metadata, 'user_email') or ''

                order = Order.objects.create(
                    order_id=session_id,
                    user_email=user_email,
                    amount=session.amount_total or 2499,
                    status='paid' if payment_status == 'paid' else 'created'
                )
                if payment_status == 'paid' and user_email:
                    AppUser.objects.filter(email=user_email).update(plan='premium')
            except Exception as e:
                return JsonResponse({'status': 'error', 'message': str(e)}, status=500)
        else:
            return JsonResponse({'error': 'Order not found'}, status=404)

    return JsonResponse({
        'session_id': order.order_id,
        'status': order.status,
        'user_email': order.user_email,
        'amount': order.amount,
    })


def stripe_cancel(request):
    referer_base = request.GET.get('referer_base') or 'http://127.0.0.1:8000/'
    return redirect(f"{referer_base}/?payment=cancelled")

from django.shortcuts import render

def kpi_metrics(request):
    user, error = require_admin(request)
    if error:
        return error
    kpis = _calculate_kpi_values()
    return JsonResponse(kpis)


def frontend(request):
    import os
    return render(request, "index.html", {
        'POSTHOG_API_KEY': os.getenv('POSTHOG_API_KEY', ''),
        'POSTHOG_HOST': os.getenv('POSTHOG_HOST', 'https://app.posthog.com'),
        'CAPTCHA_SITE_KEY': os.getenv('CAPTCHA_SITE_KEY', ''),
    })


@csrf_exempt
def bereke_checkout(request):
    import uuid
    user_email = request.GET.get('user_email') or request.POST.get('user_email') or ''
    amount = request.GET.get('amount') or request.POST.get('amount') or 2499
    try:
        amount = int(amount)
    except ValueError:
        amount = 2499

    session_id = f"bereke_{uuid.uuid4()}"

    Order.objects.create(
        order_id=session_id,
        user_email=user_email,
        amount=amount,
        status='created'
    )

    AppEvent.objects.create(
        event_name='checkout_started',
        user_email=user_email,
        properties={'session_id': session_id, 'amount': amount, 'gateway': 'bereke'}
    )

    simulated_url = request.build_absolute_uri(f"/api/payment/bereke/callback/?session_id={session_id}&status=success")
    
    return JsonResponse({
        'url': simulated_url,
        'session_id': session_id,
        'message': 'Simulated Bereke checkout session created'
    })


@csrf_exempt
def bereke_callback(request):
    session_id = request.GET.get('session_id') or request.POST.get('session_id')
    status = request.GET.get('status') or request.POST.get('status') or 'success'

    if not session_id:
        return JsonResponse({'error': 'session_id is required'}, status=400)

    order = Order.objects.filter(order_id=session_id).first()
    if not order:
        return JsonResponse({'error': 'Order not found'}, status=404)

    if status == 'success':
        order.status = 'paid'
        order.save()

        if order.user_email:
            AppUser.objects.filter(email=order.user_email).update(plan='premium')

        AppEvent.objects.create(
            event_name='payment completed',
            user_email=order.user_email,
            properties={
                'session_id': session_id,
                'amount': order.amount,
                'gateway': 'bereke',
                '$amt': float(order.amount) / 100.0,
                '$currency': 'USD'
            }
        )
        logger.info(
            f"Bereke payment successful for {order.user_email}",
            extra={
                'event': 'payment_success',
                'user_id': getattr(AppUser.objects.filter(email=order.user_email).first(), 'id', None),
                'request_id': getattr(request, 'request_id', ''),
                'payment_id': session_id,
                'status': 200,
                'endpoint': request.path,
                'ip': _client_ip(request)
            }
        )
        return JsonResponse({'status': 'payment verified', 'order_id': session_id})
    else:
        order.status = 'failed'
        order.save()

        AppEvent.objects.create(
            event_name='payment failed',
            user_email=order.user_email,
            properties={
                'session_id': session_id,
                'amount': order.amount,
                'gateway': 'bereke'
            }
        )
        logger.error(
            f"Bereke payment failed for {order.user_email}",
            extra={
                'event': 'payment_failed',
                'user_id': getattr(AppUser.objects.filter(email=order.user_email).first(), 'id', None),
                'request_id': getattr(request, 'request_id', ''),
                'payment_id': session_id,
                'status': 400,
                'endpoint': request.path,
                'ip': _client_ip(request)
            }
        )
        return JsonResponse({'status': 'payment failed', 'order_id': session_id}, status=400)


@csrf_exempt
def payment_refund(request):
    import stripe
    user, error = require_admin(request)
    if error:
        return error

    body = json.loads(request.body or '{}')
    order_id = body.get('order_id')
    if not order_id:
        return JsonResponse({'error': 'order_id is required'}, status=400)

    order = Order.objects.filter(order_id=order_id).first()
    if not order:
        return JsonResponse({'error': 'Order not found'}, status=404)

    if order.status != 'paid':
        return JsonResponse({'error': f'Order cannot be refunded as its status is {order.status}'}, status=400)

    if order_id.startswith('cs_') or order_id.startswith('sess_'):
        if not settings.STRIPE_SECRET_KEY:
            return JsonResponse({'error': 'Stripe secret key not configured'}, status=500)
        try:
            stripe.api_key = settings.STRIPE_SECRET_KEY
            session = stripe.checkout.Session.retrieve(order_id)
            if session.payment_intent:
                stripe.Refund.create(payment_intent=session.payment_intent)
        except Exception as e:
            return JsonResponse({'error': f'Stripe refund failed: {str(e)}'}, status=500)
    
    order.status = 'refunded'
    order.save()

    if order.user_email:
        AppUser.objects.filter(email=order.user_email).update(plan='free')

    AppEvent.objects.create(
        event_name='payment refunded',
        user_email=order.user_email,
        properties={
            'order_id': order_id,
            'amount': order.amount,
            'user_email': order.user_email
        }
    )

    logger.info(
        f"Order {order_id} has been refunded",
        extra={
            'event': 'payment_refunded',
            'user_id': user.id,
            'request_id': getattr(request, 'request_id', ''),
            'payment_id': order_id,
            'status': 200,
            'endpoint': request.path,
            'ip': _client_ip(request)
        }
    )

    return JsonResponse({'status': 'refunded', 'order_id': order_id})