#!/bin/bash
# setup.sh - Environment Setup Script
# Sets up the development environment with all required dependencies

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

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}  AKS Data Structures - Environment Setup${NC}"
echo -e "${BLUE}==========================================${NC}"
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

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"
echo ""

# Check Docker
if command_exists docker; then
    DOCKER_VERSION=$(docker --version)
    print_status "Docker installed: $DOCKER_VERSION"
else
    print_error "Docker is not installed. Please install Docker first."
    exit 1
fi

# Check kubectl
if command_exists kubectl; then
    KUBECTL_VERSION=$(kubectl version --client --short 2>/dev/null || kubectl version --client)
    print_status "kubectl installed: $KUBECTL_VERSION"
else
    print_warning "kubectl is not installed. Installing..."
    # Install kubectl based on OS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install kubectl
    else
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
    fi
    print_status "kubectl installed"
fi

# Check Minikube (for local development)
if command_exists minikube; then
    MINIKUBE_VERSION=$(minikube version --short 2>/dev/null || minikube version)
    print_status "Minikube installed: $MINIKUBE_VERSION"
else
    print_warning "Minikube is not installed (optional for local development)"
fi

# Check Terraform
if command_exists terraform; then
    TERRAFORM_VERSION=$(terraform version | head -n1)
    print_status "Terraform installed: $TERRAFORM_VERSION"
else
    print_warning "Terraform is not installed. Installing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew tap hashicorp/tap
        brew install hashicorp/tap/terraform
    else
        print_error "Please install Terraform manually: https://www.terraform.io/downloads"
    fi
fi

# Check Helm
if command_exists helm; then
    HELM_VERSION=$(helm version --short)
    print_status "Helm installed: $HELM_VERSION"
else
    print_warning "Helm is not installed. Installing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install helm
    else
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
    print_status "Helm installed"
fi

echo ""
echo -e "${BLUE}Setting up Kubernetes context...${NC}"

# Check if Minikube is running
if command_exists minikube; then
    if minikube status >/dev/null 2>&1; then
        print_status "Minikube is running"
        kubectl config use-context minikube
        print_status "kubectl context set to minikube"
    else
        print_warning "Minikube is not running. Starting..."
        minikube start
        print_status "Minikube started"
    fi
fi

# Verify kubectl connection
echo ""
echo -e "${BLUE}Verifying Kubernetes connection...${NC}"
if kubectl cluster-info >/dev/null 2>&1; then
    print_status "Connected to Kubernetes cluster"
    kubectl cluster-info | head -2
else
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

# Initialize Terraform
echo ""
echo -e "${BLUE}Initializing Terraform (dev environment)...${NC}"
if [ -d "$PROJECT_ROOT/devops-infra/terraform/environments/dev" ]; then
    cd "$PROJECT_ROOT/devops-infra/terraform/environments/dev"
    terraform init -backend=false >/dev/null 2>&1 || true
    print_status "Terraform initialized for dev environment"
else
    print_warning "Dev environment directory not found"
fi

# Create necessary directories
echo ""
echo -e "${BLUE}Creating required directories...${NC}"
mkdir -p "$PROJECT_ROOT/.terraform"
mkdir -p "$PROJECT_ROOT/logs"
print_status "Directories created"

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Run './scripts/deploy.sh' to deploy the application"
echo "  2. Check 'kubectl get pods' to verify deployments"
echo "  3. Access the application via the ingress"
echo ""
