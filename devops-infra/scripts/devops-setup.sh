#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# CloudRift DevOps Setup Script (EC2-safe, reboot-safe, Jenkins-friendly)
#
# - One-click initial deploy: clone repos, build images, apply manifests
# - Creates ONE reboot script: /usr/local/bin/start-cloudrift.sh
# - Reboot default is INFRA-ONLY (keeps Jenkins commit-tag deployments)
#
# Usage:
#   ./devops-setup.sh [env=dev] [deploy_monitoring=true|false] [use_helm=false|true] [skip_build=false|true]
# ============================================================

# -----------------------------
# Output helpers
# -----------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()          { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()           { echo -e "${GREEN}✓${NC} $1"; }
warn()         { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail()         { echo -e "${RED}[ERROR]${NC} $1"; }

header()       { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

# -----------------------------
# Inputs / defaults
# -----------------------------
ENVIRONMENT="${1:-dev}"
DEPLOY_MONITORING="${2:-true}"
USE_HELM="${3:-false}"
SKIP_BUILD="${4:-false}"

# image tags (initial deploy only)
: "${BACKEND_TAG:=backend-$(date +%Y%m%d%H%M%S)}"
: "${FRONTEND_TAG:=frontend-$(date +%Y%m%d%H%M%S)}"
: "${DB_TAG:=db-$(date +%Y%m%d%H%M%S)}"

: "${SKIP_BACKEND_BUILD:=false}"
: "${SKIP_FRONTEND_BUILD:=false}"
: "${SKIP_DB_BUILD:=false}"

# -----------------------------
# Detect EC2
# -----------------------------
EC2_ENV=false
EC2_USER="${USER:-ubuntu}"

if [ -d /home/ubuntu ]; then
  EC2_ENV=true
  EC2_USER="ubuntu"
  ok "Detected EC2 environment (user=${EC2_USER})"
fi

# Ensure kubectl uses ubuntu kubeconfig even if invoked via sudo
if [ "${EC2_ENV}" = true ]; then
  export KUBECONFIG="${KUBECONFIG:-/home/ubuntu/.kube/config}"
fi

# -----------------------------
# Load .env from /home/<user>/.env
# -----------------------------
ENV_FILE="/home/${EC2_USER}/.env"
if [ -f "${ENV_FILE}" ]; then
  log "Loading environment variables from ${ENV_FILE} ..."
  sed -i 's/\r$//' "${ENV_FILE}" || true
  # shellcheck disable=SC2046
  export $(grep -v '^#' "${ENV_FILE}" | xargs) || true
fi

# Required vars
: "${DEVOPS_REPO_URL:?DEVOPS_REPO_URL must be provided in /home/${EC2_USER}/.env}"
: "${BACKEND_REPO_URL:?BACKEND_REPO_URL must be provided in /home/${EC2_USER}/.env}"
: "${FRONTEND_REPO_URL:?FRONTEND_REPO_URL must be provided in /home/${EC2_USER}/.env}"

# Git creds (optional if repos public)
GITHUB_USER="${GITHUB_USER:-${GIT_USERNAME:-${GIT_USER:-}}}"
GITHUB_PAT="${GITHUB_PAT:-${GIT_PAT:-${GIT_TOKEN:-}}}"

export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=true

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}          CloudRift DevOps Setup        ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Environment:        ${ENVIRONMENT}"
echo "Deploy Monitoring:  ${DEPLOY_MONITORING}"
echo "Use Helm:           ${USE_HELM}"
echo "Skip Docker Build:  ${SKIP_BUILD}"
echo ""
echo "Repo URLs:"
echo "  DEVOPS_REPO_URL:   ${DEVOPS_REPO_URL}"
echo "  BACKEND_REPO_URL:  ${BACKEND_REPO_URL}"
echo "  FRONTEND_REPO_URL: ${FRONTEND_REPO_URL}"
echo ""

# -----------------------------
# Prereqs
# -----------------------------
header "Step 1: Checking prerequisites"

for cmd in docker kubectl minikube git; do
  if ! command_exists "$cmd"; then
    fail "Missing required command: $cmd"
    exit 1
  fi
done
ok "Core tools present (docker/kubectl/minikube/git)"

if [ "$DEPLOY_MONITORING" = "true" ] && ! command_exists helm; then
  warn "Helm not found and monitoring requested. Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null 2>&1 || {
    fail "Helm install failed"
    exit 1
  }
  ok "Helm installed"
