#!/bin/bash

# DevOps Infrastructure Destroy Script
# Complete cleanup script for AKS Data Structures Platform
# This script removes all Kubernetes resources and cleans up the environment

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

# Default configuration
ENVIRONMENT="${1:-dev}"
REMOVE_IMAGES="${2:-true}"
COMMUNICATION_LOG () { echo "$@"; }
BUILD_LOGS_DIR="/tmp/devops_cleanup_logs"
CLEAN_ALL="${3:-false}"

echo -e "${RED}========================================${NC}"
echo -e "${RED}  AKS Data Structures - DevOps Cleanup${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo "Environment: $ENVIRONMENT"
echo "Remove Docker Images: $REMOVE_IMAGES"
echo "Clean All Resources: $CLEAN_ALL"
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

print_header() {
    echo ""
    echo -e "${RED}=== $1 ===${NC}"
    echo ""
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if we're on EC2
if [ -f /etc/cloud/cloud-init.disabled ] || [ -d /home/ubuntu ]; then
    EC2_ENV=true
    print_status "Detected EC2 environment"
else
    EC2_ENV=false
fi

if [ "$EC2_ENV" = true ] && [ -z "${KUBECONFIG:-}" ] && [ -f /home/ubuntu/.kube/config ]; then
    export KUBECONFIG=/home/ubuntu/.kube/config
fi

# Warning and confirmation
print_header "⚠️  WARNING: This will delete all deployed resources!"

echo "This script will permanently delete:"
echo "  - All Kubernetes deployments, services, and ingress"
echo "  - All ConfigMaps and Secrets"
echo "  - Monitoring stack (Prometheus, Grafana)"
echo "  - Docker images (if requested)"
echo "  - Port-forward services"
echo "  - Log files and temporary data"
echo ""

if [ "$CLEAN_ALL" = "true" ]; then
    echo -e "${RED}CLEAN ALL MODE: This will also remove:${NC}"
    echo "  - All Docker images and containers"
    echo "  - Minikube cluster (if using Minikube)"
    echo "  - Kubernetes configuration"
    echo "  - All generated files"
    echo ""
fi

read -p "Are you sure you want to continue? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^yes$ ]]; then
    print_warning "Cleanup cancelled by user"
    exit 0
fi

# Stop port-forward services
print_header "Step 1: Stopping Port-Forward Services"

if [ "$EC2_ENV" = true ]; then
    # Stop systemd service
    if sudo systemctl is-active --quiet k8s-port-forward.service 2>/dev/null; then
        echo "Stopping port-forward systemd service..."
        sudo systemctl stop k8s-port-forward.service
        sudo systemctl disable k8s-port-forward.service
        print_status "Port-forward service stopped and disabled"
    fi
    
    # Remove service file
    if [ -f /etc/systemd/system/k8s-port-forward.service ]; then
        sudo rm -f /etc/systemd/system/k8s-port-forward.service
        sudo systemctl daemon-reload
        print_status "Port-forward service file removed"
    fi
else
    # Kill background port-forward processes
    if [ -f /tmp/k8s-port-forward.pid ]; then
        PID=$(cat /tmp/k8s-port-forward.pid)
        if kill -0 "$PID" 2>/dev/null; then
            echo "Stopping port-forward process (PID: $PID)..."
            kill "$PID"
            print_status "Port-forward process stopped"
        fi
    fi
fi

# Remove ingress port-forward logs
if [ -f /tmp/ingress-port-forward.log ]; then
    sudo rm -f /tmp/ingress-port-forward.log 2>/dev/null || rm -f /tmp/ingress-port-forward.log 2>/dev/null || true
    print_status "Port-forward logs removed"
fi

# Delete Kubernetes resources
print_header "Step 2: Deleting Kubernetes Resources"

kubectl delete -f "$PROJECT_ROOT/kubernetes/monitoring/grafana/" --ignore-not-found=true || true
kubectl delete -f "$PROJECT_ROOT/kubernetes/monitoring/prometheus/" --ignore-not-found=true || true
kubectl delete -f "$PROJECT_ROOT/kubernetes/ingress/" --ignore-not-found=true || true
kubectl delete -f "$PROJECT_ROOT/kubernetes/ingress-controller/" --ignore-not-found=true || true
kubectl delete -f "$PROJECT_ROOT/kubernetes/data-structures/" --ignore-not-found=true || true
kubectl delete -f "$PROJECT_ROOT/kubernetes/backend/" --ignore-not-found=true || true
kubectl delete -f "$PROJECT_ROOT/kubernetes/frontend/" --ignore-not-found=true || true
kubectl delete -f "$PROJECT_ROOT/kubernetes/namespaces/" --ignore-not-found=true || true

print_status "Kubernetes resources deleted"

# Remove ConfigMaps and Secrets created by script
kubectl delete configmap grafana-dashboards --ignore-not-found=true || true
kubectl delete configmap frontend-config backend-config --ignore-not-found=true || true
kubectl delete secret backend-secrets --ignore-not-found=true || true

print_status "ConfigMaps and Secrets cleaned"

# Delete Docker images if requested
print_header "Step 3: Cleaning Docker Images"

if [ "$REMOVE_IMAGES" = "true" ]; then
    IMAGES="backend-service:latest ui-service:latest stack-service:latest linkedlist-service:latest graph-service:latest"
    
    if [ "$EC2_ENV" = true ]; then
        eval $(sudo -u ubuntu minikube docker-env) || true
        DOCKER_CMD="sudo -E -u ubuntu docker"
    else
        DOCKER_CMD="docker"
    fi
    
    for img in $IMAGES; do
        if $DOCKER_CMD images | grep -q "$img"; then
            echo "Removing image $img ..."
            $DOCKER_CMD rmi -f "$img" || true
        fi
    done
    print_status "Docker images cleaned"
else
    print_warning "Skipping Docker image cleanup"
fi

# Additional cleanup when CLEAN_ALL is true
if [ "$CLEAN_ALL" = "true" ]; then
    print_header "Step 4: Deep Clean (Clean All)"
    
    # Delete all docker containers and images
    if [ "$EC2_ENV" = true ]; then
        DOCKER_CMD="sudo -E -u ubuntu docker"
    else
        DOCKER_CMD="docker"
    fi
    
    $DOCKER_CMD container prune -f >/dev/null 2>&1 || true
    $DOCKER_CMD image prune -a -f >/dev/null 2>&1 || true
    print_status "Docker containers/images pruned"
    
    # Delete Minikube cluster
    if command_exists minikube; then
        echo "Deleting Minikube cluster..."
        if [ "$EC2_ENV" = true ]; then
            sudo -u ubuntu minikube delete || true
        else
            minikube delete || true
        fi
        print_status "Minikube deleted"
    fi
    
    # Remove kube configs
    rm -rf /home/ubuntu/.kube /home/ubuntu/.minikube 2>/dev/null || true
    rm -rf ~/.kube ~/.minikube 2>/dev/null || true
    print_status "Kubernetes local configs removed"
fi

# Clean temporary files
print_header "Step 5: Cleaning Temporary Files"

rm -f /tmp/k8s-port-forward.pid 2>/dev/null || true
rm -f /tmp/ingress-port-forward.log 2>/dev/null || true
print_status "Temporary files removed"

echo ""
echo -e "${GREEN}DevOps infrastructure cleanup completed!${NC}"

# Next steps
echo ""
echo -e "${BLUE}Next Steps:${NC}"
if [ "$CLEAN_ALL" = "true" ]; then
    echo "1. To redeploy: ./setup.sh"
    echo "2. To redeploy AWS infrastructure: cd ../aws-infrastrucutre-terraform && ./setup.sh"
else
    echo "1. To redeploy: ./setup.sh"
    echo "2. Check remaining resources with: kubectl get all"
fi

echo ""
echo -e "${BLUE}Manual Cleanup (if needed):${NC}"
echo "- Check remaining pods: kubectl get pods --all-namespaces"
echo "- Check remaining services: kubectl get services --all-namespaces"
echo "- Check Docker images: docker images | grep -E '(backend-service|ui-service|stack-service)'"
echo "- Remove specific image: docker rmi <image-name>"
