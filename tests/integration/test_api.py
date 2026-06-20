import json
from datetime import timedelta

import pytest
from django.utils import timezone

from core import cache as cache_module
from core.models import AppEvent, AirportOrder, AppUser


@pytest.fixture(autouse=True)
def clear_cache(monkeypatch):
    cache_module._memory_cache.clear()
    monkeypatch.setattr(cache_module, '_redis_unavailable_until', timezone.now().timestamp() + 3600)


@pytest.mark.django_db
def test_register_creates_user_and_token(client, settings):
    settings.CELERY_TASK_ALWAYS_EAGER = True
    response = client.post(
        '/api/register/',
        data=json.dumps({'name': 'Aida', 'email': 'aida@example.com'}),
        content_type='application/json',
    )

    assert response.status_code == 200
    assert AppUser.objects.count() == 1
    assert response.json()['token']


@pytest.mark.django_db
def test_login_returns_token(client):
    AppUser.objects.create(name='Aida', email='aida@example.com')

    response = client.post(
        '/api/login/',
        data=json.dumps({'email': 'aida@example.com'}),
        content_type='application/json',
    )

    assert response.status_code == 200
    assert response.json()['user']['email'] == 'aida@example.com'
    assert response.json()['token']


@pytest.mark.django_db
def test_login_with_bad_password_returns_401(client):
    from core.security import hash_password

    AppUser.objects.create(
        name='Aida',
        email='secure@example.com',
        password_hash=hash_password('StrongPass1'),
    )

    response = client.post(
        '/api/login/',
        data=json.dumps({'email': 'secure@example.com', 'password': 'WrongPass1'}),
        content_type='application/json',
    )

    assert response.status_code == 401


@pytest.mark.django_db
def test_profile_requires_token(client):
    response = client.get('/api/profile/')

    assert response.status_code == 401


@pytest.mark.django_db
def test_profile_returns_current_user(client):
    register = client.post(
        '/api/register/',
        data=json.dumps({'name': 'Aida', 'email': 'profile@example.com'}),
        content_type='application/json',
    )
    token = register.json()['token']

    response = client.get('/api/profile/', HTTP_AUTHORIZATION=f'Bearer {token}')

    assert response.status_code == 200
    assert response.json()['user']['email'] == 'profile@example.com'


@pytest.mark.django_db
def test_user_cannot_access_admin_users(client):
    register = client.post(
        '/api/register/',
        data=json.dumps({'name': 'Aida', 'email': 'user@example.com'}),
        content_type='application/json',
    )

    response = client.get(
        '/api/admin/users/',
        HTTP_AUTHORIZATION=f"Bearer {register.json()['token']}",
    )

    assert response.status_code == 403


@pytest.mark.django_db
def test_admin_can_access_admin_users(client):
    register = client.post(
        '/api/register/',
        data=json.dumps({'name': 'Admin', 'email': 'admin@example.com', 'role': 'admin'}),
        content_type='application/json',
    )

    response = client.get(
        '/api/admin/users/',
        HTTP_AUTHORIZATION=f"Bearer {register.json()['token']}",
    )

    assert response.status_code == 200
    assert response.json()['users'][0]['email'] == 'admin@example.com'


@pytest.mark.django_db
def test_orders_post_and_get_uses_user_relation(client):
    AppUser.objects.create(name='Aida', email='aida@example.com')
    post_response = client.post(
        '/api/orders/',
        data=json.dumps({
            'name': 'Aida',
            'user_email': 'aida@example.com',
            'tariff': 'Comfort',
            'price': 18000,
            'pickup_location': 'Almaty Airport - Terminal 2',
            'flight_number': 'KC 123',
        }),
        content_type='application/json',
    )

    assert post_response.status_code == 200
    order = AirportOrder.objects.latest('id')
    assert order.user.email == 'aida@example.com'

    get_response = client.get('/api/orders/?user_email=aida@example.com')
    assert get_response.status_code == 200
    assert get_response.json()[0]['flight_number'] == 'KC 123'

    pay_response = client.post(f'/api/orders/{order.id}/pay/')
    order.refresh_from_db()

    assert pay_response.status_code == 200
    assert order.order_status == AirportOrder.STATUS_DONE


