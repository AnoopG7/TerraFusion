# TerraFusion — Demo Script

## Part 1: Infrastructure (Terraform)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit: ssh_allowed_cidr, rds_master_password, key_pair_name, aws creds

# First run only:
aws s3 mb s3://terrafusion-terraform-state --region ap-south-1

terraform init
terraform plan
terraform apply -auto-approve
```

**Show:** `terraform apply` output → EC2 IP, RDS endpoint, all URLs in outputs.

---

## Part 2: Server Bootstrap (Fully Automated)

```bash
# SSH into EC2
ssh -i ~/.ssh/your-key.pem ubuntu@<EC2_IP>

# Check init status
sudo tail -50 /var/log/terrafusion-init.log
```

**Show (all done by user_data):**
- Docker installed and running
- k3s nodes ready (`kubectl get nodes`)
- Helm installed
- AWS CLI configured
- Jenkins running on :8080 (admin/admin123)
- API healthy (`curl localhost:3001/api/health`)
- Frontend accessible (`curl localhost:30080`)
- Prometheus/Grafana installed (`kubectl get pods -n monitoring`)
- ELK installed (`kubectl get pods -n logging`)
- Vault installed (`kubectl get pods -n vault`)

---

## Part 3: Jenkins CI/CD Pipeline

```bash
# Open http://<EC2_IP>:8080
# Login: admin / admin123
```

**Show:**
- Pipeline job exists: `terrafusion-pipeline`
- Pipeline config: CpsScmFlowDefinition pointing to GitHub, Jenkinsfile
- Trigger a build: `Build Now`
- Watch stages: Checkout → Build Backend → Build Frontend → Push to ECR → Deploy to k3s → Smoke Test
- ECR URLs discovered dynamically (no hardcoded values)

---

## Part 4: Application Access

```bash
# Frontend via NodePort
curl http://<EC2_IP>:30080
curl http://<EC2_IP>:30080/api/health
curl http://<EC2_IP>:30080/api/sensors
```

**Show:** Browse `http://<EC2_IP>:30080` → TerraFusion dashboard loads.

---

## Part 5: Monitoring (Prometheus + Grafana)

```bash
# Open http://<EC2_IP>:30300
# Login: admin / admin
```

**Show:**
- Grafana → TerraFusion Climate Monitoring dashboard
- Sensor readings: CO2 PPM, Temperature, API request/error rates
- Prometheus data sources configured

---

## Part 6: Centralized Logging (ELK Stack)

```bash
# Open http://<EC2_IP>:30560
```

**Show:**
- Kibana → Discover → filter `kubernetes.namespace: terrafusion`
- Logs from backend pod visible
- Filebeat DaemonSet shipping container logs

---

## Part 7: Vault Integration

```bash
# Vault UI: http://<EC2_IP>:30820
# Token: root

# Read secrets from CLI:
kubectl exec -n vault -l app.kubernetes.io/name=vault -- vault kv get secret/terrafusion/backend
```

**Show:**
- Vault UI → Secrets tab → `secret/terrafusion/backend`
- Secrets stored: DB_PASSWORD, JWT_SECRET, DB_HOST, DB_NAME

---

## Part 8: Disaster Recovery Demos

### 8a — Pod Crash
```bash
kubectl delete pod -n terrafusion -l app=backend
kubectl get pods -n terrafusion -w
# Pod recreates in <5s
```

### 8b — Failed Deployment
```bash
# In Jenkins trigger build
# Watch: Build → Deploy → Smoke test fails → Rollback
kubectl rollout history deployment/backend -n terrafusion
```

### 8c — Auto-scaling
```bash
kubectl get hpa -n terrafusion -w
kubectl run -it --rm load-gen --image=busybox -- sh -c \
  "while true; do wget -q -O- http://backend.terrafusion.svc:3001/api/sensors > /dev/null; done"
# Pods scale from 2 → 3+
```

---

## Part 9: Cleanup

```bash
cd terraform
aws s3 rm s3://terrafusion-terraform-state --recursive
aws s3 rm s3://terrafusion-backups --recursive
terraform destroy -auto-approve
```
