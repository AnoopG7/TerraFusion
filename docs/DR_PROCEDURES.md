# TerraFusion — Disaster Recovery Procedures

## Scenario 1: Pod Crash

**Trigger:** `kubectl delete pod -n terrafusion backend-xxxxx`

**Expected behavior:**
1. K8s ReplicaSet detects pod count is below desired (2)
2. New pod is scheduled automatically within seconds
3. Readiness probe waits until backend is ready
4. Service routes traffic to new pod

**How to demo:**
```bash
kubectl get pods -n terrafusion -w
# In another terminal:
kubectl delete pod -n terrafusion -l app=backend
# Watch pod terminate and new one spawn
curl http://<EC2_IP>/api/health   # Should still return 200
```

**RTO:** <10 seconds | **RPO:** 0 (stateless)

---

## Scenario 2: Node Failure

**Trigger:** `sudo systemctl stop k3s` or terminate EC2

**Expected behavior (k3s single-node):**
1. k3s systemd service stops → all pods become unreachable
2. On restart, k3s recovers etcd and restarts all pods
3. Pods return to Running state with same data

**How to demo:**
```bash
sudo systemctl stop k3s
curl http://<EC2_IP>/api/health   # Fails
sudo systemctl start k3s
sleep 30
kubectl get pods -n terrafusion   # Should all be Running
curl http://<EC2_IP>/api/health   # Should return 200
```

**RTO:** ~30-60 seconds | **RPO:** 0 (etcd state preserved)

---

## Scenario 3: RDS Reboot

**Trigger:** `aws rds reboot-db-instance --db-instance-identifier terrafusion-mysql`

**Expected behavior:**
1. RDS restarts in-place, brief downtime (~30-60s)
2. Backend connection pool detects dropped connection, retries
3. Backend reconnects automatically

**How to demo:**
```bash
aws rds reboot-db-instance --db-instance-identifier terrafusion-mysql
kubectl logs -n terrafusion -l app=backend --tail=20 -f
# You'll see: "Can't connect to MySQL server" → reconnects
curl http://<EC2_IP>/api/sensors   # Should recover within 60s
```

**RTO:** ~60 seconds | **RPO:** Negligible (in-flight transactions lost)

---

## Scenario 4: Failed Deployment (Jenkins Rollback)

**Trigger:** Deploy code that breaks the health check

**Expected behavior:**
1. Jenkins pipeline: Build → Import to k3s → Deploy → Smoke test
2. Smoke test fails (curl returns non-200)
3. Jenkins catches failure → `kubectl rollout undo`
4. Previous version is restored

**How to demo:**
```bash
# Trigger Jenkins pipeline with bad code
# Jenkins will:
#   1. Build and import broken image
#   2. Deploy to k3s
#   3. Smoke test fails
#   4. Auto-rollback to last good version

# Or simulate bad deploy:
kubectl set image deployment/backend -n terrafusion backend=nginx:latest
kubectl rollout status deployment/backend -n terrafusion
# Pods will be CrashLoopBackOff

# Roll back manually:
kubectl rollout undo deployment/backend -n terrafusion

# Verify recovery
kubectl get pods -n terrafusion       # Should be Running
curl http://<EC2_IP>/api/health       # Should be 200
```

**RTO:** ~2-3 minutes | **RPO:** 0

---

## Scenario 5: High Load / Auto-scaling (HPA)

**Trigger:** Generate load on backend to trigger HorizontalPodAutoscaler

**Expected behavior:**
1. High CPU on backend pods (>70%)
2. HPA scales backend from 2 → up to 5 replicas
3. Load distributes across pods
4. CPU per pod drops
5. When load stops, HPA scales back down

**How to demo:**
```bash
kubectl get hpa -n terrafusion -w
kubectl get pods -n terrafusion -w

# Generate load:
kubectl run -it --rm load-gen --image=busybox -- sh -c "
  while true; do
    wget -q -O- http://backend.terrafusion.svc:3001/api/sensors > /dev/null 2>&1
  done
"
```

**RTO:** Auto | **RPO:** 0

---

## Scenario 6: Log Flood / Disk Full

**Trigger:** Excessive container logs

**Expected behavior:**
1. Cron job rotates logs weekly (`rotate-logs.sh`)
2. Docker system prune removes unused images/containers
3. Prometheus alerts on disk usage >80%

**How to demo:**
```bash
df -h /
sudo /opt/terrafusion/scripts/rotate-logs.sh
df -h /
```

**RTO:** N/A (preventative) | **RPO:** 0

---

## Automated Recovery Summary

| Scenario | Detection | Recovery | Time |
|---|---|---|---|
| Pod crash | Liveness probe fails | K8s recreate pod | <10s |
| Node failure | Systemd watch | k3s restart | <60s |
| RDS reboot | Connection timeout | RDS restart | <60s |
| Failed deploy | Smoke test fails | Jenkins rollback | <3min |
| High load | HPA metric >70% | Scale up replicas | <2min |
| Disk full | Cron + Prometheus alert | Log rotate + prune | Weekly |
