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

# 3. Initialize and apply
terraform init
terraform plan
terraform apply -auto-approve
```

**Expected output (~25 min):**
```
Apply complete! Resources: 32 added.

Outputs:
ec2_public_ip           = "13.xxx.xxx.xxx"
rds_endpoint            = "terrafusion-mysql.xxxxxx.ap-south-1.rds.amazonaws.com"
ssh_command             = "ssh -i ~/.ssh/your-key.pem ubuntu@13.xxx.xxx.xxx"
jenkins_url             = "http://13.xxx.xxx.xxx:8080"
application_url         = "http://13.xxx.xxx.xxx:30080"
grafana_url             = "http://13.xxx.xxx.xxx:30300"
vault_url               = "http://13.xxx.xxx.xxx:30820"
```

## Phase 2: Bootstrap (Fully Automated)

`terraform apply` writes `server-init.sh` as EC2 user_data. On first boot it runs:

| Step | What happens | Verification |
|---|---|---|
| 1 | apt update + upgrade | `cat /var/log/terrafusion-init.log` |
| 2 | Install deps: git, curl, Docker, Node.js 22, k3s, Helm, AWS CLI | `docker --version` |
| 3 | Clone repo → `/opt/terrafusion`, build Docker images, import to k3s containerd | `docker images` |
| 4 | Create namespace, ConfigMap, Secret, apply k8s manifests | `kubectl get pods -A` |
| 5 | Install metrics-server | `kubectl get pods -n kube-system` |
| 6 | Install Jenkins (native systemd), plugins, pipeline job, trigger build | `sudo systemctl status jenkins` |
| 7 | Install Helm charts: Prometheus/Grafana + Vault | `helm list -A` |
| 8 | Post-deployment health check | Check API: `/api/health` |

Wait ~5-8 min for init log to complete:

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@<EC2_PUBLIC_IP>
sudo tail -50 /var/log/terrafusion-init.log
```

If init log shows errors, re-run:
```bash
sudo bash /opt/terrafusion/scripts/server-init.sh
```

### Post-Bootstrap: RDS Values Injected

After init completes, Terraform's `null_resource "rds_config"` SSHes into the EC2 and:
1. Updates `backend-config` ConfigMap with real RDS endpoint + credentials
2. Updates `backend-secret` Secret with real RDS password
3. Restarts backend pods (old ones had placeholder values from parallel provisioning)

This is automatic — no manual steps.

## Phase 3: Verify & Access

```bash
# Check all pods
kubectl get pods -A

# Test API via pod
BACKEND_POD=$(kubectl get pod -n terrafusion -l app=backend -o name | head -1)
kubectl exec -n terrafusion "$BACKEND_POD" -- curl -s http://localhost:3001/api/health

# Test via Ingress (port 80)
curl http://localhost/api/health

# Test via NodePort
curl http://localhost:30080/api/health
```

### Service URLs

| Service | URL | Credentials |
|---|---|---|
| Frontend | `http://<EC2_IP>` (Ingress :80) | — |
| Frontend (alt) | `http://<EC2_IP>:30080` (NodePort) | — |
| Backend API | `http://<EC2_IP>/api/health` | — |
| Jenkins | `http://<EC2_IP>:8080` | admin / admin123 |
| Grafana | `http://<EC2_IP>:30300` | admin / prom-operator |
| Vault | `http://<EC2_IP>:30820` | token: root |

### Jenkins Pipeline

The `terrafusion-pipeline` job is pre-configured and runs:

1. Checkout (`scm` from GitHub)
2. Build Docker images (backend + frontend)
3. Import to k3s via `docker save | k3s ctr images import` (no ECR needed)
4. Deploy via `kubectl set image`
5. Smoke test (`curl /api/health` → rollback on failure)

Trigger: `http://<EC2_IP>:8080/job/terrafusion-pipeline/` (admin/admin123)

## Phase 4: Disaster Recovery

See `docs/DR_PROCEDURES.md` for:
- Pod crash → auto-restart (< 10s)
- Node failure → k3s restart (< 60s)
- RDS reboot → auto-reconnect (< 60s)
- Failed deployment → Jenkins rollback (< 3min)
- High load → HPA auto-scale

## Phase 5: Cleanup

```bash
cd terraform
terraform destroy -auto-approve
```

If destroy fails on S3 buckets:
```bash
aws s3 rm s3://terrafusion-terraform-state --recursive
aws s3 rm s3://terrafusion-backups --recursive
terraform destroy -auto-approve
```

## Troubleshooting

### Init script fails
```bash
sudo cat /var/log/terrafusion-init.log
sudo cat /var/log/jenkins-setup.log
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

### Backend 500 / login fails
```bash
kubectl logs -n terrafusion deploy/backend --tail=20
# Check ConfigMap has real RDS values:
kubectl get configmap -n terrafusion backend-config -o yaml
# Check Secret has real password:
kubectl get secret -n terrafusion backend-secret -o jsonpath="{.data.DB_PASSWORD}" | base64 -d
# If placeholders remain:
kubectl delete pod -n terrafusion -l app=backend
```

### RDS connection fails
```bash
mysql -h <RDS_ENDPOINT> -u terrafusion_admin -p -e "SHOW DATABASES;"
```

### Jenkins login fails
```bash
sudo systemctl status jenkins
sudo journalctl -u jenkins --no-pager | tail -30
sudo bash /opt/terrafusion/scripts/setup-jenkins.sh
```

### Vault sealed
```bash
kubectl exec -n vault -l app.kubernetes.io/name=vault -- vault status
# Dev mode auto-unseals on restart
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

# Recreate secrets
source backend/.env
kubectl create secret generic backend-secret -n terrafusion \
  --from-literal=DB_PASSWORD="${DB_PASSWORD}" \
  --from-literal=JWT_SECRET="${JWT_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Re-apply all manifests
kubectl apply -f k8s/

# Redeploy Helm charts
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f helm/prometheus-values.yaml --wait --timeout 5m
helm upgrade --install vault hashicorp/vault \
  -n vault --create-namespace -f helm/vault-values.yaml --wait --timeout 3m

# Re-run Jenkins setup
sudo bash scripts/setup-jenkins.sh
```
