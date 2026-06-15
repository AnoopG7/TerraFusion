# TerraFusion — Architecture

## Network Topology

```
┌──────────────────────────────────────────────────────────────────────────┐
│                               INTERNET                                   │
│                                                                          │
│   ┌─ Browser/User ─┐   ┌─ SSH Client ─┐   ┌─ Jenkins Web ─┐            │
│   │  :80 (Ingress)  │   │  :22         │   │  :8080        │            │
│   └───────┬─────────┘   └──────┬───────┘   └──────┬────────┘            │
└───────────┼────────────────────┼───────────────────┼────────────────────┘
            │                    │                   │
            ▼                    ▼                   ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  AWS REGION (ap-south-1)                                                │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │              VPC (10.0.0.0/16)                                   │   │
│  │                                                                  │   │
│  │  ┌────── Public Subnet A (10.0.1.0/24) ─────────────────────────┐│   │
│  │  │                                                              ││   │
│  │  │  EC2 — m7i-flex.large (Ubuntu 24.04 LTS)                    ││   │
│  │  │  EIP: <public-ip> | IMDSv2: required | EBS: 20GB gp3        ││   │
│  │  │  User-data: server-init.sh | AWS CLI: configured             ││   │
│  │  │                                                              ││   │
│  │  │  ┌─────────────────────────────────────────────────────┐   ││   │
│  │  │  │  SYSTEM LAYER (systemd services)                     │   ││   │
│  │  │  │  ┌──────────┐  ┌──────────┐  ┌────────┐  ┌──────┐ │   ││   │
│  │  │  │  │ Docker   │  │ k3s      │  │ Helm   │  │Jenkins│ │   ││   │
│  │  │  │  │ v27.x    │  │ v1.35.x  │  │ v3.x   │  │systemd│ │   ││   │
│  │  │  │  └──────────┘  └──────────┘  └────────┘  └──────┘ │   ││   │
│  │  │  └─────────────────────────────────────────────────────┘   ││   │
│  │  │                                                              ││   │
│  │  │  ┌─────────────────────────────────────────────────────┐   ││   │
│  │  │  │  KUBERNETES LAYER (k3s cluster)                      │   ││   │
│  │  │  │                                                      │   ││   │
│  │  │  │  ┌─ Namespace: terrafusion ──────────────────────┐ │   ││   │
│  │  │  │  │                                                │ │   ││   │
│  │  │  │  │  ┌─ frontend ──────────────────────┐           │ │   ││   │
│  │  │  │  │  │  Deployment (2 replicas)        │           │ │   ││   │
│  │  │  │  │  │  Image: terrafusion-frontend    │           │ │   ││   │
│  │  │  │  │  │  Container: nginx :80           │           │ │   ││   │
│  │  │  │  │  │  HPA: 2-3 @ 70% CPU            │           │ │   ││   │
│  │  │  │  │  └──────────┬──────────────────────┘           │ │   ││   │
│  │  │  │  │             │ proxy_pass /api/                 │ │   ││   │
│  │  │  │  │  ┌─ backend ──────────────────────┐            │ │   ││   │
│  │  │  │  │  │  Deployment (2 replicas)        │           │ │   ││   │
│  │  │  │  │  │  Image: terrafusion-backend     │           │ │   ││   │
│  │  │  │  │  │  Container: express :3001       │           │ │   ││   │
│  │  │  │  │  │  HPA: 2-5 @ 70% CPU / 80% MEM  │           │ │   ││   │
│  │  │  │  │  │  Env: ConfigMap + Secret        │           │ │   ││   │
│  │  │  │  │  └─────────────────────────────────┘           │ │   ││   │
│  │  │  │  └────────────────────────────────────────────────┘ │   ││   │
│  │  │  │                                                      │   ││   │
│  │  │  │  ┌─ Namespace: monitoring ──────────────────────┐   │   ││   │
│  │  │  │  │  prometheus :9090 (ClusterIP)                 │   │   ││   │
│  │  │  │  │  grafana :80 (NodePort 30300)                 │   │   ││   │
│  │  │  │  │  Scrapes: backend /api/metrics :3001         │   │   ││   │
│  │  │  │  │  Alertmanager :9093                           │   │   ││   │
│  │  │  │  └──────────────────────────────────────────────┘   │   ││   │
│  │  │  │                                                      │   ││   │
│  │  │  │  ┌─ Namespace: vault ──────────────────────────┐   │   ││   │
│  │  │  │  │  vault :8200 (NodePort 30820)                │   │   ││   │
│  │  │  │  │  Dev mode, root token: root                  │   │   ││   │
│  │  │  │  │  KV store for backend secrets                │   │   ││   │
│  │  │  │  └──────────────────────────────────────────────┘   │   ││   │
│  │  │  │                                                      │   ││   │
│  │  │  │  ┌─ Ingress ───────────────────────────────────┐   │   ││   │
│  │  │  │  │  Traefik (kube-system) :80 → frontend :80   │   │   ││   │
│  │  │  │  │  Routes: / → frontend service               │   │   ││   │
│  │  │  │  └──────────────────────────────────────────────┘   │   ││   │
│  │  │  └─────────────────────────────────────────────────────┘   ││   │
│  │  │                                                              ││   │
│  │  │  ┌─────────────────────────────────────────────────────┐   ││   │
│  │  │  │  CI/CD LAYER                                         │   ││   │
│  │  │  │  Jenkins (systemd) :8080                              │   ││   │
│  │  │  │  Pipeline: git → npm ci → tsc → docker build →      │   ││   │
│  │  │  │           docker save | k3s ctr import → deploy      │   ││   │
│  │  │  │  Rollback on smoke test failure                      │   ││   │
│  │  │  └─────────────────────────────────────────────────────┘   ││   │
│  │  └──────────────────────────────────────────────────────────────┘│   │
│  │                                                                  │   │
│  │  ┌── Private Subnet A (10.0.10.0/24) ─────────────────────────┐ │   │
│  │  │  RDS MySQL 8.0 — db.t4g.micro                              │ │   │
│  │  │  ├── Endpoint: terrafusion-mysql.xxxx.ap-south-1.rds...:3306│ │   │
│  │  │  ├── Storage: 20GB gp3, encrypted, auto-backups 7 days     │ │   │
│  │  │  └── Access: EC2 security group only (port 3306)           │ │   │
│  │  └────────────────────────────────────────────────────────────┘ │   │
│  │                                                                  │   │
│  │  ┌── Private Subnet B (10.0.11.0/24) ─────────────────────────┐ │   │
│  │  │  (Reserved for future use)                                  │ │   │
│  │  └────────────────────────────────────────────────────────────┘ │   │
│  │                                                                  │   │
│  │  ┌── S3 Gateway Endpoint ────────────────────────────────────┐  │   │
│  │  │  Private subnet → S3 (free, no NAT needed)                │  │   │
│  │  └───────────────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ┌── S3 Buckets ───────────────────────────────────────────────────┐    │
│  │  terrafusion-terraform-state  ← Terraform backend (local state) │    │
│  │  terrafusion-backups          ← DB dumps (90-day retention)    │    │
│  └──────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────┘
```

