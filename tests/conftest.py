import os

import pytest
from django.test import Client


os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'backend.settings')
os.environ.setdefault('CELERY_TASK_ALWAYS_EAGER', 'True')
os.environ['TESTING'] = 'True'
os.environ['POSTHOG_API_KEY'] = ''


@pytest.fixture
def client():
    return Client()


@pytest.fixture(autouse=True)
def mock_posthog(monkeypatch):
    import core.integrations
    monkeypatch.setattr(core.integrations, 'send_posthog_event', lambda *args, **kwargs: True)

@pytest.fixture(autouse=True)
def clear_cache():
    from django.core.cache import cache
    cache.clear()
