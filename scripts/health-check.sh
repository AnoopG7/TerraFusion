#!/usr/bin/env bash
set -euo pipefail

DISK_WARN_PCT=80
MEM_WARN_PCT=80
ALERT_LOG="/var/log/terrafusion/health-alerts.log"

now() { date +"%Y-%m-%d %H:%M:%S"; }
mkdir -p "$(dirname "$ALERT_LOG")" 2>/dev/null || true

alert() {
  local level="$1" message="$2"
  echo "[$(now)] [$level] $message" | tee -a "$ALERT_LOG"
}

echo "=== TerraFusion Health Check @ $(now) ==="
FAILED=0

echo "  1. API HEALTH"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://localhost:30080/api/health 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  echo "   [✓] API is healthy (HTTP $HTTP_CODE)"
else
  echo "   [✗] API returned HTTP $HTTP_CODE"
  alert "CRITICAL" "API health check failed: HTTP $HTTP_CODE"
  FAILED=$((FAILED + 1))
fi

echo "  2. KUBERNETES PODS"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if command -v kubectl &>/dev/null; then
  BACKEND_PODS=$(kubectl get pods -n terrafusion -l app=backend --field-selector=status.phase=Running 2>/dev/null | grep -c "backend" || true)
  FRONTEND_PODS=$(kubectl get pods -n terrafusion -l app=frontend --field-selector=status.phase=Running 2>/dev/null | grep -c "frontend" || true)
  if [[ "$BACKEND_PODS" -gt 0 ]]; then
    echo "   [✓] Backend pods running ($BACKEND_PODS)"
  else
    echo "   [✗] Backend pods NOT running"
    FAILED=$((FAILED + 1))
  fi
  if [[ "$FRONTEND_PODS" -gt 0 ]]; then
    echo "   [✓] Frontend pods running ($FRONTEND_PODS)"
  else
    echo "   [✗] Frontend pods NOT running"
    FAILED=$((FAILED + 1))
  fi
fi

echo "  3. APPLICATION RESPONSE VALIDITY"
RESPONSE=$(curl -s --max-time 5 http://localhost:30080/api/health 2>/dev/null || echo '{"status":"error"}')
STATUS=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))" 2>/dev/null || echo "unknown")
if [[ "$STATUS" == "ok" ]]; then
  echo "   [✓] Backend API response valid"
else
  echo "   [✗] Backend API returned unexpected status: $STATUS"
  FAILED=$((FAILED + 1))
fi

echo "  4. k3s KUBERNETES"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if command -v kubectl &>/dev/null; then
  kubectl get nodes 2>/dev/null | grep -q Ready && echo "   [✓] k3s nodes ready" || { echo "   [✗] k3s nodes not ready"; FAILED=$((FAILED + 1)); }
  kubectl get pods -n terrafusion 2>/dev/null | grep -q Running && echo "   [✓] App pods running" || { echo "   [✗] App pods not running"; }
fi

echo "  5. INFRASTRUCTURE SERVICES"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if command -v kubectl &>/dev/null; then
  ES_PODS=$(kubectl get pods -n logging -l app=elasticsearch-master --field-selector=status.phase=Running 2>/dev/null | grep -c "elasticsearch-master" || true)
  if [[ "$ES_PODS" -gt 0 ]]; then
    echo "   [✓] Elasticsearch running"
  else
    echo "   [✗] Elasticsearch NOT running"
    FAILED=$((FAILED + 1))
  fi
  KIBANA_PODS=$(kubectl get pods -n logging -l app=kibana --field-selector=status.phase=Running 2>/dev/null | grep -c "kibana" || true)
  if [[ "$KIBANA_PODS" -gt 0 ]]; then
    echo "   [✓] Kibana running"
  else
    echo "   [✗] Kibana NOT running"
    FAILED=$((FAILED + 1))
  fi
  KIBANA_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:30560/ 2>/dev/null || echo "000")
  if [[ "$KIBANA_CODE" == "302" ]]; then
    echo "   [✓] Kibana accessible (HTTP $KIBANA_CODE)"
  else
    echo "   [✗] Kibana unreachable (HTTP $KIBANA_CODE)"
    FAILED=$((FAILED + 1))
  fi
  GRAFANA_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:30300/ 2>/dev/null || echo "000")
  if [[ "$GRAFANA_CODE" == "200" ]] || [[ "$GRAFANA_CODE" == "302" ]]; then
    echo "   [✓] Grafana accessible (HTTP $GRAFANA_CODE)"
  else
    echo "   [✗] Grafana unreachable (HTTP $GRAFANA_CODE)"
    FAILED=$((FAILED + 1))
  fi
  VAULT_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:30820/ 2>/dev/null || echo "000")
  if [[ "$VAULT_CODE" == "200" ]] || [[ "$VAULT_CODE" == "307" ]]; then
    echo "   [✓] Vault accessible (HTTP $VAULT_CODE)"
  else
    echo "   [✗] Vault unreachable (HTTP $VAULT_CODE)"
    FAILED=$((FAILED + 1))
  fi
fi

echo "  6. DISK USAGE"
DF_OUTPUT=$(df -h / | tail -1)
DISK_PCT=$(echo "$DF_OUTPUT" | awk '{gsub(/%/,"",$5); print $5}')
echo "   Root: ${DISK_PCT}% used ($(echo "$DF_OUTPUT" | awk '{print $3}')/$(echo "$DF_OUTPUT" | awk '{print $2}'))"
if [[ "$DISK_PCT" -gt "$DISK_WARN_PCT" ]]; then
  echo "   [✗] Disk exceeds ${DISK_WARN_PCT}%! (${DISK_PCT}%)"
  alert "WARNING" "Disk usage above ${DISK_WARN_PCT}%: ${DISK_PCT}%"
  FAILED=$((FAILED + 1))
fi

echo "  7. MEMORY USAGE"
if command -v free &>/dev/null; then
  MEM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
  MEM_USED=$(free -m | awk '/^Mem:/{print $3}')
  MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))
  echo "   Memory: ${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PCT}%)"
  if [[ "$MEM_PCT" -gt "$MEM_WARN_PCT" ]]; then
    echo "   [✗] Memory exceeds ${MEM_WARN_PCT}%!"
    alert "WARNING" "Memory at ${MEM_PCT}%"
    FAILED=$((FAILED + 1))
  fi
fi

echo "  8. RDS CONNECTIVITY"
if [[ -f /opt/terrafusion/backend/.env ]]; then
  source /opt/terrafusion/backend/.env
  if [[ "${DB_TYPE:-sqlite}" == "mysql" ]]; then
    mysqladmin ping -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" --silent 2>/dev/null && \
      echo "   [✓] RDS reachable" || { echo "   [✗] RDS unreachable"; FAILED=$((FAILED + 1)); }
  fi
fi

if [[ "$FAILED" -eq 0 ]]; then
  echo "   [✓] All checks passed — TerraFusion healthy"
else
  echo "   [✗] $FAILED check(s) failed"
fi
echo ""
echo "Alerts logged to: $ALERT_LOG"
exit "$FAILED"
