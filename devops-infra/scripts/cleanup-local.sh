#!/bin/bash
# cleanup-local.sh - Cleanup Local Deployment
# Destroys all resources deployed by run-local.sh

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_ROOT="$(dirname "$SCRIPT_DIR")"
TF_LOCAL_DIR="${DEVOPS_ROOT}/terraform/environments/local"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          AKS Data Structures - Local Cleanup                  ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Confirm
read -p "This will destroy all deployed resources. Continue? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo -e "${YELLOW}Removing Monitoring stack...${NC}"
kubectl delete -f "${DEVOPS_ROOT}/kubernetes/monitoring/prometheus/" --ignore-not-found=true
kubectl delete -f "${DEVOPS_ROOT}/kubernetes/monitoring/grafana/" --ignore-not-found=true
kubectl delete configmap grafana-dashboards --ignore-not-found=true

echo ""
echo -e "${YELLOW}Destroying Terraform resources...${NC}"

cd "$TF_LOCAL_DIR"
terraform destroy -auto-approve

echo ""
read -p "Stop Minikube cluster as well? (y/N): " stop_mk
if [[ "$stop_mk" =~ ^[Yy]$ ]]; then
    echo "Stopping Minikube..."
    minikube stop
fi

echo ""
echo -e "${GREEN}✓ Cleanup complete!${NC}"
echo ""
echo "Remaining pods:"
kubectl get pods 2>/dev/null || echo "No pods found"
