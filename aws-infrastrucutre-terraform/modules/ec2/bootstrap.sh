#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Logging / debug
# ------------------------------------------------------------
# Enable command tracing ONLY if explicitly requested, to avoid leaking tokens into Terraform logs.
DEBUG_BOOTSTRAP="${DEBUG_BOOTSTRAP:-0}"
if [ "${DEBUG_BOOTSTRAP}" = "1" ]; then
  set -x
fi

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { printf "${GREEN}[BOOTSTRAP]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

export DEBIAN_FRONTEND=noninteractive

need_cmd() { command -v "$1" >/dev/null 2>&1; }

# Use SSH user even when script is run with sudo
TARGET_USER="${SUDO_USER:-${USER:-ubuntu}}"
TARGET_HOME="/home/${TARGET_USER}"

# -------------------------------------------------------------------
# Controls (override via Terraform env exports or /home/<user>/.env)
# -------------------------------------------------------------------
START_MINIKUBE="${START_MINIKUBE:-1}"                 # 1=start minikube, 0=skip
MINIKUBE_DRIVER="${MINIKUBE_DRIVER:-docker}"          # docker (matches your runs)
MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-minikube}"
KUBE_CONTEXT="${KUBE_CONTEXT:-minikube}"

# IMPORTANT: minikube container resources (this is NOT the EC2 instance size)
MINIKUBE_MEMORY_MB="${MINIKUBE_MEMORY_MB:-4096}"
MINIKUBE_CPUS="${MINIKUBE_CPUS:-2}"

ENABLE_HOST_NGINX="${ENABLE_HOST_NGINX:-1}"           # 1=host nginx :80->:32080
ENABLE_INGRESS="${ENABLE_INGRESS:-1}"                 # 1=apply ingress controller + ingress rules
ENABLE_APP_DEPLOY="${ENABLE_APP_DEPLOY:-0}"           # 1=apply your k8s manifests (set paths below)

# Paths inside the cloned DevOps repo (adjust if your repo layout changes)
DEVOPS_DIR="${TARGET_HOME}/new-devops-local"
INGRESS_CONTROLLER_PATH_REL="devops-infra/kubernetes/ingress-controller/nginx-ingress-controller.yaml"
INGRESS_RULES_PATH_REL="devops-infra/kubernetes/ingress/ingress.yaml"

# Optional app deployment paths (only used if ENABLE_APP_DEPLOY=1)
APP_MANIFESTS_DIRS_REL=(
  "devops-infra/kubernetes/deployments"
  "devops-infra/kubernetes/services"
)

# -------------------------------------------------------------------
# Wait for cloud-init and apt locks
# -------------------------------------------------------------------
log "Waiting for cloud-init to complete..."
if command -v cloud-init >/dev/null 2>&1; then
  cloud-init status --wait >/dev/null 2>&1 || true
fi

log "Waiting for apt locks to be released..."
while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 \
   || sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
   || sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
  echo "Waiting for other software managers to finish..."
  sleep 5
done

# -------------------------------------------------------------------
# Base packages
# -------------------------------------------------------------------
log "Updating apt cache..."
sudo apt-get update -y

log "Installing base packages..."
sudo apt-get install -y \
  ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common \
  unzip git python3 python3-pip docker.io conntrack socat net-tools openjdk-17-jdk jq nginx openssl

# -------------------------------------------------------------------
# Ensure /home/<user>/.env exists early (systemd EnvironmentFile needs it)
# -------------------------------------------------------------------
ENV_FILE="${TARGET_HOME}/.env"
log "Ensuring ${ENV_FILE} exists (for systemd EnvironmentFile)..."
sudo -u "${TARGET_USER}" touch "${ENV_FILE}"
sudo chmod 600 "${ENV_FILE}" || true
sudo chown "${TARGET_USER}:${TARGET_USER}" "${ENV_FILE}"

# Normalize Windows CRLF early
sed -i 's/\r$//' "${ENV_FILE}" || true

# Ensure SMEE_URL/SMEE_TARGET exist (NO QUOTES; systemd does not strip them)
if ! grep -q '^SMEE_URL=' "${ENV_FILE}"; then
  echo 'SMEE_URL=https://smee.io/3kEdRwsh19vXOgv' | sudo tee -a "${ENV_FILE}" >/dev/null
