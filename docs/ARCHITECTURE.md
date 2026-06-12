# TerraFusion — Architecture

## Network Topology

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                                   INTERNET                                       │
│                                                                                  │
│   ┌─ Browser/User ─┐   ┌─ SSH Client ─┐   ┌─ Jenkins Web ─┐   ┌─ Git Push ─┐   │
│   │  :80 / :30080  │   │  :22         │   │  :8080        │   │  GitHub    │   │
│   └───────┬────────┘   └──────┬───────┘   └──────┬────────┘   └──────┬──────┘   │
└───────────┼───────────────────┼───────────────────┼───────────────────┼──────────┘
            │                   │                   │                   │
            ▼                   ▼                   ▼                   │
┌───────────────────────────────────────────────────────────────────────┼──────────┐
│  AWS REGION (ap-south-1)                          ┌──────────────────┼──────┐   │
│                                                    │  Security Groups │      │   │
│  ┌─────────────────────────────────────────────────┼──────────────────┼──┐   │   │
│  │              VPC (10.0.0.0/16)                  │                  │  │   │   │
│  │                                                  ▼                  ▼  │   │   │
│  │  ┌────────────── Public Subnet A (10.0.1.0/24) ─────────────────────────┐ │   │
│  │  │                                                                      │ │   │
│  │  │  ┌──────────────────────────────────────────────────────────────┐    │ │   │
│  │  │  │  EC2 — m7i-flex.large (Ubuntu 24.04 LTS)                     │    │ │   │
│  │  │  │  EIP: <public-ip>  |  IMDSv2: required  |  EBS: 20GB gp3    │    │ │   │
  │  │  │  │  User-data: server-init.sh            |  AWS CLI: configured    │    │ │   │
