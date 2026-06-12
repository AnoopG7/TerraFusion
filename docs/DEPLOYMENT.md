# TerraFusion — Deployment Guide

## Prerequisites

| Tool | Version | Check |
|---|---|---|
| AWS CLI | ≥ 2.x | `aws --version` |
| Terraform | ≥ 1.5 | `terraform --version` |
| SSH key pair | created in AWS Console | referenced by name in tfvars |
| AWS credentials | configured (access key + secret) | `aws sts get-caller-identity` |

## Phase 1: Provision Infrastructure

```bash
# 1. Navigate to terraform
cd terraform

# 2. Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   - ssh_allowed_cidr = "$(curl -s http://checkip.amazonaws.com)/32"
#   - rds_master_password = "YourStrongPassword123!"
#   - key_pair_name = "your-key-pair-name"

# 3. Initialize and apply (local state — no S3 bucket needed)
terraform init
terraform plan
terraform apply -auto-approve
```

**Expected output (≈8 min):**
```
Apply complete! Resources: 32 added.

Outputs:
ec2_public_ip           = "13.xxx.xxx.xxx"
rds_endpoint            = "terrafusion-mysql.xxxxxx.ap-south-1.rds.amazonaws.com"
ssh_command             = "ssh -i ~/.ssh/your-key.pem ubuntu@13.xxx.xxx.xxx"
jenkins_url             = "http://13.xxx.xxx.xxx:8080"
application_url         = "http://13.xxx.xxx.xxx:30080"
grafana_url             = "http://13.xxx.xxx.xxx:30300"
kibana_url              = "http://13.xxx.xxx.xxx:30560"
vault_url               = "http://13.xxx.xxx.xxx:30820"
```

## Phase 2: Wait for Bootstrap

`terraform apply` writes the init script as EC2 user_data. On first boot, the EC2 runs `server-init.sh` automatically:

| Step | What happens | Verification |
|---|---|---|
| 1 | apt update + upgrade | `cat /var/log/terrafusion-init.log` |
| 2 | Install deps: git, curl, Docker, Node.js 22 | `node --version` |
| 3 | Install k3s + Helm; fix kubeconfig permissions for Jenkins | `kubectl get nodes && helm version` |
| 4 | Clone repo → `/opt/terrafusion` | `ls /opt/terrafusion` |
| 5 | Create `.env` with RDS creds; create k8s Secret dynamically from `.env` (no placeholders); apply k8s manifests; install metrics-server | `kubectl get pods -A` |
| 6 | Install **Jenkins** (native systemd), add `jenkins` user to `docker` group, copy kubeconfig | `sudo systemctl status jenkins` |
| 7 | Install **Helm charts** (Prometheus/Grafana, ELK, Vault); store real secrets in Vault | `helm list -A` |
| 8 | Post-deployment checks | `kubectl exec` pod health check |

Wait ~5-8 min for the init log to complete:

```bash
# SSH into the server
ssh -i ~/.ssh/your-key.pem ubuntu@<EC2_PUBLIC_IP>

# Check init log
sudo tail -50 /var/log/terrafusion-init.log
```

**Everything is automated.** No manual Helm installs, no manual Jenkins setup.

If the init log shows errors, re-run:
```bash
sudo bash /opt/terrafusion/scripts/server-init.sh
```

## Phase 3: Verify & Access

### Health Check
```bash
# Run the health check script
sudo bash /opt/terrafusion/scripts/health-check.sh

# Check all pods
kubectl get pods -A

# Test API (via pod, since backend is not exposed on host)
BACKEND_POD=$(kubectl get pod -n terrafusion -l app=backend -o name | head -1)
kubectl exec -n terrafusion "$BACKEND_POD" -- curl -s http://localhost:3001/api/health
kubectl exec -n terrafusion "$BACKEND_POD" -- curl -s http://localhost:3001/api/sensors

# Smoke test via frontend NodePort
curl http://localhost:30080/api/health
```

### Service URLs

| Service | URL | Credentials |
|---|---|---|
| Frontend | `http://<EC2_IP>:30080` | — |
| Backend API | `http://<EC2_IP>:30080/api/health` | — |
| Jenkins | `http://<EC2_IP>:8080` | admin / admin123 |
| Grafana | `http://<EC2_IP>:30300` | admin / admin |
| Kibana | `http://<EC2_IP>:30560` | — (create index pattern: `filebeat-*`) |
| Vault | `http://<EC2_IP>:30820` | token: root |

### Jenkins Pipeline

The `terrafusion-pipeline` job is pre-configured with CpsScmFlowDefinition pointing to the GitHub repo. It:
1. Checks out the Jenkinsfile from repo
2. Builds Docker images (backend + frontend) using Docker CLI
3. Imports images into containerd via `docker save | k3s ctr images import` (no registry needed)
4. Creates/updates the k8s Secret with real values from `.env`
5. Deploys to k3s via `kubectl set image`
6. Runs smoke test (rolls back on failure)

Access: `http://<EC2_IP>:8080/job/terrafusion-pipeline/` (admin/admin123)

## Phase 4: Disaster Recovery Demos

See `docs/DR_PROCEDURES.md` for step-by-step scenarios:
- Pod crash → auto-restart (< 10s)
- Node failure → k3s restart (< 60s)
- Failed deployment → Jenkins rollback (< 3min)
- High load → HPA auto-scale

## Phase 5: Cleanup

```bash
# Destroy everything
cd terraform
terraform destroy -auto-approve

# If destroy fails on S3 buckets:
aws s3 rm s3://terrafusion-terraform-state --recursive
aws s3 rm s3://terrafusion-backups --recursive
terraform destroy -auto-approve
```

## Troubleshooting

### Init script fails
```bash
# Check the full log
sudo cat /var/log/terrafusion-init.log
# Check Jenkins setup log
sudo cat /var/log/jenkins-setup.log
# Re-run init
sudo bash /opt/terrafusion/scripts/server-init.sh
```

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

### Jenkins login fails
```bash
# Check Jenkins status
sudo systemctl status jenkins
sudo journalctl -u jenkins --no-pager | tail -30
# Reset admin password:
sudo bash /opt/terrafusion/scripts/setup-jenkins.sh
```

### Vault sealed
```bash
kubectl exec -n vault -l app.kubernetes.io/name=vault -- vault status
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

# Recreate k8s Secret from current .env values
source backend/.env
kubectl create secret generic backend-secret -n terrafusion \
  --from-literal=DB_PASSWORD="${DB_PASSWORD}" \
  --from-literal=JWT_SECRET="${JWT_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Re-apply all k8s manifests (secret.yaml no longer exists — created above)
kubectl apply -f k8s/

# Redeploy Helm charts
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f helm/prometheus-values.yaml --wait --timeout 5m

helm upgrade --install elasticsearch elastic/elasticsearch \
  -n logging --create-namespace -f helm/elasticsearch-values.yaml --wait --timeout 5m

helm upgrade --install kibana elastic/kibana \
  -n logging -f helm/kibana-values.yaml --wait --timeout 3m

helm upgrade --install filebeat elastic/filebeat \
  -n logging -f helm/filebeat-config.yaml --wait --timeout 3m

helm upgrade --install vault hashicorp/vault \
  -n vault --create-namespace -f helm/vault-values.yaml --wait --timeout 3m

# Re-run Jenkins setup
sudo bash scripts/setup-jenkins.sh
```
