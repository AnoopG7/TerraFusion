#!/usr/bin/env bash
set -euo pipefail

TERRAFUSION_HOME="/opt/terrafusion"
BRANCH="${1:-main}"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
DEPLOY_LOG="/var/log/terrafusion/deploy.log"
K8S_MANIFESTS="${TERRAFUSION_HOME}/k8s"

mkdir -p "$(dirname "$DEPLOY_LOG")"

log() {
  echo "[$(date +"%H:%M:%S")] $*" | tee -a "$DEPLOY_LOG"
}

log "=== TerraFusion Deployment Started ==="
log "Branch: $BRANCH"

cd "$TERRAFUSION_HOME"

log "[*] Pulling latest code..."
git fetch origin
git reset --hard "origin/$BRANCH"

log "[*] Building backend Docker image..."
docker build -t terrafusion-backend:"$TIMESTAMP" ./backend
docker tag terrafusion-backend:"$TIMESTAMP" terrafusion-backend:latest

log "[*] Building frontend Docker image..."
docker build -t terrafusion-frontend:"$TIMESTAMP" ./frontend
docker tag terrafusion-frontend:"$TIMESTAMP" terrafusion-frontend:latest

log "[*] Importing images into containerd..."
docker save terrafusion-backend:"$TIMESTAMP" terrafusion-frontend:"$TIMESTAMP" | sudo k3s ctr images import - || {
  log "[!] Image import failed — retrying with Docker -> containerd sync"
  docker save terrafusion-backend:"$TIMESTAMP" | sudo k3s ctr images import -
  docker save terrafusion-frontend:"$TIMESTAMP" | sudo k3s ctr images import -
}

log "[*] Deploying to k3s..."
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Recreate secret with real values from .env (never apply placeholder secret.yaml)
if [ -f backend/.env ]; then
  source backend/.env
  kubectl create secret generic backend-secret -n terrafusion \
    --from-literal=DB_PASSWORD="${DB_PASSWORD}" \
    --from-literal=JWT_SECRET="${JWT_SECRET}" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

kubectl apply -f "${K8S_MANIFESTS}/"

log "[*] Watching rollout..."
kubectl rollout status deployment/backend -n terrafusion --timeout=120s || {
  log "[✗] Backend deployment failed! Rolling back..."
  kubectl rollout undo deployment/backend -n terrafusion
  exit 1
}

kubectl rollout status deployment/frontend -n terrafusion --timeout=120s || {
  log "[✗] Frontend deployment failed! Rolling back..."
  kubectl rollout undo deployment/frontend -n terrafusion
  exit 1
}

log "[*] Smoke test..."
sleep 5
BACKEND_POD=$(kubectl get pod -n terrafusion -l app=backend -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n terrafusion "$BACKEND_POD" -- curl -s http://localhost:3001/api/health || {
  log "[✗] Smoke test failed! Rolling back..."
  kubectl rollout undo deployment/backend -n terrafusion
  kubectl rollout undo deployment/frontend -n terrafusion
  exit 1
}

docker image prune -f > /dev/null 2>&1 || true

log ""
log "=== Deployment Complete ==="
log "Backend: terrafusion-backend:${TIMESTAMP}"
log "Frontend: terrafusion-frontend:${TIMESTAMP}"
kubectl get pods -n terrafusion