fi

# -----------------------------
# Safe cleanup (no volumes)
# -----------------------------
header "Step 2: Safe cleanup (no volume prune)"

sudo systemctl start docker >/dev/null 2>&1 || true
sudo apt-get clean -y >/dev/null 2>&1 || true
sudo apt-get autoremove -y >/dev/null 2>&1 || true
sudo docker system prune -af >/dev/null 2>&1 || true
ok "Cleanup done (volumes preserved)"

if [ "${EC2_ENV}" = true ]; then
  log "Ensuring durable Postgres dir exists: /opt/cloudrift/postgres-data"
  sudo mkdir -p /opt/cloudrift/postgres-data || true
  sudo chmod 777 /opt/cloudrift/postgres-data || true
  ok "Durable Postgres directory ready"
fi

# -----------------------------
# Start / verify Minikube
# -----------------------------
header "Step 3: Minikube"

if [ "${EC2_ENV}" = true ]; then
  sudo mkdir -p "/home/${EC2_USER}/.minikube" "/home/${EC2_USER}/.kube"
  sudo chown -R "${EC2_USER}:${EC2_USER}" "/home/${EC2_USER}/.minikube" "/home/${EC2_USER}/.kube"

  if sudo -u "$EC2_USER" minikube status >/dev/null 2>&1; then
    ok "Minikube already running"
  else
    ok "Starting Minikube..."
    sudo -u "$EC2_USER" minikube start --driver=docker --memory=4096mb --cpus=2
    ok "Minikube started"
    ok "Enabling ingress addon..."
    sudo -u "$EC2_USER" minikube addons enable ingress >/dev/null 2>&1 || true
  fi

  sudo -u "$EC2_USER" kubectl config use-context minikube >/dev/null 2>&1 || true
else
  if minikube status >/dev/null 2>&1; then
    ok "Minikube already running"
  else
    ok "Starting Minikube..."
    minikube start --driver=docker --memory=4096mb --cpus=2
    ok "Minikube started"
  fi
  kubectl config use-context minikube >/dev/null 2>&1 || true
fi

kubectl cluster-info >/dev/null 2>&1 || { fail "Cannot reach cluster"; exit 1; }
ok "Cluster reachable"

# -----------------------------
# Repo helpers
# -----------------------------
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
  if [ -n "${GITHUB_PAT:-}" ]; then
    local user="${GITHUB_USER:-git}"
    echo "https://${user}:${GITHUB_PAT}@${clean#https://}"
  else
    echo "$clean"
  fi
}

ensure_repo() {
  local repo_url="$1"
  local target_dir="$2"
  local display_name="$3"

  local clean_url auth_url
  clean_url="$(normalize_url "$repo_url")"
  auth_url="$(repo_auth_url "$repo_url")"

  if [ ! -d "$target_dir/.git" ]; then
    log "Cloning ${display_name} into ${target_dir} ..."
    sudo -u "${EC2_USER}" mkdir -p "$(dirname "$target_dir")"
    git clone "$auth_url" "$target_dir" >/dev/null 2>&1 || {
      fail "Clone failed for ${display_name}"
      return 1
    }
    ok "${display_name} cloned"
  else
    log "Updating ${display_name} in ${target_dir} ..."
    git -C "$target_dir" remote set-url origin "$auth_url" >/dev/null 2>&1 || true
    git -C "$target_dir" fetch --all --tags >/dev/null 2>&1 || true
    git -C "$target_dir" reset --hard origin/main >/dev/null 2>&1 || true
    git -C "$target_dir" clean -fd >/dev/null 2>&1 || true
    ok "${display_name} updated"
  fi

  # remove token from origin after syncing
  git -C "$target_dir" remote set-url origin "$clean_url" >/dev/null 2>&1 || true

  if [ "${EC2_ENV}" = true ]; then
    sudo chown -R "${EC2_USER}:${EC2_USER}" "$target_dir" >/dev/null 2>&1 || true
    sudo chmod -R u+rwX "$target_dir" >/dev/null 2>&1 || true
  fi

  return 0
}