│  │  │  │                                                                  │ │   │
│  │  │  │  ┌─────────────────────────────────────────────────────────┐   │ │   │
│  │  │  │  │  SYSTEM LAYER (systemd services)                         │   │ │   │
│  │  │  │  │  ┌──────────┐  ┌──────────┐  ┌────────┐  ┌──────────┐ │   │ │   │
│  │  │  │  │  │ Docker   │  │ k3s      │  │ Helm   │  │ AWS CLI  │ │   │ │   │
│  │  │  │  │  │ v27.x    │  │ v1.30.x  │  │ v3.x   │  │ v2.x     │ │   │ │   │
│  │  │  │  │  └──────────┘  └──────────┘  └────────┘  └──────────┘ │   │ │   │
│  │  │  │  └─────────────────────────────────────────────────────────┘   │ │   │
│  │  │  │                                                                  │ │   │
│  │  │  │  ┌─────────────────────────────────────────────────────────┐   │ │   │
│  │  │  │  │  CONTAINER LAYER (Docker Compose — dev fallback)         │   │ │   │
│  │  │  │  │  ┌───────────────────┐    ┌──────────────────┐          │   │ │   │
│  │  │  │  │  │ terrafusion-web   │    │ terrafusion-api  │          │   │ │   │
│  │  │  │  │  │ Nginx :80 → :3001 │    │ Express :3001    │          │   │ │   │
│  │  │  │  │  │                   │──► │ SQLite (data/)   │          │   │ │   │
│  │  │  │  │  └───────────────────┘    └──────────────────┘          │   │ │   │
│  │  │  │  └─────────────────────────────────────────────────────────┘   │ │   │
│  │  │  │                                                                  │ │   │
│  │  │  │  ┌─────────────────────────────────────────────────────────┐   │ │   │
│  │  │  │  │  KUBERNETES LAYER (k3s cluster)                          │   │ │   │
│  │  │  │  │                                                          │   │ │   │
│  │  │  │  │  ┌─ Namespace: terrafusion ──────────────────────────┐   │   │ │   │
│  │  │  │  │  │                                                    │   │   │ │   │
│  │  │  │  │  │  ┌─ frontend ──────────────────────────┐           │   │   │ │   │
│  │  │  │  │  │  │  Deployment (2 replicas)            │           │   │   │ │   │
│  │  │  │  │  │  │  Image: ECR/terrafusion-frontend    │           │   │   │ │   │
│  │  │  │  │  │  │  Container: nginx :80               │           │   │   │ │   │
│  │  │  │  │  │  │  Liveness: GET / :80                │           │   │   │ │   │
│  │  │  │  │  │  │  HPA: 2-3 @ 70% CPU                 │           │   │   │ │   │
│  │  │  │  │  │  └──────────┬──────────────────────────┘           │   │   │ │   │
│  │  │  │  │  │             │                                      │   │   │ │   │
│  │  │  │  │  │             ▼ proxy_pass /api/                     │   │   │ │   │
│  │  │  │  │  │  ┌─ backend ───────────────────────────┐           │   │   │ │   │
│  │  │  │  │  │  │  Deployment (2 replicas)            │           │   │   │ │   │
│  │  │  │  │  │  │  Image: ECR/terrafusion-backend     │           │   │   │ │   │
│  │  │  │  │  │  │  Container: express :3001           │           │   │   │ │   │
│  │  │  │  │  │  │  Liveness: GET /api/health :3001    │           │   │   │ │   │
│  │  │  │  │  │  │  HPA: 2-5 @ 70% CPU / 80% MEM      │           │   │   │ │   │
│  │  │  │  │  │  │  Env: ConfigMap + Secret            │           │   │   │ │   │
│  │  │  │  │  │  └─────────────────────────────────────┘           │   │   │ │   │
│  │  │  │  │  └────────────────────────────────────────────────────┘   │   │ │   │
│  │  │  │  │                                                          │   │ │   │
│  │  │  │  │  ┌─ Namespace: monitoring ──────────────────────────┐   │   │ │   │
│  │  │  │  │  │  prometheus-kube-prometheus-prometheus :9090     │   │   │ │   │
│  │  │  │  │  │  prometheus-grafana :80 (NodePort 30300)         │   │   │ │   │
│  │  │  │  │  │  Scrapes: backend /api/metrics :3001            │   │   │ │   │
│  │  │  │  │  │  Alertmanager :9093                              │   │   │ │   │
│  │  │  │  │  └──────────────────────────────────────────────────┘   │   │ │   │
│  │  │  │  │                                                          │   │ │   │
│  │  │  │  │  ┌─ Namespace: logging ────────────────────────────┐   │   │ │   │
│  │  │  │  │  │  elasticsearch-master :9200 (ClusterIP)          │   │   │ │   │
│  │  │  │  │  │  kibana-kibana :5601 (NodePort 30560)            │   │   │ │   │
│  │  │  │  │  │  filebeat (DaemonSet, ships container logs)      │   │   │ │   │
│  │  │  │  │  │  Logs: /var/log/containers/*.log → ES            │   │   │ │   │
│  │  │  │  │  └──────────────────────────────────────────────────┘   │   │ │   │
│  │  │  │  │                                                          │   │ │   │
│  │  │  │  │  ┌─ Namespace: vault ──────────────────────────────┐   │   │ │   │
│  │  │  │  │  │  vault :8200 (NodePort 30820)                    │   │   │ │   │
│  │  │  │  │  │  Dev mode, root token: root                      │   │   │ │   │
│  │  │  │  │  │  KV store for backend secrets                     │   │   │ │   │
│  │  │  │  │  └──────────────────────────────────────────────────┘   │   │ │   │
│  │  │  │  └─────────────────────────────────────────────────────────┘   │ │   │
│  │  │  │                                                                  │ │   │
│  │  │  │  ┌─────────────────────────────────────────────────────────┐   │ │   │
│  │  │  │  │  CI/CD LAYER (Jenkins — native systemd)                  │   │ │   │
│  │  │  │  │  jenkins :8080 (systemd service)                         │   │ │   │
│  │  │  │  │  Home: /var/lib/jenkins  |  Workspace: /var/lib/jenkins/│   │ │   │
│  │  │  │  │  │                           workspaces/terrafusion-pipe│   │ │   │
│  │  │  │  │  │  line                                                │   │ │   │
│  │  │  │  │  Tools: docker, kubectl (host), aws cli, node 22       │   │ │   │
│  │  │  │  └─────────────────────────────────────────────────────────┘   │ │   │
│  │  │  │                                                                  │ │   │
│  │  │  │  ┌─────────────────────────────────────────────────────────┐   │ │   │
│  │  │  │  │  BACKUP/MAINTENANCE LAYER (Cron jobs)                   │   │ │   │
│  │  │  │  │  */5 * * * *  → health-check.sh (API + k3s + disk/mem)  │   │ │   │
│  │  │  │  │  0 2 * * *    → backup.sh (mysqldump → gzip → S3)      │   │ │   │
│  │  │  │  │  0 3 * * 0   → rotate-logs.sh (compress + truncate)    │   │ │   │
│  │  │  │  │  0 4 * * *   → docker system prune -f --volumes         │   │ │   │
│  │  │  │  └─────────────────────────────────────────────────────────┘   │ │   │
│  │  │  └──────────────────────────────────────────────────────────────┘ │   │
│  │  └──────────────────────────────────────────────────────────────────────┘   │
│  │                                                                              │
│  │  ┌──── Private Subnet A (10.0.10.0/24) ─────────────────────────────────┐  │
│  │  │  RDS MySQL 8.0 — db.t4g.micro                                          │  │
│  │  │  ├── Primary: terrafusion-mysql.xxxxxx.ap-south-1.rds.amazonaws.com:3306 │  │
│  │  │  ├── Storage: 20GB gp3, encrypted, auto-backups 7 days                │  │
│  │  │  ├── Publicly accessible: false (EC2 SG only, port 3306)              │  │
│  │  │  └── Knex connection pool in backend (max 10 connections)             │  │
│  │  └──────────────────────────────────────────────────────────────────────┘  │
│  │                                                                              │
│  │  ┌──── Private Subnet B (10.0.11.0/24) ─────────────────────────────────┐  │
│  │  │  (Reserved for future use)                                              │  │
│  │  └──────────────────────────────────────────────────────────────────────┘  │
│  │                                                                              │
│  │  ┌──── Services via VPC Endpoints ─────────────────────────────────────┐   │
│  │  │  S3 Gateway Endpoint (free) — RDS backup → S3 via private network   │   │
│  │  │  ECR API (via Internet — EC2 in public subnet has IGW access)        │   │
│  │  └─────────────────────────────────────────────────────────────────────┘   │
│  │                                                                              │
│  └──────────────────────────────────────────────────────────────────────────────┘
│                                                                                  │
│  ┌──── S3 (us-east-1) ─────────────────────────────────────────────────────┐   │
│  │  terrafusion-terraform-state  ← Terraform backend (DynamoDB locked)      │   │
│  │  terrafusion-backups          ← DB dumps (30-day retention, 90-day S3)   │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌──── ECR (ap-south-1) ───────────────────────────────────────────────────┐   │
│  │  terrafusion-frontend  ← Docker images for React frontend                │   │
│  │  terrafusion-backend   ← Docker images for Express backend               │   │
│  │  Both: scan_on_push=true, mutable tags (latest + timestamp)              │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