## Provisioning Flow

### Parallel EC2 + RDS

```
terraform apply
    │
    ├── EC2 created (user_data = file(server-init.sh))
    │   └── No reference to RDS — uses ${RDS_HOST:-__REPLACE_ME__} fallback
    │
    ├── RDS created in parallel (~9 min faster than sequential)
    │
    └── null_resource "rds_config" (depends on both EC2 + RDS)
        └── SSH into EC2, update ConfigMap + Secret + .env with real RDS values
            └── kubectl delete pod → pods restart with correct values
```

### Bootstrap Sequence

```
EC2 first boot
    │
    1. apt update/upgrade
    2. Install Docker, k3s, Helm, AWS CLI, Node.js 22
    3. Clone repo → build Docker images
    4. Import images into k3s containerd
    5. Create k8s ConfigMap + Secret from .env (placeholder values)
    6. Apply k8s manifests (namespace, deployments, services, HPAs, ingress, network policy)
    7. Install metrics-server
    8. Install Jenkins via setup-jenkins.sh (init.groovy → admin user → plugins → pipeline)
    9. Install Helm charts: Prometheus/Grafana + Vault
    10. Store backend secrets in Vault KV store
    11. Post-deployment health check

null_resource (after EC2 + RDS both ready)
    │
    ├── kubectl create configmap backend-config ... (real RDS values)
    ├── kubectl create secret backend-secret ... (real RDS password)
    ├── kubectl delete pod -l app=backend (restart with correct values)
    └── sed update .env with real RDS endpoint + password
```

