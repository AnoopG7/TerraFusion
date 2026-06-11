# Project TerraFusion — DevOps Implementation Plan

## Overview

Build a complete cloud-native DevOps ecosystem for TerraFusion (a climate engineering
platform) entirely on **AWS**. Nothing runs locally — everything is deployed, managed,
and demonstrated from the cloud.

---

## 1. Architecture Overview

```
                          ┌──────────────┐
                          │   GitHub     │
                          │  (Source)    │
                          └──────┬───────┘
                                 │ push
                          ┌──────▼───────┐
                          │   Jenkins    │
                          │   (EC2)      │  ◄── CI/CD Pipeline
                          │              │
                          │  Builds      │
                          │  Docker img  │
                          └──────┬───────┘
                                 │ push
                          ┌──────▼───────┐
                          │   ECR        │
                          │ (Docker Reg) │
                          └──────┬───────┘
                                 │ pull
                          ┌──────▼───────┐
                          │   EKS        │  ◄── Kubernetes
                          │  (K8s)       │
                          └──────────────┘
                    ┌───────────┼───────────┐
                    ▼           ▼           ▼
            ┌──────────┐ ┌──────────┐ ┌──────────┐
            │ Ingestor │ │Processor │ │ Frontend │
            │  (Pod)   │ │  (Pod)   │ │  (Pod)   │
            └────┬─────┘ └────┬─────┘ └────┬─────┘
                 │            │             │
                 ▼            ▼             │
            ┌──────────────────────┐        │
            │   S3 + RDS          │        │
            │  (Data Storage)     │        │
            └──────────────────────┘        │
                                            │
    ┌───────────────────────────────────────┘
    │
    ▼                           ┌──────────────┐
┌──────────────┐               │   ELK Stack   │
│  Prometheus  │               │  (EC2 or K8s) │
│   (Metrics)  │               │   (Logs)      │
└──────┬───────┘               └──────┬────────┘
       ▼                              ▼
┌──────────────┐               ┌──────────────┐
│   Grafana    │               │   Kibana     │
│ (Dashboards) │               │ (Log Search) │
└──────────────┘               └──────────────┘

                    ┌──────────────┐
                    │    Vault     │
                    │  (EC2/K8s)   │
                    │  (Secrets)   │
                    └──────────────┘
```

---

## 2. Services to Build (3 Dockerized Apps)

### 2.1 data-ingestor
| Detail | Value |
|---|---|
| Language | Python (Flask) or Node.js (Express) |
| What it does | Generates fake climate sensor data every 5s |
| Endpoint | `GET /api/sensors` → returns JSON array |
| Sample data | `{ "sensor_id": "sat-01", "co2_ppm": 415, "temp_c": 22.5, "humidity": 62, "region": "pacific", "timestamp": "..." }` |
| Docker base | `python:3.11-slim` or `node:18-alpine` |

### 2.2 data-processor
| Detail | Value |
|---|---|
| Language | Python (Flask) |
| What it does | Polls ingestor, computes 5-min averages, flags anomalies |
| Endpoint | `GET /api/processed` → processed climate data |
| Storage | Writes to RDS (PostgreSQL) |
| Docker base | `python:3.11-slim` |

### 2.3 frontend
| Detail | Value |
|---|---|
| Language | Python (Flask with HTML templates) or simple static HTML |
| What it does | Shows live sensor readings, health status of all services |
| Endpoint | `GET /` → rendered dashboard page |
| Docker base | `python:3.11-slim` or `nginx:alpine` |

---

## 3. AWS Infrastructure (Terraform)

All infrastructure provisioned via **Terraform** from the Jenkins EC2 instance.

| Resource | Purpose |
|---|---|
| **VPC** (2 AZs, public + private subnets) | Network isolation |
| **EKS Cluster** (managed K8s) | Orchestrate containers |
| **ECR** (3 repos) | Store Docker images |
| **RDS PostgreSQL** | Processed climate data |
| **S3 Bucket** | Raw sensor data storage |
| **EC2 (Jenkins)** | CI/CD server (t2.medium) |
| **EC2 (ELK)** | Centralized logging |
| **IAM Roles + Policies** | Permissions for all services |
| **Security Groups** | Firewall rules |
| **ALB** | Load balancer for K8s ingress |

---

## 4. Kubernetes Manifests (EKS)

| Manifest | What it does |
|---|---|
| `namespace.yaml` | Dedicated namespace (`terrafusion`) |
| `ingestor-deploy.yaml` | Deployment + Service for ingestor |
| `processor-deploy.yaml` | Deployment + Service for processor |
| `frontend-deploy.yaml` | Deployment + Service for frontend |
| `hpa.yaml` | Horizontal Pod Autoscaler (scales on CPU > 70%) |
| `configmap.yaml` | App config (API URLs, poll intervals) |
| `secrets.yaml` | DB credentials (also stored in Vault) |
| `ingress.yaml` | ALB Ingress for external access |
| `network-policy.yaml` | Restrict pod-to-pod communication |
| `pdb.yaml` | PodDisruptionBudget (min 2 pods always running) |

All pods get:
- **Liveness probe** → restart if app hangs
- **Readiness probe** → no traffic if not ready
- **Resource limits** → CPU/memory bounds
- **3 replicas** → high availability

---

## 5. Jenkins CI/CD Pipeline

Jenkins runs on **EC2** with Docker and kubectl installed.

```
Pipeline: "terrafusion-pipeline"

Stages:
  1. Git Checkout        → Pull from GitHub
  2. Build Images        → docker build for all 3 services
  3. Push to ECR         → docker push (authenticated via IAM)
  4. Deploy to EKS       → kubectl apply -f k8s/
  5. Smoke Test          → curl health endpoints
  6. Rollback (on fail)  → kubectl rollout undo
  7. Cleanup             → Remove old images
  8. Notify              → Email/Slack status
```

