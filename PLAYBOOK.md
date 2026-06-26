# Production Operations Runbook / Playbook

This runbook outlines standard operating procedures for resolving production incidents.

---

## Scenario 1: Server Down (Service Unreachable)

### Symptoms
- Prometheus alerts trigger: `ServiceDown`
- Root health check `/health` returns `503 Service Unavailable` or connection timeout.
- Users report `502 Bad Gateway` error on the frontend.

### Resolution Steps
1. SSH into the production server.
2. Check the status of the Docker containers:
   ```bash
   docker ps -a
   ```
3. Inspect system-level logs for the backend container:
   ```bash
   docker logs --tail 100 pathway_backend
   ```
4. Check if the server is out of memory or disk space:
   ```bash
   df -h
   free -m
   ```
5. Restart the containers to recover service:
   ```bash
   docker compose restart backend worker
   ```
6. Verify recovery by querying the health endpoint:
   ```bash
   curl -I http://localhost:8000/health
   ```

---

## Scenario 2: Payment Callback Failed

### Symptoms
- Users report paying successfully, but their accounts do not upgrade to Premium.
- Backend JSON logs show `event=payment_failed` or `api_request_failed` at endpoint `/api/payment/bereke/callback/` or `/api/stripe/success/`.

### Resolution Steps
1. Inspect the JSON logs for callback failures using grep:
   ```bash
   docker compose logs backend | grep -i "payment_failed"
   ```
2. Check for database locks or unique constraints on the Order model:
   ```bash
   docker compose exec db psql -U pathway -d pathway -c "SELECT pid, query, state FROM pg_stat_activity WHERE state != 'idle';"
   ```
3. Manually verify and sync the order status. Run Django shell to fix the order and upgrade the user manually:
   ```bash
   docker compose exec backend python manage.py shell -c "
   from core.models import Order, AppUser
   order = Order.objects.filter(order_id='<SESSION_ID>').first()
   if order:
       order.status = 'paid'
       order.save()
       AppUser.objects.filter(email=order.user_email).update(plan='premium')
       print('Order manually updated successfully')
   else:
       print('Order not found')
   "
   ```
4. Resend the callback simulation command to verify standard processing:
   ```bash
   curl -X GET "http://localhost:8000/api/payment/bereke/callback/?session_id=<SESSION_ID>&status=success"
   ```

---

## Scenario 3: Database Failure (Connection Loss or Corruption)

### Symptoms
- JSON logs show `django.db.utils.OperationalError: connection to server at "db" (172.18.0.2), port 5432 failed`.
- Metrics endpoint `/metrics` or `/health` returns `database: error`.

### Resolution Steps
1. Check if the database container is running:
   ```bash
   docker ps -f name=pathway_db
   ```
2. Inspect postgres logs:
   ```bash
   docker logs --tail 200 pathway_db
   ```
3. If PostgreSQL crashed, restart the container:
   ```bash
   docker compose restart db
   ```
4. Verify database readiness:
   ```bash
   docker compose exec db pg_isready -U pathway -d pathway
   ```
5. If database files are corrupted, restore from the latest daily backup:
   ```bash
   # Unzip the backup
   gunzip < backups/db_backup_latest.sql.gz > backups/db_backup_latest.sql
   # Restore SQL schema and data
   docker compose exec -T db psql -U pathway -d pathway < backups/db_backup_latest.sql
   ```