## Component Details

### Infrastructure Layer (Terraform)
| Resource | Type | Details | Purpose |
|---|---|---|---|
| VPC | `aws_vpc` | 10.0.0.0/16, DNS hostname + support enabled | Network boundary |
| Public Subnet | `aws_subnet` | 10.0.1.0/24 in ap-south-1a, auto-assign public IP | Hosts EC2 |
| Private Subnet A | `aws_subnet` | 10.0.10.0/24 in ap-south-1a | RDS primary |
| Private Subnet B | `aws_subnet` | 10.0.11.0/24 in ap-south-1b | RDS standby (single-AZ, reserved) |
| Internet Gateway | `aws_internet_gateway` | Attached to VPC | Public internet access |
| EC2 | `aws_instance` | m7i-flex.large, Ubuntu 24.04, 20GB gp3, IMDSv2 | All compute |
| Security Group EC2 | `aws_security_group` | SSH(22), HTTP(80,443), Jenkins(8080), K8s API(6443), NodePort(30000-32767) | Access control |
| Security Group RDS | `aws_security_group` | MySQL(3306) from EC2 SG only | DB isolation |
| RDS | `aws_db_instance` | MySQL 8.0, db.t4g.micro, 20GB gp3, 7-day backup | Persistence |
| ECR Frontend | `aws_ecr_repository` | scan_on_push, mutable tags | Image registry |
| ECR Backend | `aws_ecr_repository` | scan_on_push, mutable tags | Image registry |
| S3 State | `aws_s3_bucket` | Versioned, encrypted, public access blocked | Terraform backend |
| S3 Backup | `aws_s3_bucket` | Versioned, 90-day lifecycle | DB backup storage |
| DynamoDB | `aws_dynamodb_table` | PAY_PER_REQUEST, LockID hash key | Terraform state locking |


### Security Group Rules
| Rule | Port | Source | Purpose |
|---|---|---|---|
| SSH ingress | 22 | Your IP (/32) | SSH access |
| HTTP ingress | 80 | 0.0.0.0/0 | App frontend |
| HTTPS ingress | 443 | 0.0.0.0/0 | Future TLS |
| Jenkins ingress | 8080 | Your IP (/32) | Jenkins UI |
| k3s API ingress | 6443 | Your IP (/32) | Remote kubectl |
| NodePort ingress | 30000-32767 | Your IP (/32) | K8s services |
| MySQL ingress | 3306 | EC2 SG only | RDS access |
| All egress | All | 0.0.0.0/0 | Outbound traffic |

