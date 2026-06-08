# Security Hardening Implementation

## Проектная структура безопасности

- `backend/backend/settings.py` — загрузка секретов из `.env`, JWT конфигурация, жесткие security-параметры и CORS-конфиг.
- `backend/core/auth.py` — JWT генерация и декодирование, Google OAuth 2.0 обмен кодом, CAPTCHA, RBAC и роли.
- `backend/core/models.py` — модель `AppUser` с полями `role`, `password_hash`, `google_sub`.
- `backend/core/middleware.py` — заголовки безопасности и маскирование чувствительных данных.
- `backend/core/views.py` — безопасные API-эндпоинты с проверкой токена, фильтрацией по владельцу, CAPTCHA и OAuth.
- `backend/core/tests.py` — тесты для регистрации, JWT, RBAC, доступа к заказам и CAPTCHA.
- `backend/.env.example` — пример безопасной конфигурации секретов.
- `docs/nginx_security.conf` — пример правильной настройки заголовков безопасности Nginx.

## Реализация требований

### 1. Google OAuth 2.0

- `/api/oauth/google/` принимает `code` и `redirect_uri`.
- Через Google token endpoint (`https://oauth2.googleapis.com/token`) обменивает авторизационный код на `access_token`.
- Через userinfo endpoint (`https://openidconnect.googleapis.com/v1/userinfo`) получает email пользователя.
- В `AppUser` сохраняется `google_sub` и создаются JWT-токены.

### 2. JWT токены

- `core/auth.py` создаёт access и refresh JWT токены.
- Access токен содержит `sub`, `email`, `role`, `type`, `iat`, `exp`.
- `decode_jwt` проверяет подпись и тип токена.
- `/api/refresh-token/` обновляет access токен по refresh токену.

### 3. RBAC

- `AppUser` теперь имеет роли: `guest`, `user`, `admin`.
- Защищены админские эндпоинты: `/api/metrics/`, `/api/analytics/retention/`.
- `orders` и `pay_order` проверяют права и доступ только владельца или администратора.

### 4. CAPTCHA

- `/api/captcha/` выдаёт математическую задачу.
- В `register` и `login` требуется `captcha_id` и `captcha_answer`.
- В `core/auth.py` проверка CAPTCHA хранится в кеше и одноразовая.

### 5. OWASP Top 10

- A01 Broken Access Control: фильтрация заказов по текущему пользователю, запрет оплаты чужого заказа.
- A03 Sensitive Data Exposure: хранение секретов в `.env`, защищённые cookie и HSTS, маскирование логов.
- A05 Security Misconfiguration: отключён `CORS_ALLOW_ALL_ORIGINS` по умолчанию, добавлены security headers.
- A07 Identification and Authentication Failures: JWT, rate limiting, CAPTCHA, password hashing, 2FA.

### 6–15. Дополнения

- Middleware для security headers и маскирования входящих json данных.
- Логирование безопасности: неудачные логины, CAPTCHA, IP.
- .env пример для secret management.
- Пример правильного Nginx-конфига в `docs/nginx_security.conf`.

## Ключевые сценарии безопасности

1. Уязвимость: любой мог получить заказы по `user_email`.
   - Исправление: только админ может передавать email, пользователь видит только свои.

2. Уязвимость: любой мог оплачивать заказ.
   - Исправление: проверка владельца заказа или админа перед изменением статуса.

3. Уязвимость: слабые пароли и регистрация без проверки.
   - Исправление: обязательный пароль, хеширование, CAPTCHA.

4. Уязвимость: утечка секретов в коде.
   - Исправление: `SECRET_KEY`, JWT secret, Google OAuth данные берутся из `.env`.

---

## Как запустить

1. Скопируй`backend/.env.example` в `backend/.env` и заполни значения.
2. Установи зависимости `pip install -r backend/requirements.txt`.
3. Выполни миграции `python backend/manage.py migrate`.
4. Запусти сервер `python backend/manage.py runserver`.
