# Local Development Terraform Configuration
# Uses the NEW devops-infra structure for deployment

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

provider "kubectl" {
  config_path    = pathexpand("~/.kube/config")
  config_context = "minikube"
}

# Local variables - path to the new kubernetes directory
locals {
  # Go up 3 levels: local -> environments -> terraform -> devops-infra
  # Then into kubernetes
  k8s_root = "${path.module}/../../../kubernetes"
}

# ==========================================
# Ingress Controller (from new location)
# ==========================================
data "kubectl_file_documents" "ingress_controller" {
  content = file("${local.k8s_root}/ingress-controller/nginx-ingress-controller.yaml")
}

resource "kubectl_manifest" "ingress_controller" {
  for_each  = data.kubectl_file_documents.ingress_controller.manifests
  yaml_body = each.value
}

# ==========================================
# Frontend (from new structured folders)
# ==========================================
resource "kubectl_manifest" "frontend_deployment" {
  yaml_body  = file("${local.k8s_root}/frontend/deployment.yaml")
  depends_on = [kubectl_manifest.ingress_controller]
}

resource "kubectl_manifest" "frontend_service" {
  yaml_body  = file("${local.k8s_root}/frontend/service.yaml")
  depends_on = [kubectl_manifest.frontend_deployment]
}

# ==========================================
# Backend (from new structured folders)
# ==========================================
resource "kubectl_manifest" "backend_deployment" {
  yaml_body  = file("${local.k8s_root}/backend/deployment.yaml")
  depends_on = [kubectl_manifest.ingress_controller]
}

resource "kubectl_manifest" "backend_service" {
  yaml_body  = file("${local.k8s_root}/backend/service.yaml")
  depends_on = [kubectl_manifest.backend_deployment]
}

# ==========================================
# Data Structure Services (from migrated location)
# ==========================================
data "kubectl_file_documents" "stack" {
  content = file("${local.k8s_root}/data-structures/stack.yaml")
}

resource "kubectl_manifest" "stack" {
  for_each  = data.kubectl_file_documents.stack.manifests
  yaml_body = each.value
  depends_on = [kubectl_manifest.ingress_controller]
}

data "kubectl_file_documents" "linkedlist" {
  content = file("${local.k8s_root}/data-structures/linkedlist.yaml")
}

resource "kubectl_manifest" "linkedlist" {
  for_each  = data.kubectl_file_documents.linkedlist.manifests
  yaml_body = each.value
  depends_on = [kubectl_manifest.ingress_controller]
}

data "kubectl_file_documents" "graph" {
  content = file("${local.k8s_root}/data-structures/graph.yaml")
}

resource "kubectl_manifest" "graph" {
  for_each  = data.kubectl_file_documents.graph.manifests
  yaml_body = each.value
  depends_on = [kubectl_manifest.ingress_controller]
}

# ==========================================
# Database (Postgres)
# ==========================================
resource "kubectl_manifest" "database_secret" {
  yaml_body  = file("${local.k8s_root}/database/secret.yaml")
  depends_on = [kubectl_manifest.ingress_controller]
}

resource "kubectl_manifest" "database_pvc" {
  yaml_body  = file("${local.k8s_root}/database/pvc.yaml")
  depends_on = [kubectl_manifest.ingress_controller]
}

resource "kubectl_manifest" "database_statefulset" {
  yaml_body  = file("${local.k8s_root}/database/statefulset.yaml")
  depends_on = [
    kubectl_manifest.database_secret,
    kubectl_manifest.database_pvc,
    kubectl_manifest.ingress_controller
  ]
}

resource "kubectl_manifest" "database_service" {
  yaml_body  = file("${local.k8s_root}/database/service.yaml")
  depends_on = [kubectl_manifest.database_statefulset]
}

# ==========================================
# Monitoring - Prometheus
# ==========================================
resource "kubectl_manifest" "prometheus_clusterrole" {
  yaml_body  = file("${local.k8s_root}/monitoring/prometheus/clusterrole.yaml")
  depends_on = [kubectl_manifest.ingress_controller]
}

resource "kubectl_manifest" "prometheus_alerts" {
  yaml_body  = file("${local.k8s_root}/monitoring/prometheus/alerts.yaml")
  depends_on = [kubectl_manifest.ingress_controller]
}

resource "kubectl_manifest" "prometheus_configmap" {
  yaml_body  = file("${local.k8s_root}/monitoring/prometheus/configmap.yaml")
  depends_on = [kubectl_manifest.ingress_controller]
}

resource "kubectl_manifest" "prometheus_deployment" {
  yaml_body  = file("${local.k8s_root}/monitoring/prometheus/deployment.yaml")
  depends_on = [
    kubectl_manifest.prometheus_clusterrole,
    kubectl_manifest.prometheus_alerts,
    kubectl_manifest.prometheus_configmap,
    kubectl_manifest.ingress_controller
  ]
}

resource "kubectl_manifest" "prometheus_service" {
  yaml_body  = file("${local.k8s_root}/monitoring/prometheus/service.yaml")
  depends_on = [kubectl_manifest.prometheus_deployment]
}

# ==========================================
# Monitoring - Grafana
# ==========================================
data "kubectl_file_documents" "grafana_configmap" {
  content = file("${local.k8s_root}/monitoring/grafana/configmap.yaml")
}

resource "kubectl_manifest" "grafana_configmap" {
  for_each   = data.kubectl_file_documents.grafana_configmap.manifests
  yaml_body  = each.value
  depends_on = [kubectl_manifest.ingress_controller]
}

resource "kubectl_manifest" "grafana_dashboards" {
  yaml_body  = file("${local.k8s_root}/monitoring/grafana/dashboards/configmap.yaml")
  depends_on = [kubectl_manifest.ingress_controller]
}

resource "kubectl_manifest" "grafana_deployment" {
  yaml_body  = file("${local.k8s_root}/monitoring/grafana/deployment.yaml")
  depends_on = [
    kubectl_manifest.grafana_configmap,
    kubectl_manifest.grafana_dashboards,
    kubectl_manifest.prometheus_service,
    kubectl_manifest.ingress_controller
  ]
}

resource "kubectl_manifest" "grafana_service" {
  yaml_body  = file("${local.k8s_root}/monitoring/grafana/service.yaml")
  depends_on = [kubectl_manifest.grafana_deployment]
}

# ==========================================
# Ingress (from new structured folder)
# ==========================================
resource "kubectl_manifest" "ingress" {
  yaml_body = file("${local.k8s_root}/ingress/ingress.yaml")
  depends_on = [
    kubectl_manifest.backend_service,
    kubectl_manifest.frontend_service,
    kubectl_manifest.stack,
    kubectl_manifest.linkedlist,
    kubectl_manifest.graph,
    kubectl_manifest.database_service,
    kubectl_manifest.prometheus_service,
    kubectl_manifest.grafana_service
  ]
}

# ==========================================
# Outputs
# ==========================================
output "status" {
  value = "Deployment Complete using new devops-infra structure!"
}