## Component Details

### Infrastructure Layer (Terraform)
| Resource | Type | Details | Purpose |
|---|---|---|---|
| VPC | `aws_vpc` | 10.0.0.0/16 | Network boundary |
| Public Subnet | `aws_subnet` | 10.0.1.0/24, auto-assign public IP | Hosts EC2 |
| Private Subnet A | `aws_subnet` | 10.0.10.0/24 | RDS primary |
| Private Subnet B | `aws_subnet` | 10.0.11.0/24 | RDS standby (reserved) |
| Internet Gateway | `aws_internet_gateway` | Attached to VPC | Internet access |
| EC2 | `aws_instance` | m7i-flex.large, Ubuntu 24.04, 20GB gp3 | All compute |
| EC2 EIP | `aws_eip` | Elastic IP, attached to EC2 | Stable public IP |
| Security Group EC2 | `aws_security_group` | SSH(22), HTTP(80), Jenkins(8080), K8s(6443), NodePort(30000-32767) | Access control |
| Security Group RDS | `aws_security_group` | MySQL(3306) from EC2 SG only | DB isolation |
| RDS | `aws_db_instance` | MySQL 8.0, db.t4g.micro, 20GB gp3 | Persistence |
| S3 State | `aws_s3_bucket` | Versioned, encrypted | Terraform backend |
| S3 Backup | `aws_s3_bucket` | Versioned, 90-day lifecycle | DB backups |
| S3 VPC Endpoint | `aws_vpc_endpoint` | Gateway type | Private S3 access |

### Security Group Rules
| Rule | Port | Source | Purpose |
|---|---|---|---|
| SSH ingress | 22 | Your IP (/32) | SSH access |
| HTTP ingress | 80 | 0.0.0.0/0 | App frontend (Traefik) |
| HTTPS ingress | 443 | 0.0.0.0/0 | Future TLS |
| Jenkins ingress | 8080 | Your IP (/32) | Jenkins UI |
| k3s API ingress | 6443 | Your IP (/32) | Remote kubectl |
| NodePort ingress | 30000-32767 | Your IP (/32) | K8s services |
| MySQL ingress | 3306 | EC2 SG only | RDS access |
| All egress | All | 0.0.0.0/0 | Outbound |

### Kubernetes Layer (k3s)
| Namespace | Resource | Replicas | Image | Port |
|---|---|---|---|---|
| terrafusion | backend Deployment | 2-5 (HPA) | terrafusion-backend | :3001 |
| terrafusion | frontend Deployment | 2-3 (HPA) | terrafusion-frontend | :80 |
| terrafusion | backend Service | — | ClusterIP | 3001 |
| terrafusion | frontend Service | — | NodePort 30080 | 80 |
| terrafusion | Ingress | — | Traefik → frontend :80 | 80 |
| terrafusion | backend HPA | 2-5 | 70% CPU / 80% MEM | — |
| terrafusion | frontend HPA | 2-3 | 70% CPU | — |
| monitoring | prometheus-kube-prometheus-prometheus | 1 | prometheus/prometheus | :9090 |
| monitoring | prometheus-grafana | 1 | grafana/grafana | :80 (30300) |
| vault | vault | 1 | hashicorp/vault | :8200 (30820) |

