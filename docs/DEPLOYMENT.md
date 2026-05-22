# Deploy проекта

## Локальный запуск через Docker

Из корня проекта:

```powershell
docker compose up --build
```

После запуска будут доступны:

- Django API: `http://localhost:8000`
- PostgreSQL: `localhost:5432`

## Deploy на Render или Railway

Рекомендуемый вариант для backend:

1. Создать PostgreSQL database.
2. Создать web service из этого GitHub repository.
3. Указать backend как build context или root directory.
4. Использовать `backend/Dockerfile`.
5. Добавить environment variables:

```text
DJANGO_ALLOWED_HOSTS=your-domain.onrender.com,your-domain.up.railway.app
POSTGRES_DB=...
POSTGRES_USER=...
POSTGRES_PASSWORD=...
POSTGRES_HOST=...
POSTGRES_PORT=5432
DJANGO_SECURE_SSL_REDIRECT=True
DJANGO_SESSION_COOKIE_SECURE=True
DJANGO_CSRF_COOKIE_SECURE=True
```

6. Выполнить миграции при deploy:

```bash
python manage.py migrate
```

7. В Flutter заменить локальный API URL на HTTPS URL backend.

## HTTPS

Render и Railway обычно дают HTTPS автоматически для публичного домена.
