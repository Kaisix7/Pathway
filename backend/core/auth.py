import json
import os
import random
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone
from functools import wraps

import jwt
from django.conf import settings
from django.contrib.auth.hashers import check_password, make_password
from django.http import JsonResponse

from .cache import cache_delete, cache_get, cache_set
from .models import AppUser
from .security import mask_payload


class AuthenticationError(Exception):
    pass


class AuthorizationError(Exception):
    pass


class CaptchaError(Exception):
    pass


def create_captcha_challenge():
    a = random.randint(1, 9)
    b = random.randint(1, 9)
    challenge_id = uuid.uuid4().hex
    answer = str(a + b)
    cache_set(f'captcha:{challenge_id}', answer, ttl=300)
    return {
        'challenge_id': challenge_id,
        'question': f'What is {a} + {b}?',
        'expires_in': 300,
    }


def verify_captcha(challenge_id, answer):
    if not challenge_id or answer is None:
        raise CaptchaError('captcha challenge is required')

    expected = cache_get(f'captcha:{challenge_id}')
    cache_delete(f'captcha:{challenge_id}')
    if expected is None or str(answer).strip() != str(expected).strip():
        raise CaptchaError('invalid captcha')
    return True


def hash_password(raw_password):
    if not raw_password:
        return ''
    return make_password(raw_password)


def verify_password(raw_password, password_hash):
    return bool(raw_password and password_hash and check_password(raw_password, password_hash))


def _create_jwt_payload(user, token_type, expires_delta):
    now = datetime.now(timezone.utc)
    return {
        'sub': str(user.id),
        'email': user.email,
        'role': user.role,
        'type': token_type,
        'iat': int(now.timestamp()),
        'exp': int((now + expires_delta).timestamp()),
    }


def encode_jwt(payload):
    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def decode_jwt(token, expected_type=None):
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM],
            options={'verify_aud': False},
        )
    except jwt.ExpiredSignatureError:
        raise AuthenticationError('token_expired')
    except jwt.InvalidTokenError:
        raise AuthenticationError('invalid_token')

    if expected_type and payload.get('type') != expected_type:
        raise AuthenticationError('invalid_token_type')
    return payload


def create_access_token(user):
    return encode_jwt(
        _create_jwt_payload(user, 'access', timedelta(seconds=settings.JWT_ACCESS_TOKEN_EXPIRES))
    )


def create_refresh_token(user):
    return encode_jwt(
        _create_jwt_payload(user, 'refresh', timedelta(seconds=settings.JWT_REFRESH_TOKEN_EXPIRES))
    )


def create_token_set(user):
    return {
        'access_token': create_access_token(user),
        'refresh_token': create_refresh_token(user),
        'token_type': 'Bearer',
        'expires_in': settings.JWT_ACCESS_TOKEN_EXPIRES,
    }


def authenticate_request(request, required=True):
    authorization = request.headers.get('Authorization', '')
    if not authorization.startswith('Bearer '):
        if required:
            raise AuthenticationError('authorization_header_missing')
        return None

    token = authorization.split(' ', 1)[1].strip()
    if not token:
        raise AuthenticationError('authorization_header_invalid')

    payload = decode_jwt(token, expected_type='access')
    user = AppUser.objects.filter(id=payload.get('sub')).first()
    if not user:
        raise AuthenticationError('user_not_found')
    return user


def require_auth(view_func):
    @wraps(view_func)
    def inner(request, *args, **kwargs):
        try:
            request.auth_user = authenticate_request(request, required=True)
        except AuthenticationError as exc:
            return JsonResponse({'error': str(exc)}, status=401)
        return view_func(request, *args, **kwargs)

    return inner


def require_role(allowed_roles):
    def decorator(view_func):
        @wraps(view_func)
        def inner(request, *args, **kwargs):
            try:
                request.auth_user = authenticate_request(request, required=True)
            except AuthenticationError as exc:
                return JsonResponse({'error': str(exc)}, status=401)

            if request.auth_user.role not in allowed_roles:
                return JsonResponse({'error': 'forbidden'}, status=403)
            return view_func(request, *args, **kwargs)

        return inner
    return decorator


def refresh_access_token(refresh_token):
    payload = decode_jwt(refresh_token, expected_type='refresh')
    user = AppUser.objects.filter(id=payload.get('sub')).first()
    if not user:
        raise AuthenticationError('user_not_found')
    return create_access_token(user)


def exchange_google_code(code, redirect_uri):
    if not settings.GOOGLE_OAUTH_CLIENT_ID or not settings.GOOGLE_OAUTH_CLIENT_SECRET:
        raise AuthenticationError('google_oauth_not_configured')

    data = urllib.parse.urlencode({
        'code': code,
        'client_id': settings.GOOGLE_OAUTH_CLIENT_ID,
        'client_secret': settings.GOOGLE_OAUTH_CLIENT_SECRET,
        'redirect_uri': redirect_uri,
        'grant_type': 'authorization_code',
    }).encode('utf-8')
    request_obj = urllib.request.Request(
        settings.GOOGLE_OAUTH_TOKEN_URL,
        data=data,
        headers={'Content-Type': 'application/x-www-form-urlencoded'},
    )
    with urllib.request.urlopen(request_obj, timeout=10) as response:
        return json.loads(response.read().decode('utf-8'))


def fetch_google_userinfo(access_token):
    request_obj = urllib.request.Request(
        settings.GOOGLE_OAUTH_USERINFO_URL,
        headers={'Authorization': f'Bearer {access_token}'},
    )
    with urllib.request.urlopen(request_obj, timeout=10) as response:
        return json.loads(response.read().decode('utf-8'))


def create_or_update_user_from_google(userinfo):
    email = userinfo.get('email')
    if not email:
        raise AuthenticationError('google_email_required')
    user, created = AppUser.objects.get_or_create(
        email=email,
        defaults={
            'name': userinfo.get('name', email.split('@')[0]),
            'role': 'user',
            'google_sub': userinfo.get('sub') or userinfo.get('id'),
        },
    )
    if not created and user.google_sub != (userinfo.get('sub') or userinfo.get('id')):
        user.google_sub = userinfo.get('sub') or userinfo.get('id')
        user.save(update_fields=['google_sub'])
    return user


def create_user_from_google_code(code, redirect_uri):
    token_data = exchange_google_code(code, redirect_uri)
    if not token_data.get('access_token'):
        raise AuthenticationError('google_access_token_missing')
    userinfo = fetch_google_userinfo(token_data['access_token'])
    return create_or_update_user_from_google(userinfo)


def sanitize_event_properties(properties):
    return mask_payload(properties if isinstance(properties, dict) else {})
