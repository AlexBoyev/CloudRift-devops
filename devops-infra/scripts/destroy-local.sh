#!/usr/bin/env bash
set -euo pipefail

# destroy-local.sh - One-click local infrastructure destroy (self-contained)
# - deletes monitoring, runs terraform destroy (local env), optional minikube stop

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_ROOT="$(dirname "$SCRIPT_DIR")"
TF_LOCAL_DIR="${DEVOPS_ROOT}/terraform/environments/local"

print_status()  { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error()   { echo -e "${RED}✗${NC} $1"; }
print_step()    { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  Local DevOps Destroy - Remove Local Infrastructure       ${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

print_step "Step 1: Basic validations"
for cmd in kubectl terraform minikube; do
  if command -v "$cmd" >/dev/null 2>&1; then
    print_status "$cmd available"
  else
    print_warning "$cmd not found; some cleanup steps may fail or be skipped"
  fi
done

read -p "This will destroy local resources. Continue? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

print_step "Step 2: Removing monitoring stack"
kubectl delete -f "${DEVOPS_ROOT}/kubernetes/monitoring/prometheus/" --ignore-not-found=true || true
kubectl delete -f "${DEVOPS_ROOT}/kubernetes/monitoring/grafana/" --ignore-not-found=true || true
kubectl delete configmap grafana-dashboards --ignore-not-found=true || true

print_step "Step 3: Destroying Terraform resources (local env)"
if [ -d "$TF_LOCAL_DIR" ]; then
  pushd "$TF_LOCAL_DIR" >/dev/null
    terraform destroy -auto-approve || print_warning "terraform destroy returned non-zero; check logs"
  popd >/dev/null
else
  print_warning "Terraform local environment not found at $TF_LOCAL_DIR"
fi

read -p "Stop Minikube cluster as well? (y/N): " stop_mk
if [[ "$stop_mk" =~ ^[Yy]$ ]]; then
  print_step "Stopping Minikube"
  minikube stop || print_warning "Minikube stop returned non-zero"
fi

print_step "Step 4: Status"
kubectl get pods 2>/dev/null || true

print_status "Local infrastructure destroy completed via destroy-local.sh"