fi
if ! grep -q '^SMEE_TARGET=' "${ENV_FILE}"; then
  echo 'SMEE_TARGET=http://127.0.0.1:8080/generic-webhook-trigger/invoke' | sudo tee -a "${ENV_FILE}" >/dev/null
fi

# -------------------------------------------------------------------
# Node.js + smee-client (GitHub webhook relay)
# -------------------------------------------------------------------
log "Installing Node.js (for smee-client)..."
if ! need_cmd node; then
  curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
  sudo apt-get install -y nodejs
else
  warn "Node.js already installed; skipping."
fi

log "Installing smee-client..."
if ! command -v smee >/dev/null 2>&1; then
  sudo npm install -g smee-client
else
  warn "smee-client already installed; skipping."
fi

# -------------------------------------------------------------------
# AWS CLI v2
# -------------------------------------------------------------------
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

# -------------------------------------------------------------------
# kubectl / minikube
# -------------------------------------------------------------------
BIN_ARCH="amd64"
case "$(uname -m)" in
  x86_64) BIN_ARCH="amd64" ;;
  aarch64|arm64) BIN_ARCH="arm64" ;;
  *) BIN_ARCH="amd64" ;;
esac

if ! need_cmd kubectl; then
  log "Installing kubectl..."
  K_VER="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
  curl -L "https://dl.k8s.io/release/${K_VER}/bin/linux/${BIN_ARCH}/kubectl" -o /tmp/kubectl
  sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
else
  warn "kubectl already installed; skipping."
fi

if ! need_cmd minikube; then
  log "Installing Minikube..."
  curl -L "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${BIN_ARCH}" -o /tmp/minikube
  sudo install -m 0755 /tmp/minikube /usr/local/bin/minikube
else
  warn "Minikube already installed; skipping."
fi

# -------------------------------------------------------------------
# Terraform
# -------------------------------------------------------------------
if ! need_cmd terraform; then
  log "Installing Terraform..."
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y terraform
else
  warn "Terraform already installed; skipping."
fi

# -------------------------------------------------------------------
# Jenkins
# -------------------------------------------------------------------
log "Installing Jenkins..."
if ! need_cmd jenkins; then
  curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key \
    | sudo tee /usr/share/keyrings/jenkins-keyring.asc >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
    | sudo tee /etc/apt/sources.list.d/jenkins.list >/dev/null
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
sudo systemctl restart jenkins >/dev/null 2>&1 || true

log "Checking Jenkins status and URL..."
for i in $(seq 1 12); do
  if sudo systemctl is-active --quiet jenkins; then
    PUB_IP="$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || true)"
    if [ -z "$PUB_IP" ]; then
      PUB_IP="$(curl -s https://checkip.amazonaws.com || true)"
    fi
    if [ -z "$PUB_IP" ]; then
      PUB_IP="$(hostname -I | awk '{print $1}')"
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

# -------------------------------------------------------------------
# smee systemd service (reads SMEE_URL/SMEE_TARGET from /home/<user>/.env)
# -------------------------------------------------------------------
log "Creating/Updating smee-jenkins.service..."
cat <<EOF | sudo tee /etc/systemd/system/smee-jenkins.service >/dev/null
[Unit]
Description=CloudRift Smee relay (GitHub webhooks -> local Jenkins)
After=network.target jenkins.service
StartLimitIntervalSec=0

[Service]
Type=simple
User=${TARGET_USER}
EnvironmentFile=${ENV_FILE}
ExecStart=/usr/bin/env smee -u \${SMEE_URL} --target \${SMEE_TARGET}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now smee-jenkins
sudo systemctl restart smee-jenkins || true

# -------------------------------------------------------------------
# Docker
# -------------------------------------------------------------------
log "Ensuring Docker is running..."
sudo systemctl enable docker >/dev/null 2>&1 || true
sudo systemctl start docker  >/dev/null 2>&1 || true

# Ensure SSH user can run docker/minikube with docker driver
if id -nG "${TARGET_USER}" | grep -q '\bdocker\b'; then
  :
else
  sudo usermod -aG docker "${TARGET_USER}"
  warn "Added ${TARGET_USER} to docker group (effective on next login)."
fi

# Make docker.sock usable immediately
sudo chown root:docker /var/run/docker.sock || true
sudo chmod 660 /var/run/docker.sock || true

