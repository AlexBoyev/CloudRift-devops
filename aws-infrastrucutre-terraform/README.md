# AWS Infrastructure with Terraform

Complete AWS infrastructure setup using Terraform for VPC, EC2, and Security Groups.

## 📁 Directory Structure

```
terraform/
├── environments/
│   ├── dev/
│   │   ├── backend.tf              # Provider & local backend configuration
│   │   ├── main.tf                 # Infrastructure module calls
│   │   ├── variables.tf            # Variable definitions
│   │   ├── terraform.tfvars        # Dev environment values
│   │   ├── credentials.auto.tfvars # AWS credentials (gitignored)
│   │   └── outputs.tf              # Output definitions
│   └── prod/
│       ├── backend.tf
│       ├── main.tf
│       ├── variables.tf
│       ├── terraform.tfvars
│       └── outputs.tf
├── modules/
│   ├── vpc/
│   │   ├── main.tf                 # VPC, subnets, IGW, route tables
│   │   ├── output.tf               # VPC outputs
│   │   └── variable.tf             # VPC variables
│   ├── ec2/
│   │   ├── main.tf                 # EC2 instance, key pair
│   │   ├── outputs.tf              # EC2 outputs
│   │   ├── variables.tf            # EC2 variables
│   │   └── keys/                   # SSH keys (auto-generated)
│   └── sg/
│       ├── main.tf                 # Security groups
│       ├── output.tf               # SG outputs
│       └── variables.tf            # SG variables
├── .gitignore                      # Git ignore rules
├── README.md                       # This file
├── setup.sh                        # Automated deployment script
└── destroy.sh                      # Automated cleanup script
```

## 🏗️ Infrastructure Resources

### VPC & Networking
- **1 VPC** (172.20.0.0/16)
- **3 Public Subnets** (us-east-1a, us-east-1b, us-east-1c)
- **3 Private Subnets** (us-east-1a, us-east-1b, us-east-1c)
- **1 Internet Gateway**
- **2 Route Tables** (public & private)
- **6 Route Table Associations**

### Security
- **1 Security Group** (ec2-stack-sg)
  - Port 22 (SSH)
  - Port 80 (HTTP)
  - Port 443 (HTTPS)
  - Port 5000 (Custom)
  - Port 8080 (Custom)
  - Port 32080 (Custom)
  - All ports open to 0.0.0.0/0 and ::/0

### Compute
- **1 EC2 Instance** (t2.micro, Ubuntu)
- **1 SSH Key Pair** (auto-generated)

**Total Resources: 23**

### EC2 Bootstrap & Jenkins
- The EC2 module includes a `null_resource.bootstrap` that copies and runs `modules/ec2/bootstrap.sh`.
- Bootstrap installs prerequisites (Docker, kubectl, minikube, Terraform, AWS CLI v2, Java 17, Jenkins).
- Jenkins is configured to use Java 17, restarted, and the script waits briefly to print:
  - Jenkins admin password (`/var/lib/jenkins/secrets/initialAdminPassword`)
  - Jenkins URL using the detected public IP (`http://<public_ip>:8080/`)
- Root volume is gp3, default 30GB (override `root_volume_size` variable if needed).

## 🚀 Quick Start

### Prerequisites
- AWS Account with credentials
- Terraform >= 1.0 installed
- SSH client

### Option 1: Automated Setup (Recommended)

```bash
cd terraform
chmod +x setup.sh
./setup.sh
```

### Option 2: Manual Setup

#### Step 1: Configure AWS Credentials

Edit `environments/dev/credentials.auto.tfvars`:
```hcl
aws_access_key = "YOUR_AWS_ACCESS_KEY_ID"
aws_secret_key = "YOUR_AWS_SECRET_ACCESS_KEY"
```

#### Step 2: Navigate to Dev Environment

```bash
cd aws-infrastrucutre-terraform/environments/dev
```

#### Step 3: Initialize Terraform

```bash
terraform init
```

This will:
- Initialize the local backend
- Download required providers (AWS ~> 4.0)
- Initialize modules (vpc, ec2, sg)

#### Step 4: Validate Configuration

```bash
terraform validate
```

Expected output: `Success! The configuration is valid.`

#### Step 5: Format Code (Optional)

```bash
terraform fmt -recursive
```

#### Step 6: Plan Infrastructure

```bash
terraform plan
```

This shows what resources will be created (23 resources).

#### Step 7: Apply Infrastructure

```bash
terraform apply
```

Or auto-approve:
```bash
terraform apply -auto-approve
```

#### Step 8: View Outputs

```bash
terraform output
```

Expected outputs:
```
ec2_instance_id   = "i-xxxxxxxxxxxxx"
ec2_private_ip    = "172.20.x.x"
ec2_public_ip     = "x.x.x.x"
security_group_id = "sg-xxxxxxxxxxxxx"
vpc_id            = "vpc-xxxxxxxxxxxxx"
```

## 🔐 SSH Access to EC2

### Get EC2 Public IP

```bash
terraform output ec2_public_ip
```

### Connect via SSH

