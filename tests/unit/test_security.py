from django.test import override_settings

from core.models import AppUser
from core.security import (
    create_token,
    decode_token,
    hash_password,
    validate_password_strength,
    verify_password,
)


def test_password_strength_requires_minimum_length():
    assert validate_password_strength('Aa12345') == 'password must be at least 8 characters'


def test_password_strength_requires_uppercase():
    assert validate_password_strength('password1') == 'password must contain at least one uppercase letter'


def test_password_hash_roundtrip():
    password_hash = hash_password('StrongPass1')

    assert verify_password('StrongPass1', password_hash) is True
    assert verify_password('WrongPass1', password_hash) is False


@override_settings(JWT_EXP_SECONDS=60)
def test_jwt_roundtrip(db):
    user = AppUser.objects.create(name='Aida', email='jwt@example.com', role=AppUser.ROLE_ADMIN)

    payload = decode_token(create_token(user))

    assert payload['email'] == 'jwt@example.com'
    assert payload['role'] == AppUser.ROLE_ADMIN