# -----------------------------
# Clone/update repos
# -----------------------------
header "Step 4: Sync repositories"

DEVOPS_DIR="/home/${EC2_USER}/new-devops-local"
BACKEND_DIR="/home/${EC2_USER}/new-backend"
FRONTEND_DIR="/home/${EC2_USER}/new-frontend"

ensure_repo "$DEVOPS_REPO_URL"   "$DEVOPS_DIR"   "devops"   || exit 1
ensure_repo "$BACKEND_REPO_URL"  "$BACKEND_DIR"  "backend"  || exit 1
ensure_repo "$FRONTEND_REPO_URL" "$FRONTEND_DIR" "frontend" || exit 1

K8S_ROOT="${DEVOPS_DIR}/devops-infra/kubernetes"
[ -d "$K8S_ROOT" ] || { fail "Missing k8s root: $K8S_ROOT"; exit 1; }
ok "Repos ready"

# -----------------------------
# Patch YAMLs (minikube-friendly) - IMPORTANT:
# These are safe, but your manifests should ideally avoid sed patching.
# We keep your behavior because you asked for the same steps.
# -----------------------------
header "Step 5: Patch YAML templates for local/minikube usage"

find "$K8S_ROOT" -name "*.yaml" -type f -exec sed -i 's/imagePullPolicy: Always/imagePullPolicy: IfNotPresent/g' {} + || true
find "$K8S_ROOT" -name "*.yaml" -type f -exec sed -i 's/\$(BACKEND_TAG)/latest/g' {} + || true
find "$K8S_ROOT" -name "*.yaml" -type f -exec sed -i 's/\$(FRONTEND_TAG)/latest/g' {} + || true
find "$K8S_ROOT" -name "*.yaml" -type f -exec sed -i 's/\$(DB_TAG)/latest/g' {} + || true

if [ -f "$K8S_ROOT/data-structures/linkedlist.yaml" ]; then
  sed -i 's/memory: 128Mi/memory: 512Mi/g' "$K8S_ROOT/data-structures/linkedlist.yaml" || true
fi

ok "YAML patching complete"

# -----------------------------
# Build Docker images into Minikube (initial deploy)
# -----------------------------
if [ "$SKIP_BUILD" = "false" ]; then
  header "Step 6: Build Docker images into Minikube (initial deploy)"

  if [ "${EC2_ENV}" = true ]; then
    eval "$(sudo -u "$EC2_USER" minikube docker-env)"
    DOCKER_CMD="sudo -E docker"
  else
    eval "$(minikube docker-env)"
    DOCKER_CMD="docker"
  fi

  build_image() {
    local dockerfile="$1"
    local context="$2"
    local image="$3"
    local name="$4"

    log "Building $name -> $image (dockerfile=$dockerfile, context=$context)"
    if [ ! -f "${context}/${dockerfile}" ]; then
      fail "Missing Dockerfile: ${context}/${dockerfile}"
      return 1
    fi
    $DOCKER_CMD build -f "${context}/${dockerfile}" -t "$image" "$context" >/tmp/cloudrift-build.log 2>&1 || {
      fail "Build failed: $name (see /tmp/cloudrift-build.log)"
      return 1
    }
    return 0
  }

  if [ "$SKIP_BACKEND_BUILD" != "true" ]; then
    build_image "Dockerfile"            "${BACKEND_DIR}/backend" "backend-service:${BACKEND_TAG}"      "Backend Service"
    $DOCKER_CMD tag "backend-service:${BACKEND_TAG}" "backend-service:latest" >/dev/null 2>&1 || true

    build_image "stack/Dockerfile"      "${BACKEND_DIR}"         "stack-service:${BACKEND_TAG}"        "Stack Service"
    $DOCKER_CMD tag "stack-service:${BACKEND_TAG}" "stack-service:latest" >/dev/null 2>&1 || true

    build_image "linkedlist/Dockerfile" "${BACKEND_DIR}"         "linkedlist-service:${BACKEND_TAG}"   "LinkedList Service"
    $DOCKER_CMD tag "linkedlist-service:${BACKEND_TAG}" "linkedlist-service:latest" >/dev/null 2>&1 || true

    build_image "graph/Dockerfile"      "${BACKEND_DIR}"         "graph-service:${BACKEND_TAG}"        "Graph Service"
    $DOCKER_CMD tag "graph-service:${BACKEND_TAG}" "graph-service:latest" >/dev/null 2>&1 || true
  fi

  if [ "$SKIP_FRONTEND_BUILD" != "true" ]; then
    build_image "Dockerfile" "${FRONTEND_DIR}" "ui-service:${FRONTEND_TAG}" "Frontend UI"
    $DOCKER_CMD tag "ui-service:${FRONTEND_TAG}" "ui-service:latest" >/dev/null 2>&1 || true
  fi

  if [ "$SKIP_DB_BUILD" != "true" ] && [ -f "${BACKEND_DIR}/database/Dockerfile" ]; then
    build_image "database/Dockerfile" "${BACKEND_DIR}" "postgres-db:${DB_TAG}" "Postgres DB"
    $DOCKER_CMD tag "postgres-db:${DB_TAG}" "postgres-db:latest" >/dev/null 2>&1 || true
  fi

  ok "Build completed (initial deploy images tagged :latest for manifests)"
