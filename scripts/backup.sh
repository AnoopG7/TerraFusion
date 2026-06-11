#!/usr/bin/env bash
set -euo pipefail

TERRAFUSION_HOME="/opt/terrafusion"
BACKUP_DIR="${TERRAFUSION_HOME}/backups"
RETENTION_DAYS=30
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_FILE="${BACKUP_DIR}/terrafusion-${TIMESTAMP}.sql"
BACKUP_GZ="${BACKUP_FILE}.gz"
ENV_FILE="${TERRAFUSION_HOME}/backend/.env"

mkdir -p "$BACKUP_DIR"

[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

DB_TYPE="${DB_TYPE:-sqlite}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-terrafusion}"
DB_USER="${DB_USER:-terrafusion_admin}"
DB_PASSWORD="${DB_PASSWORD:-}"
S3_BUCKET="${S3_BACKUP_BUCKET:-}"

echo "=== TerraFusion Database Backup ==="
echo "Time: $(date)"
echo "Type: $DB_TYPE"

case "$DB_TYPE" in
  sqlite)
    DB_FILE="${TERRAFUSION_HOME}/backend/data/terrafusion.db"
    if [[ ! -f "$DB_FILE" ]]; then echo "[!] DB not found"; exit 1; fi
    sqlite3 "$DB_FILE" .dump > "$BACKUP_FILE"
    ;;
  mysql)
    MYSQL_PWD="$DB_PASSWORD" mysqldump \
      -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" \
      --single-transaction --routines --triggers \
      "$DB_NAME" > "$BACKUP_FILE"
    ;;
esac

if [[ ! -s "$BACKUP_FILE" ]]; then echo "[!] Backup empty"; rm -f "$BACKUP_FILE"; exit 1; fi
echo "[✓] Dump: $(wc -l < "$BACKUP_FILE") lines"

gzip -f "$BACKUP_FILE"
echo "[✓] Compressed: $(du -h "$BACKUP_GZ" | cut -f1)"

ln -sf "$BACKUP_GZ" "${BACKUP_DIR}/terrafusion-latest.sql.gz"

find "$BACKUP_DIR" -name 'terrafusion-*.sql.gz' -type f -mtime +"$RETENTION_DAYS" -delete

if [[ -n "$S3_BUCKET" ]] && command -v aws &>/dev/null; then
  aws s3 cp "$BACKUP_GZ" "s3://${S3_BUCKET}/backups/" --storage-class STANDARD_IA
  echo "[✓] Uploaded to S3"
fi

echo "=== Backup Complete ==="
echo "File: $BACKUP_GZ"
echo "Size: $(du -h "$BACKUP_GZ" | cut -f1)"
