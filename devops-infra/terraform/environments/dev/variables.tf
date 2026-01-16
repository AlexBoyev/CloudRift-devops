# Development Environment Variables
# Define all configurable variables for the dev environment

# General Configuration
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "aks-data-structures"
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# Kubernetes Configuration
variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Kubernetes context to use"
  type        = string
  default     = "minikube"
}

variable "namespace" {
  description = "Kubernetes namespace for application"
  type        = string
  default     = "default"
}

# Networking Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

# Application Configuration
variable "frontend_replicas" {
  description = "Number of frontend replicas"
  type        = number
  default     = 2
}

variable "backend_replicas" {
  description = "Number of backend replicas"
  type        = number
  default     = 2
}

variable "frontend_image" {
  description = "Docker image for frontend"
  type        = string
  default     = "ui-service:latest"
}

variable "backend_image" {
  description = "Docker image for backend"
  type        = string
  default     = "backend-service:latest"
}

# Database Configuration
variable "enable_rds" {
  description = "Enable RDS database"
  type        = bool
  default     = false
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "admin"
}