else
  ok "Skipping builds (SKIP_BUILD=true)"
fi

# -----------------------------
# Apply Kubernetes manifests (initial deploy)
# -----------------------------
header "Step 7: Apply Kubernetes manifests (initial deploy)"

[ -d "$K8S_ROOT/namespaces" ] && kubectl apply -f "$K8S_ROOT/namespaces" >/dev/null 2>&1 || true

[ -d "$K8S_ROOT/database" ] || { fail "Missing: $K8S_ROOT/database"; exit 1; }
kubectl apply -f "$K8S_ROOT/database/pvc.yaml"         >/dev/null 2>&1 || true
kubectl apply -f "$K8S_ROOT/database/secret.yaml"      >/dev/null 2>&1 || true
kubectl apply -f "$K8S_ROOT/database/service.yaml"     >/dev/null 2>&1 || true
kubectl apply -f "$K8S_ROOT/database/statefulset.yaml" >/dev/null 2>&1 || true
kubectl rollout status statefulset/postgres-db --timeout=240s || warn "DB rollout timeout"
ok "Database applied"

[ -d "$K8S_ROOT/data-structures" ] && kubectl apply -f "$K8S_ROOT/data-structures" >/dev/null 2>&1 || true
[ -d "$K8S_ROOT/backend" ] && kubectl apply -f "$K8S_ROOT/backend" >/dev/null 2>&1 || true
[ -d "$K8S_ROOT/frontend" ] && kubectl apply -f "$K8S_ROOT/frontend" >/dev/null 2>&1 || true
[ -d "$K8S_ROOT/ingress" ] && kubectl apply -f "$K8S_ROOT/ingress" >/dev/null 2>&1 || true

if [ "$DEPLOY_MONITORING" = "true" ]; then
  header "Step 7b: Monitoring"
  if [ -d "$K8S_ROOT/monitoring/prometheus" ] && [ -d "$K8S_ROOT/monitoring/grafana" ]; then
    kubectl apply -f "$K8S_ROOT/monitoring/prometheus" >/dev/null 2>&1 || true
    kubectl apply -f "$K8S_ROOT/monitoring/grafana" >/dev/null 2>&1 || true
    ok "Monitoring applied (YAML)"
  elif [ "$USE_HELM" = "true" ]; then
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
    helm repo update >/dev/null 2>&1 || true
    helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
      --create-namespace --namespace monitoring --set grafana.service.type=ClusterIP \
      --wait --timeout=5m >/dev/null 2>&1 || true
    ok "Monitoring applied (Helm)"
  else
    warn "Monitoring YAML not found and USE_HELM=false; skipping monitoring"
  fi
fi

ok "Initial deploy completed"

# -----------------------------
# Reboot-safe configuration (ONE script)
# -----------------------------
header "Step 8: EC2 Auto-start (reboot-safe, Jenkins-friendly)"

if [ "${EC2_ENV}" = true ]; then
  # Boot behavior controls
  sudo tee /etc/default/cloudrift >/dev/null <<EOF
