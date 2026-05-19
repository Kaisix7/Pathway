import json
import logging

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
