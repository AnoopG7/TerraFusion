# TerraFusion — Deployment Guide

## Prerequisites

| Tool | Version | Check |
|---|---|---|
| AWS CLI | ≥ 2.x | `aws --version` |
| Terraform | ≥ 1.5 | `terraform --version` |
| SSH key pair | ~/.ssh/id_rsa.pub | `ls -la ~/.ssh/` |
| AWS credentials | configured | `aws sts get-caller-identity` |
| Git repo | your fork | `git remote -v` |

## Phase 1: Provision Infrastructure

```bash
# 1. Navigate to terraform
cd terraform

# 2. Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   - ssh_allowed_cidr = "$(curl -s http://checkip.amazonaws.com)/32"
#   - rds_master_password = "YourStrongPassword123!"
#   - public_key_path = "/Users/you/.ssh/id_rsa.pub"

# 3. Create S3 backend bucket (first time only)
aws s3 mb s3://terrafusion-terraform-state --region ap-south-1
aws dynamodb create-table \
  --table-name terrafusion-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-south-1

# 4. Initialize and apply
terraform init
terraform plan
terraform apply -auto-approve
```

**Expected output (≈5 min):**
```
Apply complete! Resources: 22 added.

Outputs:
ec2_public_ip           = "13.xxx.xxx.xxx"
rds_endpoint            = "terrafusion-mysql.xxxxxx.ap-south-1.rds.amazonaws.com"
ecr_frontend_url        = "xxxxxx.dkr.ecr.ap-south-1.amazonaws.com/terrafusion-frontend"
ecr_backend_url         = "xxxxxx.dkr.ecr.ap-south-1.amazonaws.com/terrafusion-backend"
ssh_command             = "ssh -i ~/.ssh/id_rsa ubuntu@13.xxx.xxx.xxx"
```

## Phase 2: Server Bootstrap

Wait for user_data to complete (~3 min), then verify:

```bash
# SSH into the server
ssh -i ~/.ssh/id_rsa ubuntu@<EC2_PUBLIC_IP>

# Check init log
sudo cat /var/log/terrafusion-init.log
```

**The init script handles automatically:**

| Step | What installs | Verification |
|---|---|---|
| 1 | System update | `apt list --upgradable` |
| 2 | Dependencies (git, curl, jq, etc.) | `git --version` |
| 3 | Docker + Compose plugin | `docker --version && docker compose version` |
| 4 | k3s (Kubernetes) | `kubectl get nodes` |
| 5 | Helm | `helm version --short` |
| 6 | AWS CLI v2 | `aws --version` |
| 7 | Clone repo → /opt/terrafusion | `ls /opt/terrafusion` |
| 8 | Create backend/.env with RDS creds | `cat /opt/terrafusion/backend/.env` |
| 9 | Start Docker Compose (dev) | `curl localhost:3001/api/health` |

If any step failed, run manually:
```bash
sudo bash /opt/terrafusion/scripts/install-packages.sh
sudo bash /opt/terrafusion/scripts/server-init.sh
```

## Phase 3: Deploy App on k3s

```bash
# 1. Apply all K8s manifests
kubectl apply -f /opt/terrafusion/k8s/

# 2. Watch pods come up
kubectl get pods -n terrafusion -w
# Wait for both backend and frontend to show 2/2 Running

# 3. Verify services
kubectl get svc -n terrafusion

# 4. Test via NodePort
curl http://localhost:30080
curl http://localhost:30080/api/health

# 5. Open in browser
echo "http://<EC2_PUBLIC_IP>:30080"
```

**Login credentials:** `admin@terrafusion.io` / `admin123`

## Phase 4: Push Docker Images to ECR

