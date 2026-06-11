#!/usr/bin/env bash
set -euo pipefail

TERRAFUSION_HOME="/opt/terrafusion"
DEPLOY_USER="terrafusion"
DEPLOY_GROUP="terrafusion"

echo "=== TerraFusion File Permission Setup ==="
echo "Target: $TERRAFUSION_HOME"

if [[ ! -d "$TERRAFUSION_HOME" ]]; then
  echo "[!] $TERRAFUSION_HOME does not exist. Run server-init.sh first."
  exit 1
fi

if ! id "$DEPLOY_USER" &>/dev/null; then
  sudo useradd --no-create-home --shell /sbin/nologin "$DEPLOY_USER"
fi
if ! getent group "$DEPLOY_GROUP" &>/dev/null; then
  sudo groupadd "$DEPLOY_GROUP"
fi

sudo chown -R "$DEPLOY_USER:$DEPLOY_GROUP" "$TERRAFUSION_HOME"
sudo find "$TERRAFUSION_HOME" -type d -exec chmod 755 {} +
sudo find "$TERRAFUSION_HOME" -type f -exec chmod 644 {} +

if [[ -d "$TERRAFUSION_HOME/scripts" ]]; then
  sudo find "$TERRAFUSION_HOME/scripts" -name '*.sh' -exec chmod 755 {} +
fi

ENV_FILE="$TERRAFUSION_HOME/backend/.env"
if [[ -f "$ENV_FILE" ]]; then
  sudo chmod 600 "$ENV_FILE"
  sudo chown "$DEPLOY_USER:$DEPLOY_GROUP" "$ENV_FILE"
fi

DB_FILE="$TERRAFUSION_HOME/backend/data/terrafusion.db"
if [[ -f "$DB_FILE" ]]; then
  sudo chmod 644 "$DB_FILE"
fi

echo "[✓] Permissions configured."
