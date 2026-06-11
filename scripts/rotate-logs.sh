#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="/var/log/terrafusion"
ROTATE_DAYS=7
DELETE_DAYS=30
TIMESTAMP=$(date +"%Y-%m-%d")

echo "=== TerraFusion Log Rotation ==="
echo "Time: $(date)"

sudo mkdir -p "${LOG_DIR}/archive"
sudo chmod 755 "${LOG_DIR}"

if command -v docker &>/dev/null; then
  echo "[*] Archiving Docker logs..."
  docker ps --format "{{.Names}}" 2>/dev/null | while read -r container; do
    LOG_FILE="${LOG_DIR}/archive/${container}-${TIMESTAMP}.log"
    docker logs "$container" --tail 5000 2>"${LOG_FILE}.err" > "${LOG_FILE}.out" 2>/dev/null || true
    if [[ -s "${LOG_FILE}.out" || -s "${LOG_FILE}.err" ]]; then
      cat "${LOG_FILE}.out" "${LOG_FILE}.err" > "$LOG_FILE" 2>/dev/null
      rm -f "${LOG_FILE}.out" "${LOG_FILE}.err"
      gzip -f "$LOG_FILE"
      echo "  Compressed: ${LOG_FILE}.gz"
    else
      rm -f "${LOG_FILE}.out" "${LOG_FILE}.err"
    fi
  done
  docker ps -q 2>/dev/null | while read -r cid; do
    LOG_PATH=$(docker inspect --format='{{.LogPath}}' "$cid" 2>/dev/null || true)
    [[ -n "$LOG_PATH" && -f "$LOG_PATH" ]] && sudo truncate -s 0 "$LOG_PATH" 2>/dev/null || true
  done
fi

if command -v journalctl &>/dev/null; then
  sudo journalctl --rotate 2>/dev/null || true
  sudo journalctl --vacuum-time=7d 2>/dev/null || true
fi

find "${LOG_DIR}/archive" -name '*.gz' -type f -mtime +"$DELETE_DAYS" -delete

echo "=== Rotation Complete ==="
echo "Archive: ${LOG_DIR}/archive"
echo "Size: $(du -sh "${LOG_DIR}/archive" 2>/dev/null | cut -f1 || echo '0')"
