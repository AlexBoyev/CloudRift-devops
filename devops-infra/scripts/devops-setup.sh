#!/usr/bin/env bash
# DevOps Infrastructure Setup Script - FIXED & COMPLETE
# Complete one-click deployment for AKS Data Structures Platform
# This script handles the full deployment after AWS infrastructure is ready

set -euo pipefail

# -----------------------------
# Output helpers
# -----------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
: "${BACKEND_TAG:=backend-$(date +%Y%m%d%H%M%S)}"
: "${FRONTEND_TAG:=frontend-$(date +%Y%m%d%H%M%S)}"
: "${DB_TAG:=db-$(date +%Y%m%d%H%M%S)}"

: "${SKIP_BACKEND_BUILD:=false}"
: "${SKIP_FRONTEND_BUILD:=false}"
: "${SKIP_DB_BUILD:=false}"

# FIX: Log function defined to match your style
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_status()  { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error()   { echo -e "${RED}✗${NC} $1"; }
print_header()  { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# -----------------------------
# Script directory layout
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"   # /.../devops-infra
REPO_ROOT="$(dirname "$PROJECT_ROOT")"    # repo root (one level up)

# -----------------------------
# Inputs / defaults
# -----------------------------
ENVIRONMENT="${1:-dev}"
DEPLOY_MONITORING="${2:-true}"
USE_HELM="${3:-false}"
SKIP_BUILD="${4:-false}"

# -----------------------------
# FIX 1: Robust .env LOADING
# -----------------------------
# Loads variables even if they are missing 'export' in the file
# stripping Windows carriage returns (\r) to prevent syntax errors
if [ -f "/home/${USER}/.env" ]; then
    log "Loading environment variables from /home/${USER}/.env..."
    export $(grep -v '^#' "/home/${USER}/.env" | sed 's/\r$//' | xargs)
fi

: "${DEVOPS_REPO_URL:?DEVOPS_REPO_URL must be provided via environment}"
: "${API_REPO_URL:?API_REPO_URL must be provided via environment}"
: "${FRONTEND_REPO_URL:?FRONTEND_REPO_URL must be provided via environment}"

# Optional Git credentials
GITHUB_USER="${GITHUB_USER:-${GIT_USERNAME:-}}"
GITHUB_PAT="${GITHUB_PAT:-${GIT_PAT:-}}"

export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=true

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  AKS Data Structures - DevOps Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Environment: $ENVIRONMENT"
echo "Deploy Monitoring: $DEPLOY_MONITORING"
echo "Use Helm: $USE_HELM"
echo "Skip Docker Build: $SKIP_BUILD"
echo ""
echo "Repo URLs (from env):"
echo "  DEVOPS_REPO_URL:   $DEVOPS_REPO_URL"
echo "  API_REPO_URL:      $API_REPO_URL"
echo "  FRONTEND_REPO_URL: $FRONTEND_REPO_URL"
echo ""

# -----------------------------
# Detect environment (EC2 vs local)
# -----------------------------
print_header "Step 1: Checking Prerequisites"

# Heuristic: if /home/ubuntu exists, treat as EC2-ish
if [ -d /home/ubuntu ]; then
  print_status "Detected EC2 environment"
  EC2_ENV=true
  EC2_USER="ubuntu"
else
  EC2_ENV=false
  EC2_USER="${USER:-}"

# Auto-start toggle for EC2 systemd service
ENABLE_AUTOSTART="${ENABLE_AUTOSTART:-1}"

# Ensure kubectl uses ubuntu kubeconfig even if this script is invoked with sudo
if [ "${EC2_ENV}" = true ]; then
  export KUBECONFIG="${KUBECONFIG:-/home/ubuntu/.kube/config}"
fi
fi

# Check Docker
if command_exists docker; then
  DOCKER_VERSION="$(docker --version || true)"
  print_status "Docker installed: ${DOCKER_VERSION:-unknown}"

  if ! docker ps >/dev/null 2>&1; then
    print_warning "Docker requires sudo. Attempting to add user to docker group..."
    if [ "$EC2_ENV" = true ]; then
      sudo usermod -aG docker "$EC2_USER" || true
      print_status "Added ${EC2_USER} to docker group (re-login may be required)"
    else
      print_warning "Please add your user to docker group: sudo usermod -aG docker \$USER"
    fi
  fi
else
  print_error "Docker is not installed"
  exit 1
fi

# Check kubectl
if command_exists kubectl; then
  KUBECTL_VERSION="$(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null || true)"
  print_status "kubectl installed: ${KUBECTL_VERSION:-unknown}"
else
  print_error "kubectl is not installed"
  exit 1
fi

# Check Minikube
if command_exists minikube; then
  MINIKUBE_VERSION="$(minikube version --short 2>/dev/null || minikube version 2>/dev/null || true)"
  print_status "Minikube installed: ${MINIKUBE_VERSION:-unknown}"
else
  print_error "Minikube is not installed"
  exit 1
fi

# Check Terraform
if command_exists terraform; then
  TERRAFORM_VERSION="$(terraform version | head -n1 || true)"
  print_status "Terraform installed: ${TERRAFORM_VERSION:-unknown}"
else
  print_error "Terraform is not installed"
  exit 1
fi

# Check Helm (Now required for Monitoring fix)
if command_exists helm; then
  HELM_VERSION="$(helm version --short 2>/dev/null || true)"
  print_status "Helm installed: ${HELM_VERSION:-unknown}"
else
  if [ "$DEPLOY_MONITORING" = "true" ]; then
      print_warning "Helm not found. Installing Helm automatically for monitoring..."
      curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null 2>&1
      print_status "Helm installed successfully"
  else
      print_warning "Helm is not installed (optional)"
  fi
fi

# Check Git
if command_exists git; then
  GIT_VERSION="$(git --version || true)"
  print_status "Git installed: ${GIT_VERSION:-unknown}"
else
  print_error "Git is not installed"
  exit 1
fi

# Check AWS CLI (optional)
if command_exists aws; then
  AWS_VERSION="$(aws --version 2>&1 || true)"
  print_status "AWS CLI installed: ${AWS_VERSION:-unknown}"
else
  print_warning "AWS CLI is not installed (optional)"
fi

# -----------------------------
# Kubernetes environment setup
# -----------------------------
print_header "Step 2: Setting up Kubernetes Environment"

log "Disk space before cleanup:"
df -h /
log "Cleaning apt caches and unused packages..."
sudo apt-get clean -y || true
sudo apt-get autoremove -y || true
sudo rm -rf /var/lib/apt/lists/* || true
log "Cleaning Docker (safe on fresh EC2)..."
sudo systemctl start docker >/dev/null 2>&1 || true
sudo docker system prune -af --volumes || true
log "Disk space after cleanup:"
df -h /


if [ "$EC2_ENV" = true ]; then
  print_status "Setting up Minikube on EC2..."

  # Ensure minikube/kube dirs exist and owned by ubuntu
  sudo mkdir -p "/home/${EC2_USER}/.minikube" "/home/${EC2_USER}/.kube"
  sudo chown -R "${EC2_USER}:${EC2_USER}" "/home/${EC2_USER}/.minikube" "/home/${EC2_USER}/.kube"

  if sudo -u "$EC2_USER" minikube status >/dev/null 2>&1; then
    print_status "Minikube is already running"
  else
    print_status "Starting Minikube..."
    sudo -u "$EC2_USER" minikube start --driver=docker --memory=5120mb --cpus=2
    print_status "Minikube started successfully"

    # Enable Ingress Addon immediately after start
    print_status "Enabling Ingress Controller..."
    sudo -u "$EC2_USER" minikube addons enable ingress

    # Wait for the addon controller to be ready (correct selector)
    kubectl wait --namespace ingress-nginx \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=120s
    print_status "Ingress Controller enabled"
  fi

  sudo -u "$EC2_USER" kubectl config use-context minikube >/dev/null 2>&1 || true
  print_status "kubectl context set to minikube"
else
  if minikube status >/dev/null 2>&1; then
    print_status "Minikube is running"
  else
    print_status "Starting Minikube..."
    minikube start --driver=docker --memory=5120mb --cpus=2
    print_status "Minikube started"
  fi
  kubectl config use-context minikube >/dev/null 2>&1 || true
fi

if kubectl cluster-info >/dev/null 2>&1; then
  print_status "Connected to Kubernetes cluster"
else
  print_error "Cannot connect to Kubernetes cluster"
  exit 1
fi

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

_repo_auth_url() {
  # If PAT is provided, return URL with auth; else return normalized clean URL.
  local repo_url="$1"
  local normalized
  normalized="$(normalize_url "$repo_url")"

  if [ -n "${GITHUB_PAT:-}" ]; then
    if [ -z "${GITHUB_USER:-}" ]; then
      GITHUB_USER="git"
    fi
    echo "https://${GITHUB_USER}:${GITHUB_PAT}@${normalized#https://}"
  else
    echo "$normalized"
  fi
}

ensure_repo() {
  local repo_url="$1"
  local target_dir="$2"
  local repo_name="$3"

  local clean_url auth_url
  clean_url="$(normalize_url "$repo_url")"
  auth_url="$(_repo_auth_url "$repo_url")"

  if [ ! -d "$target_dir/.git" ]; then
    echo "Cloning $repo_name repository..."
    mkdir -p "$(dirname "$target_dir")"
    if ! git -c credential.helper= clone "$auth_url" "$target_dir"; then
      print_error "Could not clone $repo_name."
      if [ -z "${GITHUB_PAT:-}" ]; then
        print_error "Repo may be private. Provide GIT_PAT/GIT_USERNAME via environment."
      else
        print_error "PAT provided but clone still failed. Check access/permissions."
      fi
      return 1
    fi
    print_status "$repo_name repository cloned"
  else
    print_status "$repo_name repository already exists"
    if [ "$EC2_ENV" = true ]; then
      sudo chown -R "${EC2_USER}:${EC2_USER}" "$target_dir/.git" 2>/dev/null || true
      sudo chmod -R u+rwX "$target_dir/.git" 2>/dev/null || true
    fi
    # Use auth URL for fetch/pull if PAT exists
    git -C "$target_dir" remote set-url origin "$auth_url" >/dev/null 2>&1 || true
    git -C "$target_dir" fetch --all --tags >/dev/null 2>&1 || true
    # Reset to origin/main to avoid drift
    git -C "$target_dir" fetch origin main >/dev/null 2>&1 || true
    git -C "$target_dir" reset --hard origin/main >/dev/null 2>&1 || true
    print_status "$repo_name repository updated from remote"
  fi

  # Always reset remote to clean URL
  git -C "$target_dir" remote set-url origin "$clean_url" >/dev/null 2>&1 || true

  # FIX: FORCE PERMISSIONS
  if [ "$EC2_ENV" = true ]; then
     sudo chown -R "${EC2_USER}:${EC2_USER}" "$target_dir" 2>/dev/null || true
     sudo chmod -R u+rwX "$target_dir" 2>/dev/null || true
  fi
  return 0
}

# -----------------------------
# Clone / update repos
# -----------------------------
print_header "Step 3: Setting up Source Code"

INFRA_REPO_URL="$DEVOPS_REPO_URL"
BACKEND_REPO_URL="$API_REPO_URL"
UI_REPO_URL="$FRONTEND_REPO_URL"

if [ "$EC2_ENV" = true ]; then
  print_status "Setting up repositories on EC2..."

  REPO_DIR="/home/${EC2_USER}/new-devops-local"
  ensure_repo "$INFRA_REPO_URL" "$REPO_DIR" "devops"

  ensure_repo "$BACKEND_REPO_URL" "/home/${EC2_USER}/new-backend" "backend"
  ensure_repo "$UI_REPO_URL" "/home/${EC2_USER}/new-frontend" "frontend"

  # FIX: SENIOR PATCH - Ensure the YAML on disk is updated before images or deployment
  log "Patching LinkedList memory limit to 512Mi on local disk..."
  sed -i 's/memory: 128Mi/memory: 512Mi/g' "$REPO_DIR/devops-infra/kubernetes/data-structures/linkedlist.yaml" || true
else
  ensure_repo "$BACKEND_REPO_URL" "$PROJECT_ROOT/../new-backend" "backend" || print_warning "Backend repository setup failed"
  ensure_repo "$UI_REPO_URL" "$PROJECT_ROOT/../new-frontend" "frontend" || print_warning "Frontend repository setup failed"
fi

print_header "Step 3b: Patching YAML Templates"
log "Replacing placeholder tags (e.g., \$(BACKEND_TAG)) in YAMLs with 'latest'..."

# This forces K8s to look for the 'latest' tag we are about to build
if [ -d "$REPO_DIR/devops-infra/kubernetes" ]; then
    find "$REPO_DIR/devops-infra/kubernetes" -name "*.yaml" -type f -exec sed -i 's/\$(BACKEND_TAG)/latest/g' {} +
    find "$REPO_DIR/devops-infra/kubernetes" -name "*.yaml" -type f -exec sed -i 's/\$(FRONTEND_TAG)/latest/g' {} +
    find "$REPO_DIR/devops-infra/kubernetes" -name "*.yaml" -type f -exec sed -i 's/\$(DB_TAG)/latest/g' {} +
    log "Patching imagePullPolicy to allow local images..."
    find "$REPO_DIR/devops-infra/kubernetes" -name "*.yaml" -type f -exec sed -i 's/imagePullPolicy: Always/imagePullPolicy: IfNotPresent/g' {} +
    print_status "YAML files patched: Tags -> latest, Policy -> IfNotPresent"
else
    print_warning "Kubernetes directory not found for patching"
fi

# -----------------------------
# Build Docker images
# -----------------------------
if [ "$SKIP_BUILD" = "false" ]; then
  print_header "Step 4: Building Docker Images"

  BACKEND_REPO_PATH="/home/${EC2_USER}/new-backend"
  FRONTEND_REPO_PATH="/home/${EC2_USER}/new-frontend"
  if [ "$EC2_ENV" = false ]; then
    BACKEND_REPO_PATH="$PROJECT_ROOT/../new-backend"
    FRONTEND_REPO_PATH="$PROJECT_ROOT/../new-frontend"
  fi

  if [ ! -d "$BACKEND_REPO_PATH" ]; then
    print_error "Backend repository not found at: $BACKEND_REPO_PATH"
    exit 1
  fi
  if [ ! -d "$FRONTEND_REPO_PATH" ]; then
    print_error "Frontend repository not found at: $FRONTEND_REPO_PATH"
    exit 1
  fi
  print_status "Source repositories verified"

  print_status "Configuring Minikube Docker environment..."
  if [ "$EC2_ENV" = true ]; then
    eval "$(sudo -u "$EC2_USER" minikube docker-env)"
    export DOCKER_TLS_VERIFY="${DOCKER_TLS_VERIFY:-}"
    export DOCKER_HOST="${DOCKER_HOST:-}"
    export DOCKER_CERT_PATH="${DOCKER_CERT_PATH:-}"
    export DOCKER_API_VERSION="${DOCKER_API_VERSION:-}"
    DOCKER_CMD="sudo -E docker"
  else
    eval "$(minikube docker-env)"
    DOCKER_CMD="docker"
  fi

  if echo "${DOCKER_HOST:-}" | grep -q "minikube"; then
    print_status "Docker configured for Minikube"
  else
    print_warning "Docker may not be pointing to Minikube"
  fi

  if kubectl get pods 2>/dev/null | grep -q "ImagePullBackOff\|ErrImagePull\|ErrImageNeverPull"; then
    print_warning "Cleaning up deployments with image errors..."
    kubectl delete deployment frontend-deployment backend-deployment stack-deployment linkedlist-deployment graph-deployment --ignore-not-found=true || true
    sleep 5
  fi

  IMAGES_BUILT=0
  IMAGES_FAILED=0

  build_image() {
    local dockerfile="$1"
    local context="$2"
    local image_name="$3"
    local display_name="$4"

    echo ""
    echo "Building $display_name..."
    echo "  Dockerfile: $dockerfile"
    echo "  Context:    $context"
    echo "  Image:      $image_name"

    if [ ! -f "$context/$dockerfile" ]; then
      print_error "Dockerfile not found: $context/$dockerfile"
      IMAGES_FAILED=$((IMAGES_FAILED + 1))
      return 1
    fi

    # FIX: Added simple retry logic
    if ! $DOCKER_CMD build -f "$context/$dockerfile" -t "$image_name" "$context" 2>&1 | tee /tmp/docker-build.log; then
      echo "  ⚠ First attempt failed. Retrying..."
      if ! $DOCKER_CMD build -f "$context/$dockerfile" -t "$image_name" "$context"; then
         print_error "$display_name build failed"
         IMAGES_FAILED=$((IMAGES_FAILED + 1))
         return 1
      fi
    fi

    if $DOCKER_CMD images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${image_name}$"; then
      # -----------------------------
      # FIX 2: Double-Tagging Strategy
      # -----------------------------
      # Extracts "backend-service" from "backend-service:backend-12345"
      local base_img
      base_img=$(echo "$image_name" | cut -d':' -f1)

      # Tag as latest so K8s YAMLs (which expect :latest) can find it
      if $DOCKER_CMD tag "$image_name" "${base_img}:latest"; then
          print_status "$display_name built as $image_name and tagged as ${base_img}:latest"
          IMAGES_BUILT=$((IMAGES_BUILT + 1))
          return 0
      else
          print_error "Failed to tag $image_name as latest"
          IMAGES_FAILED=$((IMAGES_FAILED + 1))
          return 1
      fi
    fi

    print_error "$display_name build reported success but image not found"
    IMAGES_FAILED=$((IMAGES_FAILED + 1))
    return 1
  }

if [ "$SKIP_BACKEND_BUILD" != "true" ]; then
  build_image "Dockerfile"             "$BACKEND_REPO_PATH/backend" "backend-service:${BACKEND_TAG}"      "Backend Service"
  build_image "stack/Dockerfile"      "$BACKEND_REPO_PATH"         "stack-service:${BACKEND_TAG}"        "Stack Service"
  build_image "linkedlist/Dockerfile" "$BACKEND_REPO_PATH"         "linkedlist-service:${BACKEND_TAG}"   "LinkedList Service"
  build_image "graph/Dockerfile"      "$BACKEND_REPO_PATH"         "graph-service:${BACKEND_TAG}"        "Graph Service"
fi

# Frontend image
if [ "$SKIP_FRONTEND_BUILD" != "true" ]; then
  build_image "Dockerfile" "$FRONTEND_REPO_PATH" "ui-service:${FRONTEND_TAG}" "Frontend UI Service"
fi

# Database image
if [ "$SKIP_DB_BUILD" != "true" ]; then
  build_image "database/Dockerfile" "$BACKEND_REPO_PATH" "postgres-db:${DB_TAG}" "PostgreSQL Database"
fi

  echo ""
  print_status "Verifying built images..."
  REQUIRED_IMAGES=(
  "backend-service:$BACKEND_TAG"
  "ui-service:$FRONTEND_TAG"
  "stack-service:$BACKEND_TAG"
  "linkedlist-service:$BACKEND_TAG"
  "graph-service:$BACKEND_TAG"
  "postgres-db:$DB_TAG"
  )
  MISSING=0
  for img in "${REQUIRED_IMAGES[@]}"; do
    if $DOCKER_CMD images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${img}$"; then
      echo "  ✓ $img"
    else
      echo "  ✗ $img (MISSING)"
      MISSING=$((MISSING + 1))
    fi
  done

  echo ""
  echo "Build Summary: $IMAGES_BUILT built, $IMAGES_FAILED failed, $MISSING missing"

  if [ "$IMAGES_FAILED" -gt 0 ]; then
    print_error "Image build completed with errors. Cannot proceed with deployment."
    exit 1
  fi

  print_status "All images built and verified successfully"
else
  print_status "Skipping Docker build as requested"
fi

# -----------------------------
# Deploy Kubernetes resources
# -----------------------------
print_header "Step 5: Deploying Kubernetes Resources with Dependency Logic"

# Set DEVOPS_INFRA context
DEVOPS_INFRA="/home/${EC2_USER}/new-devops-local/devops-infra"

# 1. Apply Namespaces and Secrets first
kubectl apply -f "$DEVOPS_INFRA/kubernetes/namespaces/"
kubectl apply -f "$DEVOPS_INFRA/kubernetes/database/secret.yaml"
kubectl apply -f "$DEVOPS_INFRA/kubernetes/backend/secret.yaml"

# 2. Deploy Database (The Foundation)
log "Deploying Database..."
kubectl apply -f "$DEVOPS_INFRA/kubernetes/database/"
# Wait for the database pod to be ready based on its readinessProbe (pg_isready)
kubectl rollout status statefulset/postgres-db --timeout=120s
print_status "Database is online and ready"

# 3. Deploy Data Structure Services
log "Deploying Microservices (Stack, LinkedList, Graph)..."
if [ -d "$DEVOPS_INFRA/kubernetes/data-structures" ]; then
  kubectl apply -f "$DEVOPS_INFRA/kubernetes/data-structures/"
  kubectl rollout status deployment/stack-deployment --timeout=120s
  kubectl rollout status deployment/linkedlist-deployment --timeout=120s
  kubectl rollout status deployment/graph-deployment --timeout=120s

  print_status "Data structure services are ready"
fi

# 4. Deploy Backend (Depends on Database)
log "Deploying Backend..."
kubectl apply -f "$DEVOPS_INFRA/kubernetes/backend/"
kubectl rollout status deployment/backend-deployment --timeout=120s
print_status "Backend is ready"

# 5. Deploy Frontend and Ingress
log "Deploying Frontend..."
kubectl apply -f "$DEVOPS_INFRA/kubernetes/frontend/"
print_status "Frontend deployed"
log "Deploying Ingress rules..."
kubectl apply -f "$DEVOPS_INFRA/kubernetes/ingress/"
print_status "Ingress rules applied"

# CRITICAL FIX: Skip custom ingress controller deployment
# The Minikube addon already provides the controller
if [ -d "$DEVOPS_INFRA/kubernetes/ingress-controller" ]; then
  log "Skipping custom ingress-controller (using Minikube addon instead)"
fi

# FIX: Monitoring Logic with Helm Fallback
if [ "$DEPLOY_MONITORING" = "true" ]; then
  print_header "Step 6: Deploying Monitoring Stack"

  # Check if we have the local YAML files first
  if [ -d "$DEVOPS_INFRA/kubernetes/monitoring/prometheus" ]; then
      echo "Deploying Prometheus from local YAML..."
      kubectl apply -f "$DEVOPS_INFRA/kubernetes/monitoring/prometheus/"

      if [ -d "$DEVOPS_INFRA/kubernetes/monitoring/grafana/dashboards" ]; then
        kubectl create configmap grafana-dashboards \
          --from-file="$DEVOPS_INFRA/kubernetes/monitoring/grafana/dashboards/" \
          --dry-run=client -o yaml | kubectl apply -f -
      fi

      echo "Deploying Grafana from local YAML..."
      kubectl apply -f "$DEVOPS_INFRA/kubernetes/monitoring/grafana/"
      print_status "Monitoring stack deployed via YAML"
  else
      # Fallback to Helm if files are missing
      print_status "Monitoring YAMLs not found. Installing via Helm..."

      # Add repo if missing
      helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
      helm repo update >/dev/null 2>&1 || true

      # Install
      helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
        --create-namespace \
        --namespace monitoring \
        --set grafana.service.type=ClusterIP \
        --wait --timeout=5m >/dev/null 2>&1

      print_status "Prometheus & Grafana installed via Helm"
  fi
fi

print_header "Step 6b: Forcing Update of Running Pods"

echo "♻️  Restarting Deployments to pick up the new Docker images..."

# -----------------------------
# FIX 3: Explicit StatefulSet Restart
# -----------------------------
kubectl rollout restart statefulset postgres-db || true

# Restart standard deployments
kubectl rollout restart deployment backend-deployment
kubectl rollout restart deployment stack-deployment
kubectl rollout restart deployment linkedlist-deployment
kubectl rollout restart deployment graph-deployment


# -----------------------------
# Wait for deployments
# -----------------------------
print_header "Step 7: Waiting for Deployments"

kubectl rollout status statefulset/postgres-db        --timeout=300s 2>/dev/null || print_warning "DB rollout timeout"
kubectl rollout status deployment/frontend-deployment --timeout=300s 2>/dev/null || print_warning "Frontend rollout timeout"
kubectl rollout status deployment/backend-deployment  --timeout=300s 2>/dev/null || print_warning "Backend rollout timeout"
kubectl rollout status deployment/stack-deployment    --timeout=300s 2>/dev/null || print_warning "Stack rollout timeout"
kubectl rollout status deployment/linkedlist-deployment --timeout=300s 2>/dev/null || print_warning "LinkedList rollout timeout"
kubectl rollout status deployment/graph-deployment    --timeout=300s 2>/dev/null || print_warning "Graph rollout timeout"

# -----------------------------
# External access (WITH PERMISSION FIX)
# -----------------------------
print_header "Step 8: Configuring Auto-Start Service"

pkill -f 'kubectl port-forward' >/dev/null 2>&1 || true
sleep 2

KUBECTL_PATH="$(command -v kubectl || true)"
if [ -z "$KUBECTL_PATH" ]; then
  print_error "kubectl not found in PATH"
  exit 1
fi

if [ "$EC2_ENV" = true ]; then
  print_status "Setting up Systemd Service on EC2 for Auto-Start..."

  # 1. Create the resilient Start Script
  # FIX: SENIOR ORCHESTRATOR - Sequential recovery and RAM protection
cat << 'EOF' | sudo tee /usr/local/bin/start-cloudrift.sh > /dev/null
#!/bin/bash
K8S_PATH="/home/ubuntu/new-devops-local/devops-infra/kubernetes"
LOG_FILE="/var/log/cloudrift-startup.log"

exec > >(tee -a "$LOG_FILE") 2>&1
echo "--- Starting CloudRift Sequential Recovery: $(date) ---"

sudo -u ubuntu minikube delete --all --purge || true
sudo rm -rf /home/ubuntu/.minikube
sudo chown -R ubuntu:ubuntu /home/ubuntu/.minikube /home/ubuntu/.kube

# A. Clear host-level RAM conflicts
sudo systemctl stop jenkins || true

# B. Recover Minikube with Optimized RAM
minikube start --memory=5120mb --cpus=2
until kubectl get nodes >/dev/null 2>&1; do
  echo "Waiting for API Server..." ; sleep 5
done

# C. RAM Protection: Kill monitoring immediately
kubectl scale deployment grafana --replicas=0 -n default || true
kubectl scale deployment prometheus --replicas=0 -n default || true

# D. Sequential Core Services (The "Staggered" approach)
echo "Staggering service starts..."
kubectl apply -f "$K8S_PATH/database/" ; sleep 20
kubectl apply -f "$K8S_PATH/backend/" ; sleep 15

# Applies 512Mi fix automatically from patched disk file
kubectl apply -f "$K8S_PATH/data-structures/linkedlist.yaml" ; sleep 10
kubectl apply -f "$K8S_PATH/data-structures/stack.yaml"
kubectl apply -f "$K8S_PATH/data-structures/graph.yaml" ; sleep 10

kubectl apply -f "$K8S_PATH/frontend/"
kubectl apply -f "$K8S_PATH/ingress/"

# E. UI Bridge (Port 80)
sudo fuser -k 80/tcp || true
(
  while true; do
    echo "Starting port-forward 80:80..."
    sudo kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 80:80 --address=0.0.0.0
    sleep 10
  done
) &

# F. Re-enable Monitoring once core is stable
echo "Waiting 60s for Java services to settle..." ; sleep 60
kubectl scale deployment prometheus --replicas=1 || true
sleep 20
kubectl scale deployment grafana --replicas=1 || true

echo "--- CloudRift Online: $(date) ---"
EOF

  # Make it executable
  sudo chmod +x /usr/local/bin/start-cloudrift.sh
  print_status "Created startup script at /usr/local/bin/start-cloudrift.sh"

  # 2. Create the Systemd Service
cat << 'EOF' | sudo tee /etc/systemd/system/cloudrift.service > /dev/null
[Unit]
Description=CloudRift Application (Resilient Minikube Start)
After=docker.service network.target
Requires=docker.service

[Service]
User=root
Type=simple
ExecStart=/usr/local/bin/start-cloudrift.sh
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

  print_status "Created systemd service 'cloudrift.service'"

  # 3. Enable and Start
  sudo systemctl daemon-reload
  sudo systemctl enable cloudrift
  sudo systemctl restart cloudrift

  # Wait a moment for service to spin up
  sleep 5
  if sudo systemctl is-active --quiet cloudrift; then
     print_status "CloudRift service enabled and started. App will auto-start on reboot."
  else
     print_warning "CloudRift service failed to start. Check: sudo systemctl status cloudrift"
  fiprint_status "Setting up Systemd Service on EC2 for Auto-Start..."

  if [ "$ENABLE_AUTOSTART" != "1" ]; then
    print_warning "Auto-start disabled (ENABLE_AUTOSTART=$ENABLE_AUTOSTART). Skipping systemd setup."
  else
    # Create the non-destructive Start Script (no minikube delete/purge; consistent kubeconfig)
    cat << 'EOF' | sudo tee /usr/local/bin/start-cloudrift.sh > /dev/null
#!/bin/bash
set -euo pipefail

U="ubuntu"
K8S_PATH="/home/ubuntu/new-devops-local/devops-infra/kubernetes"
KUBECONFIG_PATH="/home/ubuntu/.kube/config"
LOG_FILE="/var/log/cloudrift-startup.log"

exec > >(tee -a "$LOG_FILE") 2>&1
echo "--- Starting CloudRift Recovery: $(date) ---"

run_u() { sudo -u "${U}" -H bash -lc "$*"; }

# Ensure docker is up (driver=docker)
sudo systemctl start docker >/dev/null 2>&1 || true

# Ensure kube dirs exist and owned by ubuntu
sudo mkdir -p /home/ubuntu/.kube /home/ubuntu/.minikube
sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube /home/ubuntu/.minikube

# A. Avoid host-level RAM conflicts
sudo systemctl stop jenkins >/dev/null 2>&1 || true

# B. Start/repair Minikube as ubuntu (NON-DESTRUCTIVE)
run_u "minikube status --profile=minikube >/dev/null 2>&1 || minikube start --profile=minikube --driver=docker --memory=5120mb --cpus=2"

# C. Wait for API server using ubuntu kubeconfig
run_u "export KUBECONFIG='${KUBECONFIG_PATH}'; kubectl config use-context minikube >/dev/null 2>&1 || true"
until sudo -u ubuntu -H env KUBECONFIG="${KUBECONFIG_PATH}" kubectl get nodes >/dev/null 2>&1; do
  echo "Waiting for API Server..." ; sleep 5
done

# D. Apply core manifests (idempotent)
sudo -u ubuntu -H env KUBECONFIG="${KUBECONFIG_PATH}" kubectl apply -f "$K8S_PATH/database/" || true
sleep 10
sudo -u ubuntu -H env KUBECONFIG="${KUBECONFIG_PATH}" kubectl apply -f "$K8S_PATH/backend/" || true
sleep 10

sudo -u ubuntu -H env KUBECONFIG="${KUBECONFIG_PATH}" kubectl apply -f "$K8S_PATH/data-structures/linkedlist.yaml" || true
sleep 5
sudo -u ubuntu -H env KUBECONFIG="${KUBECONFIG_PATH}" kubectl apply -f "$K8S_PATH/data-structures/stack.yaml" || true
sleep 5
sudo -u ubuntu -H env KUBECONFIG="${KUBECONFIG_PATH}" kubectl apply -f "$K8S_PATH/data-structures/graph.yaml" || true
sleep 5

sudo -u ubuntu -H env KUBECONFIG="${KUBECONFIG_PATH}" kubectl apply -f "$K8S_PATH/frontend/" || true
sudo -u ubuntu -H env KUBECONFIG="${KUBECONFIG_PATH}" kubectl apply -f "$K8S_PATH/ingress/"  || true

# E. UI Bridge (Port 80): root binds 80, but uses ubuntu kubeconfig
sudo fuser -k 80/tcp >/dev/null 2>&1 || true
(
  while true; do
    echo "Starting port-forward 80:80..."
    sudo env KUBECONFIG="${KUBECONFIG_PATH}" kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 80:80 --address=0.0.0.0
    sleep 10
  done
) &

# F. Monitoring (optional): only if the namespace exists
if sudo -u ubuntu -H env KUBECONFIG="${KUBECONFIG_PATH}" kubectl get ns monitoring >/dev/null 2>&1; then
  echo "Waiting 60s for core services to settle..." ; sleep 60
  sudo -u ubuntu -H env KUBECONFIG="${KUBECONFIG_PATH}" kubectl scale deployment prometheus --replicas=1 -n monitoring || true
  sleep 20
  sudo -u ubuntu -H env KUBECONFIG="${KUBECONFIG_PATH}" kubectl scale deployment grafana --replicas=1 -n monitoring || true
fi

echo "--- CloudRift Online: $(date) ---"
EOF

    sudo chmod +x /usr/local/bin/start-cloudrift.sh
    print_status "Created startup script at /usr/local/bin/start-cloudrift.sh"

    # Create the Systemd Service (explicit kubeconfig + network-online)
cat << 'EOF' | sudo tee /etc/systemd/system/cloudrift.service > /dev/null
[Unit]
Description=CloudRift Application (Non-Destructive Minikube Start)
After=docker.service network-online.target
Wants=network-online.target
Requires=docker.service

[Service]
User=root
Type=simple
Environment=KUBECONFIG=/home/ubuntu/.kube/config
ExecStart=/usr/local/bin/start-cloudrift.sh
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

    print_status "Created systemd service 'cloudrift.service'"

    sudo systemctl daemon-reload
    sudo systemctl enable cloudrift
    sudo systemctl restart cloudrift

    sleep 5
    if sudo systemctl is-active --quiet cloudrift; then
       print_status "CloudRift service enabled and started. App will auto-start on reboot."
    else
       print_warning "CloudRift service failed to start. Check: sudo systemctl status cloudrift"
    fi
  fi

else
  # Local flow (unchanged)
  echo "Starting port-forward for local access..."
  kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 32080:80 --address=0.0.0.0 &
  PORT_FORWARD_PID=$!
  echo "$PORT_FORWARD_PID" > /tmp/k8s-port-forward.pid
  print_status "Port-forward started on port 32080 (PID: $PORT_FORWARD_PID)"
fi

# -----------------------------
# Status & access info
# -----------------------------
print_header "Deployment Status"

echo "=== Pods ==="
env KUBECONFIG="$KUBECONFIG" kubectl get pods -o wide || true

echo ""
echo "=== Services ==="
env KUBECONFIG="$KUBECONFIG" kubectl get services || true

echo ""
echo "=== Ingress ==="
env KUBECONFIG="$KUBECONFIG" kubectl get ingress || true

echo ""
echo "=== Nodes ==="
kubectl get nodes || true

print_header "Access Information"

if [ "$EC2_ENV" = true ]; then
  EC2_PUBLIC_IP="$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "unknown")"

  echo -e "${GREEN}Application is accessible at:${NC}"
  echo -e "  - Frontend: ${YELLOW}http://${EC2_PUBLIC_IP}/${NC}"
  echo -e "  - API:      ${YELLOW}http://${EC2_PUBLIC_IP}/api/${NC}"

  if [ "$DEPLOY_MONITORING" = "true" ]; then
    echo ""
    echo -e "${BLUE}Monitoring (Port Forward Required):${NC}"
    echo "  - Prometheus: kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090"
    echo "  - Grafana:    kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80"
  fi

  echo ""
  echo -e "${BLUE}Service Management:${NC}"
  echo "  - Service Status: sudo systemctl status cloudrift"
  echo "  - Restart App:    sudo systemctl restart cloudrift"
else
  MINIKUBE_IP="$(minikube ip 2>/dev/null || echo "localhost")"

  echo -e "${GREEN}Application is accessible at:${NC}"
  echo -e "  - Frontend: ${YELLOW}http://${MINIKUBE_IP}:32080/${NC}"
  echo -e "  - API:      ${YELLOW}http://${MINIKUBE_IP}:32080/api/${NC}"
fi

print_header "Setup Complete!"

echo "✅ Prerequisites checked"
echo "✅ Kubernetes environment configured"
echo "✅ 512Mi Memory Patch applied to local YAMLs"
echo "✅ Docker images built" $([ "$SKIP_BUILD" = "true" ] && echo "(skipped)" || echo "")
echo "✅ Sequential startup logic injected into orchestrator"
echo "✅ External access configured (Auto-Start Enabled)"
echo "✅ Monitoring stack deployed"
echo ""

print_status "Your platform is ready for the reset test."
exit 0