#!/usr/bin/env bash
set -uo pipefail

GIT_REPO="https://github.com/AnoopG7/TerraFusion.git"
DEPLOY_DIR="/opt/terrafusion"
BRANCH="main"
LOG_FILE="/var/log/terrafusion-init.log"

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "═══════════════════════════════════════════════════════════════"
echo "  TerraFusion — Server Initialization"
echo "  Started: $(date)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

echo "────────────────────────────────────────────"
echo "  [1/7] System Update"
echo "────────────────────────────────────────────"
apt update -y && apt upgrade -y

# Elasticsearch requires vm.max_map_count >= 262144 (default is 65530)
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" >> /etc/sysctl.conf

echo "[✓] System updated."
echo ""

echo "────────────────────────────────────────────"
echo "  [2/7] Installing Dependencies"
echo "────────────────────────────────────────────"
apt install -y git curl wget sqlite3 ufw htop tree unzip jq vim mysql-client

echo "[*] Installing Node.js 22.x (for Jenkins pipeline)..."
if ! command -v node &>/dev/null || [[ "$(node --version)" != v22* ]]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt install -y nodejs
  echo "[✓] Node.js: $(node --version)  npm: $(npm --version)"
else
  echo "[✓] Node.js already installed: $(node --version)"
fi

echo "[*] Installing Docker..."
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sh /tmp/get-docker.sh
  systemctl enable docker
  systemctl start docker
fi
if ! docker compose version &>/dev/null; then
  apt install -y docker-compose-plugin
fi
usermod -aG docker ubuntu
echo "[✓] Docker: $(docker --version)"
echo ""

echo "────────────────────────────────────────────"
echo "  [3/7] Installing k3s & Helm"
echo "────────────────────────────────────────────"
if ! command -v k3s &>/dev/null; then
  curl -sfL https://get.k3s.io | sh -
  sleep 10
  mkdir -p /home/ubuntu/.kube
  cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
  chown -R ubuntu:ubuntu /home/ubuntu/.kube
  chmod 600 /home/ubuntu/.kube/config
  echo "export KUBECONFIG=/home/ubuntu/.kube/config" >> /home/ubuntu/.bashrc
fi

if grep -q "server: https://127.0.0.1" /etc/rancher/k3s/k3s.yaml; then
  HOST_IP=$(ip -4 addr show | grep -oP 'inet \K10\.[0-9.]+|172\.1[6-9]\.[0-9.]+|172\.2[0-9]\.[0-9.]+|172\.3[0-1]\.[0-9.]+|192\.168\.[0-9.]+' | head -1)
  if [ -n "$HOST_IP" ]; then
    sed -i "s|server: https://127.0.0.1:6443|server: https://${HOST_IP}:6443|g" /etc/rancher/k3s/k3s.yaml
    echo "  kubeconfig server replaced 127.0.0.1 → ${HOST_IP}"
  fi
fi
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
chmod 644 /etc/rancher/k3s/k3s.yaml
mkdir -p /var/lib/jenkins/.kube
cp /etc/rancher/k3s/k3s.yaml /var/lib/jenkins/.kube/config
chown -R jenkins:jenkins /var/lib/jenkins/.kube || true
echo "k3s $(k3s --version | head -1)"

if ! command -v helm &>/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
echo "Helm $(helm version --short)"
echo ""

echo "────────────────────────────────────────────"
echo "  [4/7] Installing AWS CLI"
echo "────────────────────────────────────────────"
if ! command -v aws &>/dev/null; then
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install
fi
echo "AWS CLI $(aws --version)"

echo ""

echo "────────────────────────────────────────────"
echo "  [5/7] Cloning Repository"
echo "────────────────────────────────────────────"
if [[ -d "$DEPLOY_DIR" ]]; then
  cd "$DEPLOY_DIR"
  git fetch origin
  git reset --hard "origin/$BRANCH"