```bash
# 1. Login to ECR
aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin \
  $(aws ecr describe-repositories --query 'repositories[0].repositoryUri' --output text | cut -d/ -f1)

# 2. Build and push backend
cd /opt/terrafusion
docker build -t terrafusion-backend ./backend
ECR_BACKEND=$(aws ecr describe-repositories --repository-names terrafusion-backend --query 'repositories[0].repositoryUri' --output text)
docker tag terrafusion-backend:latest ${ECR_BACKEND}:latest
docker push ${ECR_BACKEND}:latest

# 3. Build and push frontend
docker build -t terrafusion-frontend ./frontend
ECR_FRONTEND=$(aws ecr describe-repositories --repository-names terrafusion-frontend --query 'repositories[0].repositoryUri' --output text)
docker tag terrafusion-frontend:latest ${ECR_FRONTEND}:latest
docker push ${ECR_FRONTEND}:latest

# 4. Update k8s manifests to use ECR images
kubectl set image deployment/backend -n terrafusion backend=${ECR_BACKEND}:latest
kubectl set image deployment/frontend -n terrafusion frontend=${ECR_FRONTEND}:latest
```

## Phase 5: Install Monitoring Stack (Prometheus + Grafana)

```bash
# 1. Add Helm repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 2. Install kube-prometheus-stack
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f /opt/terrafusion/helm/prometheus-values.yaml

# 3. Wait for pods
kubectl get pods -n monitoring -w

# 4. Access Grafana
echo "http://<EC2_PUBLIC_IP>:30300"
# Login: admin / admin
```

**Built-in dashboards:**
- Kubernetes / Compute Resources / Cluster
- Kubernetes / Compute Resources / Namespace (Pods)
- Kubernetes / Networking / Cluster
- TerraFusion / Climate Monitoring (custom)

## Phase 6: Install Logging Stack (ELK)

```bash
# 1. Add Elastic Helm repo
helm repo add elastic https://helm.elastic.co
helm repo update

# 2. Install Elasticsearch
helm upgrade --install elasticsearch elastic/elasticsearch \
  -n logging --create-namespace \
  -f /opt/terrafusion/helm/elasticsearch-values.yaml

# 3. Wait for ES to be ready
kubectl wait --for=condition=ready pod -l app=elasticsearch-master -n logging --timeout=180s

# 4. Install Kibana
helm upgrade --install kibana elastic/kibana \
  -n logging \
  -f /opt/terrafusion/helm/kibana-values.yaml

# 5. Install Filebeat
helm upgrade --install filebeat elastic/filebeat \
  -n logging \
  -f /opt/terrafusion/helm/filebeat-config.yaml

# 6. Verify all pods
kubectl get pods -n logging

# 7. Access Kibana
echo "http://<EC2_PUBLIC_IP>:30560"
# Create index pattern: filebeat-*
```

## Phase 7: Install Vault

```bash
# 1. Add HashiCorp Helm repo
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# 2. Install Vault (dev mode)
helm upgrade --install vault hashicorp/vault \
  -n vault --create-namespace \
  -f /opt/terrafusion/helm/vault-values.yaml

# 3. Wait for Vault pod
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n vault --timeout=120s

# 4. Enable KV secrets engine
kubectl exec -n vault vault-0 -- vault secrets enable -path=secret kv-v2

# 5. Store backend secrets
kubectl exec -n vault vault-0 -- vault kv put secret/terrafusion/backend \
  DB_PASSWORD="$(awk -F= '/DB_PASSWORD/ {print $2}' /opt/terrafusion/backend/.env)" \
  JWT_SECRET="$(awk -F= '/JWT_SECRET/ {print $2}' /opt/terrafusion/backend/.env)"

# 6. Verify
kubectl exec -n vault vault-0 -- vault kv get secret/terrafusion/backend

# 7. Access Vault UI
echo "http://<EC2_PUBLIC_IP>:30820"
# Root token: root (dev mode)
```

## Phase 8: Configure Jenkins CI/CD

