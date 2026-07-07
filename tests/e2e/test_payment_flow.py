import json

import pytest

from core.models import AppUser, Order


@pytest.mark.django_db
class TestBerekePaymentFlow:
    """End-to-end tests for the Bereke payment flow."""

    def _register_user(self, client, settings):
        settings.CELERY_TASK_ALWAYS_EAGER = True
        resp = client.post(
            '/api/register/',
            data=json.dumps({
                'name': 'Payment Tester',
                'email': 'pay_test@example.com',
                'password': 'StrongPass1',
                'captcha_token': 'bypass',
            }),
            content_type='application/json',
        )
        assert resp.status_code == 200
        return resp.json()

    def _login_admin(self, client, settings):
        """Create an admin user and return the auth token."""
        settings.CELERY_TASK_ALWAYS_EAGER = True
        reg = client.post(
            '/api/register/',
            data=json.dumps({
                'name': 'Admin User',
                'email': 'admin_pay@example.com',
                'password': 'StrongPass1',
                'role': 'admin',
                'captcha_token': 'bypass',
            }),
            content_type='application/json',
        )
        assert reg.status_code == 200
        user = AppUser.objects.get(email='admin_pay@example.com')
        user.role = 'admin'
        user.save()
        login = client.post(
            '/api/login/',
            data=json.dumps({
                'email': 'admin_pay@example.com',
                'password': 'StrongPass1',
            }),
            content_type='application/json',
        )
        assert login.status_code == 200
        return login.json()['token']

    def test_bereke_checkout_success_flow(self, client, settings):
        """Register → Bereke checkout → callback (success) → order paid + user premium."""
        self._register_user(client, settings)

        # Start checkout
        checkout_resp = client.post(
            '/api/payment/bereke/checkout/?user_email=pay_test@example.com&amount=2499',
        )
        assert checkout_resp.status_code == 200
        data = checkout_resp.json()
        session_id = data['session_id']
        assert session_id.startswith('bereke_')

        # Verify order was created
        order = Order.objects.get(order_id=session_id)
        assert order.status == 'created'
        assert order.user_email == 'pay_test@example.com'

        # Simulate successful callback
        callback_resp = client.get(
            f'/api/payment/bereke/callback/?session_id={session_id}&status=success',
        )
        assert callback_resp.status_code == 200
        assert callback_resp.json()['status'] == 'payment verified'

        # Verify order is now paid
        order.refresh_from_db()
        assert order.status == 'paid'

        # Verify user plan upgraded to premium
        user = AppUser.objects.get(email='pay_test@example.com')
        assert user.plan == 'premium'

    def test_bereke_checkout_failure_flow(self, client, settings):
        """Bereke checkout → callback (fail) → order status 'failed'."""
        self._register_user(client, settings)

        checkout_resp = client.post(
            '/api/payment/bereke/checkout/?user_email=pay_test@example.com&amount=2499',
        )
        assert checkout_resp.status_code == 200
        session_id = checkout_resp.json()['session_id']

        # Simulate failed callback
        callback_resp = client.get(
            f'/api/payment/bereke/callback/?session_id={session_id}&status=failed',
        )
        assert callback_resp.status_code == 400
        assert callback_resp.json()['status'] == 'payment failed'

        # Verify order is failed
        order = Order.objects.get(order_id=session_id)
        assert order.status == 'failed'

        # Verify user plan stays free
        user = AppUser.objects.get(email='pay_test@example.com')
        assert user.plan == 'free'

    def test_refund_flow(self, client, settings):
        """Full flow: checkout → pay → refund → order refunded + user downgraded."""
        self._register_user(client, settings)
        admin_token = self._login_admin(client, settings)

        # Checkout and pay
        checkout_resp = client.post(
            '/api/payment/bereke/checkout/?user_email=pay_test@example.com&amount=2499',
        )
        session_id = checkout_resp.json()['session_id']
        client.get(
            f'/api/payment/bereke/callback/?session_id={session_id}&status=success',
        )

        # Verify paid
        order = Order.objects.get(order_id=session_id)
        assert order.status == 'paid'
        user = AppUser.objects.get(email='pay_test@example.com')
        assert user.plan == 'premium'

        # Refund (admin-only)
        refund_resp = client.post(
            '/api/payment/refund/',
            data=json.dumps({'order_id': session_id}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {admin_token}',
        )
        assert refund_resp.status_code == 200
        assert refund_resp.json()['status'] == 'refunded'

        # Verify refund result
        order.refresh_from_db()
        assert order.status == 'refunded'

        user.refresh_from_db()
        assert user.plan == 'free'
