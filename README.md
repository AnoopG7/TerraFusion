# TerraFusion — Global Climate Engineering Platform

End-to-end DevOps ecosystem: **Terraform → Docker → k3s → Jenkins → Prometheus/Grafana → Vault** on a single EC2 instance.

## Quick Start

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit: ssh_allowed_cidr, rds_master_password, key_pair_name

terraform init
terraform apply -auto-approve   # ~25 min (EC2 + RDS in parallel)
```

Wait for bootstrap (automated), then access:

| Service | URL | Credentials |
|---------|-----|-------------|
| Frontend | `http://<EC2_IP>` | — |
| Backend API | `http://<EC2_IP>/api/health` | — |
| Jenkins | `http://<EC2_IP>:8080` | admin / admin123 |
| Grafana | `http://<EC2_IP>:30300` | admin / prom-operator |
| Vault | `http://<EC2_IP>:30820` | token: root |

## Architecture

```
Internet ──► EC2 (k3s + Jenkins)
               ├── terrafusion/  ← backend + frontend pods
               ├── monitoring/   ← Prometheus + Grafana
               └── vault/        ← HashiCorp Vault
               │
RDS MySQL ◄────┘ (private subnet)
```

- **Single EC2** (m7i-flex.large, Ubuntu 24.04) runs everything
- **k3s** for Kubernetes orchestration (lightweight, single binary)
- **Jenkins** as native systemd service (CI/CD pipeline)
- **No ECR** — images imported directly via `docker save | k3s ctr images import`
- **No ELK** — Elasticsearch/Filebeat/Kibana removed
- **EC2 + RDS provisioned in parallel** — saves ~9 min; null_resource injects real RDS values post-creation
- **Traefik Ingress** — routes port 80 to frontend

## Key Scripts

| Script | Purpose |
|--------|---------|
| `scripts/server-init.sh` | First-boot init: deps, k3s, Docker, Jenkins, Helm charts |
| `scripts/setup-jenkins.sh` | Jenkins setup: plugins, admin user, pipeline job, trigger build |
| `scripts/deploy-app.sh` | Manual deploy: git pull, docker build, k3s import, smoke test |
| `scripts/health-check.sh` | Cron health check (API + k3s + disk/memory) |
| `scripts/backup.sh` | MySQL dump → gzip → S3 |
| `terraform/ec2.tf` | EC2 instance + security groups + null_resource rds_config |

## CI/CD Pipeline

```
Checkout → npm ci → tsc → Docker build → docker save | k3s ctr images import →
kubectl set image → rollout status → health check (rollback on failure)
```

Trigger: Jenkins UI → `terrafusion-pipeline` (admin/admin123)

## Cleanup

```bash
cd terraform
terraform destroy -auto-approve
```
