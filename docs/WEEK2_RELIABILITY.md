# Week 2: CI/CD Reliability Evidence

## Что уже реализовано

- CI запускается на `push` и `pull_request`.
- Backend тесты запускаются через `pytest -v` с покрытием минимум 70%.
- Flutter проверяется через `flutter pub get` и `flutter test`.
- Docker запускает `backend`, `PostgreSQL`, `Redis` и `Celery worker`.
- `/health` возвращает состояние базы данных и кэша.
- Redis кэширует 3 endpoint: `/api/metrics/`, `/api/analytics/retention/`, `/api/orders/`.
- Login rate limit возвращает `429` после 5 попыток.
- N+1 в retention endpoint исправлен: события пользователей выбираются одним запросом.
- Добавлены индексы в миграции `backend/core/migrations/0008_reliability_indexes.py`.

## Команды для проверки

### 1. Тесты и coverage

```powershell
python -m pytest -v
```

Ожидаемый результат:

```text
11 passed
Required test coverage of 70% reached
```

### 2. Docker запуск

```powershell
docker compose up --build
```

После запуска должны быть контейнеры:

```powershell
docker compose ps
```

Ожидаемо: `backend`, `db`, `redis`, `worker`.

### 3. Health check

```powershell
curl.exe -i http://localhost:8000/health
```

Ожидаемо:

```text
HTTP/1.1 200 OK
```

JSON должен содержать:

```json
{
  "status": "ok",
  "database": "ok",
  "cache": "ok"
}
```

### 4. Celery worker

Создать регистрацию, чтобы отправилась фоновая задача:

```powershell
curl.exe -X POST http://localhost:8000/api/register/ -H "Content-Type: application/json" -d "{\"name\":\"Aida\",\"email\":\"celery-demo@example.com\"}"
```

Показать логи worker:

```powershell
docker compose logs worker
```

В логах должно быть:

```text
celery_task=send_welcome_event status=started
celery_task=send_welcome_event status=finished
```

### 5. Redis cache: до и после

```powershell
curl.exe -w "time=%{time_total} cache=%{header:x-cache}\n" -o NUL -s http://localhost:8000/api/metrics/
curl.exe -w "time=%{time_total} cache=%{header:x-cache}\n" -o NUL -s http://localhost:8000/api/metrics/
```

Повторить для других endpoint:

```powershell
curl.exe -w "time=%{time_total} cache=%{header:x-cache}\n" -o NUL -s http://localhost:8000/api/analytics/retention/
curl.exe -w "time=%{time_total} cache=%{header:x-cache}\n" -o NUL -s http://localhost:8000/api/orders/
```

Ожидаемо: первый запрос `MISS`, второй запрос `HIT`.

### 6. Rate limit 429

```powershell
1..6 | ForEach-Object {
  curl.exe -s -o NUL -w "%{http_code}`n" -X POST http://localhost:8000/api/login/ -H "Content-Type: application/json" -d "{\"email\":\"celery-demo@example.com\"}"
}
```

Ожидаемо: первые 5 попыток не `429`, шестая попытка `429`.

### 7. Индексы и N+1

Миграция с индексами:

```text
backend/core/migrations/0008_reliability_indexes.py
```

Исправление N+1 находится в:

```text
backend/core/views.py
```

Endpoint `/api/analytics/retention/` больше не делает запрос событий внутри цикла по пользователям.

## Что нужно сделать вручную

- В Jira переместить CICD тикеты в `Done`.
- В Jira добавить комментарии со ссылкой на GitHub PR, CI run и Render deploy.
- В Confluence обновить документ Week 2 Reliability и вставить выводы команд из этого файла.

## Короткая схема

feature branch -> Pull Request -> CI pytest/Flutter/Docker -> merge в main -> Render deploy -> доказательства в Jira/Confluence