@pytest.mark.django_db
def test_cached_endpoints_return_cache_hits(client):
    AppUser.objects.create(name='Aida', email='aida@example.com')

    first_metrics = client.get('/api/metrics/')
    second_metrics = client.get('/api/metrics/')

    assert first_metrics['X-Cache'] == 'MISS'
    assert second_metrics['X-Cache'] == 'HIT'


@pytest.mark.django_db
def test_health_endpoint_reports_database_and_cache(client):
    response = client.get('/health')

    assert response.status_code == 200
    assert response.json()['database'] == 'ok'


@pytest.mark.django_db
def test_openapi_and_docs_endpoints(client):
    assert client.get('/api/openapi.json').status_code == 200
    assert client.get('/api/docs/swagger/').status_code == 200
    assert client.get('/api/docs/redoc/').status_code == 200


@pytest.mark.django_db
def test_2fa_request_and_verify(client):
    AppUser.objects.create(name='Aida', email='2fa@example.com')

    request_response = client.post(
        '/api/2fa/request/',
        data=json.dumps({'email': '2fa@example.com'}),
        content_type='application/json',
    )
    assert request_response.status_code == 200

    verify_response = client.post(
        '/api/2fa/verify/',
        data=json.dumps({
            'email': '2fa@example.com',
            'otp_code': request_response.json()['dev_otp_code'],
        }),
        content_type='application/json',
    )

    assert verify_response.status_code == 200


@pytest.mark.django_db
def test_google_oauth_callback_creates_user_and_token(client):
    response = client.get('/api/oauth/google/callback/?email=oauth@example.com&name=OAuth')

    assert response.status_code == 200
    assert response.json()['token']
    assert AppUser.objects.get(email='oauth@example.com').name == 'OAuth'


@pytest.mark.django_db
def test_login_rate_limit_returns_429_after_five_attempts(client):
    AppUser.objects.create(name='Aida', email='rate-limit@example.com')

    for _ in range(5):
        response = client.post(
            '/api/login/',
            data=json.dumps({'email': 'rate-limit@example.com'}),
            content_type='application/json',
            REMOTE_ADDR='10.10.10.10',
        )
        assert response.status_code == 200

    blocked = client.post(
        '/api/login/',
        data=json.dumps({'email': 'rate-limit@example.com'}),
        content_type='application/json',
        REMOTE_ADDR='10.10.10.10',
    )

    assert blocked.status_code == 429


@pytest.mark.django_db
def test_track_event_and_retention(client):
    user = AppUser.objects.create(name='Aida', email='aida@example.com')
    AppEvent.objects.create(event_name='user signed up', user_email=user.email)
    AppEvent.objects.create(event_name='app_open', user_email=user.email, created_at=timezone.now())
    app_open = AppEvent.objects.latest('id')
    app_open.created_at = user.created_at + timedelta(days=1)
    app_open.save(update_fields=['created_at'])

    client.post(
        '/api/events/',
        data=json.dumps({'event_name': 'activation', 'user_email': user.email}),
        content_type='application/json',
    )
    response = client.get('/api/analytics/retention/')

    assert response.status_code == 200
    assert response.json()['activation_count'] == 1


@pytest.mark.django_db
def test_google_oauth_login(client):
    response = client.get('/api/oauth/google/?redirect_uri=http://localhost:59390/')
    assert response.status_code == 302
    assert 'accounts.google.com' in response['Location']


