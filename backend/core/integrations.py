import json
import logging
import os
from urllib import request

logger = logging.getLogger(__name__)


def send_posthog_event(event_name, distinct_id, properties=None):
    api_key = os.getenv('POSTHOG_API_KEY', '')
    host = os.getenv('POSTHOG_HOST', 'https://app.posthog.com')

    if not api_key:
        return False

    payload = json.dumps({
        'api_key': api_key,
        'event': event_name,
        'distinct_id': distinct_id or 'anonymous',
        'properties': properties or {},
    }).encode('utf-8')

    try:
        req = request.Request(
            f'{host}/capture/',
            data=payload,
            headers={'Content-Type': 'application/json'},
            method='POST',
        )
        request.urlopen(req, timeout=5)
        return True
    except Exception as exc:
        logger.warning('posthog_send_failed=%s', exc)
        return False
