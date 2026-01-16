# Production Environment Configuration
# This file orchestrates the infrastructure modules for the prod environment

terraform {
  required_version = ">= 1.0.0"

  backend "s3" {
    bucket         = "terraform-state-aks-data-structures"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

# Provider configuration for production
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "prod"
      Project     = var.project_name
      ManagedBy   = "terraform"
    }
  }
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context
  }
}

provider "kubectl" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

# Local variables
locals {
  environment = "prod"
  k8s_dir     = "${path.module}/../../../kubernetes"
}

# Networking Module
module "networking" {
  source = "../../modules/networking"

  environment         = local.environment
  project_name        = var.project_name
  vpc_cidr            = var.vpc_cidr
  availability_zones  = var.availability_zones
  public_subnet_cidrs = var.public_subnet_cidrs
}

# Kubernetes Module
module "kubernetes" {
  source = "../../modules/kubernetes"

  environment    = local.environment
  project_name   = var.project_name
  k8s_dir        = local.k8s_dir
  namespace      = var.namespace
  
  # Application configuration - Higher for production
  frontend_replicas = var.frontend_replicas
  backend_replicas  = var.backend_replicas
  
  # Image configuration
  frontend_image = var.frontend_image
  backend_image  = var.backend_image

  depends_on = [module.networking]
}

# Database Module - Enabled for production
module "database" {
  source = "../../modules/database"
  count  = var.enable_rds ? 1 : 0

  environment       = local.environment
  project_name      = var.project_name
  vpc_id            = module.networking.vpc_id
  subnet_ids        = module.networking.private_subnet_ids
  db_instance_class = var.db_instance_class
  db_name           = var.db_name
  db_username       = var.db_username

  depends_on = [module.networking]
}

# Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "kubernetes_namespace" {
  description = "Kubernetes namespace"
  value       = module.kubernetes.namespace
}

output "database_endpoint" {
  description = "Database endpoint"
  value       = var.enable_rds ? module.database[0].endpoint : null
}
