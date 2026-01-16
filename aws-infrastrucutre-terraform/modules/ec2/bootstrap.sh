#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { printf "${GREEN}[BOOTSTRAP]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

# Use SSH user even when script is run with sudo
TARGET_USER="${SUDO_USER:-${USER:-ubuntu}}"
TARGET_HOME="/home/${TARGET_USER}"

log "Updating apt cache..."
sudo apt-get update -y

log "Installing base packages..."
sudo apt-get install -y \
  ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common \
  unzip git python3 python3-pip docker.io conntrack socat net-tools openjdk-17-jdk

if ! need_cmd aws; then
  log "Installing AWS CLI v2 (official installer)..."
  ARCH="$(uname -m)"
  if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    AWS_ARCH="aarch64"
  else
    AWS_ARCH="x86_64"
  fi
  curl -L "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  sudo /tmp/aws/install
  rm -rf /tmp/aws /tmp/awscliv2.zip
else
  warn "AWS CLI already installed; skipping."
fi

if ! need_cmd kubectl; then
  log "Installing kubectl..."
  K_VER="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
  curl -L "https://dl.k8s.io/release/${K_VER}/bin/linux/amd64/kubectl" -o /tmp/kubectl
  sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
else
  warn "kubectl already installed; skipping."
fi

if ! need_cmd minikube; then
  log "Installing Minikube..."
  curl -L "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64" -o /tmp/minikube
  sudo install -m 0755 /tmp/minikube /usr/local/bin/minikube
else
  warn "Minikube already installed; skipping."
fi

if ! need_cmd terraform; then
  log "Installing Terraform..."
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y terraform
else
  warn "Terraform already installed; skipping."
fi

log "Installing Jenkins..."
if ! need_cmd jenkins; then
  curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y jenkins
else
  warn "Jenkins already installed; skipping."
fi

log "Configuring Java 17 for Jenkins..."
sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java || true
if grep -q "^JAVA_HOME=" /etc/default/jenkins; then
  sudo sed -i 's|^JAVA_HOME=.*|JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64|' /etc/default/jenkins
else
  echo 'JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64' | sudo tee -a /etc/default/jenkins >/dev/null
fi
sudo systemctl daemon-reload || true
sudo systemctl enable jenkins >/dev/null 2>&1 || true
sudo systemctl restart jenkins  >/dev/null 2>&1 || true

