#!/usr/bin/env bash
set -euo pipefail
set -x # CRITICAL: Prints every command to Terraform logs for debugging

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { printf "${GREEN}[BOOTSTRAP]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

# Prevent interactive prompts during install
export DEBIAN_FRONTEND=noninteractive

need_cmd() { command -v "$1" >/dev/null 2>&1; }

# Use SSH user even when script is run with sudo
TARGET_USER="${SUDO_USER:-${USER:-ubuntu}}"
TARGET_HOME="/home/${TARGET_USER}"

# --- FIX: Wait for EC2 Cloud-Init & Apt Locks ---
log "Waiting for cloud-init to complete..."
if command -v cloud-init >/dev/null; then
  cloud-init status --wait >/dev/null 2>&1 || true
fi

log "Waiting for apt locks to be released..."
while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 \
   || sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
   || sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
  echo "Waiting for other software managers to finish..."
  sleep 5
done
# ------------------------------------------------

log "Updating apt cache..."
sudo apt-get update -y

log "Installing base packages..."
sudo apt-get install -y \
  ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common \
  unzip git python3 python3-pip docker.io conntrack socat net-tools openjdk-17-jdk jq

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
  curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc >/dev/null
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

# IMPORTANT:
# You run minikube as ubuntu. So ensure *ubuntu* is in docker group and can access /var/run/docker.sock
if id -nG "${TARGET_USER}" | grep -q '\bdocker\b'; then
  :
else
  sudo usermod -aG docker "${TARGET_USER}"
  warn "Added ${TARGET_USER} to docker group."
fi

# Make docker.sock usable immediately (no re-login needed)
sudo chown root:docker /var/run/docker.sock || true
sudo chmod 660 /var/run/docker.sock || true

# Ensure kubectl/minikube directories exist and are owned by the SSH user
sudo mkdir -p "${TARGET_HOME}/.kube" "${TARGET_HOME}/.minikube"
sudo chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.kube" "${TARGET_HOME}/.minikube"

load_env_if_present() {
  local env_path="$1"
  if [ -f "$env_path" ]; then
    log "Sanitizing .env file (removing Windows \r characters)..."
    # FIX: Remove carriage returns (Windows format) so Linux can read it
    sed -i 's/\r$//' "$env_path" || true

    # shellcheck source=/dev/null
    . "$env_path"
  fi
}

# Optional: if Terraform uploads /home/${ssh_user}/.env, this loads it.
load_env_if_present "${TARGET_HOME}/.env"

# -------------------------------------------------------------------
# REQUIRED INPUTS (must come from Terraform remote-exec exports OR .env)
# -------------------------------------------------------------------
: "${DEVOPS_REPO_URL:?DEVOPS_REPO_URL must be provided (from Terraform/driver)}"
: "${BACKEND_REPO_URL:?BACKEND_REPO_URL must be provided (from Terraform/driver)}"
: "${FRONTEND_REPO_URL:?FRONTEND_REPO_URL must be provided (from Terraform/driver)}"

# Git auth (optional for public repos)
PAT_VALUE="${GIT_PAT:-}"
USER_VALUE="${GIT_USERNAME:-${GITHUB_USER:-git}}"

# -------------------------------------------------------------------
# URL helpers
# -------------------------------------------------------------------
strip_scheme() {
  echo "$1" | sed -E 's|^https?://||'
}

to_https_url() {
  local raw="$1"
  raw="$(strip_scheme "$raw")"
  echo "https://${raw}"
}

make_auth_url() {
  local raw="$1" user="$2" pat="$3"
  local base
  base="$(strip_scheme "$raw")"
  echo "https://${user}:${pat}@${base}"
}

# -------------------------------------------------------------------
# Clone DevOps repo -> /home/<user>/new-devops-local
# -------------------------------------------------------------------
REPO_DIR="${TARGET_HOME}/new-devops-local"

DEVOPS_AUTH_URL=""
if [ -n "$PAT_VALUE" ]; then
  DEVOPS_AUTH_URL="$(make_auth_url "$DEVOPS_REPO_URL" "$USER_VALUE" "$PAT_VALUE")"
else
  warn "GIT_PAT not set; cloning without authentication (will fail on private repos)."
  DEVOPS_AUTH_URL="$(to_https_url "$DEVOPS_REPO_URL")"
fi

DEVOPS_CLEAN_URL="$(to_https_url "$DEVOPS_REPO_URL")"

if [ ! -d "$REPO_DIR/.git" ]; then
  log "Cloning DevOps repo to $REPO_DIR"
  sudo rm -rf "$REPO_DIR"
  for i in 1 2 3; do
    if sudo -u "${TARGET_USER}" GIT_TERMINAL_PROMPT=0 git -c credential.helper= clone "$DEVOPS_AUTH_URL" "$REPO_DIR"; then
      log "DevOps clone successful on attempt $i"
      sudo -u "${TARGET_USER}" git -C "$REPO_DIR" remote set-url origin "$DEVOPS_CLEAN_URL" || true
      break
    else
      warn "DevOps clone attempt $i failed; retrying in 10s..."
      sudo rm -rf "$REPO_DIR"
      sleep 10
    fi
  done

  if [ ! -d "$REPO_DIR/.git" ]; then
    err "All DevOps clone attempts failed. Ensure GIT_PAT/GIT_USERNAME are correct."
    exit 1
  fi
else
  log "DevOps repo already present at $REPO_DIR; pulling latest"
  sudo -u "${TARGET_USER}" git -C "$REPO_DIR" remote set-url origin "$DEVOPS_AUTH_URL" || true
  sudo -u "${TARGET_USER}" GIT_TERMINAL_PROMPT=0 git -C "$REPO_DIR" pull --ff-only || warn "DevOps pull failed"
  sudo -u "${TARGET_USER}" git -C "$REPO_DIR" remote set-url origin "$DEVOPS_CLEAN_URL" || true
fi

sudo chown -R "${TARGET_USER}:${TARGET_USER}" "$REPO_DIR"

# -------------------------------------------------------------------
# Clone Backend + Frontend repos
# -------------------------------------------------------------------
BACKEND_AUTH_URL=""
FRONTEND_AUTH_URL=""

if [ -n "$PAT_VALUE" ]; then
  BACKEND_AUTH_URL="$(make_auth_url "$BACKEND_REPO_URL" "$USER_VALUE" "$PAT_VALUE")"
  FRONTEND_AUTH_URL="$(make_auth_url "$FRONTEND_REPO_URL" "$USER_VALUE" "$PAT_VALUE")"
else
  BACKEND_AUTH_URL="$(to_https_url "$BACKEND_REPO_URL")"
  FRONTEND_AUTH_URL="$(to_https_url "$FRONTEND_REPO_URL")"
fi

BACKEND_CLEAN_URL="$(to_https_url "$BACKEND_REPO_URL")"
FRONTEND_CLEAN_URL="$(to_https_url "$FRONTEND_REPO_URL")"

for pair in \
  "backend $BACKEND_AUTH_URL /home/${TARGET_USER}/new-backend $BACKEND_CLEAN_URL" \
  "frontend $FRONTEND_AUTH_URL /home/${TARGET_USER}/new-frontend $FRONTEND_CLEAN_URL"
do
  set -- $pair
  name=$1
  url=$2
  dir=$3
  clean_url=$4

  if [ ! -d "$dir/.git" ]; then
    log "Cloning $name repo into $dir"
    sudo rm -rf "$dir"
    if ! sudo -u "${TARGET_USER}" GIT_TERMINAL_PROMPT=0 git -c credential.helper= clone "$url" "$dir"; then
      err "Failed to clone $name repository. Check URL and ensure GIT_PAT/GIT_USERNAME are correct."
      exit 1
    fi
    sudo -u "${TARGET_USER}" git -C "$dir" remote set-url origin "$clean_url" || true
  else
    log "$name repo exists; pulling latest"
    sudo -u "${TARGET_USER}" git -C "$dir" remote set-url origin "$url" || true
    sudo -u "${TARGET_USER}" GIT_TERMINAL_PROMPT=0 git -C "$dir" pull --ff-only || warn "$name pull failed"
    sudo -u "${TARGET_USER}" git -C "$dir" remote set-url origin "$clean_url" || true
  fi

  sudo chown -R "${TARGET_USER}:${TARGET_USER}" "$dir"
done

log "Bootstrap tool versions:"
need_cmd kubectl   && kubectl version --client || true
need_cmd minikube  && minikube version || true
need_cmd terraform && terraform version | head -n1 || true
need_cmd docker    && docker --version || true
need_cmd git       && git --version || true
need_cmd python3   && python3 --version || true
need_cmd aws       && aws --version || true

log "Bootstrap complete."