@pytest.mark.django_db
def test_checkout_endpoint(client, monkeypatch):
    import stripe
    from django.conf import settings

    monkeypatch.setattr(settings, 'STRIPE_SECRET_KEY', 'mock_secret_key')

    class MockSession:
        id = 'mock_sess_123'
        url = 'https://checkout.stripe.com/pay/mock_sess_123'

    monkeypatch.setattr(stripe.checkout.Session, 'create', lambda **kwargs: MockSession())

    response = client.get('/api/checkout/?user_email=test@example.com')
    assert response.status_code == 200
    assert response.json()['session_id'] == 'mock_sess_123'
    assert response.json()['url'] == 'https://checkout.stripe.com/pay/mock_sess_123'


@pytest.mark.django_db
def test_stripe_success_view(client, monkeypatch):
    import stripe
    from django.conf import settings
    from core.models import Order

    monkeypatch.setattr(settings, 'STRIPE_SECRET_KEY', 'mock_secret_key')

    class MockSession:
        id = 'mock_sess_123'
        payment_status = 'paid'
        amount_total = 2499
        metadata = {'user_email': 'test@example.com', 'referer_base': 'http://localhost:8000'}

    monkeypatch.setattr(stripe.checkout.Session, 'retrieve', lambda session_id: MockSession())

    response = client.get('/api/stripe/success/?session_id=mock_sess_123')
    assert response.status_code == 302
    assert 'payment=success' in response['Location']


@pytest.mark.django_db
def test_payment_status_view_found_in_db(client):
    from core.models import Order
    Order.objects.create(order_id='mock_sess_123', user_email='test@example.com', amount=2499, status='paid')

    response = client.get('/api/payment/status/?session_id=mock_sess_123')
    assert response.status_code == 200
    assert response.json()['status'] == 'paid'


@pytest.mark.django_db
def test_payment_status_view_not_found_retrieved_from_stripe(client, monkeypatch):
    import stripe
    from django.conf import settings

    monkeypatch.setattr(settings, 'STRIPE_SECRET_KEY', 'mock_secret_key')

    class MockSession:
        id = 'mock_sess_123'
        payment_status = 'paid'
        amount_total = 2499
        metadata = {'user_email': 'test@example.com'}

    monkeypatch.setattr(stripe.checkout.Session, 'retrieve', lambda session_id: MockSession())

    response = client.get('/api/payment/status/?session_id=mock_sess_123')
    assert response.status_code == 200
    assert response.json()['status'] == 'paid'


@pytest.mark.django_db
def test_stripe_cancel_view(client):
    response = client.get('/api/stripe/cancel/?referer_base=http://localhost:8000')
    assert response.status_code == 302
    assert 'payment=cancelled' in response['Location']


@pytest.mark.django_db
def test_kpi_analytics_endpoint(client):
    from core.models import AppUser, AppEvent
    from core.security import create_token
    
    admin_user = AppUser.objects.create(name='Admin User', email='admin@example.com', role='admin')
    user = AppUser.objects.create(name='Premium User', email='premium@example.com', plan='premium')
    AppUser.objects.create(name='Free User', email='free@example.com', plan='free')
    
    AppEvent.objects.create(event_name='app_open', user_email='premium@example.com')
    AppEvent.objects.create(event_name='payment failed', user_email='free@example.com')
    
    # 1. Anonymous request should fail with 401
    response = client.get('/api/analytics/kpi/')
    assert response.status_code == 401
    
    # 2. Non-admin request should fail with 403
    normal_token = create_token(user)
    response = client.get('/api/analytics/kpi/', HTTP_AUTHORIZATION=f'Bearer {normal_token}')
    assert response.status_code == 403
    
    # 3. Admin request should succeed with 200
    admin_token = create_token(admin_user)
    response = client.get('/api/analytics/kpi/', HTTP_AUTHORIZATION=f'Bearer {admin_token}')
    assert response.status_code == 200
    data = response.json()
    assert data['registered_users'] == 3  # premium + free + admin
    assert data['premium_users'] == 1
    assert data['conversion_rate_percent'] == 33.33
    assert data['mrr_usd'] == 24.99
    assert data['churn_rate_percent'] == 100.0


