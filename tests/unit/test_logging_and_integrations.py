import os
import json
import logging
from unittest.mock import patch, MagicMock
from django.test import SimpleTestCase, TestCase
from core.logging import JSONFormatter
from core.integrations import send_posthog_event
from django.test import Client
from django.db import connection

class LoggingAndIntegrationsTests(SimpleTestCase):
    def test_json_formatter_normal(self):
        formatter = JSONFormatter()
        logger = logging.getLogger('test_logger')
        record = logger.makeRecord('name', logging.INFO, 'fn', 10, 'msg', (), None)
        
        # Add dynamic extra attributes
        record.custom_field = 'custom_value'
        
        result_str = formatter.format(record)
        result = json.loads(result_str)
        
        self.assertEqual(result['level'], 'INFO')
        self.assertEqual(result['message'], 'msg')
        self.assertEqual(result['custom_field'], 'custom_value')

    def test_json_formatter_exception(self):
        formatter = JSONFormatter()
        logger = logging.getLogger('test_logger')
        try:
            raise ValueError("Test error")
        except Exception:
            import sys
            exc_info = sys.exc_info()
            
        record = logger.makeRecord('name', logging.ERROR, 'fn', 10, 'error message', (), exc_info)
        result_str = formatter.format(record)
        result = json.loads(result_str)
        
        self.assertEqual(result['level'], 'ERROR')
        self.assertEqual(result['message'], 'error message')
        self.assertIn('error', result)
        self.assertIn('ValueError: Test error', result['error'])

    @patch('core.integrations.request.urlopen')
    def test_send_posthog_event_success(self, mock_urlopen):
        # Set dummy env key
        with patch.dict(os.environ, {'POSTHOG_API_KEY': 'phc_dummykey'}):
            mock_response = MagicMock()
            mock_urlopen.return_value = mock_response
            
            result = send_posthog_event('test_event', 'user_123', {'prop': 'val'})
            self.assertTrue(result)
            self.assertTrue(mock_urlopen.called)

    @patch('core.integrations.request.urlopen')
    def test_send_posthog_event_failure(self, mock_urlopen):
        with patch.dict(os.environ, {'POSTHOG_API_KEY': 'phc_dummykey'}):
            mock_urlopen.side_effect = Exception("Network timeout")
            
            result = send_posthog_event('test_event', 'user_123', {'prop': 'val'})
            self.assertFalse(result)
            self.assertTrue(mock_urlopen.called)


class MetricsAndHealthTests(TestCase):
    def setUp(self):
        self.client = Client()

    @patch('core.cache._redis_is_available')
    @patch('core.cache.get_redis_client')
    def test_metrics_endpoint_with_redis(self, mock_get_redis, mock_redis_available):
        mock_redis_available.return_value = True
        mock_redis = MagicMock()
        mock_redis.get.side_effect = lambda key: {
            "metrics:http_requests_total:2xx": "10",
            "metrics:http_requests_total:3xx": "2",
            "metrics:http_requests_total:4xx": "1",
            "metrics:http_requests_total:5xx": "0",
            "metrics:http_request_duration_seconds_bucket:0.1": "5",
            "metrics:http_request_duration_seconds_bucket:0.5": "3",
            "metrics:http_request_duration_seconds_bucket:1.0": "2",
            "metrics:http_request_duration_seconds_bucket:5.0": "0",
            "metrics:http_request_duration_seconds_bucket:inf": "10",
            "metrics:http_request_duration_seconds_sum_ms": "1200",
            "metrics:http_request_duration_seconds_count": "10"
        }.get(key, None)
        mock_get_redis.return_value = mock_redis

        response = self.client.get('/api/metrics/')
        self.assertEqual(response.status_code, 200)
        self.assertIn("pathway_users_total", response.content.decode())

    @patch('django.core.handlers.base.log_response')
    @patch('core.views.connection.cursor')
    def test_health_endpoint_db_failure(self, mock_cursor, mock_log_response):
        mock_cursor.side_effect = Exception("DB Connection Failed")
        response = self.client.get('/health/')
        self.assertEqual(response.status_code, 503)
        data = response.json()
        self.assertEqual(data['database'], 'error')
