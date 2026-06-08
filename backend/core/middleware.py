import json
import logging

from django.conf import settings
from .security import mask_payload

logger = logging.getLogger(__name__)


class SensitiveDataMaskingMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.method in {'POST', 'PUT', 'PATCH'} and request.body:
            try:
                body = json.loads(request.body.decode('utf-8'))
                logger.info('masked_request_payload=%s path=%s', mask_payload(body), request.path)
            except Exception:
                logger.info('masked_request_payload=unavailable path=%s', request.path)
        return self.get_response(request)


class SecurityHeadersMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        response.setdefault('X-Content-Type-Options', 'nosniff')
        response.setdefault('X-Frame-Options', 'DENY')
        response.setdefault('Referrer-Policy', 'strict-origin-when-cross-origin')
        response.setdefault('Permissions-Policy', 'geolocation=(), microphone=()')
        response.setdefault('Content-Security-Policy', "default-src 'self'; frame-ancestors 'none';")
        if settings.SECURE_HSTS_SECONDS:
            response.setdefault('Strict-Transport-Security', 'max-age=%d; includeSubDomains; preload' % settings.SECURE_HSTS_SECONDS)
        return response
