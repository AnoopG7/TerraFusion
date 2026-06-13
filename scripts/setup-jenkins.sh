#!/usr/bin/env bash
set -euo pipefail

JENKINS_URL="http://localhost:8080"
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com 2>/dev/null || echo "localhost")
TERRAFORM_DIR="/opt/terrafusion"

echo "═══════════════════════════════════════════════════════════════"
echo "  TerraFusion — Native Jenkins Setup (Ubuntu 24.04)"
echo "═══════════════════════════════════════════════════════════════"

# ── 1. Install Java 21 ──
echo "[1/7] Installing Java 21..."
apt install -y openjdk-21-jdk 2>/dev/null || {
  echo "[!] apt failed, trying manual install..."
  curl -fsSL https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.deb -o /tmp/jdk21.deb
  dpkg -i /tmp/jdk21.deb || true
}
echo "[✓] Java: $(java --version | head -1)"

# ── 2. Install Jenkins from official apt repo ──
echo "[2/7] Installing Jenkins from apt repo..."

# Remove any previous sources/keys
rm -f /etc/apt/sources.list.d/jenkins.list
rm -f /usr/share/keyrings/jenkins-keyring.asc /usr/share/keyrings/jenkins-keyring.gpg
rm -f /etc/apt/keyrings/jenkins-keyring.asc

apt install -y fontconfig openjdk-21-jre 2>/dev/null || true

mkdir -p /etc/apt/keyrings
wget -q -O /etc/apt/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" > /etc/apt/sources.list.d/jenkins.list
apt update -y 2>/dev/null || true

# Create systemd override BEFORE installing Jenkins (prevents setup wizard on first boot)
mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/override.conf << 'EOF'
[Service]
Environment="JAVA_OPTS=-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false -Xmx256m -Xms128m -Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true"
EOF
systemctl daemon-reload

apt install -y jenkins
systemctl enable jenkins
echo "[✓] Jenkins installed: $(dpkg -l jenkins 2>/dev/null | awk '/^ii/ {print $3}')"

# ── 3. Configure Jenkins (docker group + sudoers + init.groovy.d) ──
echo "[3/7] Configuring Jenkins..."
# Add jenkins to docker group
usermod -aG docker jenkins 2>/dev/null || true

# Allow jenkins to run k3s and kubectl without password
echo "jenkins ALL=(ALL) NOPASSWD: /usr/local/bin/k3s, /usr/local/bin/kubectl" > /etc/sudoers.d/jenkins-k3s 2>/dev/null
chmod 440 /etc/sudoers.d/jenkins-k3s 2>/dev/null

# Ensure jenkins can access k3s kubeconfig
mkdir -p /var/lib/jenkins/.kube
cp /etc/rancher/k3s/k3s.yaml /var/lib/jenkins/.kube/config 2>/dev/null || true
chown -R jenkins:jenkins /var/lib/jenkins/.kube 2>/dev/null || true
chmod 600 /var/lib/jenkins/.kube/config 2>/dev/null || true

# init.groovy.d — idempotent admin user + Jenkins URL
JENKINS_HOME="/var/lib/jenkins"
INIT_DIR="${JENKINS_HOME}/init.groovy.d"
mkdir -p "$INIT_DIR"

# Wait for Jenkins home to be ready
for i in $(seq 1 30); do
  [ -d "$JENKINS_HOME" ] && break
  sleep 2
done

cat > "${INIT_DIR}/01-admin-user.groovy" << 'GROOVY'
import jenkins.model.*
import hudson.security.*
import jenkins.install.*

def instance = Jenkins.getInstanceOrNull()
if (instance == null) return

def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount("admin", "admin123")
instance.setSecurityRealm(hudsonRealm)

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)
instance.save()
println "init: admin user created (admin/admin123), setup wizard skipped"
GROOVY

cat > "${INIT_DIR}/02-jenkins-url.groovy" << 'GROOVY'
import jenkins.model.*
def instance = Jenkins.getInstanceOrNull()
if (instance == null) return
def url = "http://__PUBLIC_IP__:8080"
instance.setRootUrl(url)
instance.save()
println "init: Jenkins URL set to ${url}"
GROOVY
sed -i "s|__PUBLIC_IP__|${PUBLIC_IP}|g" "${INIT_DIR}/02-jenkins-url.groovy"

chown -R jenkins:jenkins "$INIT_DIR"
echo "[✓] init.groovy.d scripts installed"

# ── 4. Start Jenkins (first boot — no plugins yet) ──
echo "[4/7] Starting Jenkins..."
systemctl enable jenkins 2>/dev/null || true
systemctl restart jenkins || true

echo "[*] Waiting for Jenkins to start..."
for i in $(seq 1 90); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$JENKINS_URL" 2>/dev/null || echo "000")
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "403" ]; then break; fi
  sleep 3
done
echo "[✓] Jenkins ready (HTTP $STATUS)"
echo "[*] Waiting for init.groovy.d scripts to execute..."
sleep 15

PASS=$(cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || echo "")
echo "[✓] Initial admin password (before groovy override): $PASS"

# ── 5. Install plugins FIRST (before creating pipeline job) ──
echo "[5/7] Installing plugins..."

JENKINS_COOKIE=$(mktemp)
CRUMB_JSON=$(curl -s -u "admin:admin123" -c "$JENKINS_COOKIE" "$JENKINS_URL/crumbIssuer/api/json")
CRUMB=$(echo "$CRUMB_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumb'])" 2>/dev/null || echo "")
CRUMB_HEADER=$(echo "$CRUMB_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumbRequestField'])" 2>/dev/null || echo "Jenkins-Crumb")