# CloudRift boot configuration
PROFILE=minikube
DRIVER=docker

# Repos
DEVOPS_DIR=/home/ubuntu/new-devops-local

# K8s path inside devops repo
K8S_PATH=/home/ubuntu/new-devops-local/devops-infra/kubernetes
KUBECONFIG_PATH=/home/ubuntu/.kube/config

# 0 = infra-only on boot (recommended, keeps Jenkins versions)
# 1 = also apply app manifests on boot (WILL overwrite if manifests are :latest)
APPLY_APP_MANIFESTS=0

# Apply apps if deployments are missing (fresh cluster bootstrap)
APPLY_APPS_IF_MISSING=1
EOF
  ok "Wrote /etc/default/cloudrift (infra-only default)"

  # ONE boot script on the instance
  sudo tee /usr/local/bin/start-cloudrift.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

CFG="/etc/default/cloudrift"
[ -f "$CFG" ] && source "$CFG"

: "${PROFILE:=minikube}"
: "${DRIVER:=docker}"
: "${DEVOPS_DIR:=/home/ubuntu/new-devops-local}"
: "${K8S_PATH:=/home/ubuntu/new-devops-local/devops-infra/kubernetes}"
: "${KUBECONFIG_PATH:=/home/ubuntu/.kube/config}"
: "${APPLY_APP_MANIFESTS:=0}"
: "${APPLY_APPS_IF_MISSING:=1}"

LOG_FILE="/var/log/cloudrift-startup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "--- CloudRift Boot: $(date -u +%Y-%m-%dT%H:%M:%SZ) ---"

run_u() { sudo -u ubuntu -H bash -lc "$*"; }

# Load /home/ubuntu/.env (for DEVOPS_REPO_URL + git creds)
ENV_FILE="/home/ubuntu/.env"
if [ -f "$ENV_FILE" ]; then
  sed -i 's/\r$//' "$ENV_FILE" || true
  # shellcheck disable=SC2046
  export $(grep -v '^#' "$ENV_FILE" | xargs) || true
fi

sudo systemctl start docker >/dev/null 2>&1 || true
sudo mkdir -p /home/ubuntu/.kube /home/ubuntu/.minikube
sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube /home/ubuntu/.minikube

sudo mkdir -p /opt/cloudrift/postgres-data || true
sudo chmod 777 /opt/cloudrift/postgres-data || true

# Pull latest devops repo on each boot (so changes take effect after restart)
if [ -n "${DEVOPS_REPO_URL:-}" ] && [ -d "${DEVOPS_DIR}/.git" ]; then
  echo "[BOOT] Updating devops repo..."
  clean_url="$DEVOPS_REPO_URL"
  # normalize ssh -> https if needed
  if echo "$clean_url" | grep -qiE '^git@github.com:'; then
    clean_url="$(echo "$clean_url" | sed -E 's|^git@github.com:|https://github.com/|')"
  fi

  auth_url="$clean_url"
  if [ -n "${GIT_PAT:-${GITHUB_PAT:-}}" ]; then
    user="${GIT_USERNAME:-${GITHUB_USER:-git}}"
    pat="${GIT_PAT:-${GITHUB_PAT}}"
    auth_url="https://${user}:${pat}@${clean_url#https://}"
  fi

  run_u "cd '${DEVOPS_DIR}' && git remote set-url origin '${auth_url}' && git fetch origin main && git reset --hard origin/main && git clean -fd"
  # scrub token
  run_u "cd '${DEVOPS_DIR}' && git remote set-url origin '${clean_url}'"
fi

# Start minikube if needed
run_u "minikube status --profile='${PROFILE}' >/dev/null 2>&1 || minikube start --profile='${PROFILE}' --driver='${DRIVER}' --memory=4096mb --cpus=2"

# Ensure context
run_u "export KUBECONFIG='${KUBECONFIG_PATH}'; kubectl config use-context '${PROFILE}' >/dev/null 2>&1 || true"

