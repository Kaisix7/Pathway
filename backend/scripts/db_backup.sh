#!/usr/bin/env bash
# Daily Database Backup Script
BACKUP_DIR="/app/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/db_backup_${TIMESTAMP}.sql.gz"

mkdir -p "${BACKUP_DIR}"

echo "Starting database backup..."
pg_dump -h db -U pathway -d pathway | gzip > "${BACKUP_FILE}"

# Maintain latest symlink
ln -sf "${BACKUP_FILE}" "${BACKUP_DIR}/db_backup_latest.sql.gz"

echo "Backup completed: ${BACKUP_FILE}"
