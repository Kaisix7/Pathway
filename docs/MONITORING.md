# Документация системы мониторинга и логирования (Monitoring Stack)

Данный документ описывает структуру мониторинга, конфигурацию алертинга и формат структурированных логов в проекте Pathway.

---

## 1. Стек мониторинга (Monitoring Stack)

Система мониторинга построена на базе встроенных инструментов хостинга **Render** и интеграции с **PostHog**:

1. **Render Metrics Dashboard:** 
   * Используется для отслеживания системного состояния бэкенда (CPU, Memory/RAM, Network Traffic, Latency).
   * Позволяет контролировать использование оперативной памяти на бесплатном тарифе (лимит 512 МБ RAM) для предотвращения сбоев по нехватке памяти (OOM - Out of Memory).
2. **PostHog:**
   * Отвечает за продуктовый мониторинг, конверсию воронок и запись сессий пользователей.

---

## 2. Метрики «Четыре золотых сигнала» (4 Golden Signals)

В панели управления Render настроены и визуализируются следующие метрики:

* **Request Rate (Traffic):** Количество запросов в секунду (RPS) к API. Помогает оценить текущую активность пользователей.
* **Latency (Задержка):** Среднее время ответа бэкенда и процентили (p50, p90, p95). p95 удерживается в рамках < 200 мс.
* **Error Rate (Частота ошибок):** Процент неуспешных запросов (HTTP 5xx). Используется для детекции сбоев кода или сбоев базы данных.
* **Saturation (Насыщение):** Уровень загрузки CPU процессора и оперативной памяти RAM в процентах от лимита контейнера.

---

## 3. Настройка Алертинга (Alerting)

В системе настроены два критических алерта:

### Алерт 1: Service Down (Сайт недоступен)
* **Триггер:** Сервер Render возвращает HTTP-код ошибки или перестает отвечать на пинги проверки здоровья (`GET /api/health/`) в течение 3 последовательных проверок (период 1 минута).
* **Канал отправки:** Email на адрес администратора и Slack-уведомление через входящий вебхук (Incoming Webhook).

### Алерт 2: Error Rate > 5% (Высокий уровень ошибок)
* **Триггер:** Доля ответов с кодами HTTP 5xx превышает 5% от общего объема трафика за скользящее окно в 5 минут.
* **Канал отправки:** Slack-уведомление с логами инцидента.

---

## 4. Формат JSON-логирования (Structured Logging)

Все ключевые бизнес-события записываются в лог в формате структурированного JSON. Это позволяет автоматическим сборщикам логов легко парсить и индексировать записи.

### Пример лога успешного входа (Login Success):
```json
{
  "timestamp": "2026-06-27 17:30:15,123",
  "level": "INFO",
  "message": "successful_login email=user@example.com ip=127.0.0.1",
  "logger": "core.views",
  "path": "/Users/karina.b/Documents/GitHub/backend/core/views.py:804",
  "event": "login",
  "status": "success",
  "email": "user@example.com",
  "ip": "127.0.0.1"
}
```

### Пример лога успешной регистрации (Registration Success):
```json
{
  "timestamp": "2026-06-27 17:31:05,456",
  "level": "INFO",
  "message": "successful_registration email=user@example.com",
  "logger": "core.views",
  "path": "/Users/karina.b/Documents/GitHub/backend/core/views.py:929",
  "event": "registration",
  "status": "success",
  "email": "user@example.com",
  "role": "user",
  "company": "Pathway Corp"
}
```

### Пример лога успешной оплаты подписки (Payment Success):
```json
{
  "timestamp": "2026-06-27 17:32:20,789",
  "level": "INFO",
  "message": "payment_completed_success email=user@example.com amount=2499 session_id=cs_test_abc123",
  "logger": "core.views",
  "path": "/Users/karina.b/Documents/GitHub/backend/core/views.py:1064",
  "event": "payment",
  "status": "success",
  "email": "user@example.com",
  "amount": 2499,
  "session_id": "cs_test_abc123"
}
```

### Пример лога системной ошибки (Error):
```json
{
  "timestamp": "2026-06-27 17:33:01,012",
  "level": "ERROR",
  "message": "Error verifying Stripe session: Request failed...",
  "logger": "core.views",
  "path": "/Users/karina.b/Documents/GitHub/backend/core/views.py:1078",
  "event": "payment_error",
  "status": "error",
  "session_id": "cs_test_abc123",
  "error": "Request failed...",
  "exception": "Traceback (most recent call last):\n  File \"/Users/karina.b/Documents/GitHub/backend/core/views.py\", line 1028, in stripe_success..."
}
```
