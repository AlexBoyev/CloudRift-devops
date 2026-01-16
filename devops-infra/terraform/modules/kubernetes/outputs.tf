# Kubernetes Module Outputs

output "namespace" {
  description = "The Kubernetes namespace used"
  value       = local.namespace
}

output "frontend_deployment_name" {
  description = "Name of the frontend deployment"
  value       = "frontend-deployment"
}

output "backend_deployment_name" {
  description = "Name of the backend deployment"
  value       = "backend-deployment"
}

output "ingress_name" {
  description = "Name of the ingress resource"
  value       = "main-ingress"
}
