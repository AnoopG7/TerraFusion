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

source backend/.env

log "[*] Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$(echo $ECR_BACKEND | cut -d/ -f1)"

log "[*] Building backend Docker image..."
docker build -t terrafusion-backend:latest ./backend
docker tag terrafusion-backend:latest "${ECR_BACKEND}:${TIMESTAMP}"
docker tag terrafusion-backend:latest "${ECR_BACKEND}:latest"
docker push "${ECR_BACKEND}:${TIMESTAMP}"
docker push "${ECR_BACKEND}:latest"

log "[*] Building frontend Docker image..."
docker build -t terrafusion-frontend:latest ./frontend
docker tag terrafusion-frontend:latest "${ECR_FRONTEND}:${TIMESTAMP}"
docker tag terrafusion-frontend:latest "${ECR_FRONTEND}:latest"
docker push "${ECR_FRONTEND}:${TIMESTAMP}"
docker push "${ECR_FRONTEND}:latest"

log "[*] Deploying to k3s..."
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
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
log "Backend: ${ECR_BACKEND}:${TIMESTAMP}"
log "Frontend: ${ECR_FRONTEND}:${TIMESTAMP}"
kubectl get pods -n terrafusion
