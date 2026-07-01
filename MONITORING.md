# 📊 Pathway — Мониторинг и Observability

Полная документация по настройке и использованию системы мониторинга проекта Pathway.

## Содержание

1. [Архитектура](#архитектура)
2. [Быстрый старт](#быстрый-старт)
3. [Настройка Telegram-уведомлений](#настройка-telegram-уведомлений)
4. [Компоненты](#компоненты)
5. [Нагрузочное тестирование](#нагрузочное-тестирование)
6. [Проверка работы](#проверка-работы)
7. [Устранение неполадок](#устранение-неполадок)

---

## Архитектура

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Backend   │────▶│  Prometheus  │────▶│   Grafana   │
│  /metrics   │     │  (scrape)    │     │ (dashboards)│
└─────────────┘     └──────┬───────┘     └─────────────┘
                           │
┌─────────────┐            │         ┌───────────────┐
│Node Exporter│────────────┤         │ Alertmanager  │
│ (host CPU,  │            │────────▶│  (Telegram)   │
│  RAM, disk) │            │         └───────┬───────┘
└─────────────┘            │                 │
                           │                 ▼
┌─────────────┐            │         ┌───────────────┐
│  cAdvisor   │────────────┘         │   Telegram    │
│ (containers)│                      │   Bot API     │
└─────────────┘                      └───────────────┘
```

### Стек

| Компонент | Порт | Назначение |
|-----------|------|------------|
| Backend | 8000 | Django API + `/metrics` endpoint |
| Prometheus | 9090 | Сбор и хранение метрик |
| Grafana | 3000 | Визуализация (дашборды) |
| Alertmanager | 9093 | Управление алертами → Telegram |
| Node Exporter | 9100 | Метрики хоста (CPU, RAM, disk) |
| cAdvisor | 8080 | Метрики контейнеров |
| Celery Beat | — | Обновление бизнес-метрик каждые 30 мин |

---

## Быстрый старт

### 1. Настроить переменные окружения

Создайте файл `.env` в корне проекта:

```bash
# Telegram (см. раздел ниже)
TELEGRAM_BOT_TOKEN=123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11
TELEGRAM_CHAT_ID=-1001234567890

# Django (опционально)
DJANGO_SECRET_KEY=your-production-secret-key
DJANGO_DEBUG=False
```

### 2. Запустить весь стек

```bash
docker-compose up -d --build
```

### 3. Проверить статус

```bash
docker-compose ps
```

Все контейнеры должны быть в состоянии `Up (healthy)`.

### 4. Открыть интерфейсы

| Сервис | URL | Логин |
|--------|-----|-------|
| Backend API | http://localhost:8000 | — |
| Prometheus | http://localhost:9090 | — |
| Grafana | http://localhost:3000 | admin / admin |
| Alertmanager | http://localhost:9093 | — |
| cAdvisor | http://localhost:8080 | — |

---

## Настройка Telegram-уведомлений

### Шаг 1: Создать бота

1. Откройте Telegram, найдите **@BotFather**
2. Отправьте `/newbot`
3. Выберите имя и username для бота
4. Скопируйте **token** (формат: `123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11`)

### Шаг 2: Получить Chat ID

**Для личных сообщений:**
1. Отправьте боту любое сообщение
2. Откройте: `https://api.telegram.org/bot<TOKEN>/getUpdates`
3. Найдите `"chat":{"id": 123456789}` — это ваш Chat ID

**Для группового чата:**
1. Добавьте бота в группу
2. Отправьте сообщение в группу
3. Откройте: `https://api.telegram.org/bot<TOKEN>/getUpdates`
4. Chat ID будет отрицательным: `-1001234567890`

### Шаг 3: Добавить в .env

```bash
TELEGRAM_BOT_TOKEN=123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11
TELEGRAM_CHAT_ID=-1001234567890
```

### Шаг 4: Перезапустить Alertmanager

```bash
docker-compose restart alertmanager
```

---

## Компоненты

### Prometheus Метрики (`/metrics`)

Backend экспортирует следующие метрики:

#### HTTP-метрики (автоматические, через middleware)

| Метрика | Тип | Labels | Описание |
|---------|-----|--------|----------|
| `pathway_http_requests_total` | Counter | method, endpoint, status_class | Общее число HTTP-запросов |
| `pathway_http_request_duration_seconds` | Histogram | method, endpoint | Время ответа (buckets: 50ms–10s) |
| `pathway_active_requests` | Gauge | — | Текущие in-flight запросы |
| `pathway_app_info` | Info | version, framework | Метаданные приложения |

#### Бизнес-метрики (обновляются каждые 30 мин через Celery Beat)

| Метрика | Тип | Описание |
|---------|-----|----------|
| `pathway_users_total` | Gauge | Зарегистрированные пользователи |
| `pathway_orders_total` | Gauge | Общее число заказов |
| `pathway_events_total` | Gauge | Отслеживаемые события |
| `pathway_dau` | Gauge | Дневные активные пользователи |
| `pathway_mau` | Gauge | Месячные активные пользователи |
| `pathway_mrr_usd` | Gauge | Месячный доход (MRR) |
| `pathway_conversion_rate_percent` | Gauge | Конверсия |
| `pathway_churn_rate_percent` | Gauge | Отток |

### Алерты

| Алерт | Условие | Severity | Задержка |
|-------|---------|----------|----------|
| ServiceDown | `up{job="backend"} == 0` | critical | 1 мин |
| HighErrorRate | Error Rate > 5% | critical | 1 мин |
| HighLatency | P95 > 500ms | critical | 2 мин |
| HighCPUUsage | CPU > 80% | critical | 5 мин |
| HighMemoryUsage | RAM > 80% | critical | 5 мин |
| DiskSpaceLow | Диск < 20% | warning | 5 мин |
| ContainerRestarting | Контейнер перезапущен | warning | 0 мин |

### Grafana Дашборд

Дашборд **"Pathway — Production Observability"** содержит 12 панелей:

**Stat-панели (верхняя строка):**
- App Status (UP/DOWN)
- Active Users (DAU)
- Active Requests (in-flight)
- Registered Users

**Time Series (основные):**
- Request Rate (RPS) по status_class
- Error Rate (%) — 4xx и 5xx отдельно
- Latency — P50, P95, P99
- Latency by Endpoint (P95)

**Saturation:**
- Host CPU Usage (%)
- Host Memory Usage (%)
- Container CPU Usage (cAdvisor)
- Container Memory Usage (cAdvisor)

---

## Нагрузочное тестирование

### Установка Locust

```bash
pip install locust
```

### Запуск Web UI

```bash
locust -f locustfile.py --host=http://localhost:8000
```

Откройте http://localhost:8089 и настройте:
- **Number of users**: 50–100
- **Spawn rate**: 5–10

### Запуск в CLI (без UI)

```bash
locust -f locustfile.py \
    --host=http://localhost:8000 \
    --users 50 \
    --spawn-rate 5 \
    --run-time 5m \
    --headless
```

### Сценарии (с весами)

| Сценарий | Вес | Тег | Описание |
|----------|-----|-----|----------|
| health_check | 10 | read | GET /health/ |
| get_profile | 5 | read | GET /api/profile/ |
| browse_orders | 5 | read | GET /api/orders/ |
| get_metrics | 2 | read | GET /metrics/ |
| get_kpi | 2 | read | GET /api/analytics/kpi/ |
| create_order | 3 | write | POST /api/orders/ |
| track_event | 2 | write | POST /api/events/ |
| re_login | 1 | auth | POST /api/login/ |
| checkout_flow | 1 | checkout | GET /api/checkout/ |

### Запуск только определённых сценариев

```bash
# Только чтение
locust -f locustfile.py --host=http://localhost:8000 --tags read

# Только запись
locust -f locustfile.py --host=http://localhost:8000 --tags write
```

---

## Проверка работы

### 1. Метрики Backend

```bash
curl -s http://localhost:8000/metrics | head -30
```

Ожидаемый результат — Prometheus-формат с метриками:
```
# HELP pathway_http_requests_total Total number of HTTP requests
# TYPE pathway_http_requests_total counter
pathway_http_requests_total{endpoint="/health",method="GET",status_class="2xx"} 5.0
...
```

### 2. Prometheus Targets

Откройте http://localhost:9090/targets

Все targets должны быть в состоянии **UP**:
- `backend` (endpoint: backend:8000)
- `node-exporter` (endpoint: node-exporter:9100)
- `cadvisor` (endpoint: cadvisor:8080)
- `prometheus` (endpoint: localhost:9090)

### 3. Prometheus Alerts

Откройте http://localhost:9090/alerts

Все 7 правил должны быть загружены и в состоянии **inactive** (зелёные).

### 4. Alertmanager

```bash
curl -s http://localhost:9093/api/v2/status | python -m json.tool
```

Проверьте, что `config` содержит `telegram_configs`.

### 5. Grafana

1. Откройте http://localhost:3000 (admin / admin)
2. Перейдите в **Dashboards** → **Pathway — Production Observability**
3. Все панели должны отображать данные

### 6. Telegram — тест алертов

Самый простой способ проверить:

```bash
# Остановить backend — через ~1 мин сработает ServiceDown
docker-compose stop backend

# Проверить Alertmanager
curl http://localhost:9093/api/v2/alerts

# Запустить backend обратно
docker-compose start backend
```

Ожидание:
- Через ~1 мин: 🚨 **CRITICAL ALERT** — ServiceDown в Telegram
- После запуска: ✅ **RESOLVED** — ServiceDown в Telegram

---

## Устранение неполадок

### Метрики не появляются в Prometheus

```bash
# Проверить, что backend отвечает
curl http://localhost:8000/metrics

# Проверить логи Prometheus
docker-compose logs prometheus | tail -20
```

### Алерты не приходят в Telegram

```bash
# Проверить конфиг Alertmanager
docker-compose exec alertmanager cat /etc/alertmanager/alertmanager.yml

# Проверить логи
docker-compose logs alertmanager | tail -20

# Проверить, что бот может отправлять сообщения
curl "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage?chat_id=${TELEGRAM_CHAT_ID}&text=Test"
```

### cAdvisor не запускается на Windows/Mac

cAdvisor требует доступа к `/proc`, `/sys`, `/var/lib/docker` — это работает **только на Linux**.

На Windows/Mac можно закомментировать сервис `cadvisor` в `docker-compose.yml`. Метрики хоста (CPU/RAM) от Node Exporter будут работать.

### Celery Beat не обновляет метрики

```bash
# Проверить логи Beat
docker-compose logs beat | tail -20

# Убедиться, что worker запущен
docker-compose logs worker | tail -20
```

---

## Зависимости

### Python (добавлены в requirements.txt)

```
prometheus_client
```

### Docker-образы

| Образ | Версия |
|-------|--------|
| prom/prometheus | latest |
| grafana/grafana | latest |
| prom/node-exporter | latest |
| prom/alertmanager | v0.28.1 |
| gcr.io/cadvisor/cadvisor | latest |

### Для нагрузочного тестирования (локально)

```bash
pip install locust
```
