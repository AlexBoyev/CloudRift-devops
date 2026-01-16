# Kubernetes Module
# Manages Kubernetes resources including deployments, services, and ingress

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

# Namespace
resource "kubernetes_namespace" "app" {
  count = var.namespace != "default" ? 1 : 0

  metadata {
    name = var.namespace
    labels = {
      environment = var.environment
      project     = var.project_name
    }
  }
}

# Apply Kubernetes manifests from files
locals {
  namespace = var.namespace != "default" ? kubernetes_namespace.app[0].metadata[0].name : "default"
}

# Frontend Deployment
data "kubectl_file_documents" "frontend" {
  content = file("${var.k8s_dir}/frontend/deployment.yaml")
}

resource "kubectl_manifest" "frontend_deployment" {
  for_each  = data.kubectl_file_documents.frontend.manifests
  yaml_body = each.value
  
  override_namespace = local.namespace
}

# Frontend Service
data "kubectl_file_documents" "frontend_service" {
  content = file("${var.k8s_dir}/frontend/service.yaml")
}

resource "kubectl_manifest" "frontend_service" {
  for_each  = data.kubectl_file_documents.frontend_service.manifests
  yaml_body = each.value
  
  override_namespace = local.namespace

  depends_on = [kubectl_manifest.frontend_deployment]
}

# Frontend HPA
data "kubectl_file_documents" "frontend_hpa" {
  content = file("${var.k8s_dir}/frontend/hpa.yaml")
}

resource "kubectl_manifest" "frontend_hpa" {
  for_each  = data.kubectl_file_documents.frontend_hpa.manifests
  yaml_body = each.value
  
  override_namespace = local.namespace

  depends_on = [kubectl_manifest.frontend_deployment]
}

# Backend Deployment
data "kubectl_file_documents" "backend" {
  content = file("${var.k8s_dir}/backend/deployment.yaml")
}

resource "kubectl_manifest" "backend_deployment" {
  for_each  = data.kubectl_file_documents.backend.manifests
  yaml_body = each.value
  
  override_namespace = local.namespace
}

# Backend Service
data "kubectl_file_documents" "backend_service" {
  content = file("${var.k8s_dir}/backend/service.yaml")
}

resource "kubectl_manifest" "backend_service" {
  for_each  = data.kubectl_file_documents.backend_service.manifests
  yaml_body = each.value
  
  override_namespace = local.namespace

  depends_on = [kubectl_manifest.backend_deployment]
}

# Backend HPA
data "kubectl_file_documents" "backend_hpa" {
  content = file("${var.k8s_dir}/backend/hpa.yaml")
}

resource "kubectl_manifest" "backend_hpa" {
  for_each  = data.kubectl_file_documents.backend_hpa.manifests
  yaml_body = each.value
  
  override_namespace = local.namespace

  depends_on = [kubectl_manifest.backend_deployment]
}

# Data Structure Services
resource "kubectl_manifest" "stack" {
  yaml_body = file("${var.k8s_dir}/data-structures/stack.yaml")
  override_namespace = local.namespace
}

resource "kubectl_manifest" "linkedlist" {
  yaml_body = file("${var.k8s_dir}/data-structures/linkedlist.yaml")
  override_namespace = local.namespace
}

resource "kubectl_manifest" "graph" {
  yaml_body = file("${var.k8s_dir}/data-structures/graph.yaml")
  override_namespace = local.namespace
}

# Database manifests
data "kubectl_file_documents" "database_statefulset" {
  content = file("${var.k8s_dir}/database/statefulset.yaml")
}

resource "kubectl_manifest" "database_statefulset" {
  for_each          = data.kubectl_file_documents.database_statefulset.manifests
  yaml_body         = each.value
  override_namespace = local.namespace
}

data "kubectl_file_documents" "database_service" {
  content = file("${var.k8s_dir}/database/service.yaml")
}

resource "kubectl_manifest" "database_service" {
  for_each          = data.kubectl_file_documents.database_service.manifests
  yaml_body         = each.value
  override_namespace = local.namespace
  depends_on = [kubectl_manifest.database_statefulset]
}

data "kubectl_file_documents" "database_secret" {
  content = file("${var.k8s_dir}/database/secret.yaml")
}

resource "kubectl_manifest" "database_secret" {
  for_each          = data.kubectl_file_documents.database_secret.manifests
  yaml_body         = each.value
  override_namespace = local.namespace
}

data "kubectl_file_documents" "database_pvc" {
  content = file("${var.k8s_dir}/database/pvc.yaml")
}

