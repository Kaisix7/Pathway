import json
import logging
import os
import time

import redis

logger = logging.getLogger(__name__)

_memory_cache = {}
_redis_unavailable_until = 0


def _redis_is_available():
    return time.time() >= _redis_unavailable_until


def _mark_redis_unavailable():
    global _redis_unavailable_until
    _redis_unavailable_until = time.time() + 30


def get_redis_client():
    return redis.Redis.from_url(
        os.getenv('REDIS_URL', 'redis://localhost:6379/0'),
        decode_responses=True,
        socket_connect_timeout=1,
        socket_timeout=1,
    )


def cache_get(key):
    if _redis_is_available():
        try:
            value = get_redis_client().get(key)
            if value is not None:
                return json.loads(value)
        except redis.RedisError as exc:
            _mark_redis_unavailable()
            logger.warning('redis_cache_get_failed key=%s error=%s', key, exc)

    cached = _memory_cache.get(key)
    if not cached:
        return None

    expires_at, value = cached
    if expires_at < time.time():
        _memory_cache.pop(key, None)
        return None

    return value


def cache_set(key, value, ttl=300):
    if _redis_is_available():
        try:
            get_redis_client().setex(key, ttl, json.dumps(value))
            return
        except redis.RedisError as exc:
            _mark_redis_unavailable()
            logger.warning('redis_cache_set_failed key=%s error=%s', key, exc)

    _memory_cache[key] = (time.time() + ttl, value)


def cache_delete(key):
    if _redis_is_available():
        try:
            get_redis_client().delete(key)
        except redis.RedisError as exc:
            _mark_redis_unavailable()
            logger.warning('redis_cache_delete_failed key=%s error=%s', key, exc)
    _memory_cache.pop(key, None)


def cache_status():
    try:
        get_redis_client().ping()
        return 'ok'
    except redis.RedisError:
        return 'memory-fallback'
