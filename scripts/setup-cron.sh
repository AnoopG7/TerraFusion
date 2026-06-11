#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="/opt/terrafusion/scripts"
CRON_FILE="/tmp/terrafusion-crontab"

echo "=== TerraFusion Cron Setup ==="

echo "[*] Verifying scripts..."
for script in health-check.sh backup.sh rotate-logs.sh; do
  [[ -f "${SCRIPTS_DIR}/${script}" ]] && echo "  ✓ $script" || echo "  ✗ $script NOT found"
done

cat > "$CRON_FILE" << EOF
# TerraFusion Cron Jobs
# Managed by setup-cron.sh

# Health check every 5 minutes
*/5 * * * * ${SCRIPTS_DIR}/health-check.sh > /dev/null 2>&1

# Database backup daily at 2:00 AM
0 2 * * * ${SCRIPTS_DIR}/backup.sh > /dev/null 2>&1

# Log rotation weekly on Sunday at 3:00 AM
0 3 * * 0 ${SCRIPTS_DIR}/rotate-logs.sh > /dev/null 2>&1

# Clean Docker unused resources daily at 4:00 AM
0 4 * * * docker system prune -f --volumes > /dev/null 2>&1
EOF

crontab "$CRON_FILE" 2>&1 || sudo crontab -u "$(whoami)" "$CRON_FILE" 2>/dev/null || {
  echo "[✗] Could not install crontab. Run: crontab ${CRON_FILE}"
  exit 1
}
rm -f "$CRON_FILE"

echo "[✓] Crontab installed:"
echo "  Every 5 min → health-check.sh"
echo "  Daily 2am   → backup.sh"
echo "  Sun 3am     → rotate-logs.sh"
echo "  Daily 4am   → docker system prune"
