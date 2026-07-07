# Locust Load Test — Результаты и инструкция

## Как запустить

### Локально (Docker)
```bash
docker compose up -d
pip install locust
locust -f locustfile.py --host=http://localhost:8000 --users 50 --spawn-rate 10 -t 2m --headless --csv=results/locust
```

### На проде (Render)
```bash
locust -f locustfile.py --host=https://pathway-backend-htas.onrender.com --users 50 --spawn-rate 10 -t 2m --headless --csv=results/locust
```

### Через UI
```bash
locust -f locustfile.py --host=http://localhost:8000
# Откройте http://localhost:8089
# Users: 50, Spawn rate: 10
```

---

## Критерии прохождения

| Метрика | Порог | Статус |
|---------|-------|--------|
| Кол-во юзеров | ≥ 50 | |
| Failure rate | < 1% | |
| p95 latency | < 500ms | |

---

## Шаблон результатов

> Заполните после прогона теста

**Дата прогона:** ____-__-__

**Окружение:** localhost / Render prod

| Метрика | Значение | Результат |
|---------|----------|-----------|
| Всего запросов | | |
| Failure rate | | ✅ / ❌ |
| Avg latency | | |
| p50 latency | | |
| p95 latency | | ✅ / ❌ |
| p99 latency | | |
| RPS (requests/sec) | | |

**Скриншот Locust UI:**
_(вставьте скриншот)_

**Вывод:** _(пройден / не пройден)_
