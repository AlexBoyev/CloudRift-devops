#!/bin/bash

# AWS Infrastructure Destroy Script (NO CONFIRMATION)
# If you run this script, it will destroy the Terraform-managed infrastructure immediately.

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to print section headers
print_header() {
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}$1${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
}

# Check if terraform is installed
check_terraform() {
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed."
        exit 1
    fi

    TERRAFORM_VERSION=$(terraform version | head -n1)
    print_info "Terraform found: $TERRAFORM_VERSION"
}

# Navigate to dev environment
navigate_to_env() {
    print_info "Navigating to dev environment..."

    if [ ! -d "environments/dev" ]; then
        print_error "Dev environment directory not found!"
        exit 1
    fi

    cd environments/dev
    print_success "Changed directory to: $(pwd)"
}

# Check if state file exists
check_state() {
    if [ ! -f "terraform.tfstate" ] && [ ! -d ".terraform" ] && [ ! -f ".terraform.lock.hcl" ]; then
        print_warning "No local Terraform state/cache found in environments/dev."
        print_info "If you use a remote backend, this may be normal."
        print_info "Continuing anyway..."
    else
        print_info "Checking resources in state (if available)..."
        RESOURCE_COUNT=$(terraform state list 2>/dev/null | wc -l || true)
        print_info "Found $RESOURCE_COUNT resources in state"
    fi
}

# Show what will be destroyed (optional but useful)
show_plan() {
    print_header "Destroy Plan"

    print_info "Running: terraform plan -destroy"
    terraform plan -destroy
}

# Destroy infrastructure (NO CONFIRMATION)
destroy_infrastructure() {
    print_header "Destroying Infrastructure"

    print_warning "Destroy is starting now (no confirmation prompt)."
    print_info "Running: terraform destroy -auto-approve"
    terraform destroy -auto-approve

    print_success "Destroy command completed."
}

# Clean up local files
cleanup_local_files() {
    print_header "Cleaning Up Local Files"

    print_info "Removing SSH keys..."
    if [ -d "../../modules/ec2/keys" ]; then
        rm -f ../../modules/ec2/keys/stack_key.pem
        rm -f ../../modules/ec2/keys/stack_key.pub
        print_success "SSH keys removed"
    else
        print_info "SSH keys directory not found; skipping."
    fi

    print_info "Removing local Terraform files/cache..."
    rm -f terraform.tfstate || true
    rm -f terraform.tfstate.backup || true
    rm -f .terraform.lock.hcl || true
    rm -rf .terraform || true

    print_success "Local files cleaned up"
}

# Display summary
show_summary() {
    print_header "Cleanup Summary"

    echo "✅ Destroy command executed"
    echo "✅ Local state/cache removed (if existed)"
    echo "✅ SSH keys deleted (if existed)"
    echo ""
    print_success "Cleanup completed!"
    echo ""
    print_info "To redeploy infrastructure, run: ../../setup.sh"
}

# Main execution
main() {
    clear
    print_header "AWS Infrastructure Cleanup - Terraform Destroy (NO CONFIRMATION)"

    # Get the script directory
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    cd "$SCRIPT_DIR"

    check_terraform
    navigate_to_env
    check_state
    show_plan
    destroy_infrastructure
    cleanup_local_files
    show_summary
}

main