# Ensure kube dirs exist and are owned by SSH user
sudo mkdir -p "${TARGET_HOME}/.kube" "${TARGET_HOME}/.minikube"
sudo chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.kube" "${TARGET_HOME}/.minikube"

# -------------------------------------------------------------------
# Load /home/<user>/.env if present
# -------------------------------------------------------------------
load_env_if_present() {
  local env_path="$1"
  if [ -f "$env_path" ]; then
    log "Loading .env from ${env_path} (also removing Windows CRLF)..."
    sed -i 's/\r$//' "$env_path" || true
    # shellcheck source=/dev/null
    . "$env_path"
  fi
}
load_env_if_present "${TARGET_HOME}/.env"

# -------------------------------------------------------------------
# REQUIRED INPUTS (from Terraform exports OR .env)
# -------------------------------------------------------------------
: "${DEVOPS_REPO_URL:?DEVOPS_REPO_URL must be provided (from Terraform/driver)}"
: "${BACKEND_REPO_URL:?BACKEND_REPO_URL must be provided (from Terraform/driver)}"
: "${FRONTEND_REPO_URL:?FRONTEND_REPO_URL must be provided (from Terraform/driver)}"

PAT_VALUE="${GIT_PAT:-}"
USER_VALUE="${GIT_USERNAME:-${GITHUB_USER:-git}}"

strip_scheme() { echo "$1" | sed -E 's|^https?://||'; }
to_https_url() { local raw="$1"; raw="$(strip_scheme "$raw")"; echo "https://${raw}"; }
make_auth_url() { local raw="$1" user="$2" pat="$3"; local base; base="$(strip_scheme "$raw")"; echo "https://${user}:${pat}@${base}"; }

# -------------------------------------------------------------------
# Clone DevOps repo -> /home/<user>/new-devops-local
# -------------------------------------------------------------------
REPO_DIR="${DEVOPS_DIR}"

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
  "backend $BACKEND_AUTH_URL ${TARGET_HOME}/new-backend $BACKEND_CLEAN_URL" \
  "frontend $FRONTEND_AUTH_URL ${TARGET_HOME}/new-frontend $FRONTEND_CLEAN_URL"
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

# -------------------------------------------------------------------
# Minikube + kubectl context fix (prevents localhost:8080 fallback)
# -------------------------------------------------------------------
log "Minikube bring-up: START_MINIKUBE=${START_MINIKUBE}, DRIVER=${MINIKUBE_DRIVER}, PROFILE=${MINIKUBE_PROFILE}, MEM=${MINIKUBE_MEMORY_MB}MB, CPUS=${MINIKUBE_CPUS}"

sudo -u "${TARGET_USER}" -H bash -lc "mkdir -p ~/.kube ~/.minikube"

if [ "${START_MINIKUBE}" = "1" ]; then
  sudo -u "${TARGET_USER}" -H bash -lc "
    set -euo pipefail
    minikube start --driver='${MINIKUBE_DRIVER}' --profile='${MINIKUBE_PROFILE}' --memory='${MINIKUBE_MEMORY_MB}mb' --cpus='${MINIKUBE_CPUS}'
    kubectl config use-context '${KUBE_CONTEXT}'
    kubectl get nodes
  "
else
  sudo -u "${TARGET_USER}" -H bash -lc "
    set -euo pipefail
    if [ ! -f ~/.kube/config ]; then
      echo '[WARN] ~/.kube/config does not exist. kubectl may fall back to http://localhost:8080 until a context exists.'
    fi
  " || true
fi

# -------------------------------------------------------------------
# Apply ingress controller + ingress rules
# -------------------------------------------------------------------
if [ "${START_MINIKUBE}" = "1" ] && [ "${ENABLE_INGRESS}" = "1" ]; then
  INGRESS_CONTROLLER_PATH="${DEVOPS_DIR}/${INGRESS_CONTROLLER_PATH_REL}"
  INGRESS_RULES_PATH="${DEVOPS_DIR}/${INGRESS_RULES_PATH_REL}"

  log "Applying ingress controller: ${INGRESS_CONTROLLER_PATH}"
  log "Applying ingress rules: ${INGRESS_RULES_PATH}"

  sudo -u "${TARGET_USER}" -H bash -lc "
    set -euo pipefail

    if [ ! -f '${INGRESS_CONTROLLER_PATH}' ]; then
      echo '[ERROR] ingress controller yaml not found: ${INGRESS_CONTROLLER_PATH}' >&2
      exit 1
    fi
    if [ ! -f '${INGRESS_RULES_PATH}' ]; then
      echo '[ERROR] ingress rules yaml not found: ${INGRESS_RULES_PATH}' >&2
      exit 1
    fi

    kubectl apply -f '${INGRESS_CONTROLLER_PATH}'
    kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=240s
    kubectl apply -f '${INGRESS_RULES_PATH}'

    kubectl get pods -n ingress-nginx -o wide || true
    kubectl get svc -n ingress-nginx -o wide || true
    kubectl get ingress -A || true
  "