### Kubernetes Layer (k3s)
| Namespace | Resource | Replicas | Image | Port | Probe |
|---|---|---|---|---|---|
| terrafusion | backend Deployment | 2-5 (HPA) | ECR/terrafusion-backend | :3001 | GET /api/health |
| terrafusion | frontend Deployment | 2-3 (HPA) | ECR/terrafusion-frontend | :80 | GET / |
| terrafusion | backend Service | — | ClusterIP | 3001 | — |
| terrafusion | frontend Service | — | NodePort 30080 | 80 | — |
| terrafusion | backend HPA | 2-5 | 70% CPU / 80% MEM | — | — |
| terrafusion | frontend HPA | 2-3 | 70% CPU | — | — |
| monitoring | prometheus | 1 | prometheus/prometheus | :9090 | — |
| monitoring | grafana | 1 | grafana/grafana | :80 (30300) | — |
| monitoring | alertmanager | 1 | prometheus/alertmanager | :9093 | — |
| logging | elasticsearch | 1 | elastic/elasticsearch:8.11.0 | :9200 | — |
| logging | kibana | 1 | elastic/kibana:8.11.0 | :5601 (30560) | — |
| logging | filebeat | DaemonSet | elastic/filebeat:8.11.0 | — | — |
| vault | vault | 1 | hashicorp/vault | :8200 (30820) | — |

### Jenkins CI/CD Pipeline
```
Git Push (main)
     │
     ▼
┌─────────────┐    ┌──────────────┐    ┌────────────┐
│ 1. Checkout  │──►│ 2. Build     │──►│ 3. Push    │
│ git fetch    │    │ docker build │    │ aws ecr    │
│ reset --hard │    │ backend +    │    │ push :tag  │
│              │    │ frontend     │    │ push :latest│
└─────────────┘    └──────────────┘    └──────┬─────┘
                                              │
                                              ▼
┌─────────────┐    ┌──────────────┐    ┌────────────┐
│ 6. Rollback  │◄──│ 5. Smoke Test│◄──│ 4. Deploy  │
│ kubectl      │    │ curl /api/   │    │ kubectl    │
│ rollout undo │    │ health 200?  │    │ set image  │
└─────────────┘    └──────────────┘    └────────────┘
     │                                              │
     └────────────── FAIL ──────────────┘
```

## Data Flow Diagrams

### 1. User Request Flow (App Access)
```
User Browser
     │
     │ http://<EC2_PUBLIC_IP>:30080    ← NodePort 30080
     ▼
┌─────────────────────────────────────────┐
│  k3s Node → iptables → frontend:80      │
│  Service (NodePort 30080)                │
└────────────────┬────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────┐
│  Nginx (frontend pod)                    │
│  Serves: /index.html (React SPA)         │
│  Proxies: /api/* → backend:3001         │
└────────────────┬────────────────────────┘
                 │
                 │ http://backend.terrafusion.svc:3001
                 ▼
┌─────────────────────────────────────────┐
│  backend Service (ClusterIP :3001)      │
│  kube-proxy → round-robin → pod         │
└────────────────┬────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────┐
│  Express (backend pod)                   │
│  Routes:                                 │
│    GET /api/health    → 200 OK          │
│    POST /api/auth     → JWT login       │
│    GET /api/sensors   → sensor data     │
│    GET /api/kpis      → climate KPIs    │
│  Knex connection pool                    │
└────────────────┬────────────────────────┘
                 │
                 │ TCP :3306 (via VPC private IP)
                 ▼
┌─────────────────────────────────────────┐
│  RDS MySQL (Private Subnet)             │
│  Database: terrafusion                  │
│  Tables: users, sensor_readings,        │
│          regions, tasks, alerts         │
└─────────────────────────────────────────┘
```

### 2. CI/CD Flow (Jenkins Deployment)
```
Developer pushes to GitHub main
     │
     │ Webhook → Jenkins
     ▼
┌─────────────────────────────────────────┐
│  Jenkins (Docker :8080)                  │
│  1. git pull → /opt/terrafusion         │
│  2. docker build -t backend:${TAG}      │
│  3. docker build -t frontend:${TAG}     │
│  4. aws ecr get-login-password          │
│  5. docker push ${ECR}:${TAG}           │
│  6. docker push ${ECR}:latest           │
│  7. kubectl set image deployment/...    │
│  8. kubectl rollout status deployment   │
│  9. curl /api/health (smoke test)       │
│ 10. On fail: kubectl rollout undo       │
└─────────────────────────────────────────┘
```