**Triggers:**
- Automatic: on push to `main` branch
- Manual: via Jenkins UI with "Build Now"

---

## 6. Monitoring (Prometheus + Grafana)

### Prometheus
- Deployed on EKS via **Helm chart** (`prometheus-community/kube-prometheus-stack`)
- Scrapes:
  - K8s cluster metrics (node/pod CPU, memory, network)
  - Custom app metrics from ingestor + processor (`/metrics` endpoint)

### Grafana
- Deployed alongside Prometheus
- **Dashboards to build:**
  1. **Cluster Health** — Node status, pod counts, resource usage
  2. **Climate Data** — CO2 trends, temperature by region
  3. **Service SLO** — Uptime, latency, error rates

---

## 7. Logging (ELK Stack)

### Setup
- **Elasticsearch** + **Kibana** installed on a separate EC2 (or as K8s statefulset)
- **Filebeat** DaemonSet on EKS → ships pod logs to Elasticsearch

### What gets logged
- Every HTTP request to each service
- Sensor readings from ingestor
- Processing errors from processor
- System health events

### Kibana
- Search logs by service name, region, error code
- Visualize log volume over time
- Alert on error spikes

---

## 8. Vault (HashiCorp Vault)

### Setup
- Vault server on EC2 (or on EKS)
- Backend: S3 (for HA) or file storage
- Unseal: manual or auto-unseal via AWS KMS

### What's stored
| Secret | Used by |
|---|---|
| RDS PostgreSQL password | data-processor |
| AWS API keys | Jenkins (ECR push) |
| Internal service API keys | ingestor → processor auth |

### Integration
- **Kubernetes auth method**: pods authenticate via service account token
- **Sidecar injector**: Vault agent sidecar injects secrets into pods
- **Dynamic secrets**: RDS credentials auto-rotate every 24h

---

## 9. Disaster Recovery (What Evaluators Will Test)

| Scenario | How we handle it |
|---|---|
| **Pod crash** | Liveness probe → K8s auto-restarts within seconds |
| **Node failure** | 3 replicas across 2 AZs → pods reschedule on healthy nodes |
| **Region outage** | Terraform provision in us-east-1 + us-west-2 backup |
| **RDS failure** | Multi-AZ RDS with auto-failover |
| **S3 loss** | Cross-region replication enabled |
| **Cyberattack** | Network policies restrict pod traffic; Vault for secrets; SG limits ports |
| **Failed deploy** | Jenkins rollback stage → `kubectl rollout undo` |
| **Data corruption** | RDS point-in-time recovery (7-day backup) |
| **ELK down** | Logs buffer on Filebeat; auto-reconnect |
| **All services down** | Terraform destroy + apply from scratch (drill documented) |

---

## 10. Deliverables Checklist

### Code & Configs
- [ ] `docker/data-ingestor/` — Dockerfile + app code
- [ ] `docker/data-processor/` — Dockerfile + app code
- [ ] `docker/frontend/` — Dockerfile + app code
- [ ] `terraform/` — All .tf files (vpc, eks, rds, ecr, s3, jenkins, elk, vault)
- [ ] `k8s/` — All deployment manifests
- [ ] `jenkins/Jenkinsfile` — Pipeline definition
- [ ] `monitoring/` — Prometheus config + Grafana dashboard JSONs
- [ ] `logging/` — Filebeat config
- [ ] `vault/` — Policy files + setup scripts
- [ ] `dr/` — Disaster recovery playbook

### Documentation
- [ ] Architecture report (with diagrams)
- [ ] Security documentation
- [ ] DR procedures document
- [ ] README with setup instructions

### Demo (Live Evaluation)
- [ ] Jenkins pipeline running and deploying
- [ ] All 3 services responding on ALB URL
- [ ] Grafana dashboards showing live metrics
- [ ] Kibana showing real-time logs
- [ ] Vault secrets accessible from pods
- [ ] Self-healing demo (kill a pod → auto-restart)
- [ ] Rollback demo (deploy bad image → Jenkins rollback)

---

## 11. Implementation Order

| Phase | Tasks | AWS Services Used |
|---|---|---|
| **Phase 1** | Write 3 Docker apps + Dockerfiles | (tested on Jenkins EC2) |
| **Phase 2** | Terraform: VPC, ECR, RDS, S3, Jenkins EC2 | VPC, ECR, RDS, S3, EC2 |
| **Phase 3** | Set up Jenkins on EC2 (Docker, kubectl, AWS CLI) | EC2 |
| **Phase 4** | Terraform: EKS cluster + node group | EKS |
| **Phase 5** | Build & push Docker images via Jenkins | ECR |
| **Phase 6** | Deploy K8s manifests (services, HPA, ingress) | EKS, ALB |
| **Phase 7** | Install Prometheus + Grafana (Helm) | EKS |
| **Phase 8** | Install ELK (Filebeat + ES + Kibana) | EC2 or EKS |
| **Phase 9** | Install & configure Vault | EC2 or EKS |
| **Phase 10** | DR testing + documentation | All |
| **Phase 11** | Report writing + demo prep | — |

---

## 12. Cost Estimate (AWS Free Tier Friendly)

| Service | Estimated monthly cost |
|---|---|
| EC2 (Jenkins + ELK + Vault) | ~$50 (t2.medium × 3) |
| EKS cluster | ~$73 (control plane) |
| ECR | Free (within limits) |
| RDS (db.t3.micro) | ~$15 |
| S3 | ~$1 |
| ALB | ~$20 |
| **Total** | **~$160/month** |

> Tip: Shut down non-demo resources when not in use to save costs.
