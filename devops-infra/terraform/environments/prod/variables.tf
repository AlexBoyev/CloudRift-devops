# Production Environment Variables
# Define all configurable variables for the prod environment

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
}

variable "namespace" {
  description = "Kubernetes namespace for application"
  type        = string
  default     = "production"
}

# Networking Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
}

# Application Configuration - Higher defaults for production
variable "frontend_replicas" {
  description = "Number of frontend replicas"
  type        = number
  default     = 3
}

variable "backend_replicas" {
  description = "Number of backend replicas"
  type        = number
  default     = 3
}

variable "frontend_image" {
  description = "Docker image for frontend"
  type        = string
}

variable "backend_image" {
  description = "Docker image for backend"
  type        = string
}

# Database Configuration - Enabled by default for production
variable "enable_rds" {
  description = "Enable RDS database"
  type        = bool
  default     = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.small"
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
