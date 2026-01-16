#!/bin/bash

# AWS Infrastructure Destroy Script
# This script automates the complete Terraform infrastructure cleanup

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
    if [ ! -f "terraform.tfstate" ]; then
        print_warning "No terraform.tfstate file found."
        print_info "Infrastructure may not be deployed or already destroyed."
        read -p "Do you want to continue? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    else
        print_info "State file found. Checking resources..."
        RESOURCE_COUNT=$(terraform state list 2>/dev/null | wc -l)
        print_info "Found $RESOURCE_COUNT resources in state"
    fi
}

# Show what will be destroyed
show_plan() {
    print_header "Destroy Plan"
    
    print_info "Running: terraform plan -destroy"
    terraform plan -destroy
    
    if [ $? -ne 0 ]; then
        print_error "Failed to generate destroy plan"
        exit 1
    fi
}

# Destroy infrastructure
destroy_infrastructure() {
    print_header "Destroying Infrastructure"
    
    print_warning "⚠️  WARNING: This will PERMANENTLY DELETE all AWS resources!"
    print_warning "This includes:"
    echo "   - VPC and all subnets"
    echo "   - EC2 instance"
    echo "   - Security groups"
    echo "   - Route tables and associations"
    echo "   - Internet gateway"
    echo "   - SSH key pair"
    echo ""
    print_error "This action CANNOT be undone!"
    echo ""
    
    read -p "Are you absolutely sure you want to destroy all resources? (yes/no): " -r
    echo
    
    if [[ $REPLY == "yes" ]]; then
        print_info "Running: terraform destroy -auto-approve"
        terraform destroy -auto-approve
        
        if [ $? -eq 0 ]; then
            print_success "All infrastructure destroyed successfully!"
        else
            print_error "Infrastructure destruction failed"
            print_info "Some resources may still exist. Check AWS Console."
            exit 1
        fi
    else
        print_warning "Destroy cancelled by user"
        print_info "No resources were destroyed"
        exit 0
    fi
}

# Clean up local files
cleanup_local_files() {
    print_header "Cleaning Up Local Files"
    
    print_info "Removing SSH keys..."
    if [ -d "../../modules/ec2/keys" ]; then
        rm -f ../../modules/ec2/keys/stack_key.pem
        rm -f ../../modules/ec2/keys/stack_key.pub
        print_success "SSH keys removed"
    fi
    
    print_info "Removing Terraform files..."
    rm -f terraform.tfstate
    rm -f terraform.tfstate.backup
    rm -f .terraform.lock.hcl
    rm -rf .terraform
    
    print_success "Local files cleaned up"
}

# Display summary
show_summary() {
    print_header "Cleanup Summary"
    
    echo "✅ Infrastructure destroyed"
    echo "✅ State files removed"
    echo "✅ SSH keys deleted"
    echo "✅ Terraform cache cleaned"
    echo ""
    print_success "All resources have been cleaned up!"
    echo ""
    print_info "To redeploy infrastructure, run: ../../setup.sh"
}

# Main execution
main() {
    clear
    print_header "AWS Infrastructure Cleanup - Terraform Destroy"
    
    # Get the script directory
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    cd "$SCRIPT_DIR"
    
    # Run all steps
    check_terraform
    navigate_to_env
    check_state
    show_plan
    destroy_infrastructure
    cleanup_local_files
    show_summary
}

# Run main function
main
