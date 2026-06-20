import os

import pytest
from django.test import Client


os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'backend.settings')
os.environ.setdefault('CELERY_TASK_ALWAYS_EAGER', 'True')


@pytest.fixture
def client():
    return Client()


@pytest.fixture(autouse=True)
def clear_cache():
    from django.core.cache import cache
    cache.clear()
