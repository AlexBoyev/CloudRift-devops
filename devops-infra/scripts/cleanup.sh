#!/bin/bash
# cleanup.sh - Cleanup/Teardown Script
# Removes all deployed resources

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEVOPS_INFRA="$PROJECT_ROOT/devops-infra"

# Options
CLEANUP_MONITORING="${1:-false}"
CLEANUP_TERRAFORM="${2:-false}"
FORCE="${3:-false}"

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}  AKS Data Structures - Cleanup${NC}"
echo -e "${BLUE}==========================================${NC}"
echo ""
echo "Cleanup Monitoring: $CLEANUP_MONITORING"
echo "Cleanup Terraform: $CLEANUP_TERRAFORM"
echo ""

# Function to print status
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Confirm cleanup
if [ "$FORCE" != "true" ]; then
    echo -e "${YELLOW}Warning: This will delete all deployed resources.${NC}"
    read -p "Are you sure you want to continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
    echo ""
fi

# Check kubectl connection
echo -e "${BLUE}Verifying Kubernetes connection...${NC}"
if ! kubectl cluster-info >/dev/null 2>&1; then
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi
print_status "Connected to Kubernetes cluster"
echo ""

# Delete Helm releases
echo -e "${BLUE}Step 1: Cleaning up Helm releases...${NC}"
helm uninstall frontend 2>/dev/null && print_status "Frontend Helm release deleted" || print_warning "No frontend Helm release found"
helm uninstall backend 2>/dev/null && print_status "Backend Helm release deleted" || print_warning "No backend Helm release found"
echo ""

# Delete Kubernetes resources
echo -e "${BLUE}Step 2: Cleaning up Kubernetes resources...${NC}"

# Delete ingress
echo "Deleting ingress..."
kubectl delete -f "$DEVOPS_INFRA/kubernetes/ingress/" 2>/dev/null || true
print_status "Ingress deleted"

# Delete frontend
echo "Deleting frontend..."
kubectl delete -f "$DEVOPS_INFRA/kubernetes/frontend/" 2>/dev/null || true
print_status "Frontend deleted"

# Delete backend
echo "Deleting backend..."
kubectl delete -f "$DEVOPS_INFRA/kubernetes/backend/" 2>/dev/null || true
print_status "Backend deleted"

# Delete data structure services (from original k8s folder)
if [ -d "$PROJECT_ROOT/k8s" ]; then
    echo "Deleting data structure services..."
    for file in stack.yaml graph.yaml linkedlist.yaml; do
        if [ -f "$PROJECT_ROOT/k8s/$file" ]; then
            kubectl delete -f "$PROJECT_ROOT/k8s/$file" 2>/dev/null || true
        fi
    done
    print_status "Data structure services deleted"
fi

# Delete database resources
echo "Deleting database resources..."
kubectl delete -f "$DEVOPS_INFRA/kubernetes/database/" 2>/dev/null || true
print_status "Database resources deleted"

# Delete NGINX ingress controller
if [ -f "$PROJECT_ROOT/k8s/nginx-ingress-controller.yaml" ]; then
    echo "Deleting NGINX ingress controller..."
    kubectl delete -f "$PROJECT_ROOT/k8s/nginx-ingress-controller.yaml" 2>/dev/null || true
    print_status "NGINX ingress controller deleted"
fi

echo ""

# Delete monitoring stack
if [ "$CLEANUP_MONITORING" = "true" ]; then
    echo -e "${BLUE}Step 3: Cleaning up monitoring stack...${NC}"
    
    # Delete Grafana
    echo "Deleting Grafana..."
    kubectl delete -f "$DEVOPS_INFRA/kubernetes/monitoring/grafana/" 2>/dev/null || true
    kubectl delete configmap grafana-dashboards 2>/dev/null || true
    print_status "Grafana deleted"
    
    # Delete Prometheus
    echo "Deleting Prometheus..."
    kubectl delete -f "$DEVOPS_INFRA/kubernetes/monitoring/prometheus/" 2>/dev/null || true
    print_status "Prometheus deleted"
    
    echo ""
fi

# Delete namespaces (optional, be careful with this)
echo -e "${BLUE}Step 4: Cleaning up namespaces...${NC}"
# kubectl delete -f "$DEVOPS_INFRA/kubernetes/namespaces/" 2>/dev/null || true
print_warning "Skipping namespace deletion (uncomment if needed)"
echo ""

# Cleanup Terraform
if [ "$CLEANUP_TERRAFORM" = "true" ]; then
    echo -e "${BLUE}Step 5: Cleaning up Terraform resources...${NC}"
    
    if [ -d "$DEVOPS_INFRA/terraform/environments/dev" ]; then
        cd "$DEVOPS_INFRA/terraform/environments/dev"
        terraform destroy -auto-approve 2>/dev/null || print_warning "Terraform destroy failed"
        print_status "Terraform resources destroyed"
    fi
    
    echo ""
fi

# Clean up Docker images (optional)
echo -e "${BLUE}Step 6: Docker image cleanup (optional)...${NC}"
print_warning "Skipping Docker image cleanup. Run manually if needed:"
echo "  docker rmi backend-service:latest ui-service:latest stack-service:latest linkedlist-service:latest graph-service:latest"
echo ""

# Print remaining resources
echo -e "${BLUE}Remaining resources:${NC}"
echo ""
echo "=== Pods ==="
kubectl get pods 2>/dev/null || echo "No pods found"
echo ""
echo "=== Services ==="
kubectl get services 2>/dev/null || echo "No services found"
echo ""

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  Cleanup Complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
