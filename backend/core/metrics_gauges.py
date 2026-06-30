"""Business metric gauges for Prometheus.

These gauges are updated periodically by a Celery Beat task
(every 30 minutes) to avoid hitting the database on every
Prometheus scrape (every 10 seconds).

The ``refresh_business_gauges_if_stale()`` helper is also called
from the ``/metrics`` view as a safety net — it only queries the DB
if the gauges have never been set (first startup before Celery Beat
kicks in).
"""
import logging
import time

from prometheus_client import Gauge

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Gauge definitions
# ---------------------------------------------------------------------------
USERS_TOTAL = Gauge('pathway_users_total', 'Total registered users')
ORDERS_TOTAL = Gauge('pathway_orders_total', 'Total orders')
EVENTS_TOTAL = Gauge('pathway_events_total', 'Total tracked events')
ACTIVATION_TOTAL = Gauge('pathway_activation_total', 'Total activation events')
PAID_ORDERS_TOTAL = Gauge('pathway_paid_orders_total', 'Total paid/done orders')

CONVERSION_RATE = Gauge('pathway_conversion_rate_percent', 'Conversion rate of premium users')
MRR_USD = Gauge('pathway_mrr_usd', 'Monthly recurring revenue in USD')
CHURN_RATE = Gauge('pathway_churn_rate_percent', 'Subscription cancellation rate')

DAU = Gauge('pathway_dau', 'Daily active users')
MAU = Gauge('pathway_mau', 'Monthly active users')
STICKINESS = Gauge('pathway_stickiness_ratio_percent', 'DAU/MAU stickiness percentage')

# ---------------------------------------------------------------------------
# Refresh logic
# ---------------------------------------------------------------------------
_last_refresh = 0  # epoch timestamp of last successful refresh
STALE_THRESHOLD = 60 * 30  # 30 minutes — same as Celery Beat interval


def refresh_business_gauges():
    """Query the DB and update all business gauges.

    Called by the Celery Beat task ``update_business_metrics``.
    """
    global _last_refresh

    try:
        from .models import AppUser, AirportOrder, AppEvent
        from .views import _calculate_kpi_values

        USERS_TOTAL.set(AppUser.objects.count())
        ORDERS_TOTAL.set(AirportOrder.objects.count())
        EVENTS_TOTAL.set(AppEvent.objects.count())
        ACTIVATION_TOTAL.set(AppEvent.objects.filter(event_name='activation').count())
        PAID_ORDERS_TOTAL.set(
            AirportOrder.objects.filter(order_status=AirportOrder.STATUS_DONE).count()
        )

        kpis = _calculate_kpi_values()
        CONVERSION_RATE.set(kpis['conversion_rate_percent'])
        MRR_USD.set(kpis['mrr_usd'])
        CHURN_RATE.set(kpis['churn_rate_percent'])
        DAU.set(kpis['dau'])
        MAU.set(kpis['mau'])
        STICKINESS.set(kpis['stickiness_ratio_percent'])

        _last_refresh = time.time()
        logger.info('business_gauges_refreshed')
    except Exception:
        logger.exception('business_gauges_refresh_failed')


def refresh_business_gauges_if_stale():
    """Refresh only when gauges have never been set or are very stale.

    This is a safety net for the ``/metrics`` view — normally the
    Celery Beat task keeps the gauges fresh.
    """
    if time.time() - _last_refresh > STALE_THRESHOLD:
        refresh_business_gauges()