# Install all plugins in a single batch via Script Console (much faster + reliable)
echo "[*] Installing default plugins + Blue Ocean (batch)..."
PLUGIN_LIST="ant build-timeout credentials-binding docker-workflow email-ext git github-branch-source jackson2-api mailer matrix-auth pipeline-build-step pipeline-graph-analysis pipeline-input-step pipeline-milestone-step pipeline-stage-view plain-credentials ssh-slaves timestamper ws-cleanup workflow-aggregator blueocean"

curl -s -X POST -u "admin:admin123" -b "$JENKINS_COOKIE" \
  -H "${CRUMB_HEADER}: ${CRUMB}" \
  "$JENKINS_URL/scriptText" \
  --data-urlencode "script=
def plugins = '${PLUGIN_LIST}'.split(' ').toList()
def pm = Jenkins.instance.pluginManager
def uc = Jenkins.instance.updateCenter
uc.updateAllSites()
Thread.sleep(5000)
def futures = pm.install(plugins.collect { uc.getPlugin(it) }.findAll { it != null }, true)
futures.each { try { it.get() } catch(e) { println \"WARN: \${e.message}\" } }
println 'All plugins queued for install'
" > /dev/null 2>&1

echo "[✓] Plugins download initiated"

# ── 6. Restart Jenkins to load plugins ──
echo "[6/7] Restarting Jenkins to activate plugins..."
systemctl restart jenkins

echo "[*] Waiting for Jenkins to restart with plugins..."
sleep 10
for i in $(seq 1 90); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$JENKINS_URL" 2>/dev/null || echo "000")
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "403" ]; then break; fi
  sleep 3
done
echo "[✓] Jenkins ready with plugins (HTTP $STATUS)"
sleep 15

# Re-acquire crumb after restart
JENKINS_COOKIE=$(mktemp)
CRUMB_JSON=$(curl -s -u "admin:admin123" -c "$JENKINS_COOKIE" "$JENKINS_URL/crumbIssuer/api/json")
CRUMB=$(echo "$CRUMB_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumb'])" 2>/dev/null || echo "")
CRUMB_HEADER=$(echo "$CRUMB_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumbRequestField'])" 2>/dev/null || echo "Jenkins-Crumb")

# ── 7. Create Pipeline job + trigger build (plugins now loaded) ──
echo "[7/7] Creating Pipeline job & triggering build..."

# git safe.directory for Jenkins
su - jenkins -c "git config --global --add safe.directory /opt/terrafusion" 2>/dev/null || true
su - jenkins -c "git config --global --add safe.directory '*' 2>/dev/null" || true
echo "[✓] safe.directory configured"

echo "[*] Creating Pipeline job via Script Console..."
curl -s -X POST -u "admin:admin123" -b "$JENKINS_COOKIE" \
  -H "${CRUMB_HEADER}: ${CRUMB}" \
  "$JENKINS_URL/scriptText" \
  --data-urlencode 'script=import jenkins.model.Jenkins
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition
import hudson.plugins.git.GitSCM
import hudson.plugins.git.UserRemoteConfig
import hudson.plugins.git.BranchSpec

def j = Jenkins.getInstanceOrNull()
def name = "terrafusion-pipeline"
def existing = j.getItem(name)
if (existing != null) { existing.delete() }
def job = j.createProject(WorkflowJob.class, name)
job.setDisplayName("TerraFusion CI/CD Pipeline")
def rc = new UserRemoteConfig("/opt/terrafusion", null, null, null)
def bs = new BranchSpec("*/main")
def scm = new GitSCM([rc], [bs], false, [], null, null, null)
job.setDefinition(new CpsScmFlowDefinition(scm, "Jenkinsfile"))
job.save()
j.save()
println("Pipeline job created: " + name)' > /dev/null 2>&1 && \
echo "[✓] Pipeline job created" || echo "[WARN] Pipeline creation failed — may need manual setup"

if grep -q '__REPLACE_ME__' /opt/terrafusion/backend/.env 2>/dev/null; then
  echo "[!] .env still has placeholder RDS host — skipping auto-build."
  echo "[!] After SSH, fix RDS host, then trigger build:"
  echo "    curl -X POST 'http://$PUBLIC_IP:8080/job/terrafusion-pipeline/build' -u admin:admin123"
else
  echo "[*] Triggering build..."
  curl -s -o /dev/null -X POST \
    -u "admin:admin123" -b "$JENKINS_COOKIE" \
    -H "${CRUMB_HEADER}: ${CRUMB}" \
    "$JENKINS_URL/job/terrafusion-pipeline/build"
  echo "  Build triggered!"
fi

rm -f "$JENKINS_COOKIE"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Native Jenkins Setup Complete!"
echo "  URL:        http://$PUBLIC_IP:8080"
echo "  Login:      admin / admin123"
echo "  Job:        http://$PUBLIC_IP:8080/job/terrafusion-pipeline/"
echo "  Blue Ocean: http://$PUBLIC_IP:8080/blue/"
echo "  Workspace:  /var/lib/jenkins/workspace/terrafusion-pipeline/"
echo "  Log:        journalctl -u jenkins.service"
echo "═══════════════════════════════════════════════════════════════"
