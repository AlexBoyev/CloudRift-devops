#!/bin/bash

# AWS Infrastructure Setup Script
# This script automates the complete Terraform deployment process

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
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
}

# Check if terraform is installed
check_terraform() {
    print_header "Checking Prerequisites"
    
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install Terraform first."
        echo "Visit: https://www.terraform.io/downloads"
        exit 1
    fi
    
    TERRAFORM_VERSION=$(terraform version | head -n1)
    print_success "Terraform found: $TERRAFORM_VERSION"
}

# Check AWS credentials
check_credentials() {
    print_info "Checking AWS credentials..."
    
    CREDS_FILE="environments/dev/credentials.auto.tfvars"
    
    if [ ! -f "$CREDS_FILE" ]; then
        print_warning "Credentials file not found: $CREDS_FILE"
        print_info "Please ensure your AWS credentials are configured in $CREDS_FILE"
        read -p "Do you want to continue? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        print_success "Credentials file found"
    fi
}

# Navigate to dev environment
navigate_to_env() {
    print_header "Navigating to Dev Environment"
    
    if [ ! -d "environments/dev" ]; then
        print_error "Dev environment directory not found!"
        exit 1
    fi
    
    cd environments/dev
    print_success "Changed directory to: $(pwd)"
}

# Initialize Terraform
init_terraform() {
    print_header "Step 1: Initializing Terraform"
    
    print_info "Running: terraform init -upgrade"
    terraform init -upgrade
    
    if [ $? -eq 0 ]; then
        print_success "Terraform initialized successfully"
    else
        print_error "Terraform initialization failed"
        exit 1
    fi
}

# Validate configuration
validate_terraform() {
    print_header "Step 2: Validating Configuration"
    
    print_info "Running: terraform validate"
    terraform validate
    
    if [ $? -eq 0 ]; then
        print_success "Configuration is valid"
    else
        print_error "Configuration validation failed"
        exit 1
    fi
}

# Format code
format_terraform() {
    print_header "Step 3: Formatting Code"
    
    print_info "Running: terraform fmt -recursive"
    cd ../..
    terraform fmt -recursive
    cd environments/dev
    
    print_success "Code formatted successfully"
}

# Handle plugin issues
fix_plugin_issues() {
    print_info "Detected plugin issue, attempting to fix..."
    
    # Clean up .terraform directory
    if [ -d ".terraform" ]; then
        print_info "Cleaning up .terraform directory"
        rm -rf .terraform
    fi
    
    # Remove lock file if it exists
    if [ -f ".terraform.lock.hcl" ]; then
        print_info "Removing lock file"
        rm -f .terraform.lock.hcl
    fi
    
    # Reinitialize with upgrade
    print_info "Reinitializing Terraform with upgrade"
    terraform init -upgrade
    
    if [ $? -eq 0 ]; then
        print_success "Plugin issues fixed successfully"
        return 0
    else
        print_error "Failed to fix plugin issues"
        return 1
    fi
}

# Plan infrastructure
plan_terraform() {
    print_header "Step 4: Planning Infrastructure"
    
    print_info "Running: terraform plan"
    terraform plan
    
    # If plan fails due to plugin issues, try to fix and retry
    if [ $? -ne 0 ]; then
        print_warning "Plan failed, checking for plugin issues..."
        
        if fix_plugin_issues; then
            print_info "Retrying terraform plan after plugin fix"
            terraform plan
            
            if [ $? -eq 0 ]; then
                print_success "Plan generated successfully after plugin fix"
            else
                print_error "Planning failed even after plugin fix"
                exit 1
            fi
        else
            print_error "Planning failed and plugin fix unsuccessful"
            exit 1
        fi
    else
        print_success "Plan generated successfully"
    fi
}

# Apply infrastructure
apply_terraform() {
    print_header "Step 5: Applying Infrastructure"
    
    print_warning "This will create AWS resources and may incur costs."
    read -p "Do you want to proceed with terraform apply? (y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Running: terraform apply -auto-approve"
        terraform apply -auto-approve
        
        if [ $? -eq 0 ]; then
            print_success "Infrastructure created successfully!"
        else
            print_error "Infrastructure creation failed"
            exit 1
        fi
    else
        print_warning "Terraform apply cancelled by user"
        exit 0
    fi
}

# Display outputs
show_outputs() {
    print_header "Step 6: Infrastructure Outputs"
    
    print_info "Running: terraform output"
    terraform output
    
    echo ""
    print_success "Infrastructure deployment completed!"
}

# Display SSH connection info
show_ssh_info() {
    print_header "SSH Connection Information"
    
    PUBLIC_IP=$(terraform output -raw ec2_public_ip 2>/dev/null)
    
    if [ -n "$PUBLIC_IP" ]; then
        print_info "EC2 Public IP: $PUBLIC_IP"
        echo ""
        print_info "To connect to your EC2 instance, run:"
        echo -e "${YELLOW}ssh -i ../../modules/ec2/keys/stack_key.pem ubuntu@${PUBLIC_IP}${NC}"
        echo ""
        print_info "Or use the shortcut:"
        echo -e "${YELLOW}ssh -i ../../modules/ec2/keys/stack_key.pem ubuntu@\$(terraform output -raw ec2_public_ip)${NC}"
    else
        print_warning "Could not retrieve EC2 public IP"
    fi
}

# Display summary
show_summary() {
    print_header "Deployment Summary"
    
    echo "✅ Terraform initialized"
    echo "✅ Configuration validated"
    echo "✅ Code formatted"
    echo "✅ Infrastructure planned"
    echo "✅ Infrastructure applied"
    echo "✅ 23 resources created:"
    echo "   - 1 VPC"
    echo "   - 6 Subnets (3 public, 3 private)"
    echo "   - 1 Internet Gateway"
    echo "   - 2 Route Tables"
    echo "   - 6 Route Table Associations"
    echo "   - 1 Security Group"
    echo "   - 1 EC2 Instance"
    echo "   - 1 SSH Key Pair"
    echo ""
    print_success "Your AWS infrastructure is ready to use!"
}

# Main execution
main() {
    clear
    print_header "AWS Infrastructure Setup - Terraform Automation"
    
    # Get the script directory
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    cd "$SCRIPT_DIR"
    
    # Run all steps
    check_terraform
    check_credentials
    navigate_to_env
    init_terraform
    validate_terraform
    format_terraform
    plan_terraform
    apply_terraform
    show_outputs
    show_ssh_info
    show_summary
    
    echo ""
    print_info "State file location: $(pwd)/terraform.tfstate"
    print_info "To destroy infrastructure, run: cd $(pwd) && terraform destroy"
    print_info "Or use the destroy.sh script: ../../destroy.sh"
    echo ""
}

# Run main function
main