# Always apply INFRA (safe)
run_u "export KUBECONFIG='${KUBECONFIG_PATH}'; \
  kubectl apply -f '${K8S_PATH}/database/pvc.yaml' || true; \
  kubectl apply -f '${K8S_PATH}/database/secret.yaml' || true; \
  kubectl apply -f '${K8S_PATH}/database/service.yaml' || true; \
  kubectl apply -f '${K8S_PATH}/database/statefulset.yaml' || true; \
  kubectl apply -f '${K8S_PATH}/ingress/' || true"

# Decide whether to apply APPS
apply_apps=false

if [ "${APPLY_APP_MANIFESTS}" = "1" ]; then
  apply_apps=true
elif [ "${APPLY_APPS_IF_MISSING}" = "1" ]; then
  if ! run_u "export KUBECONFIG='${KUBECONFIG_PATH}'; kubectl get deploy backend-deployment -n default >/dev/null 2>&1"; then
    apply_apps=true
  fi
fi

if [ "$apply_apps" = true ]; then
  echo "[BOOT] Applying app manifests (APPLY_APP_MANIFESTS=${APPLY_APP_MANIFESTS}, APPLY_APPS_IF_MISSING=${APPLY_APPS_IF_MISSING})"
  run_u "export KUBECONFIG='${KUBECONFIG_PATH}'; kubectl apply -f '${K8S_PATH}/data-structures/' || true"
  run_u "export KUBECONFIG='${KUBECONFIG_PATH}'; kubectl apply -f '${K8S_PATH}/backend/' || true"
  run_u "export KUBECONFIG='${KUBECONFIG_PATH}'; kubectl apply -f '${K8S_PATH}/frontend/' || true"
else
  echo "[BOOT] Infra-only mode. Not applying backend/frontend/data-structures (preserving Jenkins versions)."
fi

echo "--- CloudRift Boot Completed: $(date -u +%Y-%m-%dT%H:%M:%SZ) ---"
EOF
  sudo chmod +x /usr/local/bin/start-cloudrift.sh
  ok "Installed /usr/local/bin/start-cloudrift.sh (single boot script)"

  # systemd oneshot to run it
  sudo tee /etc/systemd/system/cloudrift-setup.service >/dev/null <<'EOF'
[Unit]
Description=CloudRift Setup (Minikube Start - reboot safe)
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/start-cloudrift.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  # proxy service (optional) - keep if you still want it
  sudo tee /etc/systemd/system/k8s-proxy.service >/dev/null <<'EOF'
[Unit]
Description=Kubernetes Ingress Proxy (Port 80)
After=network.target docker.service
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
Environment=KUBECONFIG=/home/ubuntu/.kube/config
ExecStart=/usr/local/bin/kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 80:80 --address=0.0.0.0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable cloudrift-setup.service >/dev/null 2>&1 || true
  sudo systemctl enable k8s-proxy.service >/dev/null 2>&1 || true

  sudo systemctl restart cloudrift-setup.service >/dev/null 2>&1 || true
  sudo systemctl restart k8s-proxy.service >/dev/null 2>&1 || true

  ok "Auto-start configured (cloudrift-setup + k8s-proxy)"
  ok "Reboot behavior: infra-only default (preserves Jenkins versions)"
else
  warn "Not EC2; skipping systemd auto-start configuration"
fi

# -----------------------------
# Final status
# -----------------------------
header "Deployment status"
kubectl get pods -o wide || true
echo ""
kubectl get svc || true
echo ""
kubectl get ingress -A || true

header "Access info"
if [ "${EC2_ENV}" = true ]; then
  EC2_PUBLIC_IP="$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "unknown")"
  echo "App: http://${EC2_PUBLIC_IP}/"
  echo "API: http://${EC2_PUBLIC_IP}/api/"
  echo ""
  echo "Boot mode is infra-only by default to preserve Jenkins versions."
  echo "To force boot to apply apps (NOT recommended with :latest manifests):"
  echo "  sudo sed -i 's/^APPLY_APP_MANIFESTS=.*/APPLY_APP_MANIFESTS=1/' /etc/default/cloudrift"
  echo "  sudo systemctl restart cloudrift-setup"
else
  MINIKUBE_IP="$(minikube ip 2>/dev/null || echo "localhost")"
  echo "Minikube IP: ${MINIKUBE_IP}"
fi

ok "Setup complete"
exit 0
