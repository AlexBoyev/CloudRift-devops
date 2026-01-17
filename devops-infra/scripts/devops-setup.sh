#!/usr/bin/env bash
# DevOps Infrastructure Setup Script
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
# IMPORTANT: NO .env LOADING ON EC2
# -----------------------------
# This script does NOT source any .env files.
# Repo URLs and optional Git creds must be provided via environment variables
# (e.g., injected by Terraform remote-exec or by your SSH session).
#
# Required repo URLs:
: "${DEVOPS_REPO_URL:?DEVOPS_REPO_URL must be provided via environment}"
: "${API_REPO_URL:?API_REPO_URL must be provided via environment}"
: "${FRONTEND_REPO_URL:?FRONTEND_REPO_URL must be provided via environment}"

# Optional Git credentials (for private repos)
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

# Check Helm (optional)
if command_exists helm; then
  HELM_VERSION="$(helm version --short 2>/dev/null || true)"
  print_status "Helm installed: ${HELM_VERSION:-unknown}"
else
  print_warning "Helm is not installed (optional)"
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
    sudo -u "$EC2_USER" minikube start --driver=docker --memory=2500mb --cpus=2
    print_status "Minikube started successfully"
  fi

  sudo -u "$EC2_USER" kubectl config use-context minikube >/dev/null 2>&1 || true
  print_status "kubectl context set to minikube"
else
  if minikube status >/dev/null 2>&1; then
    print_status "Minikube is running"
  else
    print_status "Starting Minikube..."
    minikube start --driver=docker --memory=2500mb --cpus=2
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
      # GitHub accepts PAT as username in practice, but we avoid guessing.
      # Use "git" if user wasn't provided.
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
    # Use auth URL for fetch/pull if PAT exists
    git -C "$target_dir" remote set-url origin "$auth_url" >/dev/null 2>&1 || true
    git -C "$target_dir" fetch --all --tags >/dev/null 2>&1 || true
    # Reset to origin/main to avoid drift (matches your original behavior)
    git -C "$target_dir" fetch origin main >/dev/null 2>&1 || true
    git -C "$target_dir" reset --hard origin/main >/dev/null 2>&1 || true
    print_status "$repo_name repository updated from remote"
  fi

  # Always reset remote to clean URL (avoid leaving PAT in git config)
  git -C "$target_dir" remote set-url origin "$clean_url" >/dev/null 2>&1 || true
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
else
  ensure_repo "$BACKEND_REPO_URL" "$PROJECT_ROOT/../new-backend" "backend" || print_warning "Backend repository setup failed"
  ensure_repo "$UI_REPO_URL" "$PROJECT_ROOT/../new-frontend" "frontend" || print_warning "Frontend repository setup failed"
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

    if $DOCKER_CMD build -f "$context/$dockerfile" -t "$image_name" "$context" 2>&1 | tee /tmp/docker-build.log; then
      if $DOCKER_CMD images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${image_name}$"; then
        print_status "$display_name built successfully"
        IMAGES_BUILT=$((IMAGES_BUILT + 1))
        return 0
      fi
      print_error "$display_name build reported success but image not found"
      IMAGES_FAILED=$((IMAGES_FAILED + 1))
      return 1
    fi

    print_error "$display_name build failed"
    IMAGES_FAILED=$((IMAGES_FAILED + 1))
    return 1
  }

  build_image "Dockerfile" "$BACKEND_REPO_PATH/backend" "backend-service:latest" "Backend Service"
  build_image "Dockerfile" "$FRONTEND_REPO_PATH"        "ui-service:latest"      "Frontend UI Service"
  build_image "stack/Dockerfile"      "$BACKEND_REPO_PATH" "stack-service:latest"      "Stack Service"
  build_image "linkedlist/Dockerfile" "$BACKEND_REPO_PATH" "linkedlist-service:latest" "LinkedList Service"
  build_image "graph/Dockerfile"      "$BACKEND_REPO_PATH" "graph-service:latest"      "Graph Service"
  build_image "database/Dockerfile"   "$BACKEND_REPO_PATH" "postgres-db:latest"        "PostgreSQL Database"

  echo ""
  print_status "Verifying built images..."
  REQUIRED_IMAGES=("backend-service:latest" "ui-service:latest" "stack-service:latest" "linkedlist-service:latest" "graph-service:latest" "postgres-db:latest")
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

  if [ "$IMAGES_FAILED" -gt 0 ] || [ "$MISSING" -gt 0 ]; then
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
print_header "Step 5: Deploying Kubernetes Resources"

DEVOPS_INFRA="$REPO_ROOT/devops-infra"
echo "Deploying Kubernetes resources from: $DEVOPS_INFRA"

echo "Applying namespaces..."
kubectl apply -f "$DEVOPS_INFRA/kubernetes/namespaces/" 2>/dev/null || true
print_status "Namespaces applied"

echo "Deploying database..."
kubectl apply -f "$DEVOPS_INFRA/kubernetes/database/"
print_status "Database deployed"

echo "Deploying frontend..."
kubectl apply -f "$DEVOPS_INFRA/kubernetes/frontend/"
print_status "Frontend deployed"

echo "Deploying backend..."
kubectl apply -f "$DEVOPS_INFRA/kubernetes/backend/"
print_status "Backend deployed"

echo "Deploying data structure services..."
if [ -d "$DEVOPS_INFRA/kubernetes/data-structures" ]; then
  kubectl apply -f "$DEVOPS_INFRA/kubernetes/data-structures/"
  print_status "Data structure services deployed"
