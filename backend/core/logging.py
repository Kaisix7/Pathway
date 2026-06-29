import json
import logging
from datetime import datetime, timezone

class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_data = {
            'timestamp': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
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
        
        # Merge all dynamic extra attributes
        standard_attrs = {
            'args', 'asctime', 'created', 'exc_info', 'exc_text', 'filename',
            'funcName', 'levelname', 'levelno', 'lineno', 'module',
            'msecs', 'message', 'msg', 'name', 'pathname', 'process',
            'processName', 'relativeCreated', 'stack_info', 'thread', 'threadName',
            'event', 'user_id', 'request_id', 'payment_id', 'status', 'endpoint',
            'response_time', 'ip'
        }
        for key, value in record.__dict__.items():
            if key not in standard_attrs:
                log_data[key] = value

        if record.exc_info:
            log_data['error'] = self.formatException(record.exc_info)
            
        return json.dumps(log_data)
