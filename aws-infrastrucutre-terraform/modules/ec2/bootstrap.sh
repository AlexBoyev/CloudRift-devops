#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# CloudRift EC2 Bootstrap (long + robust + reboot-safe)
#
# What it does:
#  1) Waits for cloud-init + apt locks
#  2) Installs base tooling: docker, git, awscli v2, kubectl, minikube, terraform, helm, node + smee, nginx, java17, jenkins
#  3) Writes/normalizes /home/ubuntu/.env (CRLF-safe) from TF/userdata exports
#  4) Clones repos: devops, backend, frontend
#  5) Runs devops-setup.sh once (initial deploy)
#  6) Ensures reboot-safe services are enabled (via devops-setup.sh)
#
# Reboot safety:
#  - On reboot, we bring Minikube + ingress + DB infra up
#  - We DO NOT re-apply backend/frontend manifests by default
#    (so Jenkins commit-tag deployments are preserved)
#
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[BOOTSTRAP]${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

export DEBIAN_FRONTEND=noninteractive

TARGET_USER="${SUDO_USER:-${USER:-ubuntu}}"
TARGET_HOME="/home/${TARGET_USER}"
ENV_FILE="${TARGET_HOME}/.env"

# ---- Controls (override via Terraform exports) ----
# Initial install/deploy behavior:
: "${RUN_DEVOPS_SETUP_ONCE:=1}"         # 1 = run devops-setup.sh at end, 0 = only install tools
: "${DEVOPS_SETUP_SKIP_BUILD:=0}"       # 1 = pass skip_build=true to devops-setup.sh
: "${DEVOPS_SETUP_DEPLOY_MONITORING:=true}"
: "${DEVOPS_SETUP_USE_HELM:=false}"
: "${DEVOPS_SETUP_ENV:=dev}"

# Repo target dirs
: "${DEVOPS_DIR:=${TARGET_HOME}/new-devops-local}"
: "${BACKEND_DIR:=${TARGET_HOME}/new-backend}"
: "${FRONTEND_DIR:=${TARGET_HOME}/new-frontend}"

# ---- Expected env vars (from TF or existing .env) ----
# DEVOPS_REPO_URL, BACKEND_REPO_URL, FRONTEND_REPO_URL
# GIT_USERNAME, GIT_PAT
# Optional: SMEE_BACKEND/SMEE_FRONTEND/SMEE_DEVOPS
# Optional: JENKINS_WEBHOOK_TOKEN_* (else defaults)

need_cmd() { command -v "$1" >/dev/null 2>&1; }

# ------------------------------------------------------------
# Wait for cloud-init + apt locks
# ------------------------------------------------------------
wait_cloud_init() {
  log "Waiting for cloud-init to finish (if present)..."
  if need_cmd cloud-init; then
    cloud-init status --wait >/dev/null 2>&1 || true
  fi
  ok "cloud-init done"
}

wait_apt_locks() {
  log "Waiting for apt/dpkg locks..."
  while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 \
     || sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
     || sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    echo "  another apt/dpkg process is running... waiting 5s"
    sleep 5
  done
  ok "apt locks released"
}

# ------------------------------------------------------------
# Ensure env file exists and normalize CRLF
# ------------------------------------------------------------
ensure_env_file() {
  log "Ensuring ${ENV_FILE} exists with safe permissions..."
  sudo -u "${TARGET_USER}" touch "${ENV_FILE}"
  sudo chown "${TARGET_USER}:${TARGET_USER}" "${ENV_FILE}"
  sudo chmod 600 "${ENV_FILE}" || true
  sed -i 's/\r$//' "${ENV_FILE}" || true
  ok ".env ready"
}

# Add or replace KEY=VALUE in .env (no quotes)
ensure_env_kv() {
  local key="$1"
  local val="$2"
  [ -z "${val}" ] && return 0
  if grep -qE "^${key}=" "${ENV_FILE}"; then
    sudo sed -i "s|^${key}=.*|${key}=${val}|" "${ENV_FILE}"
  else
    echo "${key}=${val}" | sudo tee -a "${ENV_FILE}" >/dev/null
  fi
}

get_env_val() {
  grep -E "^$1=" "${ENV_FILE}" | tail -n 1 | cut -d= -f2- | tr -d '[:space:]'
}

load_env_if_present() {
  if [ -f "${ENV_FILE}" ]; then
    sed -i 's/\r$//' "${ENV_FILE}" || true
    # shellcheck source=/dev/null
    . "${ENV_FILE}" || true
  fi
}

# ------------------------------------------------------------
# Package install helpers
# ------------------------------------------------------------
apt_update() {
  log "apt-get update..."
  sudo apt-get update -y
  ok "apt updated"
}

apt_install_base() {
  log "Installing base packages..."
  sudo apt-get install -y \
    ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common \
    unzip git jq nginx openssl \
    python3 python3-pip \
    net-tools conntrack socat \
    docker.io \
    openjdk-17-jdk
  ok "base packages installed"
}

ensure_docker() {
  log "Enabling/starting docker..."
  sudo systemctl enable docker >/dev/null 2>&1 || true
  sudo systemctl start docker  >/dev/null 2>&1 || true

  if ! id -nG "${TARGET_USER}" | grep -q '\bdocker\b'; then
    sudo usermod -aG docker "${TARGET_USER}"
    warn "Added ${TARGET_USER} to docker group (effective next login)."
  fi

  sudo chown root:docker /var/run/docker.sock || true
  sudo chmod 660 /var/run/docker.sock || true
  ok "docker ready"
}

install_node_and_smee() {
  log "Installing Node.js + smee-client..."
  if ! need_cmd node; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
  else
    warn "Node already installed"
  fi

  if ! need_cmd smee; then
    sudo npm install -g smee-client
  else
    warn "smee-client already installed"
  fi
  ok "node + smee ready"
}

install_awscli_v2() {
  if need_cmd aws; then
    warn "AWS CLI already installed"
    return 0
  fi
  log "Installing AWS CLI v2..."
  local arch
  arch="$(uname -m)"
  local AWS_ARCH="x86_64"
  if [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ]; then AWS_ARCH="aarch64"; fi

  curl -L "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  sudo /tmp/aws/install
  rm -rf /tmp/aws /tmp/awscliv2.zip
  ok "awscli installed"
}

install_kubectl() {
  if need_cmd kubectl; then
    warn "kubectl already installed"
    return 0
  fi
  log "Installing kubectl..."
  local arch="amd64"
  case "$(uname -m)" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
  esac

  local kver
  kver="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
  curl -L "https://dl.k8s.io/release/${kver}/bin/linux/${arch}/kubectl" -o /tmp/kubectl
  sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
  rm -f /tmp/kubectl
  ok "kubectl installed"
}

install_minikube() {
  if need_cmd minikube; then
    warn "minikube already installed"
    return 0
  fi
  log "Installing minikube..."
  local arch="amd64"
  case "$(uname -m)" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
  esac

  curl -L "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${arch}" -o /tmp/minikube
  sudo install -m 0755 /tmp/minikube /usr/local/bin/minikube
  rm -f /tmp/minikube
  ok "minikube installed"
}

install_terraform() {
  if need_cmd terraform; then
    warn "terraform already installed"
    return 0
  fi
  log "Installing terraform..."
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y terraform
  ok "terraform installed"
}

install_helm() {
  if need_cmd helm; then
    warn "helm already installed"
    return 0
  fi
  log "Installing helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null 2>&1
  ok "helm installed"
}

install_jenkins() {
  if systemctl list-unit-files | grep -q '^jenkins\.service'; then
    warn "jenkins service already present"
  else
    log "Installing Jenkins..."
    curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key \
      | sudo tee /usr/share/keyrings/jenkins-keyring.asc >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
      | sudo tee /etc/apt/sources.list.d/jenkins.list >/dev/null
    sudo apt-get update -y
    sudo apt-get install -y jenkins
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

  # known_hosts for jenkins user (github)
  log "Ensuring Jenkins known_hosts includes github.com..."
  sudo -u jenkins sh -c 'mkdir -p /var/lib/jenkins/.ssh && touch /var/lib/jenkins/.ssh/known_hosts && chmod 600 /var/lib/jenkins/.ssh/known_hosts'
  if ! sudo -u jenkins sh -c "grep -q 'github.com' /var/lib/jenkins/.ssh/known_hosts"; then
    ssh-keyscan -t rsa,ecdsa,ed25519 github.com 2>/dev/null | sudo -u jenkins tee -a /var/lib/jenkins/.ssh/known_hosts >/dev/null || true
  fi
  sudo chown -R jenkins:jenkins /var/lib/jenkins/.ssh

  ok "jenkins ready"
}

# ------------------------------------------------------------
# Smee services (optional, reads from .env)
# ------------------------------------------------------------
create_smee_service() {
  local svc_name="$1"
  local src_var="$2"
  local tgt_var="$3"
  local unit="/etc/systemd/system/${svc_name}.service"

  local src_val
  src_val="$(get_env_val "${src_var}")"
  if [ -z "${src_val}" ]; then
    warn "Skipping ${svc_name}: ${src_var} missing/empty in ${ENV_FILE}"
    return 0
  fi

  log "Creating ${svc_name}.service..."
  cat <<EOF | sudo tee "${unit}" >/dev/null
[Unit]
Description=CloudRift Smee relay (${svc_name} -> Jenkins)
After=network.target jenkins.service
StartLimitIntervalSec=0

[Service]
Type=simple
User=${TARGET_USER}
EnvironmentFile=${ENV_FILE}
ExecStart=/bin/bash -lc 'exec /usr/bin/smee -u "\$$src_var" --target "\$$tgt_var"'
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable --now "${svc_name}" >/dev/null 2>&1 || true
  sudo systemctl restart "${svc_name}" >/dev/null 2>&1 || true
  ok "${svc_name} enabled"
}

ensure_smee_env_defaults() {
  log "Ensuring smee token defaults..."
  if ! grep -q '^JENKINS_WEBHOOK_TOKEN_BACKEND=' "${ENV_FILE}"; then
    echo 'JENKINS_WEBHOOK_TOKEN_BACKEND=cloudrift-backend' | sudo tee -a "${ENV_FILE}" >/dev/null
  fi
  if ! grep -q '^JENKINS_WEBHOOK_TOKEN_FRONTEND=' "${ENV_FILE}"; then
    echo 'JENKINS_WEBHOOK_TOKEN_FRONTEND=cloudrift-frontend' | sudo tee -a "${ENV_FILE}" >/dev/null
  fi
  if ! grep -q '^JENKINS_WEBHOOK_TOKEN_DEVOPS=' "${ENV_FILE}"; then
    echo 'JENKINS_WEBHOOK_TOKEN_DEVOPS=cloudrift-devops' | sudo tee -a "${ENV_FILE}" >/dev/null
  fi

  local tb tf td
  tb="$(get_env_val JENKINS_WEBHOOK_TOKEN_BACKEND)";  [ -z "$tb" ] && tb="cloudrift-backend"
  tf="$(get_env_val JENKINS_WEBHOOK_TOKEN_FRONTEND)"; [ -z "$tf" ] && tf="cloudrift-frontend"
  td="$(get_env_val JENKINS_WEBHOOK_TOKEN_DEVOPS)";    [ -z "$td" ] && td="cloudrift-devops"

  local idb idf idd
  idb="$(get_env_val SMEE_BACKEND)"
  idf="$(get_env_val SMEE_FRONTEND)"
  idd="$(get_env_val SMEE_DEVOPS)"

  [ -n "$idb" ] && ensure_env_kv "SMEE_SOURCE_BACKEND"  "https://smee.io/${idb}"
  [ -n "$idf" ] && ensure_env_kv "SMEE_SOURCE_FRONTEND" "https://smee.io/${idf}"
  [ -n "$idd" ] && ensure_env_kv "SMEE_SOURCE_DEVOPS"   "https://smee.io/${idd}"

  ensure_env_kv "SMEE_TARGET_BACKEND"  "http://127.0.0.1:8080/generic-webhook-trigger/invoke?token=${tb}"
  ensure_env_kv "SMEE_TARGET_FRONTEND" "http://127.0.0.1:8080/generic-webhook-trigger/invoke?token=${tf}"
  ensure_env_kv "SMEE_TARGET_DEVOPS"   "http://127.0.0.1:8080/generic-webhook-trigger/invoke?token=${td}"

  # legacy backend vars (kept)
  if ! grep -q '^SMEE_SOURCE=' "${ENV_FILE}" && [ -n "$idb" ]; then
    echo "SMEE_SOURCE=https://smee.io/${idb}" | sudo tee -a "${ENV_FILE}" >/dev/null
  fi
  if ! grep -q '^SMEE_URL=' "${ENV_FILE}" && [ -n "$idb" ]; then
    echo "SMEE_URL=https://smee.io/${idb}" | sudo tee -a "${ENV_FILE}" >/dev/null
  fi
  if grep -q '^SMEE_TARGET=' "${ENV_FILE}"; then
    sudo sed -i "s|^SMEE_TARGET=.*|SMEE_TARGET=http://127.0.0.1:8080/generic-webhook-trigger/invoke?token=${tb}|" "${ENV_FILE}"
  else
    echo "SMEE_TARGET=http://127.0.0.1:8080/generic-webhook-trigger/invoke?token=${tb}" | sudo tee -a "${ENV_FILE}" >/dev/null
  fi

  ok "smee env prepared"
}

enable_smee_services() {
  ensure_smee_env_defaults
  create_smee_service "smee-jenkins-backend"  "SMEE_SOURCE_BACKEND"  "SMEE_TARGET_BACKEND"
  create_smee_service "smee-jenkins-frontend" "SMEE_SOURCE_FRONTEND" "SMEE_TARGET_FRONTEND"
  create_smee_service "smee-jenkins-devops"   "SMEE_SOURCE_DEVOPS"   "SMEE_TARGET_DEVOPS"

  # legacy service (kept)
  log "Creating legacy smee-jenkins.service..."
  cat <<EOF | sudo tee /etc/systemd/system/smee-jenkins.service >/dev/null
[Unit]
Description=CloudRift Smee relay (legacy backend -> local Jenkins)
After=network.target jenkins.service
StartLimitIntervalSec=0

[Service]
Type=simple
User=${TARGET_USER}
EnvironmentFile=${ENV_FILE}
ExecStart=/bin/bash -lc 'exec /usr/bin/smee -u "\$SMEE_SOURCE" --target "\$SMEE_TARGET"'
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now smee-jenkins >/dev/null 2>&1 || true
  sudo systemctl restart smee-jenkins >/dev/null 2>&1 || true
  ok "smee services enabled"
}

# ------------------------------------------------------------
# Git clone helpers (PAT safe)
# ------------------------------------------------------------
normalize_url() {
  local input="$1"
  if echo "$input" | grep -qiE '^git@github.com:'; then
    input="$(echo "$input" | sed -E 's|^git@github.com:|https://github.com/|')"
  elif echo "$input" | grep -qiE '^ssh://git@github.com/'; then
    input="$(echo "$input" | sed -E 's|^ssh://git@github.com/|https://github.com/|')"
  elif ! echo "$input" | grep -qiE '^https?://'; then
    input="https://$input"
  fi
  echo "$input"
}

repo_auth_url() {
  local repo_url="$1"
  local clean
  clean="$(normalize_url "$repo_url")"
  local user pat
  user="$(get_env_val GIT_USERNAME)"
  pat="$(get_env_val GIT_PAT)"
  if [ -z "$user" ]; then user="git"; fi
  if [ -n "$pat" ]; then
    echo "https://${user}:${pat}@${clean#https://}"
  else
    echo "$clean"
  fi
}

ensure_repo() {
  local repo_url="$1"
  local target_dir="$2"
  local display="$3"

  local clean auth
  clean="$(normalize_url "$repo_url")"
  auth="$(repo_auth_url "$repo_url")"

  if [ ! -d "${target_dir}/.git" ]; then
    log "Cloning ${display} -> ${target_dir}"
    sudo rm -rf "${target_dir}"
    sudo -u "${TARGET_USER}" mkdir -p "$(dirname "${target_dir}")"
    if ! sudo -u "${TARGET_USER}" GIT_TERMINAL_PROMPT=0 git clone "${auth}" "${target_dir}"; then
      err "Clone failed: ${display}"
      exit 1
    fi
  else
    log "Updating ${display} in ${target_dir}"
    sudo -u "${TARGET_USER}" git -C "${target_dir}" remote set-url origin "${auth}" >/dev/null 2>&1 || true
    sudo -u "${TARGET_USER}" GIT_TERMINAL_PROMPT=0 git -C "${target_dir}" fetch --all --tags >/dev/null 2>&1 || true
    sudo -u "${TARGET_USER}" git -C "${target_dir}" reset --hard origin/main >/dev/null 2>&1 || true
    sudo -u "${TARGET_USER}" git -C "${target_dir}" clean -fd >/dev/null 2>&1 || true
  fi

  # scrub token
  sudo -u "${TARGET_USER}" git -C "${target_dir}" remote set-url origin "${clean}" >/dev/null 2>&1 || true
  sudo chown -R "${TARGET_USER}:${TARGET_USER}" "${target_dir}" >/dev/null 2>&1 || true
  ok "${display} repo ready"
}

# ------------------------------------------------------------
# Run devops-setup.sh once
# ------------------------------------------------------------
run_devops_setup() {
  local script_path="${DEVOPS_DIR}/devops-setup.sh"
  if [ ! -f "${script_path}" ]; then
    err "Missing devops-setup.sh at ${script_path}"
    exit 1
  fi
  sudo chmod +x "${script_path}" || true

  log "Running devops-setup.sh (initial deployment)..."

  local skip_build="false"
  if [ "${DEVOPS_SETUP_SKIP_BUILD}" = "1" ]; then skip_build="true"; fi

  sudo -u "${TARGET_USER}" -H bash -lc "
    set -euo pipefail
    export KUBECONFIG=/home/${TARGET_USER}/.kube/config
    cd '${DEVOPS_DIR}'
    sed -i 's/\r$//' devops-setup.sh || true
    ./devops-setup.sh '${DEVOPS_SETUP_ENV}' '${DEVOPS_SETUP_DEPLOY_MONITORING}' '${DEVOPS_SETUP_USE_HELM}' '${skip_build}'
  "

  ok "devops-setup.sh completed"
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
main() {
  wait_cloud_init
  wait_apt_locks

  apt_update
  apt_install_base
  ensure_docker

  ensure_env_file

  # Persist TF/userdata-exported vars into .env (if present in environment)
  # (This is what makes the machine self-contained after reboot)
  ensure_env_kv "DEVOPS_REPO_URL"    "${DEVOPS_REPO_URL:-${TF_VAR_devops_repo_url:-}}"
  ensure_env_kv "BACKEND_REPO_URL"   "${BACKEND_REPO_URL:-${TF_VAR_backend_repo_url:-}}"
  ensure_env_kv "FRONTEND_REPO_URL"  "${FRONTEND_REPO_URL:-${TF_VAR_frontend_repo_url:-}}"
  ensure_env_kv "GIT_USERNAME"       "${GIT_USERNAME:-${TF_VAR_git_username:-}}"
  ensure_env_kv "GIT_PAT"            "${GIT_PAT:-${TF_VAR_git_pat:-}}"

  ensure_env_kv "SMEE_BACKEND"       "${SMEE_BACKEND:-}"
  ensure_env_kv "SMEE_FRONTEND"      "${SMEE_FRONTEND:-}"
  ensure_env_kv "SMEE_DEVOPS"        "${SMEE_DEVOPS:-}"

  # Reload env after writing
  load_env_if_present

  # Install tooling
  install_node_and_smee
  install_awscli_v2
  install_kubectl
  install_minikube
  install_terraform
  install_helm
  install_jenkins

  # Smee services (optional, only if you set SMEE_* ids)
  enable_smee_services || true

  # Make kube dirs stable
  sudo -u "${TARGET_USER}" mkdir -p "${TARGET_HOME}/.kube" "${TARGET_HOME}/.minikube"
  sudo chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.kube" "${TARGET_HOME}/.minikube"

  # Ensure durable postgres dir
  sudo mkdir -p /opt/cloudrift/postgres-data || true
  sudo chmod 777 /opt/cloudrift/postgres-data || true
  ok "durable postgres dir ready"

  # Validate required vars exist now
  local d b f
  d="$(get_env_val DEVOPS_REPO_URL)"
  b="$(get_env_val BACKEND_REPO_URL)"
  f="$(get_env_val FRONTEND_REPO_URL)"
  if [ -z "$d" ] || [ -z "$b" ] || [ -z "$f" ]; then
    err "Missing repo URLs in ${ENV_FILE}. Need DEVOPS_REPO_URL, BACKEND_REPO_URL, FRONTEND_REPO_URL"
    exit 1
  fi

  # Clone repos
  ensure_repo "$d" "${DEVOPS_DIR}"   "devops"
  ensure_repo "$b" "${BACKEND_DIR}"  "backend"
  ensure_repo "$f" "${FRONTEND_DIR}" "frontend"

  # Run initial deployment (optional)
  if [ "${RUN_DEVOPS_SETUP_ONCE}" = "1" ]; then
    run_devops_setup
  else
    warn "RUN_DEVOPS_SETUP_ONCE=0 -> skipping initial deploy"
  fi

  # Print final URLs
  local ip
  ip="$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || true)"
  [ -z "$ip" ] && ip="$(curl -s https://checkip.amazonaws.com || true)"
  [ -z "$ip" ] && ip="$(hostname -I | awk '{print $1}' || true)"

  echo ""
  echo "=============================================================="
  echo "BOOTSTRAP COMPLETE"
  echo "=============================================================="
  if [ -n "$ip" ]; then
    echo "App:     http://${ip}/"
    echo "API:     http://${ip}/api/"
    echo "Jenkins: http://${ip}:8080/ (tunnel optional if SG closed)"
  else
    echo "Could not detect public IP. App is on :80, Jenkins on :8080."
  fi
  echo "=============================================================="
}

main "$@"
