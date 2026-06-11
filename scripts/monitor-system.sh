#!/usr/bin/env bash
set -euo pipefail

echo "═══════════════════════════════════════════════════════════════"
echo "  TerraFusion System Monitoring Report"
echo "  Generated: $(date)"
echo "═══════════════════════════════════════════════════════════════"

echo "1. SYSTEM UPTIME & LOAD"
uptime
echo "Load: $(cat /proc/loadavg 2>/dev/null | cut -d' ' -f1-3 || echo 'N/A')"

echo "2. CPU & MEMORY"
free -h 2>/dev/null || echo "N/A"
echo "Top CPU processes:"
ps aux --sort=-%cpu 2>/dev/null | head -6

echo "3. DISK USAGE"
df -h 2>/dev/null || echo "N/A"
[[ -d /opt/terrafusion ]] && du -sh /opt/terrafusion/*/ 2>/dev/null | sort -rh | head -10

echo "4. DOCKER CONTAINERS"
command -v docker &>/dev/null && docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" || echo "Docker N/A"

echo "5. k3s CLUSTER"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if command -v kubectl &>/dev/null; then
  echo "--- Nodes ---"
  kubectl get nodes -o wide 2>/dev/null || echo "k3s not ready"
  echo "--- Pods ---"
  kubectl get pods -A 2>/dev/null || true
  echo "--- Services ---"
  kubectl get svc -A 2>/dev/null || true
  echo "--- Helm Releases ---"
  helm list -A 2>/dev/null || true
fi

echo "6. LISTENING PORTS"
ss -tlnp 2>/dev/null | head -20 || netstat -tlnp 2>/dev/null | head -20 || echo "N/A"

echo "7. TROUBLESHOOTING"
echo "  Docker logs:  docker logs terrafusion-backend --tail 50"
echo "  k3s pods:     kubectl get pods -n terrafusion"
echo "  k3s logs:     kubectl logs -n terrafusion deployment/backend"
echo "  API check:    curl localhost:3001/api/health"
echo "  Helm status:  helm list -A"
echo "  k3s restart:  sudo systemctl restart k3s"
echo "═══════════════════════════════════════════════════════════════"
