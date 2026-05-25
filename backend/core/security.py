SENSITIVE_KEYS = {
    'password',
    'token',
    'authorization',
    'email',
    'contact',
    'passport',
    'otp_code',
}


def mask_value(key, value):
    if value is None:
        return value

    key_lower = str(key).lower()
    if key_lower not in SENSITIVE_KEYS:
        return value

    text = str(value)
    if len(text) <= 4:
        return '*' * len(text)
    return f"{text[:2]}***{text[-2:]}"


def mask_payload(payload):
    if isinstance(payload, dict):
        return {key: mask_value(key, value) for key, value in payload.items()}
    return payload