# Wait briefly for Jenkins to start and then print admin password and URL
log "Checking Jenkins status and admin password..."
for i in $(seq 1 12); do
  if sudo systemctl is-active --quiet jenkins; then
    if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
      ADMIN_PASS=$(sudo cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || true)
      if [ -n "$ADMIN_PASS" ]; then
        log "Jenkins admin password: $ADMIN_PASS"
      fi
    fi
    PUB_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || true)
    if [ -z "$PUB_IP" ]; then
      PUB_IP=$(curl -s https://checkip.amazonaws.com || true)
    fi
    if [ -z "$PUB_IP" ]; then
      PUB_IP=$(dig +short myip.opendns.com @resolver1.opendns.com || true)
    fi
    if [ -z "$PUB_IP" ]; then
      PUB_IP=$(hostname -I | awk '{print $1}')
    fi
    if [ -n "$PUB_IP" ]; then
      log "Jenkins URL: http://${PUB_IP}:8080/"
    else
      warn "Could not determine public IP for Jenkins URL."
    fi
    break
  fi
  sleep 5
done

log "Adding GitHub host key to Jenkins known_hosts..."
sudo -u jenkins sh -c 'mkdir -p /var/lib/jenkins/.ssh && touch /var/lib/jenkins/.ssh/known_hosts && chmod 600 /var/lib/jenkins/.ssh/known_hosts'
if ! sudo -u jenkins sh -c "grep -q 'github.com' /var/lib/jenkins/.ssh/known_hosts"; then
  ssh-keyscan -t rsa,ecdsa,ed25519 github.com 2>/dev/null | sudo -u jenkins tee -a /var/lib/jenkins/.ssh/known_hosts >/dev/null || true
fi
sudo chown -R jenkins:jenkins /var/lib/jenkins/.ssh

log "Ensuring Docker is running..."
sudo systemctl enable docker >/dev/null 2>&1 || true
sudo systemctl start docker  >/dev/null 2>&1 || true

if groups "$USER" | grep -q '\bdocker\b'; then
  :
else
  sudo usermod -aG docker "$USER"
  warn "User added to docker group; re-login may be required."
fi

# Ensure kubectl/minikube directories exist and are owned by the SSH user
sudo mkdir -p "${TARGET_HOME}/.kube" "${TARGET_HOME}/.minikube"
sudo chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.kube" "${TARGET_HOME}/.minikube"

load_env_if_present() {
  local env_path="$1"
  if [ -f "$env_path" ]; then
    # shellcheck source=/dev/null
    . "$env_path"
  fi
}

# --- UPDATED GIT CLONE SECTION (no hardcoded creds) ---
REPO_DIR="${TARGET_HOME}/new-devops-local"

# Optional env files for credentials (set GIT_PAT and GIT_USERNAME, and repo URLs)
load_env_if_present "${TARGET_HOME}/.env"
load_env_if_present "${REPO_DIR}/.env"

DEVOPS_REPO_URL="${DEVOPS_REPO_URL:-https://github.com/simple-ec2-deployment/new-devops-local.git}"
BACKEND_REPO_URL="${BACKEND_REPO_URL:-https://github.com/simple-ec2-deployment/new-backend.git}"
FRONTEND_REPO_URL="${FRONTEND_REPO_URL:-https://github.com/simple-ec2-deployment/new-frontend.git}"
REPO_URL_BASE="$(echo "$DEVOPS_REPO_URL" | sed -E 's|^https?://||')"

PAT_VALUE="${GIT_PAT:-}"
USER_VALUE="${GIT_USERNAME:-git}"

if [ -z "$PAT_VALUE" ]; then
  warn "GIT_PAT not set; cloning without authentication (will fail on private repos)."
  REPO_URL="https://${REPO_URL_BASE}"
else
  REPO_URL="https://${USER_VALUE}:${PAT_VALUE}@${REPO_URL_BASE}"
fi

if [ ! -d "$REPO_DIR/.git" ]; then
  log "Cloning infrastructure repo to $REPO_DIR"
  rm -rf "$REPO_DIR"
  for i in {1..3}; do
    if sudo -u "${TARGET_USER}" git clone "$REPO_URL" "$REPO_DIR"; then
      log "Clone successful on attempt $i"
      sudo -u "${TARGET_USER}" git -C "$REPO_DIR" remote set-url origin "https://${REPO_URL_BASE}"
      break
    else
      warn "Clone attempt $i failed; retrying in 10s..."
      rm -rf "$REPO_DIR"
      sleep 10
    fi
  done
  
  if [ ! -d "$REPO_DIR/.git" ]; then
    err "All clone attempts failed. Ensure GIT_PAT/GIT_USERNAME are set (via env or ${TARGET_HOME}/.env)."
    exit 1
  fi
else
  log "Repo already present at $REPO_DIR"
  sudo -u "${TARGET_USER}" git -C "$REPO_DIR" remote set-url origin "$REPO_URL"
  if ! sudo -u "${TARGET_USER}" git -C "$REPO_DIR" pull --ff-only; then
    warn "Git pull failed; please check repo access"
  fi
  sudo -u "${TARGET_USER}" git -C "$REPO_DIR" remote set-url origin "https://${REPO_URL_BASE}"
fi
sudo chown -R "${TARGET_USER}:${TARGET_USER}" "$REPO_DIR"
# --- END UPDATED GIT CLONE SECTION ---

# Pre-clone backend and frontend using dynamic creds/URLs
BACKEND_URL_RAW="${BACKEND_REPO_URL:-https://github.com/simple-ec2-deployment/new-backend.git}"
FRONTEND_URL_RAW="${FRONTEND_REPO_URL:-https://github.com/simple-ec2-deployment/new-frontend.git}"
BACKEND_URL_BASE="$(echo "$BACKEND_URL_RAW" | sed -E 's|^https?://||')"
FRONTEND_URL_BASE="$(echo "$FRONTEND_URL_RAW" | sed -E 's|^https?://||')"
if [ -n "$PAT_VALUE" ]; then
  BACKEND_URL="https://${USER_VALUE}:${PAT_VALUE}@${BACKEND_URL_BASE}"
  FRONTEND_URL="https://${USER_VALUE}:${PAT_VALUE}@${FRONTEND_URL_BASE}"
else
  BACKEND_URL="https://${BACKEND_URL_BASE}"
  FRONTEND_URL="https://${FRONTEND_URL_BASE}"
fi

for pair in "backend $BACKEND_URL /home/${TARGET_USER}/new-backend" "frontend $FRONTEND_URL /home/${TARGET_USER}/new-frontend"; do
  set -- $pair
  name=$1 url=$2 dir=$3
  if [ ! -d "$dir/.git" ]; then
    warn "Cloning $name repository..."
    if ! sudo -u "${TARGET_USER}" GIT_TERMINAL_PROMPT=0 git -c credential.helper= clone "$url" "$dir"; then
      err "Failed to clone $name repository. Ensure GIT_PAT/GIT_USERNAME are set."
      exit 1
    fi
  else
    sudo -u "${TARGET_USER}" git -C "$dir" remote set-url origin "$url" || true
    sudo -u "${TARGET_USER}" GIT_TERMINAL_PROMPT=0 git -C "$dir" pull --ff-only || warn "$name pull failed"
  fi
done

log "Versions:"
if need_cmd kubectl; then kubectl version --client || true; else warn "kubectl not found"; fi
if need_cmd minikube; then minikube version || true; else warn "minikube not found"; fi
if need_cmd terraform; then terraform version | head -n1 || true; else warn "terraform not found"; fi
if need_cmd docker; then docker --version || true; else warn "docker not found"; fi
if need_cmd git; then git --version || true; else warn "git not found"; fi
if need_cmd python3; then python3 --version || true; else warn "python3 not found"; fi
if need_cmd aws; then aws --version || true; else warn "aws not found"; fi

if need_cmd jenkins; then
  log "Jenkins detected; showing admin info..."
  if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
    ADMIN_PASS=$(sudo cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || true)
    if [ -n "$ADMIN_PASS" ]; then
      log "Jenkins admin password: $ADMIN_PASS"
    else
      warn "Jenkins admin password file empty or unreadable."
    fi
  else
    warn "Jenkins admin password file not found yet."
  fi
  PUB_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || hostname -I | awk '{print $1}')
  if [ -n "$PUB_IP" ]; then
    log "Jenkins URL: http://${PUB_IP}:8080/"
  fi
fi

log "Bootstrap complete."