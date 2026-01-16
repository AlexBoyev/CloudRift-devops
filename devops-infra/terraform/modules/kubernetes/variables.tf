# Kubernetes Module Variables

variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "k8s_dir" {
  description = "Path to Kubernetes manifests directory"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "default"
}

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
