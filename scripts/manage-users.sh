#!/usr/bin/env bash
set -euo pipefail

TERRAFUSION_HOME="/opt/terrafusion"
SCRIPT_NAME=$(basename "$0")

usage() {
  echo "Usage: $SCRIPT_NAME {add|remove|list|add-to-group|ssh-key} [args...]"
  echo ""
  echo "Commands:"
  echo "  add <username>                    Create user + docker group"
  echo "  remove <username>                 Delete user and home"
  echo "  list                              List all platform users"
  echo "  add-to-group <user> <group>       Add user to group"
  echo "  ssh-key <username> '<pubkey>'     Set SSH authorized key"
  exit 1
}

case "${1:-}" in
  add)
    USERNAME="${2:-}"
    [[ -z "$USERNAME" ]] && usage
    if id "$USERNAME" &>/dev/null; then echo "User '$USERNAME' exists."; exit 0; fi
    sudo useradd -m -s /bin/bash -c "TerraFusion User" "$USERNAME"
    echo "$USERNAME:TerraFusion@123" | sudo chpasswd
    sudo passwd --expire "$USERNAME" 2>/dev/null || true
    sudo usermod -aG docker "$USERNAME"
    sudo usermod -aG sudo "$USERNAME"
    echo "[✓] User $USERNAME created"
    ;;
  remove)
    USERNAME="${2:-}"
    [[ -z "$USERNAME" ]] && usage
    sudo userdel -r "$USERNAME" 2>/dev/null || sudo userdel "$USERNAME"
    echo "[✓] User $USERNAME removed"
    ;;
  list)
    echo "=== TerraFusion Platform Users ==="
    awk -F: '!/^nobody|^root|^daemon|^bin|^sys/ && $3 >= 1000 { print $1, $3 }' /etc/passwd
    ;;
  add-to-group)
    USERNAME="${2:-}"; GROUPNAME="${3:-}"
    [[ -z "$USERNAME" || -z "$GROUPNAME" ]] && usage
    getent group "$GROUPNAME" &>/dev/null || sudo groupadd "$GROUPNAME"
    sudo usermod -aG "$GROUPNAME" "$USERNAME"
    echo "[✓] $USERNAME added to $GROUPNAME"
    ;;
  ssh-key)
    USERNAME="${2:-}"; PUBKEY="${3:-}"
    [[ -z "$USERNAME" || -z "$PUBKEY" ]] && usage
    SSH_DIR="/home/$USERNAME/.ssh"
    sudo mkdir -p "$SSH_DIR"
    echo "$PUBKEY" | sudo tee -a "$SSH_DIR/authorized_keys" > /dev/null
    sudo chmod 700 "$SSH_DIR" && sudo chmod 600 "$SSH_DIR/authorized_keys"
    sudo chown -R "$USERNAME:$USERNAME" "$SSH_DIR"
    echo "[✓] SSH key installed for $USERNAME"
    ;;
  *) usage ;;
esac
