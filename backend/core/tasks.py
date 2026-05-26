import logging

from celery import shared_task

logger = logging.getLogger(__name__)


@shared_task
def send_welcome_event(email, name):
    logger.info('celery_task=send_welcome_event status=started email=%s', email)
    logger.info('celery_task=send_welcome_event status=finished email=%s name=%s', email, name)
    return {'email': email, 'status': 'sent'}
