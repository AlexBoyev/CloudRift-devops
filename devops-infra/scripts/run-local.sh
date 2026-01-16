#!/bin/bash
# run-local.sh - Complete Local Deployment Script
# Deploys the AKS Data Structures application to Minikube
#
# Usage: ./run-local.sh [--skip-build] [--skip-ds] [--no-monitoring]
#   --skip-build: Skip building images (use existing)
#   --skip-ds: Skip data structure services (faster deployment)
#   --no-monitoring: Skip deployment of Prometheus and Grafana

set -eo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Parse arguments
SKIP_BUILD=false
SKIP_DS=false
DEPLOY_MONITORING=true
for arg in "$@"; do
    case $arg in
        --skip-build) SKIP_BUILD=true ;;
        --skip-ds) SKIP_DS=true ;;
        --no-monitoring) DEPLOY_MONITORING=false ;;
    esac
done

# Script directory and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$DEVOPS_ROOT")"
WORKSPACE_ROOT="$(dirname "$PROJECT_ROOT")"

# Repository paths
BACKEND_REPO="${WORKSPACE_ROOT}/new-backend"
FRONTEND_REPO="${WORKSPACE_ROOT}/new-frontend"
DEVOPS_REPO="${PROJECT_ROOT}"

# Terraform local directory
TF_LOCAL_DIR="${DEVOPS_ROOT}/terraform/environments/local"

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║      ${BOLD}AKS Data Structures - Local Deployment${NC}${CYAN}                       ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

print_status() { echo -e "  ${GREEN}✓${NC} $1"; }
print_warning() { echo -e "  ${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "  ${RED}✗${NC} $1"; }
print_step() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}\n"; }

# ==========================================
# Step 1: Check Prerequisites
# ==========================================
print_step "Step 1: Checking Prerequisites"

for cmd in docker minikube kubectl terraform; do
    if command -v $cmd &> /dev/null; then
        print_status "$cmd installed"
    else
        print_error "$cmd is not installed"
        exit 1
    fi
done

# Check repos
[ -d "$BACKEND_REPO" ] && print_status "Backend repo found" || { print_error "Backend repo missing"; exit 1; }
[ -d "$FRONTEND_REPO" ] && print_status "Frontend repo found" || { print_error "Frontend repo missing"; exit 1; }

# ==========================================
# Step 2: Start Minikube
# ==========================================
print_step "Step 2: Starting Minikube"

if minikube status 2>/dev/null | grep -q "Running"; then
    print_status "Minikube is already running"
else
    echo "  Starting Minikube..."
    minikube start --memory=4096 --cpus=2
    print_status "Minikube started"
fi

MINIKUBE_IP=$(minikube ip)
print_status "Minikube IP: $MINIKUBE_IP"

# ==========================================
# Step 3: Configure Docker for Minikube
# ==========================================
print_step "Step 3: Configuring Docker"

eval $(minikube docker-env)
print_status "Docker configured for Minikube"

# ==========================================
# Step 4: Build Docker Images
# ==========================================
if [ "$SKIP_BUILD" = true ]; then
    print_step "Step 4: Skipping Docker Builds (--skip-build)"
else
    print_step "Step 4: Building Docker Images"
    
    echo -e "  Building ${YELLOW}backend-service${NC}..."
    docker build -t backend-service:latest "$BACKEND_REPO"
    print_status "backend-service:latest"
    
    echo -e "  Building ${YELLOW}ui-service${NC}..."
    docker build -t ui-service:latest "$FRONTEND_REPO"
    print_status "ui-service:latest"
    
    if [ "$SKIP_DS" = false ]; then
        echo ""
        echo -e "  ${YELLOW}Building data structure services...${NC}"
        echo ""
        
        for service in stack linkedlist graph; do
            if [ -d "$DEVOPS_REPO/$service" ] && [ -f "$DEVOPS_REPO/$service/Dockerfile" ]; then
                echo -e "  Building ${YELLOW}${service}-service${NC}..."
                docker build -t "${service}-service:latest" "$DEVOPS_REPO/$service"
                print_status "${service}-service:latest"
            fi
        done
    else
        print_warning "Skipping data structure services (--skip-ds)"
    fi
fi

echo ""
echo "  Docker images:"
docker images --format "    {{.Repository}}:{{.Tag}} ({{.Size}})" | grep -E "(backend|ui|stack|linkedlist|graph)-service" || true

# ==========================================
# Step 5: Deploy with Terraform
# ==========================================
print_step "Step 5: Deploying with Terraform"

