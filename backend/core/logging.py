import json
import logging
from datetime import datetime

class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_data = {
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'event': getattr(record, 'event', 'log_message'),
            'user_id': getattr(record, 'user_id', None),
            'request_id': getattr(record, 'request_id', None),
            'payment_id': getattr(record, 'payment_id', None),
            'status': getattr(record, 'status', None),
            'endpoint': getattr(record, 'endpoint', None),
            'response_time': getattr(record, 'response_time', None),
            'ip': getattr(record, 'ip', None),
            'level': record.levelname,
            'message': record.getMessage(),
        }
        if record.exc_info:
            log_data['error'] = self.formatException(record.exc_info)
        return json.dumps(log_data)
