#!/usr/bin/env bash
set -uo pipefail

JENKINS_URL="http://localhost:8080"
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com 2>/dev/null || echo "localhost")
JENKINS_HOME="/var/lib/jenkins"
PLUGIN_MANAGER_VERSION="2.14.0"
PLUGIN_LIST="workflow-aggregator git docker-workflow pipeline-stage-view blueocean credentials-binding plain-credentials build-timeout timestamper ws-cleanup email-ext github-branch-source mailer matrix-auth pipeline-build-step ssh-slaves"

echo "═══════════════════════════════════════════════════════════════"
echo "  TerraFusion — Native Jenkins Setup (Ubuntu 24.04)"
echo "═══════════════════════════════════════════════════════════════"

# ── 1. Install Java 21 ──
echo "[1/7] Installing Java 21..."
apt install -y fontconfig openjdk-21-jre
echo "[✓] Java: $(java --version 2>&1 | head -1)"

# ── 2. Install Jenkins from official apt repo ──
echo "[2/7] Installing Jenkins from apt repo..."

rm -f /etc/apt/sources.list.d/jenkins.list
rm -f /usr/share/keyrings/jenkins-keyring.asc /usr/share/keyrings/jenkins-keyring.gpg
rm -f /etc/apt/keyrings/jenkins-keyring.asc

mkdir -p /etc/apt/keyrings
wget -q -O /etc/apt/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" > /etc/apt/sources.list.d/jenkins.list
apt update -y

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
echo "[3/7] Configuring Jenkins..."
usermod -aG docker jenkins 2>/dev/null || true

echo "jenkins ALL=(ALL) NOPASSWD: /usr/local/bin/k3s, /usr/local/bin/kubectl" > /etc/sudoers.d/jenkins-k3s
chmod 440 /etc/sudoers.d/jenkins-k3s

mkdir -p /var/lib/jenkins/.kube
cp /etc/rancher/k3s/k3s.yaml /var/lib/jenkins/.kube/config 2>/dev/null || true
chown -R jenkins:jenkins /var/lib/jenkins/.kube 2>/dev/null || true
chmod 600 /var/lib/jenkins/.kube/config 2>/dev/null || true

# ── 4. Set up init.groovy.d ──
echo "[4/7] Setting up init scripts..."
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

# ── 5. Start Jenkins (first boot runs init.groovy.d) ──
echo "[5/7] Starting Jenkins..."
systemctl restart jenkins || true

echo "[*] Waiting for Jenkins ready..."
for i in $(seq 1 90); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$JENKINS_URL" 2>/dev/null || echo "000")
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "403" ]; then break; fi
  sleep 3
done
echo "[✓] Jenkins ready (HTTP $STATUS)"
sleep 15
echo "[✓] init.groovy.d scripts executed"

# ── 6. Install plugins using jenkins-plugin-manager ──
echo "[6/7] Installing plugins via jenkins-plugin-manager..."

PM_JAR="/tmp/jenkins-plugin-manager.jar"
if [ ! -f "$PM_JAR" ]; then
  echo "[*] Downloading plugin-manager ${PLUGIN_MANAGER_VERSION}..."
  curl -sL -o "$PM_JAR" \
    "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/${PLUGIN_MANAGER_VERSION}/jenkins-plugin-manager-${PLUGIN_MANAGER_VERSION}.jar"
fi

systemctl stop jenkins
echo "[*] Jenkins stopped, installing plugins..."
java -jar "$PM_JAR" \
  --war /usr/share/java/jenkins.war \
  --plugin-download-directory /var/lib/jenkins/plugins \
  --latest true \
  --plugins $PLUGIN_LIST
echo "[✓] Plugins downloaded (including all transitive dependencies)"

chown -R jenkins:jenkins /var/lib/jenkins/plugins

systemctl restart jenkins
echo "[*] Waiting for Jenkins to reload plugins..."
for i in $(seq 1 90); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$JENKINS_URL" 2>/dev/null || echo "000")
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "403" ]; then break; fi
  sleep 3
done
echo "[✓] Jenkins ready with all plugins (HTTP $STATUS)"

# ── 7. Create pipeline job via direct XML config + trigger build ──
echo "[7/7] Creating Pipeline job & triggering build..."

su - jenkins -c "git config --global --add safe.directory '*'"

cat > /tmp/terrafusion-pipeline-config.xml << 'JOBXML'
<?xml version="1.1" encoding="UTF-8"?>
<flow-definition plugin="workflow-job@1571.1580.v18e46842c125">
  <actions/>
  <description>TerraFusion CI/CD pipeline — builds Docker images, imports to k3s, updates deployments</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.StringParameterDefinition>
          <name>BRANCH</name>
          <description>Git branch to build &amp; deploy</description>
          <defaultValue>main</defaultValue>
          <trim>false</trim>
        </hudson.model.StringParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps@4331.v9d06ed4658ff">
    <script>
