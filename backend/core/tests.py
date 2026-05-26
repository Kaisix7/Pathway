import json
from datetime import timedelta

from django.test import Client, TestCase, override_settings
from django.utils import timezone

from .cache import _memory_cache
from .models import AppEvent, AirportOrder, AppUser


@override_settings(
    ALLOWED_HOSTS=['testserver', 'localhost', '127.0.0.1'],
    CELERY_TASK_ALWAYS_EAGER=True,
)
class ApiTests(TestCase):
    def setUp(self):
        self.client = Client()
        _memory_cache.clear()

    def test_register_creates_user(self):
        response = self.client.post(
            '/api/register/',
            data=json.dumps({'name': 'Aida', 'email': 'aida@example.com'}),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(AppUser.objects.count(), 1)

        login_response = self.client.post(
            '/api/login/',
            data=json.dumps({'email': 'aida@example.com'}),
            content_type='application/json',
        )

        self.assertEqual(login_response.status_code, 200)
        self.assertEqual(login_response.json()['user']['email'], 'aida@example.com')

    def test_orders_post_and_get(self):
        AppUser.objects.create(name='Aida', email='aida@example.com')
        post_response = self.client.post(
            '/api/orders/',
            data=json.dumps({
                'name': 'Aida',
                'user_email': 'aida@example.com',
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
        )

        self.assertEqual(post_response.status_code, 200)
        self.assertEqual(AirportOrder.objects.count(), 1)
        order = AirportOrder.objects.latest('id')
        self.assertEqual(order.user_email, 'aida@example.com')
        self.assertEqual(order.user.email, 'aida@example.com')
        self.assertEqual(order.order_status, 'pending')

        get_response = self.client.get('/api/orders/?user_email=aida@example.com')

        self.assertEqual(get_response.status_code, 200)
        data = get_response.json()
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]['flight_number'], 'KC 123')
        self.assertEqual(data[0]['pickup_location'], 'Almaty Airport - Terminal 2')

        pay_response = self.client.post(f'/api/orders/{order.id}/pay/')
        self.assertEqual(pay_response.status_code, 200)
        order.refresh_from_db()
        self.assertEqual(order.order_status, 'done')

    def test_generic_iin_order_post(self):
        post_response = self.client.post(
            '/api/orders/',
            data=json.dumps({
                'name': 'Aida',
                'tariff': 'IIN Booking',
                'price': 0,
                'service_type': 'iin',
                'order_title': 'IIN appointment: Medeu',
                'details': 'PSC Almaty\n2026-04-22 at 10:00',
                'order_status': 'pending',
            }),
            content_type='application/json',
        )

        self.assertEqual(post_response.status_code, 200)
        order = AirportOrder.objects.latest('id')
        self.assertEqual(order.service_type, 'iin')
        self.assertEqual(order.order_title, 'IIN appointment: Medeu')

    def test_openapi_and_docs_endpoints(self):
        self.assertEqual(self.client.get('/api/openapi.json').status_code, 200)
        self.assertEqual(self.client.get('/api/docs/swagger/').status_code, 200)
        self.assertEqual(self.client.get('/api/docs/redoc/').status_code, 200)

    def test_metrics_endpoint(self):
        response = self.client.get('/api/metrics/')
        self.assertEqual(response.status_code, 200)
        self.assertIn('pathway_users_total', response.content.decode())

    def test_health_endpoint_reports_database_and_cache(self):
        response = self.client.get('/health')

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data['status'], 'ok')
        self.assertEqual(data['database'], 'ok')
        self.assertIn(data['cache'], ['ok', 'memory-fallback'])

    def test_cached_endpoints_return_cache_hits(self):
        AppUser.objects.create(name='Aida', email='aida@example.com')

        first_metrics = self.client.get('/api/metrics/')
        second_metrics = self.client.get('/api/metrics/')
        self.assertEqual(first_metrics['X-Cache'], 'MISS')
        self.assertEqual(second_metrics['X-Cache'], 'HIT')

        first_retention = self.client.get('/api/analytics/retention/')
        second_retention = self.client.get('/api/analytics/retention/')
        self.assertEqual(first_retention['X-Cache'], 'MISS')
        self.assertEqual(second_retention['X-Cache'], 'HIT')

        first_orders = self.client.get('/api/orders/')
        second_orders = self.client.get('/api/orders/')
        self.assertEqual(first_orders['X-Cache'], 'MISS')
        self.assertEqual(second_orders['X-Cache'], 'HIT')

    def test_login_rate_limit_returns_429_after_five_attempts(self):
        AppUser.objects.create(name='Aida', email='rate-limit@example.com')

        for _ in range(5):
            response = self.client.post(
                '/api/login/',
                data=json.dumps({'email': 'rate-limit@example.com'}),
                content_type='application/json',
                REMOTE_ADDR='10.10.10.10',
            )
            self.assertEqual(response.status_code, 200)

        blocked = self.client.post(
            '/api/login/',
            data=json.dumps({'email': 'rate-limit@example.com'}),
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

        response = self.client.get('/api/analytics/retention/')
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
        otp_code = request_response.json()['dev_otp_code']

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
