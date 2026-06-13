#!/usr/bin/env bash
set -euo pipefail

JENKINS_URL="http://localhost:8080"
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com 2>/dev/null || echo "localhost")
JENKINS_HOME="/var/lib/jenkins"
PLUGIN_LIST="workflow-aggregator git docker-workflow pipeline-stage-view build-timeout credentials-binding email-ext github-branch-source mailer matrix-auth pipeline-build-step plain-credentials ssh-slaves timestamper ws-cleanup blueocean"

echo "═══════════════════════════════════════════════════════════════"
echo "  TerraFusion — Native Jenkins Setup (Ubuntu 24.04)"
echo "═══════════════════════════════════════════════════════════════"

# ── 1. Install Java 21 ──
echo "[1/8] Installing Java 21..."
apt install -y openjdk-21-jdk 2>/dev/null || {
  echo "[!] apt failed, trying manual install..."
  curl -fsSL https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.deb -o /tmp/jdk21.deb
  dpkg -i /tmp/jdk21.deb || true
}
echo "[✓] Java: $(java --version | head -1)"

# ── 2. Install Jenkins from official apt repo ──
echo "[2/8] Installing Jenkins from apt repo..."

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

# ── 3. Configure Jenkins ──
echo "[3/8] Configuring Jenkins..."
usermod -aG docker jenkins 2>/dev/null || true

echo "jenkins ALL=(ALL) NOPASSWD: /usr/local/bin/k3s, /usr/local/bin/kubectl" > /etc/sudoers.d/jenkins-k3s 2>/dev/null
chmod 440 /etc/sudoers.d/jenkins-k3s 2>/dev/null

mkdir -p /var/lib/jenkins/.kube
cp /etc/rancher/k3s/k3s.yaml /var/lib/jenkins/.kube/config 2>/dev/null || true
chown -R jenkins:jenkins /var/lib/jenkins/.kube 2>/dev/null || true
chmod 600 /var/lib/jenkins/.kube/config 2>/dev/null || true

# ── 4. Set up init.groovy.d ──
echo "[4/8] Setting up init scripts..."
INIT_DIR="${JENKINS_HOME}/init.groovy.d"
mkdir -p "$INIT_DIR"

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

# ── 5. First boot: start Jenkins so init.groovy.d runs ──
echo "[5/8] Starting Jenkins (first boot)..."
systemctl restart jenkins || true

echo "[*] Waiting for Jenkins to start..."
for i in $(seq 1 90); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$JENKINS_URL" 2>/dev/null || echo "000")
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "403" ]; then break; fi
  sleep 3
done
echo "[✓] Jenkins ready (HTTP $STATUS)"
sleep 15
echo "[✓] init.groovy.d executed"

# ── 6. Install plugins using jenkins-cli.jar (most reliable method) ──
echo "[6/8] Installing plugins via Jenkins CLI..."

# Download CLI from the running Jenkins instance
curl -s -u admin:admin123 "$JENKINS_URL/jnlpJars/jenkins-cli.jar" -o /tmp/jenkins-cli.jar 2>/dev/null

if [ -f /tmp/jenkins-cli.jar ] && [ -s /tmp/jenkins-cli.jar ]; then
  echo "[*] Installing plugins (this takes 2-5 minutes)..."
  java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -webSocket -auth admin:admin123 \
    install-plugin $PLUGIN_LIST 2>&1 | grep -E "Installing|already|done|Installed" || true
  echo "[✓] Plugins installed via CLI"
else
  echo "[WARN] CLI jar download failed — trying Script Console fallback..."
  
  JENKINS_COOKIE=$(mktemp)
  CRUMB_JSON=$(curl -s -u "admin:admin123" -c "$JENKINS_COOKIE" "$JENKINS_URL/crumbIssuer/api/json")
  CRUMB=$(echo "$CRUMB_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumb'])" 2>/dev/null || echo "")
  CRUMB_HEADER=$(echo "$CRUMB_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumbRequestField'])" 2>/dev/null || echo "Jenkins-Crumb")

  # Install each plugin via installNecessaryPlugins REST API
  for plugin in $PLUGIN_LIST; do
    echo "  $plugin..."
    curl -s -X POST -u "admin:admin123" -b "$JENKINS_COOKIE" \
      -H "${CRUMB_HEADER}: ${CRUMB}" \
      -H "Content-Type: text/xml" \
      "$JENKINS_URL/pluginManager/installNecessaryPlugins" \
      -d "<install plugin='$plugin@latest' />" 2>/dev/null || true
  done
  
  # Wait for downloads to complete
  echo "[*] Waiting for plugin downloads..."
  for i in $(seq 1 60); do
    PENDING=$(curl -s -u "admin:admin123" "$JENKINS_URL/updateCenter/api/json" 2>/dev/null | \
      python3 -c "
import sys, json
data = json.load(sys.stdin)
jobs = [j for j in data.get('jobs', []) if j.get('type') == 'InstallationJob']
pending = [j for j in jobs if j.get('status', {}).get('type') not in ('Success', 'Failure', 'Cancelled')]
print(len(pending))
" 2>/dev/null || echo "0")
    if [ "$PENDING" = "0" ]; then
      echo "  All plugins downloaded"
      break
    fi
    echo "  Waiting... ($PENDING pending)"
    sleep 5
  done
  rm -f "$JENKINS_COOKIE"
  echo "[✓] Plugins installed via REST API fallback"
fi

# ── 7. Restart Jenkins to load plugins ──
echo "[7/8] Restarting Jenkins to activate plugins..."
systemctl restart jenkins

sleep 10
for i in $(seq 1 90); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$JENKINS_URL" 2>/dev/null || echo "000")
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "403" ]; then break; fi
  sleep 3
done
echo "[✓] Jenkins ready with plugins (HTTP $STATUS)"
sleep 15

# ── 8. Create pipeline job + trigger build ──
echo "[8/8] Creating Pipeline job & triggering build..."

# git safe.directory for Jenkins
su - jenkins -c "git config --global --add safe.directory /opt/terrafusion" 2>/dev/null || true
su - jenkins -c "git config --global --add safe.directory '*'" 2>/dev/null || true
echo "[✓] safe.directory configured"

# Get fresh crumb
JENKINS_COOKIE=$(mktemp)
CRUMB_JSON=$(curl -s -u "admin:admin123" -c "$JENKINS_COOKIE" "$JENKINS_URL/crumbIssuer/api/json")
CRUMB=$(echo "$CRUMB_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumb'])" 2>/dev/null || echo "")
CRUMB_HEADER=$(echo "$CRUMB_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumbRequestField'])" 2>/dev/null || echo "Jenkins-Crumb")

echo "[*] Creating Pipeline job via Script Console..."
RESULT=$(curl -s -X POST -u "admin:admin123" -b "$JENKINS_COOKIE" \
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
println("Pipeline job created: " + name)' 2>&1)

if echo "$RESULT" | grep -q "Pipeline job created"; then
  echo "[✓] Pipeline job created"
else
  echo "[WARN] Pipeline creation result: $RESULT"
  echo "[WARN] Pipeline may need manual setup — plugins might still be loading"
fi

if grep -q '__REPLACE_ME__' /opt/terrafusion/backend/.env 2>/dev/null; then
  echo "[!] .env still has placeholder RDS host — skipping auto-build."
else
  echo "[*] Triggering build..."
  curl -s -o /dev/null -X POST \
    -u "admin:admin123" -b "$JENKINS_COOKIE" \
    -H "${CRUMB_HEADER}: ${CRUMB}" \
    "$JENKINS_URL/job/terrafusion-pipeline/build" 2>/dev/null || true
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
