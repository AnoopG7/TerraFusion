# TerraFusion — Demo Script

## Part 1: Infrastructure (Terraform)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit: ssh_allowed_cidr, rds_master_password, key_pair_name

terraform init
terraform plan
terraform apply -auto-approve
```

**Show:** `terraform apply` output → EC2 IP, RDS endpoint, all URLs in outputs.

---

## Part 2: Server Bootstrap (Fully Automated)

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@<EC2_IP>

# Check init status
sudo tail -50 /var/log/terrafusion-init.log
```

**Show (all done by user_data):**
- Docker installed and running
- k3s nodes ready (`kubectl get nodes`)
- Helm installed
- Jenkins running on :8080 (admin/admin123)
- API healthy (`curl localhost:3001/api/health`)
- Frontend accessible (`curl -s http://localhost/`)
- Prometheus/Grafana installed (`kubectl get pods -n monitoring`)
- Vault installed (`kubectl get pods -n vault`)

After init, Terraform's `null_resource` automatically injects real RDS values:
```
RDS ready ──► SSH into EC2 ──► update ConfigMap + Secret + .env
           ──► restart backend pods
```

---

## Part 3: Jenkins CI/CD Pipeline

```bash
# Open http://<EC2_IP>:8080
# Login: admin / admin123
```

**Show:**
- Pipeline job exists: `terrafusion-pipeline`
- Trigger a build: `Build with Parameters` → BRANCH=main
- Watch stages: Checkout → Build Backend → Build Frontend → Import to k3s → Deploy → Smoke Test
- No ECR push — `docker save` piped directly into `k3s ctr images import`
- Smoke test passes → healthy deployment

---

## Part 4: Application Access

```bash
# Frontend via Ingress (port 80)
curl http://<EC2_IP>
curl http://<EC2_IP>/api/health

# Alternative: via NodePort
curl http://<EC2_IP>:30080
```

**Show:** Browse `http://<EC2_IP>` → TerraFusion dashboard loads.
Login with `admin@terrafusion.io` / `admin123`.

---

## Part 5: Monitoring (Prometheus + Grafana)

```bash
# Open http://<EC2_IP>:30300
# Login: admin / prom-operator
```

**Show:**
- Grafana dashboards
- Prometheus data sources configured
- Cluster health, pod metrics, API request rates

---

## Part 6: Vault Integration

```bash
# Vault UI: http://<EC2_IP>:30820
# Token: root

# Read secrets from CLI:
kubectl exec -n vault -l app.kubernetes.io/name=vault -- vault kv get secret/terrafusion/backend
```

**Show:**
- Vault UI → Secrets tab → `secret/terrafusion/backend`
- Secrets: DB_PASSWORD, JWT_SECRET, DB_HOST, DB_NAME

---

## Part 7: Disaster Recovery Demos

### 7a — Pod Crash
```bash
kubectl delete pod -n terrafusion -l app=backend
kubectl get pods -n terrafusion -w
# Pod recreates in <5s
```

### 7b — Failed Deployment
```bash
# In Jenkins trigger build with broken code or:
kubectl set image deployment/backend -n terrafusion backend=nginx:latest
kubectl rollout status deployment/backend -n terrafusion
# Pods go CrashLoopBackOff — roll back:
kubectl rollout undo deployment/backend -n terrafusion
```

### 7c — Auto-scaling
```bash
kubectl get hpa -n terrafusion -w
kubectl run -it --rm load-gen --image=busybox -- sh -c \
  "while true; do wget -q -O- http://backend.terrafusion.svc:3001/api/sensors > /dev/null; done"
# Pods scale from 2 → up to 5
```

---

## Part 8: Cleanup

```bash
cd terraform
terraform destroy -auto-approve
```
