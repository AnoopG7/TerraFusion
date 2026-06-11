# TerraFusion — Demo Script

## Part 1: Infrastructure (Terraform)

```bash
# 1. Init Terraform
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your IP + SSH key path + RDS password

# 2. Create S3 state bucket manually (first run only)
aws s3 mb s3://terrafusion-terraform-state --region ap-south-1

# 3. Apply
terraform init
terraform plan
terraform apply -auto-approve
# Wait ~5 minutes. Note the EC2_IP and RDS_ENDPOINT in outputs.
```

**Show:** `terraform apply` output → EC2 IP, RDS endpoint, ECR URLs, S3 buckets

---

## Part 2: Server Bootstrap

```bash
# SSH into EC2
ssh -i ~/.ssh/id_rsa ubuntu@<EC2_IP>

# Check init status
cat /var/log/terrafusion-init.log
```

**Show:**
- Docker installed and running
- k3s nodes ready (`kubectl get nodes`)
- Helm installed
- AWS CLI configured
- App running via Docker Compose (`docker ps`)
- API healthy (`curl localhost:3001/api/health`)

---

## Part 3: Deploy App on k3s

```bash
# Apply K8s manifests
kubectl apply -f /opt/terrafusion/k8s/

# Watch pods come up
kubectl get pods -n terrafusion -w

# Check services
kubectl get svc -n terrafusion

# Access app
curl http://localhost:30080
curl http://localhost:30080/api/health
```

**Show:** Browse `http://<EC2_IP>` → TerraFusion dashboard loads with climate data
**Show:** Login with `admin@terrafusion.io` / `admin123`
**Show:** Navigate Dashboard, Monitoring, Zones pages

---

## Part 4: CI/CD Pipeline (Jenkins)

```bash
# Access Jenkins
# Open http://<EC2_IP>:8080
# Get initial admin password:
sudo docker exec jenkins-blueocean cat /var/jenkins_home/secrets/initialAdminPassword

# Configure:
# 1. Install suggested plugins + docker, kubernetes-cli, aws-credentials
# 2. Add credentials: GitHub PAT, AWS IAM keys
# 3. Create pipeline → Jenkinsfile from repo
```

**Show:** Jenkins UI
**Show:** Pipeline stages: Checkout → Build → Push → Deploy → Smoke test
**Show:** Push a trivial commit → watch auto-deploy
**Show:** (Optional) Deploy bad code → watch auto-rollback

---

## Part 5: Monitoring (Prometheus + Grafana)

```bash
# Install Prometheus stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f /opt/terrafusion/helm/prometheus-values.yaml

# Access Grafana at http://<EC2_IP>:30300
# Login: admin / admin
```

**Show:**
- Grafana → Cluster Health dashboard (nodes, pods, CPU, memory)
- TerraFusion → Climate Monitoring dashboard (CO2, temperature, API metrics)
- Prometheus alerts (pod crash, high CPU, API errors)

---

## Part 6: Centralized Logging (ELK Stack)

```bash
# Install Elasticsearch + Kibana + Filebeat
helm repo add elastic https://helm.elastic.co
helm upgrade --install elasticsearch elastic/elasticsearch \
  -n logging --create-namespace -f /opt/terrafusion/helm/elasticsearch-values.yaml
helm upgrade --install kibana elastic/kibana \
  -n logging -f /opt/terrafusion/helm/kibana-values.yaml
helm upgrade --install filebeat elastic/filebeat \
  -n logging -f /opt/terrafusion/helm/filebeat-config.yaml

# Access Kibana at http://<EC2_IP>:30560
```

**Show:**
- Kibana → Discover → filter `kubernetes.namespace: terrafusion`
- Logs from backend pod visible
- Error search: `message: error or message: exception`

---

## Part 7: Vault Integration

```bash
# Install Vault
helm repo add hashicorp https://helm.releases.hashicorp.com
helm upgrade --install vault hashicorp/vault \
  -n vault --create-namespace -f /opt/terrafusion/helm/vault-values.yaml

# Access Vault at http://<EC2_IP>:30820
# Root token: root

# Enable KV secrets engine
kubectl exec -n vault vault-0 -- vault secrets enable -path=secret kv-v2

# Store backend secrets
kubectl exec -n vault vault-0 -- vault kv put secret/terrafusion/backend \
  DB_PASSWORD="<RDS password>" \
  JWT_SECRET="terrafusion-secret-key"
```

**Show:**
- Vault UI → Secrets tab → `secret/terrafusion/backend`
- Read a secret: `vault kv get secret/terrafusion/backend`

---

## Part 8: Disaster Recovery Demos

### 8a — Pod Crash
```bash
kubectl delete pod -n terrafusion -l app=backend
kubectl get pods -n terrafusion -w
# Pod recreates in <5s, app stays up
```

### 8b — Failed Deployment
```bash
# In Jenkins, trigger build with bad code
# Watch: Build → Deploy → Smoke test fails → Rollback
kubectl rollout history deployment/backend -n terrafusion
```

### 8c — RDS Failover
```bash
aws rds reboot-db-instance --db-instance-identifier terrafusion-mysql --force-failover
watch kubectl logs -n terrafusion -l app=backend --tail=5
# Backend reconnects automatically
curl http://<EC2_IP>:30080/api/sensors  # Still returns data
```

### 8d — Auto-scaling
```bash
kubectl run -it --rm load-gen --image=busybox -- sh -c "while true; do wget -q -O- http://backend.terrafusion.svc:3001/api/sensors > /dev/null; done"
kubectl get hpa -n terrafusion -w
# Pods scale 2 → 5
```

---

## Part 9: Cleanup

```bash
# Destroy all AWS resources
cd terraform
terraform destroy -auto-approve

# Verify
aws ec2 describe-instances --filters "Name=tag:Project,Values=terrafusion" --query 'Reservations[*].Instances[*].[InstanceId,State.Name]'
```