else
  mkdir -p "$(dirname "$DEPLOY_DIR")"
  git clone --branch "$BRANCH" "$GIT_REPO" "$DEPLOY_DIR"
fi
echo "[✓] Repository cloned at $DEPLOY_DIR"
echo ""

echo "────────────────────────────────────────────"
echo "  [5.5] Building Docker Images"
echo "────────────────────────────────────────────"
cd "$DEPLOY_DIR"

echo "[*] Building backend Docker image..."
docker build -t terrafusion-backend:latest ./backend
echo "[✓] Backend image built"

echo "[*] Building frontend Docker image..."
docker build -t terrafusion-frontend:latest ./frontend
echo "[✓] Frontend image built"

echo "[*] Importing images into k3s containerd..."
docker save terrafusion-backend:latest | sudo k3s ctr images import -
docker save terrafusion-frontend:latest | sudo k3s ctr images import -
echo "[✓] Docker images imported into k3s"
echo ""

echo "────────────────────────────────────────────"
echo "  [6/7] Configuring & Starting Application"
echo "────────────────────────────────────────────"
cd "$DEPLOY_DIR"

cat > backend/.env << EOF
PORT=3001
DB_TYPE=mysql
DB_HOST=${RDS_HOST:-__REPLACE_ME__}
DB_PORT=${RDS_PORT:-3306}
DB_NAME=${RDS_DB_NAME:-terrafusion}
DB_USER=${RDS_USER:-terrafusion_admin}
DB_PASSWORD=${RDS_PASSWORD:-__RDS_PASSWORD__}
JWT_SECRET=terrafusion-$(openssl rand -hex 16)
AWS_REGION=${AWS_REGION:-ap-south-1}
S3_BACKUP_BUCKET=${S3_BACKUP_BUCKET:-}
EOF

chmod -R 755 .
chmod 600 backend/.env

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl create namespace terrafusion || true

# Create k8s Secret and ConfigMap with real values from .env (not placeholders)
source backend/.env

# ConfigMap with real RDS values (overrides static k8s/configmap.yaml placeholder)
kubectl create configmap backend-config -n terrafusion \
  --from-literal=DB_HOST="${DB_HOST}" \
  --from-literal=DB_PORT="${DB_PORT:-3306}" \
  --from-literal=DB_NAME="${DB_NAME:-terrafusion}" \
  --from-literal=DB_USER="${DB_USER:-terrafusion_admin}" \
  --from-literal=DB_TYPE="${DB_TYPE:-mysql}" \
  --from-literal=NODE_ENV="production" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic backend-secret -n terrafusion \
  --from-literal=DB_PASSWORD="${DB_PASSWORD}" \
  --from-literal=JWT_SECRET="${JWT_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f /opt/terrafusion/k8s/ || echo "[WARN] k8s manifests not yet present"

echo "[*] Installing metrics-server..."
if ! kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml; then
  echo "[ERROR] Failed to install metrics-server — check network connectivity"
fi

echo "[*] Setting up native Jenkins..."
bash scripts/setup-jenkins.sh || echo "  [WARN] Jenkins setup had issues — check /var/log/jenkins-setup.log"

echo "[*] Installing Helm charts (Prometheus/Grafana, ELK, Vault)..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo add elastic https://helm.elastic.co || true
helm repo add hashicorp https://helm.releases.hashicorp.com || true
helm repo update || true

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f helm/prometheus-values.yaml --wait --timeout 5m || \
  echo "  [WARN] Prometheus/Grafana install timed out — run manually later"

kubectl create namespace logging || true

# ES needs longer than 5m on single-node EC2 — install without --wait, then poll
kubectl delete secret elasticsearch-master-credentials -n logging --ignore-not-found 
helm upgrade --install elasticsearch elastic/elasticsearch \
  -n logging --create-namespace -f helm/elasticsearch-values.yaml \
  --version 8.5.1 --timeout 10m  && \
  echo "  [✓] Elasticsearch chart submitted" || \
  echo "  [WARN] Elasticsearch install failed — run manually later"

