import base64
import hashlib
import hmac
import json
import logging
import time

from django.conf import settings
from django.contrib.auth.hashers import check_password, make_password
from django.http import JsonResponse


SENSITIVE_KEYS = {
    'password',
    'token',
    'authorization',
    'email',
    'contact',
    'passport',
    'otp_code',
}

logger = logging.getLogger(__name__)


def mask_value(key, value):
    if value is None:
        return value

    key_lower = str(key).lower()
    if key_lower not in SENSITIVE_KEYS:
        return value

    text = str(value)
    if len(text) <= 4:
        return '*' * len(text)
    return f"{text[:2]}***{text[-2:]}"


def mask_payload(payload):
    if isinstance(payload, dict):
        return {key: mask_value(key, value) for key, value in payload.items()}
    return payload


def validate_password_strength(password):
    if not password:
        return None
    if len(password) < 8:
        return 'password must be at least 8 characters'
    if not any(char.isupper() for char in password):
        return 'password must contain at least one uppercase letter'
    return None


def hash_password(password):
    return make_password(password)


def verify_password(password, password_hash):
    if not password_hash:
        return True
    return check_password(password, password_hash)


def _b64encode(payload):
    return base64.urlsafe_b64encode(payload).rstrip(b'=').decode('ascii')


def _b64decode(payload):
    padding = '=' * (-len(payload) % 4)
    return base64.urlsafe_b64decode((payload + padding).encode('ascii'))


def create_token(user):
    header = {'alg': 'HS256', 'typ': 'JWT'}
    body = {
        'sub': user.id,
        'email': user.email,
        'role': user.role,
        'exp': int(time.time()) + settings.JWT_EXP_SECONDS,
    }
    signing_input = '.'.join([
        _b64encode(json.dumps(header, separators=(',', ':')).encode('utf-8')),
        _b64encode(json.dumps(body, separators=(',', ':')).encode('utf-8')),
    ])
    signature = hmac.new(
        settings.SECRET_KEY.encode('utf-8'),
        signing_input.encode('ascii'),
        hashlib.sha256,
    ).digest()
    return f'{signing_input}.{_b64encode(signature)}'


def decode_token(token):
    try:
        header_b64, payload_b64, signature_b64 = token.split('.')
        signing_input = f'{header_b64}.{payload_b64}'
        expected = hmac.new(
            settings.SECRET_KEY.encode('utf-8'),
            signing_input.encode('ascii'),
            hashlib.sha256,
        ).digest()
        received = _b64decode(signature_b64)
        if not hmac.compare_digest(expected, received):
            return None
        payload = json.loads(_b64decode(payload_b64))
        if payload.get('exp', 0) < int(time.time()):
            return None
        return payload
    except Exception:
        return None


def get_current_user(request):
    from .models import AppUser

    auth_header = request.META.get('HTTP_AUTHORIZATION', '')
    if not auth_header.startswith('Bearer '):
        return None

    payload = decode_token(auth_header.removeprefix('Bearer ').strip())
    if not payload:
        return None
    return AppUser.objects.filter(id=payload.get('sub'), email=payload.get('email')).first()


def require_role(request, allowed_roles):
    user = get_current_user(request)
    if not user:
        return None, JsonResponse({'error': 'authentication required'}, status=401)
    if user.role not in allowed_roles:
        return None, JsonResponse({'error': 'forbidden'}, status=403)
    return user, None


def require_admin(request):
    return require_role(request, ['admin'])