resource "kubectl_manifest" "database_pvc" {
  for_each          = data.kubectl_file_documents.database_pvc.manifests
  yaml_body         = each.value
  override_namespace = local.namespace
}

# Monitoring - Prometheus
data "kubectl_file_documents" "prometheus" {
  content = file("${var.k8s_dir}/monitoring/prometheus/deployment.yaml")
}

data "kubectl_file_documents" "prometheus_alerts" {
  content = file("${var.k8s_dir}/monitoring/prometheus/alerts.yaml")
}

resource "kubectl_manifest" "prometheus_alerts" {
  for_each          = data.kubectl_file_documents.prometheus_alerts.manifests
  yaml_body         = each.value
  override_namespace = local.namespace
}

resource "kubectl_manifest" "prometheus_deployment" {
  for_each          = data.kubectl_file_documents.prometheus.manifests
  yaml_body         = each.value
  override_namespace = local.namespace
  depends_on = [
    kubectl_manifest.prometheus_clusterrole,
    kubectl_manifest.prometheus_alerts,
    kubectl_manifest.prometheus_config
  ]
}

data "kubectl_file_documents" "prometheus_service" {
  content = file("${var.k8s_dir}/monitoring/prometheus/service.yaml")
}

resource "kubectl_manifest" "prometheus_service" {
  for_each          = data.kubectl_file_documents.prometheus_service.manifests
  yaml_body         = each.value
  override_namespace = local.namespace
  depends_on = [kubectl_manifest.prometheus_deployment]
}

data "kubectl_file_documents" "prometheus_config" {
  content = file("${var.k8s_dir}/monitoring/prometheus/configmap.yaml")
}

resource "kubectl_manifest" "prometheus_config" {
  for_each          = data.kubectl_file_documents.prometheus_config.manifests
  yaml_body         = each.value
  override_namespace = local.namespace
}

data "kubectl_file_documents" "prometheus_clusterrole" {
  content = file("${var.k8s_dir}/monitoring/prometheus/clusterrole.yaml")
}

resource "kubectl_manifest" "prometheus_clusterrole" {
  for_each          = data.kubectl_file_documents.prometheus_clusterrole.manifests
  yaml_body         = each.value
  override_namespace = local.namespace
}

# Monitoring - Grafana
data "kubectl_file_documents" "grafana_deployment" {
  content = file("${var.k8s_dir}/monitoring/grafana/deployment.yaml")
}

resource "kubectl_manifest" "grafana_deployment" {
  for_each          = data.kubectl_file_documents.grafana_deployment.manifests
  yaml_body         = each.value
  override_namespace = local.namespace
  depends_on = [
    kubectl_manifest.prometheus_service,
    kubectl_manifest.grafana_configmaps,
    kubectl_manifest.grafana_dashboards
  ]
}

data "kubectl_file_documents" "grafana_service" {
  content = file("${var.k8s_dir}/monitoring/grafana/service.yaml")
}

resource "kubectl_manifest" "grafana_service" {
  for_each          = data.kubectl_file_documents.grafana_service.manifests
  yaml_body         = each.value
  override_namespace = local.namespace
  depends_on = [kubectl_manifest.grafana_deployment]
}

data "kubectl_file_documents" "grafana_configmaps" {
  content = file("${var.k8s_dir}/monitoring/grafana/configmap.yaml")
}

resource "kubectl_manifest" "grafana_configmaps" {
  for_each          = data.kubectl_file_documents.grafana_configmaps.manifests
  yaml_body         = each.value
  override_namespace = local.namespace
}

data "kubectl_file_documents" "grafana_dashboards" {
  content = file("${var.k8s_dir}/monitoring/grafana/dashboards/configmap.yaml")
}

resource "kubectl_manifest" "grafana_dashboards" {
  for_each          = data.kubectl_file_documents.grafana_dashboards.manifests
  yaml_body         = each.value
  override_namespace = local.namespace
}

# Ingress
data "kubectl_file_documents" "ingress" {
  content = file("${var.k8s_dir}/ingress/ingress.yaml")
}

resource "kubectl_manifest" "ingress" {
  for_each  = data.kubectl_file_documents.ingress.manifests
  yaml_body = each.value
  
  override_namespace = local.namespace

  depends_on = [
    kubectl_manifest.frontend_service,
    kubectl_manifest.backend_service,
    kubectl_manifest.stack,
    kubectl_manifest.linkedlist,
    kubectl_manifest.graph,
    kubectl_manifest.prometheus_service,
    kubectl_manifest.grafana_service,
    kubectl_manifest.database_service
  ]
}