else
  warn "Skipping ingress apply (START_MINIKUBE=${START_MINIKUBE}, ENABLE_INGRESS=${ENABLE_INGRESS})"
fi

# -------------------------------------------------------------------
# Optional: Deploy your microservices manifests
# -------------------------------------------------------------------
if [ "${START_MINIKUBE}" = "1" ] && [ "${ENABLE_APP_DEPLOY}" = "1" ]; then
  log "Deploying application manifests (ENABLE_APP_DEPLOY=1)"
  for rel in "${APP_MANIFESTS_DIRS_REL[@]}"; do
    abs="${DEVOPS_DIR}/${rel}"
    sudo -u "${TARGET_USER}" -H bash -lc "
      set -euo pipefail
      if [ -d '${abs}' ]; then
        kubectl apply -f '${abs}'
      else
        echo '[WARN] Manifests dir not found (skipping): ${abs}'
      fi
    " || true
  done

  sudo -u "${TARGET_USER}" -H bash -lc "
    set -euo pipefail
    kubectl get pods -A
    kubectl get svc -A
  " || true
fi

# -------------------------------------------------------------------
# Host NGINX: expose the app on :80 by forwarding to ingress NodePort :32080
# Jenkins remains on :8080
# -------------------------------------------------------------------
if [ "${ENABLE_HOST_NGINX}" = "1" ]; then
  log "Configuring host nginx to expose app on :80 -> 127.0.0.1:32080"

  sudo tee /etc/nginx/sites-available/cloudrift >/dev/null <<'EOF'
server {
  listen 80 default_server;
  listen [::]:80 default_server;

  location / {
    proxy_pass http://127.0.0.1:32080;
    proxy_http_version 1.1;

    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
EOF

  sudo rm -f /etc/nginx/sites-enabled/default
  sudo ln -sf /etc/nginx/sites-available/cloudrift /etc/nginx/sites-enabled/cloudrift
  sudo nginx -t
  sudo systemctl enable nginx >/dev/null 2>&1 || true
  sudo systemctl restart nginx
else
  warn "ENABLE_HOST_NGINX=0 -> not exposing app on :80"
fi

# -------------------------------------------------------------------
# Convenience aliases
# -------------------------------------------------------------------
sudo -u "${TARGET_USER}" -H bash -lc '
  if ! grep -q "alias kpo=" ~/.bashrc 2>/dev/null; then
    echo "alias kpo='\''kubectl get pods'\''" >> ~/.bashrc
    echo "alias kpods='\''kubectl get pods'\''" >> ~/.bashrc
    echo "alias kctx='\''kubectl config current-context'\''" >> ~/.bashrc
  fi
' || true

# -------------------------------------------------------------------
# Versions
# -------------------------------------------------------------------
log "Bootstrap tool versions:"
need_cmd kubectl   && kubectl version --client || true
need_cmd minikube  && minikube version || true
need_cmd terraform && terraform version | head -n1 || true
need_cmd docker    && docker --version || true
need_cmd git       && git --version || true
need_cmd python3   && python3 --version || true
need_cmd aws       && aws --version || true
need_cmd nginx     && nginx -v || true

# Helpful final URLs
PUB_IP="$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || true)"
if [ -z "$PUB_IP" ]; then PUB_IP="$(curl -s https://checkip.amazonaws.com || true)"; fi
if [ -z "$PUB_IP" ]; then PUB_IP="$(hostname -I | awk '{print $1}')" || true; fi

if [ -n "$PUB_IP" ]; then
  log "Jenkins: http://${PUB_IP}:8080/"
  log "App (Ingress via host nginx): http://${PUB_IP}/"
else
  warn "Could not determine public IP. Jenkins is on :8080 and app is on :80 on this host."
fi

log "Bootstrap complete."
