# Backups

## PostgreSQL в Docker

В Docker данные PostgreSQL хранятся в volume `postgres_data` из `docker-compose.yml`.

Сделать backup:

```bash
docker exec pathway_db pg_dump -U pathway pathway > pathway_backup.sql
```

Восстановить backup:

```bash
docker exec -i pathway_db psql -U pathway pathway < pathway_backup.sql
```

## SQLite fallback

Если backend запускается без Docker, Django может использовать файл:

```text
backend/db.sqlite3
```

Backup SQLite делается обычным копированием файла:

```powershell
Copy-Item backend\db.sqlite3 backend\backups\db_backup.sqlite3
```

## Что важно объяснить

PostgreSQL лучше подходит для deploy и командной работы, потому что база работает как отдельный сервис.

SQLite проще для локальной разработки, но хуже подходит для production, потому что это один файл внутри проекта.