cd "$TF_LOCAL_DIR"

terraform init -upgrade -input=false > /dev/null 2>&1
print_status "Terraform initialized"

echo "  Applying configuration..."
terraform apply -auto-approve -input=false 2>&1 | grep -E "(Apply|created|destroyed|complete)" | sed 's/^/    /'
print_status "Terraform applied"

# ==========================================
# Step 5b: Deploy Monitoring (Optional)
# ==========================================
if [ "$DEPLOY_MONITORING" = true ]; then
    print_step "Step 5b: Deploying Monitoring Stack"
    
    echo -e "  Deploying ${YELLOW}Prometheus${NC}..."
    kubectl apply -f "${DEVOPS_ROOT}/kubernetes/monitoring/prometheus/" >/dev/null
    print_status "Prometheus deployed"
    
    echo -e "  Deploying ${YELLOW}Grafana${NC}..."
    # Create ConfigMap for dashboards first
    if [ -d "${DEVOPS_ROOT}/kubernetes/monitoring/grafana/dashboards" ]; then
        kubectl create configmap grafana-dashboards \
            --from-file="${DEVOPS_ROOT}/kubernetes/monitoring/grafana/dashboards/" \
            --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    fi
    kubectl apply -f "${DEVOPS_ROOT}/kubernetes/monitoring/grafana/" >/dev/null
    print_status "Grafana deployed"
fi

# ==========================================
# Step 6: Wait for Pods
# ==========================================
print_step "Step 6: Waiting for Pods"

echo "  Waiting for deployments to be ready..."
sleep 5

for deploy in backend-deployment frontend-deployment stack-deployment linkedlist-deployment graph-deployment; do
    echo -n "    $deploy: "
    if kubectl rollout status deployment/$deploy --timeout=60s 2>/dev/null; then
        echo ""
    else
        echo -e "${YELLOW}still starting / check logs${NC}"
    fi
done

# ==========================================
# Step 7: Status
# ==========================================
print_step "Step 7: Deployment Status"

echo -e "${BLUE}Pods:${NC}"
kubectl get pods --no-headers 2>/dev/null | sed 's/^/  /' || echo "  No pods"

echo ""
echo -e "${BLUE}Services:${NC}"
kubectl get services --no-headers 2>/dev/null | sed 's/^/  /' || echo "  No services"

# ==========================================
# Done
# ==========================================
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                    ${GREEN}${BOLD}✓ DEPLOYMENT COMPLETE!${NC}${CYAN}                        ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Detect OS for specific access instructions
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo -e "${YELLOW}NOTE: On macOS (Docker driver), the Minikube IP is not directly reachable.${NC}"
    echo "To access the application, run this command in a NEW terminal:"
    echo ""
    echo -e "  ${BOLD}minikube service ingress-nginx-controller -n ingress-nginx${NC}"
    echo ""
    echo "Or use port-forwarding:"
    echo "  kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80"
    echo "  Then access: http://localhost:8080/"
else
    echo -e "  ${YELLOW}Frontend:${NC}    ${BOLD}http://${MINIKUBE_IP}:32080/${NC}"
    echo -e "  ${YELLOW}API:${NC}         ${BOLD}http://${MINIKUBE_IP}:32080/api/dashboard${NC}"
    
    if [ "$DEPLOY_MONITORING" = true ]; then
        GRAFANA_PASS=$(kubectl get secret grafana-secrets -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 --decode || echo "admin123")
        
        echo ""
        echo -e "  ${YELLOW}Monitoring (via Ingress):${NC}"
        echo -e "    ${YELLOW}Prometheus:${NC} ${BOLD}http://${MINIKUBE_IP}:32080/prometheus/${NC}"
        echo -e "    ${YELLOW}Grafana:${NC}    ${BOLD}http://${MINIKUBE_IP}:32080/grafana/${NC}"
        echo -e "    ${YELLOW}User/Pass:${NC}  admin / ${GRAFANA_PASS}"
    fi
fi
echo ""
echo -e "${YELLOW}NOTE:${NC} On macOS, you must run this to access the URLs above:"
echo -e "      ${BOLD}minikube service ingress-nginx-controller -n ingress-nginx --url${NC}"
echo -e "      (Or keep the tunnel running: ${BOLD}minikube tunnel${NC})"
echo -e "      (Or use port-forwarding on port 80: ${BOLD}sudo kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 80:80${NC})"
echo ""
