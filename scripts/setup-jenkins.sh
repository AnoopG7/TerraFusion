#!/usr/bin/env bash
set -euo pipefail

JENKINS_URL="http://localhost:8080"
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com 2>/dev/null || echo "localhost")
TERRAFORM_DIR="/opt/terrafusion"

echo "═══════════════════════════════════════════════════════════════"
echo "  TerraFusion — Native Jenkins Setup (Ubuntu 24.04)"
echo "═══════════════════════════════════════════════════════════════"

# ── 1. Install Java 21 ──
echo "[1/6] Installing Java 21..."
apt install -y openjdk-21-jdk 2>/dev/null || {
  echo "[!] apt failed, trying manual install..."
  curl -fsSL https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.deb -o /tmp/jdk21.deb
  dpkg -i /tmp/jdk21.deb || true
}
echo "[✓] Java: $(java --version | head -1)"

# ── 2. Install Jenkins from apt repo ──
echo "[2/6] Installing Jenkins from apt repo..."
if [ ! -f /usr/share/keyrings/jenkins-keyring.asc ]; then
  curl -fsSL https://pkg.jenkins.io/debian/jenkins.io-2023.key -o /usr/share/keyrings/jenkins-keyring.asc
fi
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian binary/" > /etc/apt/sources.list.d/jenkins.list
apt update -y
apt install -y jenkins
echo "[✓] Jenkins installed: $(dpkg -l jenkins 2>/dev/null | awk '/^ii/ {print $3}')"

# ── 3. Configure Jenkins (systemd memory + init.groovy.d) ──
echo "[3/6] Configuring Jenkins..."
mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/override.conf << 'EOF'
[Service]
Environment="JAVA_OPTS=-Xmx256m -Xms128m"
EOF
systemctl daemon-reload

# Add jenkins to docker group
usermod -aG docker jenkins 2>/dev/null || true

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

def instance = Jenkins.getInstanceOrNull()
if (instance == null) return

// Remove existing admin user if any (idempotent)
def existing = instance.getSecurityRealm().allUsers
if (existing != null) {
  existing.each { u ->
    if (u.getId() == "admin") {
      instance.getSecurityRealm().deleteUser("admin")
    }
  }
}

def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount("admin", "admin123")
instance.setSecurityRealm(hudsonRealm)

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

instance.save()
println "init: admin user created (admin/admin123)"
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

# ── 4. Start Jenkins ──
echo "[4/6] Starting Jenkins..."
systemctl enable jenkins 2>/dev/null || true
systemctl restart jenkins || true

echo "[*] Waiting for Jenkins..."
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

# ── 5. Create Pipeline job ──
echo "[5/6] Creating Pipeline job..."

python3 << 'PYEOF' > /tmp/pipeline-config.xml
import xml.etree.ElementTree as ET

root = ET.Element("flow-definition")
root.set("plugin", "workflow-job@1571.1580.v18e46842c125")

ET.SubElement(root, "actions")
ET.SubElement(root, "description").text = "TerraFusion CI/CD Pipeline"
ET.SubElement(root, "keepDependencies").text = "false"

# Properties
props = ET.SubElement(root, "properties")

# SCM trigger: poll every 5 minutes
trig = ET.SubElement(props, "hudson.triggers.SCMTrigger")
ET.SubElement(trig, "spec").text = "H/5 * * * *"
ET.SubElement(trig, "ignorePostCommitHooks").text = "false"

# Definition: CpsScmFlowDefinition referencing Jenkinsfile from repo
definition = ET.SubElement(root, "definition")
definition.set("class", "org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition")
definition.set("plugin", "workflow-cps@4331.v9d06ed4658ff")

scm = ET.SubElement(definition, "scm")
scm.set("class", "hudson.plugins.git.GitSCM")
scm.set("plugin", "git@5.6.0")

ET.SubElement(scm, "configVersion").text = "2"