```bash
ssh -i ../../modules/ec2/keys/stack_key.pem ubuntu@$(terraform output -raw ec2_public_ip)
```

Or directly:
```bash
ssh -i ../../modules/ec2/keys/stack_key.pem ubuntu@<PUBLIC_IP>
```

**Note:** The SSH key is auto-generated and saved in `modules/ec2/keys/`

## 📋 Terraform Commands Reference

### Initialization & Setup
```bash
terraform init              # Initialize working directory
terraform init -upgrade     # Upgrade providers to latest version
```

### Planning & Validation
```bash
terraform validate          # Validate configuration syntax
terraform fmt              # Format code to canonical style
terraform fmt -recursive   # Format all .tf files recursively
terraform plan             # Preview changes
terraform plan -out=plan   # Save plan to file
```

### Applying Changes
```bash
terraform apply                    # Apply changes (with confirmation)
terraform apply -auto-approve      # Apply without confirmation
terraform apply plan               # Apply saved plan
terraform apply -var="key=value"   # Apply with variable override
```

### Viewing State & Outputs
```bash
terraform show                     # Show current state
terraform output                   # Show all outputs
terraform output ec2_public_ip     # Show specific output
terraform output -raw ec2_public_ip # Show output without quotes
terraform state list               # List all resources in state
terraform state show <resource>    # Show specific resource details
```

### Refreshing & Importing
```bash
terraform refresh          # Update state from real infrastructure
terraform import          # Import existing infrastructure
```

### Destroying Infrastructure
```bash
terraform destroy                  # Destroy all resources (with confirmation)
terraform destroy -auto-approve    # Destroy without confirmation
terraform destroy -target=<resource> # Destroy specific resource
```

### Workspace Management
```bash
terraform workspace list           # List workspaces
terraform workspace new <name>     # Create new workspace
terraform workspace select <name>  # Switch workspace
```

### Other Useful Commands
```bash
terraform graph                    # Generate dependency graph
terraform providers                # Show required providers
terraform version                  # Show Terraform version
terraform console                  # Interactive console
```

## 🔄 Complete Deployment Sequence

```bash
# 1. Navigate to environment
cd aws-infrastrucutre-terraform/environments/dev

# 2. Initialize
terraform init

# 3. Validate
terraform validate

# 4. Format (optional)
terraform fmt -recursive

# 5. Plan
terraform plan

# 6. Apply
terraform apply -auto-approve

# 7. View outputs
terraform output

# 8. SSH to EC2
ssh -i ../../modules/ec2/keys/stack_key.pem ubuntu@$(terraform output -raw ec2_public_ip)
```

## 🧹 Cleanup

### Option 1: Automated Cleanup

```bash
cd aws-infrastrucutre-terraform
chmod +x destroy.sh
./destroy.sh
```

### Option 2: Manual Cleanup

```bash
cd aws-infrastrucutre-terraform/environments/dev
terraform destroy -auto-approve
```

## 📝 Configuration Files

### Backend Configuration (`backend.tf`)
- Uses **local backend** for state management
- State file: `terraform.tfstate` (in environment directory)
- Provider: AWS (~> 4.0)

### Variables (`terraform.tfvars`)
- Region: us-east-1
- Environment: dev
- Project: stack
- VPC CIDR: 172.20.0.0/16
- Instance Type: t2.micro
- AMI: Ubuntu (ami-0ecb62995f68bb549)

### Credentials (`credentials.auto.tfvars`)
- AWS Access Key ID
- AWS Secret Access Key
- **Gitignored for security**

## 🔒 Security Notes

1. **SSH Keys**: Auto-generated and stored in `modules/ec2/keys/`
2. **Credentials**: Never commit `credentials.auto.tfvars` to git
3. **State Files**: Contains sensitive data, keep secure
4. **Security Groups**: Currently open to 0.0.0.0/0 - restrict in production

## 🐛 Troubleshooting

### Issue: Terraform init fails
**Solution**: Check AWS credentials and internet connection

### Issue: SSH connection refused
**Solution**: 
- Verify security group allows port 22
- Check EC2 instance is running
- Use correct username (`ubuntu` for Ubuntu AMI)

### Issue: Permission denied (publickey)
**Solution**:
```bash
chmod 400 ../../modules/ec2/keys/stack_key.pem
```

### Issue: Resource already exists
**Solution**:
```bash
terraform import <resource_type>.<name> <resource_id>
```

## 📚 Additional Resources

- [Terraform Documentation](https://www.terraform.io/docs)
- [AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)

## 🎯 Next Steps

1. ✅ Infrastructure deployed
2. 🔧 Configure EC2 instance (install software, deploy apps)
3. 🌐 Set up domain/DNS (optional)
4. 📊 Add monitoring and logging
5. 🔐 Implement proper security hardening
6. 📦 Add additional resources as needed

## 📞 Support

For issues or questions:
1. Check the troubleshooting section
2. Review Terraform documentation
3. Check AWS service status
4. Review CloudWatch logs

---

**Created**: December 2025  
**Terraform Version**: >= 1.0  
**AWS Provider Version**: ~> 4.0  
**Backend**: Local
