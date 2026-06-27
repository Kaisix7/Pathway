import json
import logging

class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_data = {
            'timestamp': self.formatTime(record, self.datefmt),
            'level': record.levelname,
            'message': record.getMessage(),
            'logger': record.name,
            'path': f"{record.pathname}:{record.lineno}",
        }
        
        # Extract any extra attributes passed to the logger
        standard_attrs = {
            'args', 'asctime', 'created', 'exc_info', 'exc_text', 'filename',
            'funcName', 'levelname', 'levelno', 'lineno', 'module',
            'msecs', 'message', 'msg', 'name', 'pathname', 'process',
            'processName', 'relativeCreated', 'stack_info', 'thread', 'threadName'
        }
        for key, value in record.__dict__.items():
            if key not in standard_attrs:
                log_data[key] = value

        if record.exc_info:
            log_data['exception'] = self.formatException(record.exc_info)
            
        return json.dumps(log_data)
