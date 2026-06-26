# Pathway - Production-Ready Travel Services Platform

Pathway is a production-ready mobile and web application built with Flutter and Django that simplifies user services such as visa applications, service requests, and airport pickup orders.

---

## 📱 Features

* **User Registration & Security**: JWT Authentication, RBAC (Role-Based Access Control), CAPTCHA protection, Google OAuth 2.0, and 2FA (Two-Factor Authentication).
* **Order Management**: Comprehensive order creation, status tracking, and paid/done order workflows.
* **Unified Payment Flow**: E2E Stripe Card payment & Bereke Bank callback simulation (including success/failed states and admin refunds).
* **Monitoring & Alerts**: Full VPS deployment configuration with Prometheus, Grafana, Node Exporter, and Alertmanager.
* **JSON Logging**: Every API request and response is structured into standardized JSON format for production audit trail.
* **Performance Suite**: Built-in Locust load test suite, database indexing optimizations, and query performance safeguards.

---

## 🧱 Tech Stack

* **Frontend**: Flutter (Dart)
* **Backend**: Django (Python)
* **Cache & Message Broker**: Redis
* **Database**: PostgreSQL (with optimized indexes)
* **Task Queue**: Celery
* **Monitoring**: Prometheus, Grafana, Node Exporter, Alertmanager
* **Load Testing**: Locust

---

## 🚀 Getting Started

### 1. Clone the repository
```bash
git clone https://github.com/Kaisix7/Pathway.git
cd Pathway
```

### 2. Run with Docker Compose (Includes Monitoring Stack)
```bash
docker compose up --build -d
```
This command starts:
- **Django Backend** at `http://localhost:8000`
- **PostgreSQL Database** at `localhost:5432`
- **Redis Cache & Celery Worker**
- **Prometheus** at `http://localhost:9090`
- **Grafana** at `http://localhost:3000` (Default credentials: `admin` / `admin`)
- **Alertmanager** at `http://localhost:9093`
- **Node Exporter** at `localhost:9100`

---

## 📈 Monitoring & Alerts

### 4 Golden Signals Dashboard
Access Grafana (`http://localhost:3000`) to view preconfigured panels for:
1. **Request Rate (Traffic)**: HTTP requests/sec grouped by status class.
2. **Error Rate (%)**: Percentage of 5xx server errors relative to total requests.
3. **P95 Latency**: 95th percentile response latency in seconds.
4. **Saturation (CPU & Memory)**: CPU load percentage and memory consumption statistics.

### Production Alert Rules
Prometheus Alertmanager is configured with two default alerts:
- **Service Down**: Fires when any service is unreachable for >30 seconds.
- **Error Rate > 5%**: Fires when 5xx HTTP response codes exceed 5% of total traffic.

---

## 🔄 Database Backups
A daily database backup script is located at `backend/scripts/db_backup.sh`. It outputs compressed SQL dumps into `/app/backups/`.
To execute manually:
```bash
docker compose exec backend bash /app/scripts/db_backup.sh
```

---

## 💳 Payment Integrations
- **Stripe**: E2E checkout session creation (`/api/checkout/`) and verification callbacks.
- **Bereke Bank**:
  - Checkout Simulation: `GET/POST /api/payment/bereke/checkout/`
  - Callback Webhook: `GET/POST /api/payment/bereke/callback/?session_id=<ID>&status=success|failed`
- **Refunds**: Admin endpoint `POST /api/payment/refund/` supporting both Stripe sessions and Bereke transactions.

---

## 🪵 JSON Logging System
All application logs are printed as single-line JSON format containing:
- `timestamp`, `event`, `user_id`, `request_id`, `payment_id`, `status`, `endpoint`, `response_time`, `ip`, and standard logging levels.

---

## ⚡ Performance Load Tests (Locust)
A locust file is configured to run load tests against the API endpoints:
- **Test parameters**: 100 concurrent users, spawn rate of 10 users/sec, run duration of 2 minutes.
- **Tasks**: Login flow, Health Check, Order Retrieval, Order Creation.

To run the load test headlessly and export the HTML report:
```bash
# On Linux/macOS
bash scripts/run_locust.sh

# On Windows (PowerShell)
powershell -File scripts/run_locust.ps1
```

---

## 🧪 Running Unit Tests
```bash
docker compose exec backend pytest
```