echo "[*] Waiting for Elasticsearch to be ready (up to 10 min)..."
ES_READY=false
for i in $(seq 1 60); do
  STATUS=$(kubectl get pod -n logging -l app=elasticsearch-master -o jsonpath='{.items[0].status.phase}' || echo "")
  if [ "$STATUS" = "Running" ]; then
    ES_READY=true
    echo "  [✓] Elasticsearch ready"
    break
  fi
  sleep 10
done

# Filebeat — log shipping to ES (no auth since xpack.security is disabled)
if [ "$ES_READY" = "true" ]; then
  helm upgrade --install filebeat elastic/filebeat \
    -n logging -f helm/filebeat-config.yaml \
    --version 8.5.1 --wait --timeout 3m  && \
    echo "  [✓] Filebeat installed" || \
    echo "  [WARN] Filebeat install timed out — run manually later"
fi

helm upgrade --install vault hashicorp/vault \
  -n vault --create-namespace -f helm/vault-values.yaml --wait --timeout 3m || \
  echo "  [WARN] Vault install timed out — run manually later"

echo "[*] Configuring Vault secrets..."
for i in $(seq 1 30); do
  VAULT_POD=$(kubectl get pod -n vault -l app.kubernetes.io/name=vault -o name  | head -1)
  if [ -n "$VAULT_POD" ]; then break; fi
  sleep 5
done
if [ -n "$VAULT_POD" ]; then
  # Wait for Vault pod to be fully ready
  kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=vault -n vault --timeout=120s || true
  sleep 5
  kubectl exec -n vault "$VAULT_POD" -- sh -c "
    export VAULT_ADDR=http://127.0.0.1:8200
    export VAULT_TOKEN=root
    vault kv put secret/terrafusion/backend \
      DB_PASSWORD='${DB_PASSWORD}' \
      JWT_SECRET='${JWT_SECRET}' \
      DB_HOST='${DB_HOST}' \
      DB_NAME='${RDS_DB_NAME:-terrafusion}'
  "  && \
    echo "  [✓] Backend secrets stored in Vault" || \
    echo "  [WARN] Vault secret store failed — may need manual setup"
else
  echo "  [WARN] Vault pod not found after installation — may need manual setup"
fi
echo ""

echo "────────────────────────────────────────────"
echo "  [7/7] Post-Deployment Verification"
echo "────────────────────────────────────────────"
sleep 5
echo ""
echo "--- Docker Containers ---"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "--- k3s Nodes ---"
kubectl get nodes || echo "k3s not ready yet"

echo ""
echo "--- API Health ---"
BACKEND_POD=$(kubectl get pod -n terrafusion -l app=backend -o name  | head -1)
if [ -n "$BACKEND_POD" ]; then
  kubectl exec -n terrafusion "$BACKEND_POD" -- wget -q -O - --timeout=5 http://localhost:3001/api/health || echo "Health check pending"
else
  echo "Backend pod not ready yet"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Initialization Complete!"
echo "  Time: $(date)"
echo "  Log:  $LOG_FILE"
echo ""
echo "  Jenkins:  http://$(curl -s http://checkip.amazonaws.com):8080 (admin / admin123)"
echo "  Frontend: http://$(curl -s http://checkip.amazonaws.com):30080"
echo "  Grafana:  http://$(curl -s http://checkip.amazonaws.com):30300 (admin:admin)"
echo   "  Elasticsearch: http://$(curl -s http://checkip.amazonaws.com):30920"
echo "  Vault:    http://$(curl -s http://checkip.amazonaws.com):30820 (token: root)"
echo "  Vault secret: vault kv get secret/terrafusion/backend"
echo "  k3s:      kubectl get nodes"
echo "═══════════════════════════════════════════════════════════════"
