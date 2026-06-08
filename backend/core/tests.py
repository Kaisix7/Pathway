import json
import re
from datetime import timedelta

from django.contrib.auth.hashers import make_password
from django.test import Client, TestCase, override_settings
from django.utils import timezone

from .cache import _memory_cache, get_redis_client
from .models import AppEvent, AirportOrder, AppUser


@override_settings(
    ALLOWED_HOSTS=['testserver', 'localhost', '127.0.0.1'],
    CELERY_TASK_ALWAYS_EAGER=True,
)
class ApiTests(TestCase):
    def setUp(self):
        self.client = Client()
        _memory_cache.clear()
        try:
            get_redis_client().flushdb()
        except Exception:
            pass

    def _get_captcha(self):
        response = self.client.get('/api/captcha/')
        self.assertEqual(response.status_code, 200)
        data = response.json()
        question = data['question']
        numbers = re.findall(r'\d+', question)
        self.assertEqual(len(numbers), 2)
        return data['challenge_id'], str(int(numbers[0]) + int(numbers[1]))

    def _register_user(self, email='aida@example.com', name='Aida', password='SecurePass123'):
        challenge_id, challenge_answer = self._get_captcha()
        response = self.client.post(
            '/api/register/',
            data=json.dumps({
                'name': name,
                'email': email,
                'password': password,
                'captcha_id': challenge_id,
                'captcha_answer': challenge_answer,
            }),
            content_type='application/json',
        )
        self.assertEqual(response.status_code, 200)
        return response.json()

    def _login_user(self, email='aida@example.com', password='SecurePass123'):
        challenge_id, challenge_answer = self._get_captcha()
        response = self.client.post(
            '/api/login/',
            data=json.dumps({
                'email': email,
                'password': password,
                'captcha_id': challenge_id,
                'captcha_answer': challenge_answer,
            }),
            content_type='application/json',
        )
        self.assertEqual(response.status_code, 200)
        return response.json()

    def test_register_creates_user_and_returns_tokens(self):
        data = self._register_user()
        self.assertEqual(AppUser.objects.count(), 1)
        self.assertIn('tokens', data)
        self.assertEqual(data['user']['email'], 'aida@example.com')

        login_response = self._login_user()
        self.assertEqual(login_response['user']['email'], 'aida@example.com')
        self.assertIn('access_token', login_response['tokens'])

    def test_orders_post_and_get_with_owner_filter(self):
        registration = self._register_user()
        access_token = registration['tokens']['access_token']

        post_response = self.client.post(
            '/api/orders/',
            data=json.dumps({
                'name': 'Aida',
                'tariff': 'Comfort',
                'price': 18000,
                'pickup_location': 'Almaty Airport - Terminal 2',
                'flight_number': 'KC 123',
                'arrival_date': '2026-04-21',
                'arrival_time': '12:00',
                'passengers': 2,
                'destination': 'Almaty Hotel',
            }),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {access_token}',
        )

        self.assertEqual(post_response.status_code, 200)
        self.assertEqual(AirportOrder.objects.count(), 1)
        order = AirportOrder.objects.latest('id')
        self.assertEqual(order.user_email, 'aida@example.com')
        self.assertEqual(order.user.email, 'aida@example.com')
        self.assertEqual(order.order_status, 'pending')

        get_response = self.client.get(
            '/api/orders/',
            HTTP_AUTHORIZATION=f'Bearer {access_token}',
        )
        self.assertEqual(get_response.status_code, 200)
        data = get_response.json()
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]['flight_number'], 'KC 123')
        self.assertEqual(data[0]['pickup_location'], 'Almaty Airport - Terminal 2')

        pay_response = self.client.post(
            f'/api/orders/{order.id}/pay/',
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {access_token}',
        )
        self.assertEqual(pay_response.status_code, 200)
        order.refresh_from_db()
        self.assertEqual(order.order_status, 'done')

    def test_user_cannot_access_other_user_orders(self):
        first = self._register_user(email='first@example.com', name='First')
        second = self._register_user(email='second@example.com', name='Second')

        second_token = second['tokens']['access_token']
        self.client.post(
            '/api/orders/',
            data=json.dumps({
                'name': 'Second order',
                'tariff': 'Standard',
                'price': 1000,
                'pickup_location': 'A',
                'flight_number': 'F1',
            }),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {second_token}',
        )

        blocked = self.client.get(
            '/api/orders/?user_email=first@example.com',
            HTTP_AUTHORIZATION=f'Bearer {second_token}',
        )
        self.assertEqual(blocked.status_code, 403)

    def test_admin_can_access_metrics_and_retention(self):
        admin = AppUser.objects.create(
            name='Admin',
            email='admin@example.com',
            role=AppUser.ROLE_ADMIN,
            password_hash=make_password('AdminPass123'),
        )
        tokens = self._login_user(email='admin@example.com', password='AdminPass123')['tokens']
        access_token = tokens['access_token']
        response = self.client.get('/api/metrics/', HTTP_AUTHORIZATION=f'Bearer {access_token}')
        self.assertEqual(response.status_code, 200)

        response = self.client.get('/api/analytics/retention/', HTTP_AUTHORIZATION=f'Bearer {access_token}')
        self.assertEqual(response.status_code, 200)

    def test_openapi_and_docs_endpoints(self):
        self.assertEqual(self.client.get('/api/openapi.json').status_code, 200)
        self.assertEqual(self.client.get('/api/docs/swagger/').status_code, 200)
        self.assertEqual(self.client.get('/api/docs/redoc/').status_code, 200)

    def test_health_endpoint_reports_database_and_cache(self):
        response = self.client.get('/health')
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data['status'], 'ok')
        self.assertEqual(data['database'], 'ok')
        self.assertIn(data['cache'], ['ok', 'memory-fallback'])

    def test_cached_endpoints_return_cache_hits(self):
        AppUser.objects.create(name='Aida', email='aida@example.com')
        admin = AppUser.objects.create(
            name='Admin',
            email='admin@example.com',
            role=AppUser.ROLE_ADMIN,
            password_hash=make_password('AdminPass123'),
        )
        admin_token = self._login_user(email='admin@example.com', password='AdminPass123')['tokens']['access_token']

        first_metrics = self.client.get('/api/metrics/', HTTP_AUTHORIZATION=f'Bearer {admin_token}')
        second_metrics = self.client.get('/api/metrics/', HTTP_AUTHORIZATION=f'Bearer {admin_token}')
        self.assertEqual(first_metrics['X-Cache'], 'MISS')
        self.assertEqual(second_metrics['X-Cache'], 'HIT')

        first_retention = self.client.get('/api/analytics/retention/', HTTP_AUTHORIZATION=f'Bearer {admin_token}')
        second_retention = self.client.get('/api/analytics/retention/', HTTP_AUTHORIZATION=f'Bearer {admin_token}')
        self.assertEqual(first_retention['X-Cache'], 'MISS')
        self.assertEqual(second_retention['X-Cache'], 'HIT')

        first_token = self._register_user()['tokens']['access_token']
        second_token = self._register_user(email='other@example.com', name='Other')['tokens']['access_token']
        first_orders = self.client.get('/api/orders/', HTTP_AUTHORIZATION=f'Bearer {first_token}')
        second_orders = self.client.get('/api/orders/', HTTP_AUTHORIZATION=f'Bearer {second_token}')
        self.assertEqual(first_orders['X-Cache'], 'MISS')
        self.assertEqual(second_orders['X-Cache'], 'MISS')

    def test_login_rate_limit_returns_429_after_five_attempts(self):
        self._register_user(email='rate-limit@example.com', name='Limiter')
        for _ in range(5):
            challenge_id, challenge_answer = self._get_captcha()
            response = self.client.post(
                '/api/login/',
                data=json.dumps({
                    'email': 'rate-limit@example.com',
                    'password': 'SecurePass123',
                    'captcha_id': challenge_id,
                    'captcha_answer': challenge_answer,
                }),
                content_type='application/json',
                REMOTE_ADDR='10.10.10.10',
            )
            self.assertEqual(response.status_code, 200)

        challenge_id, challenge_answer = self._get_captcha()
        blocked = self.client.post(
            '/api/login/',
            data=json.dumps({
                'email': 'rate-limit@example.com',
                'password': 'SecurePass123',
                'captcha_id': challenge_id,
                'captcha_answer': challenge_answer,
            }),
            content_type='application/json',
            REMOTE_ADDR='10.10.10.10',
        )
        self.assertEqual(blocked.status_code, 429)

    def test_track_event_and_retention(self):
        user = AppUser.objects.create(name='Aida', email='aida@example.com')
        AppEvent.objects.create(event_name='registration', user_email=user.email)
        AppEvent.objects.create(
            event_name='app_open',
            user_email=user.email,
            created_at=timezone.now(),
        )
        app_open = AppEvent.objects.latest('id')
        app_open.created_at = user.created_at + timedelta(days=1)
        app_open.save(update_fields=['created_at'])

        self.client.post(
            '/api/events/',
            data=json.dumps({
                'event_name': 'activation',
                'user_email': user.email,
                'properties': {'passport': 'N1234567'},
            }),
            content_type='application/json',
        )

        admin = AppUser.objects.create(
            name='Admin',
            email='admin@example.com',
            role=AppUser.ROLE_ADMIN,
            password_hash=make_password('AdminPass123'),
        )
        admin_token = self._login_user(email='admin@example.com', password='AdminPass123')['tokens']['access_token']

        response = self.client.get('/api/analytics/retention/', HTTP_AUTHORIZATION=f'Bearer {admin_token}')
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data['registered_users'], 1)
        self.assertEqual(data['activation_count'], 1)

    def test_2fa_request_and_verify(self):
        AppUser.objects.create(name='Aida', email='aida@example.com')

        request_response = self.client.post(
            '/api/2fa/request/',
            data=json.dumps({'email': 'aida@example.com'}),
            content_type='application/json',
        )
        self.assertEqual(request_response.status_code, 200)
        user = AppUser.objects.get(email='aida@example.com')
        otp_code = user.otp_code

        verify_response = self.client.post(
            '/api/2fa/verify/',
            data=json.dumps({'email': 'aida@example.com', 'otp_code': otp_code}),
            content_type='application/json',
        )
        self.assertEqual(verify_response.status_code, 200)

    def test_load_style_multiple_event_posts(self):
        for index in range(20):
            response = self.client.post(
                '/api/events/',
                data=json.dumps({
                    'event_name': f'load_event_{index}',
                    'user_email': 'load@example.com',
                }),
                content_type='application/json',
            )
            self.assertEqual(response.status_code, 200)

        self.assertEqual(AppEvent.objects.count(), 20)