```bash
# 1. Get Jenkins initial admin password
sudo docker exec jenkins-blueocean cat /var/jenkins_home/secrets/initialAdminPassword

# 2. Open Jenkins
echo "http://<EC2_PUBLIC_IP>:8080"

# 3. First-time setup:
#    - Paste initial admin password
#    - Install suggested plugins
#    - Create admin user (save credentials)
```

### Jenkins Pipeline Setup

```bash
# 4. Add credentials:
#    Manage Jenkins → Credentials → System → Global:
#    - Kind: "AWS Credentials" → ID: "aws-credentials"
#      Access Key ID + Secret Access Key
#    - Kind: "Username with password" → ID: "github-credentials"
#      GitHub username + PAT

# 6. Create pipeline:
#    New Item → "terrafusion-pipeline" → Pipeline
#    Definition: Pipeline script from SCM
#    SCM: Git
#    Repository URL: https://github.com/YOUR_ORG/terrafusion-platform.git
#    Script Path: jenkins/Jenkinsfile
#    Credentials: (your GitHub creds)

# 7. Test the pipeline:
#    Click "Build Now"
#    Watch stages: Checkout → Build → Push → Deploy → Smoke Test
```

## Phase 9: Verify Everything

### Quick Health Check

```bash
# Run the health check script
sudo bash /opt/terrafusion/scripts/health-check.sh
```

**Expected:**
```
✓ API is healthy (HTTP 200)
✓ Backend container running
✓ Frontend container running
✓ k3s nodes ready
✓ App pods running
✓ Disk OK
✓ Memory OK
✓ RDS reachable
✓ All checks passed — TerraFusion healthy
```

### Service Access Summary

| Service | URL | Credentials |
|---|---|---|
| Frontend | http://EC2_IP:30080 | admin@terrafusion.io / admin123 |
| Backend API | http://EC2_IP:30080/api/health | — |
| Jenkins | http://EC2_IP:8080 | (set during setup) |
| Grafana | http://EC2_IP:30300 | admin / admin |
| Kibana | http://EC2_IP:30560 | — |
| Vault | http://EC2_IP:30820 | root token: root |

### Verify DR Scenarios

See `docs/DR_PROCEDURES.md` for step-by-step demos:
- Pod crash recovery
- Node failure recovery
- RDS failover
- Failed deployment rollback
- Auto-scaling under load

## Phase 10: Cleanup

```bash
# Destroy everything
cd terraform
terraform destroy -auto-approve

# Empty S3 buckets first if destroy fails
aws s3 rm s3://terrafusion-terraform-state --recursive
aws s3 rm s3://terrafusion-backups --recursive
terraform destroy -auto-approve
```

## Troubleshooting

### k3s not starting
```bash
sudo systemctl status k3s
sudo journalctl -u k3s --no-pager | tail -30
```

### Pods stuck in Pending
```bash
kubectl describe pod <pod-name> -n terrafusion
kubectl get events -n terrafusion --sort-by='.lastTimestamp' | tail -10
```

### RDS connection fails
```bash
# From EC2
mysql -h <RDS_ENDPOINT> -u terrafusion_admin -p -e "SHOW DATABASES;"
# Check security group: RDS SG must allow port 3306 from EC2 SG
```

### Jenkins pipeline failing
```bash
# Check Jenkins logs
sudo docker logs jenkins-blueocean --tail 50
# Check if kubectl works inside Jenkins
sudo docker exec jenkins-blueocean kubectl get nodes
```

### Vault sealed
```bash
kubectl exec -n vault vault-0 -- vault status
# Dev mode auto-unseals on restart, no action needed
```

### Disk full
```bash
df -h
sudo /opt/terrafusion/scripts/rotate-logs.sh
docker system prune -f --volumes
```

### Reset everything on EC2
```bash
cd /opt/terrafusion
git fetch origin && git reset --hard origin/main
docker compose down -v
docker compose up --build -d
kubectl delete namespace terrafusion
kubectl apply -f k8s/
```