### Jenkins CI/CD Pipeline
```
Git Push (main)
     │
     ▼
┌─────────────┐    ┌──────────────┐    ┌──────────────────────────┐
│ 1. Checkout  │──►│ 2. Build     │──►│ 3. Import to k3s         │
│ git fetch    │    │ docker build │    │ docker save |            │
│ (scm)        │    │ backend +    │    │ k3s ctr images import   │
│              │    │ frontend     │    │ (no ECR needed)          │
└─────────────┘    └──────────────┘    └────────────┬─────────────┘
                                                    │
                                                    ▼
┌─────────────┐    ┌──────────────┐    ┌──────────────────────────┐
│ 4. Rollback  │◄──│ 3. Smoke Test│◄──│ 2. Deploy                │
│ kubectl      │    │ curl /api/   │    │ kubectl set image       │
│ rollout undo │    │ health 200?  │    │ rollout status --wait   │
└─────────────┘    └──────────────┘    └──────────────────────────┘
```

## Data Flow

### User Request
```
Browser ──► :80 ──► Traefik Ingress ──► frontend Service (NodePort 30080)
              └── nginx pod ──► /api/* ──► backend ClusterIP :3001
                                              └── Express ──► RDS MySQL :3306
```

### Monitoring
```
Prometheus ──► kube-state-metrics (K8s API)
            ──► kubelet cAdvisor :10250
            ──► backend /api/metrics :3001
            ──► node-exporter DaemonSet :9100
              │
              └── Grafana (NodePort 30300)
```

### Secrets
```
Vault (k3s pod :8200, dev mode)
  └── KV v2: secret/terrafusion/backend
        ├── DB_PASSWORD
        ├── JWT_SECRET
        ├── DB_HOST
        └── DB_NAME
```

### Backup
```
RDS MySQL ──► backup.sh (mysqldump → gzip → timestamp)
                └── S3 bucket (terrafusion-backups, 90-day lifecycle)
                    Daily at 2AM (cron)
```

## Technology Stack

| Category | Technology | Version | Purpose |
|---|---|---|---|
| Cloud | AWS ap-south-1 | — | Mumbai region |
| Compute | EC2 m7i-flex.large | — | 2 vCPU, 8GB RAM |
| OS | Ubuntu 24.04 LTS | Noble | LTS, Docker/k3s native |
| Containers | Docker | 27.x | Image build/runtime |
| Orchestration | k3s | 1.35.x | Lightweight K8s |
| CI/CD | Jenkins (systemd) | Latest | Pipeline as Code |
| IaC | Terraform | ≥ 1.5 | AWS provider |
| Database | MySQL (RDS) | 8.0.44 | Relational |
| Monitoring | Prometheus + Grafana | Latest | Observability |
| Secrets | HashiCorp Vault | Latest | KV store |
| Frontend | React + Nginx | Node 22 | SPA, Vite build |
| Backend | Node.js + Express + Knex | 22 | REST API |
| Ingress | Traefik (k3s built-in) | Latest | HTTP routing |
| Backup | AWS CLI + S3 | v2 | DB snapshots |

## Service URLs

| Service | URL | Access |
|---|---|---|
| Frontend | `http://<EC2_IP>` | Port 80 (Traefik Ingress) |
| Backend API | `http://<EC2_IP>/api/health` | Via Ingress |
| Frontend (direct) | `http://<EC2_IP>:30080` | NodePort fallback |
| Jenkins | `http://<EC2_IP>:8080` | admin / admin123 |
| Grafana | `http://<EC2_IP>:30300` | admin / prom-operator |
| Vault | `http://<EC2_IP>:30820` | token: root |
