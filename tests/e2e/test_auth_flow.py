import json

import pytest


@pytest.mark.django_db
def test_register_login_profile_flow(client, settings):
    settings.CELERY_TASK_ALWAYS_EAGER = True

    register = client.post(
        '/api/register/',
        data=json.dumps({
            'name': 'Aida',
            'email': 'flow@example.com',
            'password': 'StrongPass1',
        }),
        content_type='application/json',
    )
    assert register.status_code == 200

    login = client.post(
        '/api/login/',
        data=json.dumps({'email': 'flow@example.com', 'password': 'StrongPass1'}),
        content_type='application/json',
    )
    assert login.status_code == 200

    profile = client.get(
        '/api/profile/',
        HTTP_AUTHORIZATION=f"Bearer {login.json()['token']}",
    )
    assert profile.status_code == 200
    assert profile.json()['user']['email'] == 'flow@example.com'
