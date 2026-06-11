#!/usr/bin/env bash
set -euo pipefail

detect_pkg_manager() {
  if command -v apt &>/dev/null; then echo "apt"
  elif command -v yum &>/dev/null; then echo "yum"
  elif command -v dnf &>/dev/null; then echo "dnf"
  else echo "unknown"; fi
}

PKG_MANAGER=$(detect_pkg_manager)
echo "=== TerraFusion Package Installation ==="
echo "Package manager: $PKG_MANAGER"

if [[ "$PKG_MANAGER" == "unknown" ]]; then
  echo "[!] Unsupported package manager"
  exit 1
fi

COMMON_PACKAGES=(git curl wget htop tree unzip jq vim ufw)

install_docker() {
  if command -v docker &>/dev/null; then
    echo "[✓] Docker already installed: $(docker --version)"
    return
  fi
  echo "[*] Installing Docker..."
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sh /tmp/get-docker.sh
  systemctl enable docker
  systemctl start docker
  echo "[✓] Docker installed"
}

install_k3s() {
  if command -v k3s &>/dev/null; then
    echo "[✓] k3s already installed"
    return
  fi
  echo "[*] Installing k3s..."
  curl -sfL https://get.k3s.io | sh -
  echo "[✓] k3s installed"
}

install_helm() {
  if command -v helm &>/dev/null; then
    echo "[✓] Helm already installed"
    return
  fi
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  echo "[✓] Helm installed"
}

install_aws_cli() {
  if command -v aws &>/dev/null; then
    echo "[✓] AWS CLI already installed"
    return
  fi
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install
  echo "[✓] AWS CLI installed"
}

echo "[*] Installing common packages..."
case "$PKG_MANAGER" in
  apt)
    apt update -y
    apt install -y "${COMMON_PACKAGES[@]}"
    ;;
  yum|dnf)
    "$PKG_MANAGER" install -y "${COMMON_PACKAGES[@]}"
    ;;
esac
echo "[✓] Common packages installed."

install_docker
install_k3s
install_helm
install_aws_cli

echo ""
echo "=== Installed Versions ==="
echo "Docker:  $(docker --version 2>/dev/null || echo 'N/A')"
echo "k3s:     $(k3s --version 2>/dev/null | head -1 || echo 'N/A')"
echo "Helm:    $(helm version --short 2>/dev/null || echo 'N/A')"
echo "AWS CLI: $(aws --version 2>/dev/null || echo 'N/A')"
echo ""
echo "[✓] Installation complete."
