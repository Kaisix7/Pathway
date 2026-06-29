import json
import logging
import time
import uuid
from .security import mask_payload

logger = logging.getLogger('pathway.json')


class SensitiveDataMaskingMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.method in {'POST', 'PUT', 'PATCH'} and request.body:
            try:
                body = json.loads(request.body.decode('utf-8'))
                logger.info('masked_request_payload=%s path=%s', mask_payload(body), request.path, extra={'event': 'request_payload_masked'})
            except Exception:
                logger.info('masked_request_payload=unavailable path=%s', request.path, extra={'event': 'request_payload_masked'})
        return self.get_response(request)


def record_request_metrics(status_code, duration_seconds):
    from .cache import get_redis_client, _redis_is_available
    if _redis_is_available():
        try:
            r = get_redis_client()
            status_class = f"{status_code // 100}xx"
            r.incrby(f"metrics:http_requests_total:{status_class}", 1)
            r.incrby(f"metrics:http_requests_total:all", 1)
            
            # Buckets: 0.1s, 0.5s, 1.0s, 5.0s, inf
            buckets = [0.1, 0.5, 1.0, 5.0]
            for b in buckets:
                if duration_seconds <= b:
                    r.incrby(f"metrics:http_request_duration_seconds_bucket:{b}", 1)
            r.incrby(f"metrics:http_request_duration_seconds_bucket:inf", 1)
            
            r.incrby(f"metrics:http_request_duration_seconds_sum_ms", int(duration_seconds * 1000))
            r.incrby(f"metrics:http_request_duration_seconds_count", 1)
        except Exception:
            pass


class JSONLoggingMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        request_id = request.META.get('HTTP_X_REQUEST_ID') or str(uuid.uuid4())
        request.request_id = request_id

        forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
        if forwarded_for:
            ip = forwarded_for.split(',')[0].strip()
        else:
            ip = request.META.get('REMOTE_ADDR', 'unknown')

        payment_id = request.GET.get('session_id') or request.GET.get('payment_id') or ''
        if not payment_id and request.method in {'POST', 'PUT', 'PATCH'}:
            try:
                payment_id = request.POST.get('session_id') or request.POST.get('payment_id') or ''
            except Exception:
                pass

        start_time = time.time()
        
        response = self.get_response(request)

        duration_seconds = time.time() - start_time
        response_time = int(duration_seconds * 1000)

        # Record metrics for Prometheus
        record_request_metrics(response.status_code, duration_seconds)

        user_id = None
        if hasattr(request, 'user') and request.user and not request.user.is_anonymous:
            user_id = request.user.id
        else:
            from core.security import get_current_user
            try:
                user = get_current_user(request)
                if user:
                    user_id = user.id
            except Exception:
                pass

        if not payment_id and hasattr(request, 'payment_id'):
            payment_id = request.payment_id

        status_code = response.status_code
        event = "api_request_success" if status_code < 400 else "api_request_failed"

        logger.info(
            f"HTTP {request.method} {request.path} returned {status_code}",
            extra={
                'event': event,
                'user_id': user_id,
                'request_id': request_id,
                'payment_id': payment_id or None,
                'status': status_code,
                'endpoint': request.path,
                'response_time': response_time,
                'ip': ip
            }
        )

        return response


class SecurityHeadersMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        # Content-Security-Policy
        response['Content-Security-Policy'] = (
            "default-src 'self'; "
            "script-src 'self' 'unsafe-inline' 'unsafe-eval' https:; "
            "style-src 'self' 'unsafe-inline' https:; "
            "img-src 'self' data: https:; "
            "connect-src 'self' https: wss:; "
            "frame-src 'self' https:; "
            "font-src 'self' data: https:;"
        )
        # Permissions-Policy
        response['Permissions-Policy'] = "geolocation=(), microphone=(), camera=()"
        # Referrer-Policy
        response['Referrer-Policy'] = "same-origin"
        # X-Content-Type-Options
        response['X-Content-Type-Options'] = "nosniff"
        # X-Frame-Options
        response['X-Frame-Options'] = "DENY"
        return response