### 3. Monitoring Flow (Prometheus/Grafana)
```
Prometheus scrapes:
  │
  ├── kube-state-metrics (K8s API)       → Node/Pod CPU, memory, status
  ├── kubelet (cAdvisor :10250)           → Container resource usage
  ├── backend /api/metrics :3001         → Custom: sensor CO2, temp, humidity
  └── node-exporter (DaemonSet :9100)     → EC2 disk, network, processes
     │
     ▼
┌─────────────────────────────────────────┐
│  Prometheus TSDB                        │
│  Retention: 7d                          │
│  Storage: 10GB                          │
│  Alert rules:                           │
│    ● BackendDown (5m)                   │
│    ● HighCPU (>80% 5m)                  │
│    ● HighMemory (>90% 5m)              │
│    ● API5xxRate (>5% 5m)               │
└──────────┬──────────────────────────────┘
           │
           ├──→ Alertmanager (Slack/none in demo)
           │
           ▼
┌─────────────────────────────────────────┐
│  Grafana (NodePort 30300)               │
│  Dashboards:                            │
│    ● K8s Cluster Health (nodes, pods)   │
│    ● TerraFusion Climate Monitoring     │
│      → CO2 PPM over time                │
│      → Temperature over time            │
│      → API request rate                 │
│      → API error rate                   │
│      → Sensor readings per region       │
└─────────────────────────────────────────┘
```

### 4. Logging Flow (ELK Stack)
```
Container runs → stdout/stderr
     │
     ▼
/var/log/containers/*.log  (on host, JSON format)
     │
     ▼
┌─────────────────────────────────────────┐
│  Filebeat DaemonSet (one per node)      │
│  Autodiscover: kubernetes provider      │
│  Adds metadata: pod_name, namespace,    │
│    container_name, node, labels         │
│  Output: Elasticsearch                  │
└──────────────────┬──────────────────────┘
                   │
                   │ http://elasticsearch-master:9200
                   ▼
┌─────────────────────────────────────────┐
│  Elasticsearch (single node)            │
│  Index: filebeat-8.11.0-yyyy.MM.dd     │
│  Shards: 1, Replicas: 0                │
│  Storage: 10GB PV                      │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│  Kibana (NodePort 30560)                │
│  Index Pattern: filebeat-*              │
│  Discover: filter by namespace          │
│  Dashboards:                            │
│    ● Container Logs Overview            │
│    ● Error Rate by Pod                  │
│    ● API Request Logs                   │
└─────────────────────────────────────────┘
```

### 5. Secrets Flow (Vault)
```
Vault Server (k3s pod :8200)
     │
     └── KV Secrets Engine v2
           ├── path: secret/terrafusion/backend
           ├── DB_PASSWORD : <RDS master password>
           └── JWT_SECRET  : <random 32 char secret>

Manual flow:
  vault kv put secret/terrafusion/backend \
    DB_PASSWORD=<password> \
    JWT_SECRET=<secret>
```

## Backup Flow
```
┌─────────────┐     ┌───────────────┐     ┌──────────────┐
│  RDS MySQL   │────►│  backup.sh    │────►│  S3 Bucket   │
│  (primary)   │     │  mysqldump    │     │  tier: IA    │
│              │     │  → gzip       │     │  30-day life │
└─────────────┘     │  → timestamp   │     └──────────────┘
                    │  → symlink     │
                    └───────────────┘
                         Daily at 2AM (cron)
```

## Technology Stack Summary

| Category | Technology | Version | Justification |
|---|---|---|---|
| Cloud | AWS (ap-south-1) | — | Student account, Mumbai region lowest latency |
| Compute | EC2 m7i-flex.large | — | 2 vCPU, 8GB RAM, EBS-only, free-tier eligible size |
| OS | Ubuntu 24.04 LTS | Noble | Long-term support, Docker/k3s native support |
| Containers | Docker | 27.x | PS mandated, image build/runtime |
| Orchestration | k3s | 1.30.x | Lightweight K8s (PS mandated), single binary, <50MB RAM |
| CI/CD | Jenkins | Latest (systemd) | PS mandated, Pipeline as Code |
| IaC | Terraform | ≥ 1.5 | PS mandated, AWS provider |
| Database | MySQL (RDS) | 8.0.40 | PS mentioned "environmental data", relational |
| Monitoring | Prometheus + Grafana | Latest | PS mandated |
| Logging | ELK (Elasticsearch + Kibana + Filebeat) | 8.11.0 | PS mandated |
| Secrets | Vault | Latest | PS mandated, KV secrets store |
| App Frontend | React + Nginx | Node 22 | Modern SPA, Vite build |
| App Backend | Node.js + Express + Knex | 22 | REST API, SQL query builder |
| Backup | AWS CLI + S3 | v2 | Cron-driven automated backups |

