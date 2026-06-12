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
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
BACKEND_POD=$(kubectl get pod -n terrafusion -l app=backend -o name 2>/dev/null | head -1)
if [ -n "$BACKEND_POD" ]; then
  HTTP_CODE=$(kubectl exec -n terrafusion "$BACKEND_POD" -- curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://localhost:3001/api/health 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" == "200" ]]; then
    echo "   [✓] API is healthy (HTTP $HTTP_CODE)"
  else
    echo "   [✗] API returned HTTP $HTTP_CODE"
    alert "CRITICAL" "API health check failed: HTTP $HTTP_CODE"
    FAILED=$((FAILED + 1))
  fi
else
  echo "   [✗] No backend pod found"
  alert "CRITICAL" "No backend pod found for health check"
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
BACKEND_POD=$(kubectl get pod -n terrafusion -l app=backend -o name 2>/dev/null | head -1)
if [ -n "$BACKEND_POD" ] && command -v kubectl &>/dev/null; then
  RESPONSE=$(kubectl exec -n terrafusion "$BACKEND_POD" -- curl -s --max-time 5 http://localhost:3001/api/health 2>/dev/null || echo '{"status":"error"}')
  STATUS=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))" 2>/dev/null || echo "unknown")
  if [[ "$STATUS" == "ok" ]]; then
    echo "   [✓] Backend API response valid"
  else
    echo "   [✗] Backend API returned unexpected status: $STATUS"
    FAILED=$((FAILED + 1))
  fi
fi

echo "  4. k3s KUBERNETES"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if command -v kubectl &>/dev/null; then
  kubectl get nodes 2>/dev/null | grep -q Ready && echo "   [✓] k3s nodes ready" || { echo "   [✗] k3s nodes not ready"; FAILED=$((FAILED + 1)); }
  kubectl get pods -n terrafusion 2>/dev/null | grep -q Running && echo "   [✓] App pods running" || { echo "   [✗] App pods not running"; }
fi

echo "  5. DISK USAGE"
df -h / | tail -1 | awk '{print "   Root: " $5 " used (" $3 "/" $2 ")"}'
df -h / | tail -1 | awk '{gsub(/%/, "", $5); if ($5+0 > '"$DISK_WARN_PCT"') exit 1}' || {
  echo "   [✗] Disk exceeds ${DISK_WARN_PCT}%!"
  alert "WARNING" "Disk usage above ${DISK_WARN_PCT}%"
  FAILED=$((FAILED + 1))
}

echo "  6. MEMORY USAGE"
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

  SWAP_USED=$(free -m | awk '/^Swap:/{print $3}')
  if [[ "${SWAP_USED:-0}" -gt 0 ]]; then
    echo "   Swap: ${SWAP_USED}MB used"
  fi
fi

echo "  7. RDS CONNECTIVITY"
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
