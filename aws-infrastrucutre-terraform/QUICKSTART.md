# 🚀 Quick Start Guide

Deploy your AWS infrastructure in **3 simple steps**.

## Prerequisites

- AWS Account with Access Key and Secret Key
- Terraform installed ([Download here](https://www.terraform.io/downloads))

## Step 1: Configure AWS Credentials

Edit the file: `environments/dev/credentials.auto.tfvars`

```hcl
aws_access_key = "YOUR_AWS_ACCESS_KEY_ID"
aws_secret_key = "YOUR_AWS_SECRET_ACCESS_KEY"
```

## Step 2: Run Setup Script

```bash
cd aws-infrastrucutre-terraform
./setup.sh
```

**That's it!** The script will automatically:
- Initialize Terraform
- Validate configuration
- Create all infrastructure (24 resources)
- Display connection details

## Step 3: Connect to EC2

After deployment completes, connect via SSH:

```bash
cd environments/dev
ssh -i ../../modules/ec2/keys/stack_key.pem ubuntu@$(terraform output -raw ec2_public_ip)
```

---

## 📋 What Gets Created?

- **1 VPC** with 6 subnets (3 public, 3 private)
- **1 EC2 Instance** (Ubuntu, t2.micro)
- **1 Security Group** with ports: 22, 80, 443, 5000, 8080, 32080
- **Networking** (Internet Gateway, Route Tables)

**Total: 23 AWS Resources**

---

## 🧹 Cleanup

To destroy all resources:

```bash
cd aws-infrastrucutre-terraform
./destroy.sh
```

---

## 📖 Need More Details?

See the full [README.md](README.md) for:
- Manual deployment steps
- Complete Terraform commands reference
- Troubleshooting guide
- Security notes

---