userRemoteConfigs = ET.SubElement(scm, "userRemoteConfigs")
remoteConfig = ET.SubElement(userRemoteConfigs, "hudson.plugins.git.UserRemoteConfig")
ET.SubElement(remoteConfig, "url").text = "https://github.com/AnoopG7/TerraFusion.git"

branches = ET.SubElement(scm, "branches")
branchSpec = ET.SubElement(branches, "hudson.plugins.git.BranchSpec")
ET.SubElement(branchSpec, "name").text = "*/main"

ET.SubElement(definition, "scriptPath").text = "Jenkinsfile"
ET.SubElement(definition, "lightweightCheckout").text = "true"

ET.SubElement(root, "disabled").text = "false"

xml_str = ET.tostring(root, encoding="unicode", xml_declaration=False)
xml_str = '<?xml version="1.1" encoding="UTF-8"?>\n' + xml_str
print(xml_str)
PYEOF

mkdir -p /var/lib/jenkins/jobs/terrafusion-pipeline
cp /tmp/pipeline-config.xml /var/lib/jenkins/jobs/terrafusion-pipeline/config.xml
chown -R jenkins:jenkins /var/lib/jenkins/jobs/terrafusion-pipeline
echo "[✓] Pipeline job config written"

# ── 6. Install plugins + trigger ──
echo "[6/6] Installing plugins & triggering build..."

JENKINS_COOKIE=$(mktemp)
CRUMB_JSON=$(curl -s -u "admin:admin123" -c "$JENKINS_COOKIE" "$JENKINS_URL/crumbIssuer/api/json")
CRUMB=$(echo "$CRUMB_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumb'])" 2>/dev/null || echo "")
CRUMB_HEADER=$(echo "$CRUMB_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumbRequestField'])" 2>/dev/null || echo "Jenkins-Crumb")

echo "[*] Installing default plugins..."
PLUGINS="ant build-timeout credentials-binding docker-workflow email-ext git github-branch-source jackson2-api mailer matrix-auth pipeline-build-step pipeline-graph-analysis pipeline-input-step pipeline-milestone-step pipeline-stage-view plain-credentials ssh-slaves timestamper ws-cleanup workflow-aggregator"
for plugin in $PLUGINS; do
  echo "  $plugin..."
  curl -s -X POST -u "admin:admin123" -b "$JENKINS_COOKIE" \
    -H "${CRUMB_HEADER}: ${CRUMB}" \
    "$JENKINS_URL/scriptText" \
    --data-urlencode "script=Jenkins.instance.pluginManager.install(Arrays.asList(\"$plugin\"), false).each{ it.get() }" > /dev/null 2>&1
done

echo "[*] Installing Blue Ocean..."
curl -s -X POST -u "admin:admin123" -b "$JENKINS_COOKIE" \
  -H "${CRUMB_HEADER}: ${CRUMB}" \
  "$JENKINS_URL/scriptText" \
  --data-urlencode "script=Jenkins.instance.pluginManager.install(Arrays.asList(\"blueocean\"), false).each{ it.get() }" > /dev/null 2>&1

echo "[*] Plugins installed (will load after restart)"

systemctl restart jenkins

for i in $(seq 1 90); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 2>/dev/null || echo "000")
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "403" ]; then break; fi
  sleep 3
done
echo "  Jenkins ready (HTTP $STATUS)"

JENKINS_COOKIE=$(mktemp)
CRUMB_JSON=$(curl -s -u "admin:admin123" -c "$JENKINS_COOKIE" "$JENKINS_URL/crumbIssuer/api/json")
CRUMB=$(echo "$CRUMB_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumb'])" 2>/dev/null || echo "")
CRUMB_HEADER=$(echo "$CRUMB_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumbRequestField'])" 2>/dev/null || echo "Jenkins-Crumb")

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
echo "  Workspace:  /var/lib/jenkins/workspace/terrafusion-pipeline/"
echo "  Log:        journalctl -u jenkins.service"
echo "═══════════════════════════════════════════════════════════════"
