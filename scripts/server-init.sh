#!/usr/bin/env bash
set -euo pipefail

GIT_REPO="${GIT_REPO_URL:-https://github.com/YOUR_ORG/terrafusion-platform.git}"
DEPLOY_DIR="/opt/terrafusion"
BRANCH="${DEPLOY_BRANCH:-main}"
LOG_FILE="/var/log/terrafusion-init.log"

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "═══════════════════════════════════════════════════════════════"
echo "  TerraFusion — Server Initialization"
echo "  Started: $(date)"
echo "═══════════════════════════════════════════════════════════════"

echo "[1/9] System Update"
apt update -y && apt upgrade -y

echo "[2/9] Installing Dependencies"
apt install -y git curl wget sqlite3 ufw htop tree unzip jq vim default-mysql-client

echo "[3/9] Installing Docker"
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

echo "[4/9] Installing k3s (Lightweight Kubernetes)"
if ! command -v k3s &>/dev/null; then
  curl -sfL https://get.k3s.io | sh -
  sleep 10
  mkdir -p /home/ubuntu/.kube
  cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
  chown -R ubuntu:ubuntu /home/ubuntu/.kube
  chmod 600 /home/ubuntu/.kube/config
  echo "export KUBECONFIG=/home/ubuntu/.kube/config" >> /home/ubuntu/.bashrc
fi

# Fix kubeconfig server IP for Docker container access (replace 127.0.0.1 with host private IP)
if grep -q "server: https://127.0.0.1" /etc/rancher/k3s/k3s.yaml; then
  HOST_IP=$(ip -4 addr show | grep -oP 'inet \K10\.[0-9.]+|172\.1[6-9]\.[0-9.]+|172\.2[0-9]\.[0-9.]+|172\.3[0-1]\.[0-9.]+|192\.168\.[0-9.]+' | head -1)
  if [ -n "$HOST_IP" ]; then
    sed -i "s|server: https://127.0.0.1:6443|server: https://${HOST_IP}:6443|g" /etc/rancher/k3s/k3s.yaml
    echo "  kubeconfig server replaced 127.0.0.1 → ${HOST_IP}"
  fi
fi
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo "k3s $(k3s --version | head -1)"

echo "[5/9] Installing Helm"
if ! command -v helm &>/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
echo "Helm $(helm version --short)"

echo "[6/9] Installing AWS CLI v2"
if ! command -v aws &>/dev/null; then
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install
fi
echo "AWS CLI $(aws --version)"

echo "[*] Configuring AWS credentials..."
if [[ ! -f /home/ubuntu/.aws/credentials ]]; then
  mkdir -p /home/ubuntu/.aws
  cat > /home/ubuntu/.aws/credentials << EOF
[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID:-}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY:-}
EOF
  cat > /home/ubuntu/.aws/config << EOF
[default]
region = ${AWS_REGION:-ap-south-1}
output = json
EOF
  chown -R ubuntu:ubuntu /home/ubuntu/.aws
  chmod 600 /home/ubuntu/.aws/credentials
fi

echo "[7/9] Cloning Repository"
if [[ -d "$DEPLOY_DIR" ]]; then
  cd "$DEPLOY_DIR"
  git fetch origin
  git reset --hard "origin/$BRANCH"
else
  mkdir -p "$(dirname "$DEPLOY_DIR")"
  git clone --branch "$BRANCH" "$GIT_REPO" "$DEPLOY_DIR"
fi

echo "[8/9] Configuring Application"
cd "$DEPLOY_DIR"

cat > backend/.env << EOF
PORT=3001
DB_TYPE=mysql
DB_HOST=${RDS_HOST:-localhost}
DB_PORT=${RDS_PORT:-3306}
DB_NAME=${RDS_DB_NAME:-terrafusion}
DB_USER=${RDS_USER:-terrafusion_admin}
DB_PASSWORD=${RDS_PASSWORD:-}
JWT_SECRET=terrafusion-$(openssl rand -hex 16)

AWS_REGION=${AWS_REGION:-ap-south-1}
ECR_FRONTEND=${ECR_FRONTEND:-}
ECR_BACKEND=${ECR_BACKEND:-}
S3_BACKUP_BUCKET=${S3_BACKUP:-}
EOF

chmod -R 755 .
chmod 600 backend/.env

echo "[9/9] Starting Application Stack"

