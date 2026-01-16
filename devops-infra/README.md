# AKS Data Structures - DevOps Infrastructure

A comprehensive DevOps infrastructure repository for the AKS Data Structures project, featuring Kubernetes deployments, Terraform modules, Jenkins CI/CD pipelines, Helm charts, and monitoring with Prometheus & Grafana.

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           AWS Cloud / Minikube                          │
├─────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                     Kubernetes Cluster                            │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐   │   │
│  │  │   Frontend  │  │   Backend   │  │   Data Structure Svcs   │   │   │
│  │  │  (UI/React) │  │   (Flask)   │  │  Stack │ List │ Graph   │   │   │
│  │  └──────┬──────┘  └──────┬──────┘  └─────────────────────────┘   │   │
│  │         │                │                                        │   │
│  │         └────────┬───────┘                                        │   │
│  │                  ▼                                                 │   │
│  │         ┌───────────────┐                                         │   │
│  │         │    Ingress    │◄──── External Traffic                   │   │
│  │         │    (NGINX)    │                                         │   │
│  │         └───────────────┘                                         │   │
│  │                                                                    │   │
│  │  ┌────────────────────────────────────────────────────────────┐   │   │
│  │  │                    Monitoring Stack                         │   │   │
│  │  │    ┌────────────┐            ┌────────────┐                │   │   │
│  │  │    │ Prometheus │───────────▶│  Grafana   │                │   │   │
│  │  │    └────────────┘            └────────────┘                │   │   │
│  │  └────────────────────────────────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

## 📁 Directory Structure

```
devops-infra/
├── terraform/                    # Infrastructure as Code
│   ├── environments/
│   │   ├── dev/                  # Development environment
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── terraform.tfvars.example
│   │   └── prod/                 # Production environment
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── terraform.tfvars.example
│   ├── modules/
│   │   ├── kubernetes/           # K8s resources module
│   │   ├── networking/           # VPC, subnets, etc.
│   │   └── database/             # RDS PostgreSQL
│   └── providers.tf
│
├── kubernetes/                   # Kubernetes manifests
│   ├── namespaces/
│   ├── frontend/                 # Frontend (deployment, service, hpa, configmap)
│   ├── backend/                  # Backend (deployment, service, hpa, configmap, secret)
│   ├── database/                 # PostgreSQL (statefulset, service, pvc, secret)
│   ├── ingress/
│   └── monitoring/
│       ├── prometheus/
│       └── grafana/
│
├── jenkins/                      # CI/CD Pipelines
│   ├── Jenkinsfile               # Main orchestration pipeline
│   ├── Jenkinsfile.frontend      # Frontend-specific pipeline
│   ├── Jenkinsfile.backend       # Backend-specific pipeline
│   └── jenkins-config/
│       └── plugins.txt
│
├── helm/                         # Helm Charts
│   ├── frontend/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   └── backend/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│
├── scripts/                      # Automation scripts
│   ├── setup.sh                  # Environment setup
│   ├── deploy.sh                 # Deployment automation
│   └── cleanup.sh                # Teardown script
│
└── README.md
```

## 🚀 Quick Start

### Prerequisites

- Docker
- kubectl
- Minikube (for local development)
- Terraform >= 1.0.0
- Helm >= 3.0

### 1. Setup Environment

```bash
# Run the setup script
chmod +x devops-infra/scripts/*.sh
./devops-infra/scripts/setup.sh
```

### 2. Deploy Application

```bash
# Deploy to development environment
./devops-infra/scripts/deploy.sh dev

# Deploy with monitoring
./devops-infra/scripts/deploy.sh dev true

# Deploy using Helm
./devops-infra/scripts/deploy.sh dev false true
```

### 3. Access the Application

```bash
# Get Minikube IP
minikube ip

# Access URLs:
# Frontend: http://<minikube-ip>:32080/
# API:      http://<minikube-ip>:32080/api/
```

## 📦 Components

### Terraform Modules

| Module | Description |
|--------|-------------|
| `networking` | VPC, subnets, internet gateway, NAT gateway |
| `kubernetes` | Kubernetes resources deployment via kubectl |
| `database` | RDS PostgreSQL with Secrets Manager |

### Kubernetes Resources

| Component | Resources |
|-----------|-----------|
| Frontend | Deployment, Service, HPA, ConfigMap |
| Backend | Deployment, Service, HPA, ConfigMap, Secret |
| Database | StatefulSet, Service, PVC, Secret |
| Ingress | NGINX Ingress Controller, Ingress rules |
| Monitoring | Prometheus, Grafana with dashboards |

### CI/CD Pipelines

- **Main Pipeline**: Orchestrates entire deployment
- **Frontend Pipeline**: Build, test, deploy frontend
- **Backend Pipeline**: Build, test, security scan, deploy backend

## 🔧 Configuration

### Environment Variables

Copy the example tfvars file and customize:

```bash
cd devops-infra/terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### Helm Values

Customize Helm deployments:

```bash
# Deploy frontend with custom values
helm upgrade --install frontend devops-infra/helm/frontend \
  --set replicaCount=3 \
  --set image.tag=v1.0.0
```

## 📊 Monitoring

### Prometheus

Access Prometheus UI:
```bash
kubectl port-forward svc/prometheus-service 9090:9090
# Open http://localhost:9090
```

### Grafana

Access Grafana UI:
```bash
kubectl port-forward svc/grafana-service 3000:3000
# Open http://localhost:3000
# Default credentials: admin / admin123
```

Pre-built dashboards:
- Flask Backend Dashboard
- Kubernetes Cluster Dashboard

## 🧹 Cleanup

```bash
# Basic cleanup
./devops-infra/scripts/cleanup.sh

# Cleanup with monitoring
./devops-infra/scripts/cleanup.sh true

# Cleanup with Terraform resources
./devops-infra/scripts/cleanup.sh true true

# Force cleanup (no confirmation)
./devops-infra/scripts/cleanup.sh true true true
```

## 📝 Related Repositories

- **Backend**: `new-backend` - Flask API service
- **Frontend**: `new-frontend` - UI service

## 🛠️ Development

### Local Development with Minikube

```bash
# Start Minikube
minikube start

# Point Docker to Minikube
eval $(minikube docker-env)

# Build and deploy
./devops-infra/scripts/deploy.sh dev
```

### Running Terraform

```bash
cd devops-infra/terraform/environments/dev

# Initialize
terraform init

# Plan changes
terraform plan

# Apply changes
terraform apply
```

## 📋 Troubleshooting

### Common Issues

1. **Pods not starting**
   ```bash
   kubectl describe pod <pod-name>
   kubectl logs <pod-name>
   ```

2. **Ingress not working**
   ```bash
   kubectl get ingress
   kubectl describe ingress main-ingress
   ```

3. **Image pull errors (local development)**
   ```bash
   # Ensure Docker is pointing to Minikube
   eval $(minikube docker-env)
   # Rebuild images
   docker build -t backend-service:latest ../new-backend
   ```

## 📄 License

This project is licensed under the MIT License.

## 👥 Contributing

1. Create a feature branch
2. Make your changes
3. Submit a pull request

---

**Maintained by the DevOps Team**