else
  print_warning "Data structures manifests not found"
fi

echo "Deploying ingress..."
kubectl apply -f "$DEVOPS_INFRA/kubernetes/ingress/"
print_status "Ingress deployed"

if [ -d "$DEVOPS_INFRA/kubernetes/ingress-controller" ]; then
  echo "Deploying NGINX ingress controller..."
  kubectl apply -f "$DEVOPS_INFRA/kubernetes/ingress-controller/"
  print_status "NGINX ingress controller deployed"
fi

if [ "$DEPLOY_MONITORING" = "true" ]; then
  print_header "Step 6: Deploying Monitoring Stack"

  echo "Deploying Prometheus..."
  kubectl apply -f "$DEVOPS_INFRA/kubernetes/monitoring/prometheus/"
  print_status "Prometheus deployed"

  if [ -d "$DEVOPS_INFRA/kubernetes/monitoring/grafana/dashboards" ]; then
    kubectl create configmap grafana-dashboards \
      --from-file="$DEVOPS_INFRA/kubernetes/monitoring/grafana/dashboards/" \
      --dry-run=client -o yaml | kubectl apply -f -
  fi

  echo "Deploying Grafana..."
  kubectl apply -f "$DEVOPS_INFRA/kubernetes/monitoring/grafana/"
  print_status "Grafana deployed"
fi

# -----------------------------
# Wait for deployments
# -----------------------------
print_header "Step 7: Waiting for Deployments"

kubectl rollout status deployment/frontend-deployment --timeout=300s 2>/dev/null || print_warning "Frontend rollout timeout"
kubectl rollout status deployment/backend-deployment  --timeout=300s 2>/dev/null || print_warning "Backend rollout timeout"
kubectl rollout status deployment/stack-deployment    --timeout=300s 2>/dev/null || print_warning "Stack rollout timeout"
kubectl rollout status deployment/linkedlist-deployment --timeout=300s 2>/dev/null || print_warning "LinkedList rollout timeout"
kubectl rollout status deployment/graph-deployment    --timeout=300s 2>/dev/null || print_warning "Graph rollout timeout"

# -----------------------------
# External access
# -----------------------------
print_header "Step 8: Setting up External Access"

pkill -f 'kubectl port-forward' >/dev/null 2>&1 || true
sleep 2

KUBECTL_PATH="$(command -v kubectl || true)"
if [ -z "$KUBECTL_PATH" ]; then
  print_error "kubectl not found in PATH"
  exit 1
fi

if [ "$EC2_ENV" = true ]; then
  echo "Setting up port-forward service on EC2..."

  sudo tee /etc/systemd/system/k8s-port-forward.service > /dev/null << EOF
[Unit]
Description=Kubernetes Port Forward for Ingress on Port 80
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/${EC2_USER}
Environment="KUBECONFIG=/home/${EC2_USER}/.kube/config"
ExecStart=${KUBECTL_PATH} port-forward -n ingress-nginx svc/ingress-nginx-controller 80:80 --address=0.0.0.0
Restart=always
RestartSec=5
StandardOutput=append:/tmp/ingress-port-forward.log
StandardError=append:/tmp/ingress-port-forward.log

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable k8s-port-forward.service
  sudo systemctl restart k8s-port-forward.service

  sleep 3
  if sudo systemctl is-active --quiet k8s-port-forward.service; then
    print_status "Port-forward service is running on port 80"
  else
    print_warning "Port-forward service failed to start"
  fi
else
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
kubectl get pods -o wide || true

echo ""
echo "=== Services ==="
kubectl get services || true

echo ""
echo "=== Ingress ==="
kubectl get ingress || true

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
    echo -e "${BLUE}Monitoring (port-forward required):${NC}"
    echo "  - Prometheus: kubectl port-forward svc/prometheus-service 9090:9090"
    echo "  - Grafana:    kubectl port-forward svc/grafana-service 3000:3000"
  fi

  echo ""
  echo -e "${BLUE}Service Management:${NC}"
  echo "  - View port-forward logs: tail -f /tmp/ingress-port-forward.log"
  echo "  - Restart port-forward: sudo systemctl restart k8s-port-forward"
  echo "  - Stop port-forward: sudo systemctl stop k8s-port-forward"
else
  MINIKUBE_IP="$(minikube ip 2>/dev/null || echo "localhost")"

  echo -e "${GREEN}Application is accessible at:${NC}"
  echo -e "  - Frontend: ${YELLOW}http://${MINIKUBE_IP}:32080/${NC}"
  echo -e "  - API:      ${YELLOW}http://${MINIKUBE_IP}:32080/api/${NC}"

  if [ "$DEPLOY_MONITORING" = "true" ]; then
    echo ""
    echo -e "${BLUE}Monitoring:${NC}"
    echo "  - Prometheus: kubectl port-forward svc/prometheus-service 9090:9090"
    echo "  - Grafana:    kubectl port-forward svc/grafana-service 3000:3000"
  fi
fi

print_header "Setup Complete!"

echo "✅ Prerequisites checked"
echo "✅ Kubernetes environment configured"
echo "✅ Source code repositories prepared"
echo "✅ Docker images built" $([ "$SKIP_BUILD" = "true" ] && echo "(skipped)" || echo "")
echo "✅ Kubernetes resources deployed"
echo "✅ External access configured"
echo "✅ Monitoring stack deployed" $([ "$DEPLOY_MONITORING" = "true" ] && echo "" || echo "(skipped)")
echo ""

print_status "Your AKS Data Structures Platform is ready."
exit 0