# Apply Kubernetes manifests (primary deployment target)
echo "[*] Deploying to k3s..."
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl apply -f /opt/terrafusion/k8s/ 2>/dev/null || echo "[WARN] k8s manifests not yet present — will be deployed after git clone"

# Install metrics-server for HPA
echo "[*] Installing metrics-server..."
if ! kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml; then
  echo "[ERROR] Failed to install metrics-server — check network connectivity"
  echo "  Run manually: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
fi

# Start Jenkins as Docker container
echo "[*] Starting Jenkins..."
docker volume create jenkins_home 2>/dev/null || true
docker run -d \
  --name jenkins-blueocean \
  --restart unless-stopped \
  -p 8080:8080 \
  -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$(which kubectl):/usr/local/bin/kubectl" \
  -v /etc/rancher/k3s/k3s.yaml:/etc/rancher/k3s/k3s.yaml:ro \
  jenkins/jenkins:lts-jdk17 || echo "[WARN] Jenkins start had issues"

# Install Jenkins plugins automatically
echo "[*] Installing Jenkins plugins..."
echo "  Waiting for Jenkins to be ready..."
for i in $(seq 1 30); do
  if docker exec jenkins-blueocean test -f /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null; then
    echo "  Jenkins ready after ${i}s"
    break
  fi
  sleep 2
done
docker run --rm \
  -v jenkins_home:/var/jenkins_home \
  jenkins/jenkins:lts-jdk17 \
  jenkins-plugin-cli --plugins \
    git \
    workflow-aggregator \
    pipeline-stage-view \
    blueocean \
    docker-workflow \
    kubernetes-cli \
    aws-credentials \
    credentials-binding 2>&1 || echo "[WARN] Plugin install had issues"

# Restart Jenkins to load plugins
docker restart jenkins-blueocean || true

# Store backend secrets in Vault
echo "[*] Configuring Vault secrets..."
if kubectl get pod -n vault -l app.kubernetes.io/name=vault --field-selector=status.phase=Running 2>/dev/null | grep -q vault; then
  VAULT_POD=$(kubectl get pod -n vault -l app.kubernetes.io/name=vault -o name 2>/dev/null | head -1)
  if [ -n "$VAULT_POD" ]; then
    kubectl exec -n vault "$VAULT_POD" -- vault kv put secret/terrafusion/backend \
      DB_PASSWORD="${RDS_PASSWORD:-}" \
      JWT_SECRET="$(grep JWT_SECRET backend/.env | cut -d= -f2)" \
      DB_HOST="${RDS_HOST:-localhost}" \
      DB_NAME="${RDS_DB_NAME:-terrafusion}" 2>/dev/null && \
      echo "  [✓] Backend secrets stored in Vault" || \
      echo "  [WARN] Vault secret store failed — may need manual setup"
  fi
else
  echo "  [WARN] Vault pod not found — install Vault first: helm upgrade --install vault hashicorp/vault -n vault --create-namespace -f helm/vault-values.yaml"
  echo "  Then run: kubectl exec -n vault deploy/vault -- vault kv put secret/terrafusion/backend DB_PASSWORD=... JWT_SECRET=..."
fi

sleep 5
echo ""
echo "--- Docker Containers ---"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "--- k3s Nodes ---"
kubectl get nodes || echo "k3s not ready yet"

echo ""
echo "--- API Health ---"
curl -s --max-time 5 http://localhost:3001/api/health || echo "Health check pending"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Initialization Complete!"
echo "  Time: $(date)"
echo "  Log:  $LOG_FILE"
echo ""
JENKINS_PASS=$(docker exec jenkins-blueocean cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || echo "check jenkins logs")
echo "  Jenkins:  http://$(curl -s http://checkip.amazonaws.com):8080"
echo "  Jenkins initial password: ${JENKINS_PASS}"
echo "  Frontend: http://$(curl -s http://checkip.amazonaws.com)"
echo "  Grafana:  http://$(curl -s http://checkip.amazonaws.com):30300 (admin:admin)"
echo "  Kibana:   http://$(curl -s http://checkip.amazonaws.com):30560"
echo "  Vault:    http://$(curl -s http://checkip.amazonaws.com):30820 (token: root)"
echo "  Vault secret: vault kv get secret/terrafusion/backend"
echo "  k3s:      kubectl get nodes"
echo "═══════════════════════════════════════════════════════════════"