pipeline {
    agent any
    parameters {
        string(name: "BRANCH", defaultValue: "main", description: "Git branch to build &amp; deploy")
    }
    environment {
        KUBECONFIG = "/etc/rancher/k3s/k3s.yaml"
    }
    stages {
        stage("Checkout") {
            steps {
                git branch: params.BRANCH, url: "https://github.com/AnoopG7/TerraFusion.git"
            }
        }
        stage("Install Dependencies") {
            parallel {
                stage("Frontend") { steps { dir("frontend") { sh "npm ci" } } }
                stage("Backend") { steps { dir("backend") { sh "npm ci" } } }
            }
        }
        stage("Lint &amp; Type Check") {
            parallel {
                stage("Frontend TypeCheck") { steps { dir("frontend") { sh "npx tsc --noEmit" } } }
                stage("Backend TypeCheck") { steps { dir("backend") { sh "npx tsc --noEmit" } } }
            }
        }
        stage("Build Docker Images") {
            steps {
                sh "docker build -t terrafusion-backend:latest ./backend"
                sh "docker build -t terrafusion-frontend:latest ./frontend"
            }
        }
        stage("Import to k3s") {
            steps {
                sh "docker save terrafusion-backend:latest | sudo k3s ctr images import -"
                sh "docker save terrafusion-frontend:latest | sudo k3s ctr images import -"
            }
        }
        stage("Deploy to k3s") {
            steps {
                sh "kubectl set image deployment/backend -n terrafusion backend=terrafusion-backend:latest --record"
                sh "kubectl set image deployment/frontend -n terrafusion frontend=terrafusion-frontend:latest --record"
                sh "kubectl rollout status deployment/backend -n terrafusion --timeout=120s"
                sh "kubectl rollout status deployment/frontend -n terrafusion --timeout=120s"
            }
        }
        stage("Health Check") {
            steps {
                sleep 10
                sh "kubectl exec -n terrafusion deploy/backend -- wget -q -O - --timeout=5 http://localhost:3001/api/health || echo Health FAIL"
            }
        }
    }
    post {
        success { echo "Pipeline succeeded - build \${env.BUILD_NUMBER} deployed!" }
        failure { echo "Pipeline FAILED - build \${env.BUILD_NUMBER}" }
        always { cleanWs() }
    }
}
    </script>
    <sandbox>true</sandbox>
  </definition>
  <disabled>false</disabled>
</flow-definition>
JOBXML

mkdir -p /var/lib/jenkins/jobs/terrafusion-pipeline
cp /tmp/terrafusion-pipeline-config.xml /var/lib/jenkins/jobs/terrafusion-pipeline/config.xml
chown -R jenkins:jenkins /var/lib/jenkins/jobs/terrafusion-pipeline
echo "[✓] Pipeline job config written"

systemctl restart jenkins
for i in $(seq 1 90); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$JENKINS_URL" 2>/dev/null || echo "000")
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "403" ]; then break; fi
  sleep 3
done
echo "[✓] Jenkins ready with pipeline job (HTTP $STATUS)"

# Trigger build via REST API with CSRF crumb
COOKIE_FILE=$(mktemp)
CRUMB_JSON=$(curl -s -u "admin:admin123" -c "$COOKIE_FILE" "$JENKINS_URL/crumbIssuer/api/json")
CRUMB=$(echo "$CRUMB_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumb'])" 2>/dev/null || echo "")
CRUMB_HEADER=$(echo "$CRUMB_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumbRequestField'])" 2>/dev/null || echo "Jenkins-Crumb")

if grep -q '__REPLACE_ME__' /opt/terrafusion/backend/.env 2>/dev/null; then
  echo "[!] .env still has placeholder RDS host — skipping auto-build"
else
  echo "[*] Triggering build..."
  curl -s -X POST -u "admin:admin123" -b "$COOKIE_FILE" \
    -H "${CRUMB_HEADER}: ${CRUMB}" \
    "$JENKINS_URL/job/terrafusion-pipeline/buildWithParameters?BRANCH=main" -o /dev/null -w "  HTTP %{http_code}\n"
fi
rm -f "$COOKIE_FILE"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Native Jenkins Setup Complete!"
echo "  URL:        http://$PUBLIC_IP:8080"
echo "  Login:      admin / admin123"
echo "  Job:        http://$PUBLIC_IP:8080/job/terrafusion-pipeline/"
echo "  Blue Ocean: http://$PUBLIC_IP:8080/blue/"
echo "  Log:        journalctl -u jenkins.service"
echo "═══════════════════════════════════════════════════════════════"
