# Cloud-Native Data Structures Platform on AWS

A complete, production-oriented DevOps infrastructure for deploying and operating a cloud-native data structures application on AWS using Kubernetes.

## 🏗️ Architecture Overview

This project demonstrates a full DevOps workflow featuring:
- **Infrastructure as Code** with Terraform
- **Microservices** deployed on Kubernetes
- **CI/CD automation** with Jenkins
- **Configuration management** with Helm
- **Monitoring and observability** with Prometheus and Grafana

### System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Cloud                                │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Kubernetes Cluster                          │   │
│  │                                                           │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐             │   │
│  │  │ Frontend │  │ Backend  │  │ Database │             │   │
│  │  │ (React)  │─▶│ (Flask)  │─▶│(Postgres)│             │   │
│  │  └──────────┘  └──────────┘  └──────────┘             │   │
│  │                                                           │   │
│  │  ┌──────────────────────────────────────────────┐      │   │
│  │  │         Monitoring Stack                      │      │   │
│  │  │  ┌──────────┐         ┌──────────┐            │      │   │
│  │  │  │Prometheus│────────▶│ Grafana  │            │      │   │
│  │  │  └──────────┘         └──────────┘            │      │   │
│  │  └──────────────────────────────────────────────┘      │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              │
                    ┌─────────┴─────────┐
                    │   CI/CD Pipeline   │
                    │     (Jenkins)      │
                    └─────────┬─────────┘
                              │
                    ┌─────────┴─────────┐
                    │  GitHub Repos     │
                    │  (Frontend/Backend)│
                    └───────────────────┘
```

## 📁 Repository Structure

This is the **DevOps Infrastructure Repository** (`new-devops-local`).

### Directory Structure

```
new-devops-local/
├── devops-infra/              # Main DevOps infrastructure
│   ├── terraform/             # Infrastructure as Code
│   │   ├── environments/      # Environment-specific configs
│   │   │   ├── dev/
│   │   │   └── prod/
│   │   └── modules/           # Reusable Terraform modules
│   │       ├── kubernetes/
│   │       ├── networking/
│   │       └── database/
│   ├── kubernetes/            # Kubernetes manifests
│   │   ├── namespaces/
│   │   ├── frontend/
│   │   ├── backend/
│   │   ├── database/
│   │   ├── ingress/
│   │   └── monitoring/
│   ├── jenkins/               # CI/CD Pipelines
│   │   ├── Jenkinsfile        # Main orchestration
│   │   ├── Jenkinsfile.frontend
│   │   ├── Jenkinsfile.backend
│   │   └── jenkins-config/
│   ├── helm/                  # Helm Charts
│   │   ├── frontend/
│   │   └── backend/
│   └── scripts/               # Deployment scripts
├── aws-infrastrucutre-terraform/  # AWS infrastructure
└── README.md                  # This file
```

## 🚀 Quick Start

### Prerequisites

- Docker
- kubectl
- Minikube (for local development) or AWS EKS access
- Terraform >= 1.0.0
- Helm >= 3.0
- Jenkins (for CI/CD)

### Local Development Setup

1. **Start Minikube**
   ```bash
   minikube start
   eval $(minikube docker-env)
   ```

2. **Deploy Infrastructure**
   ```bash
   cd devops-infra/scripts
   chmod +x *.sh
   ./setup.sh
   ```

3. **Deploy Application**
   ```bash
   ./deploy.sh dev
   ```

4. **Access the Application**
   ```bash
   minikube service frontend-service
   minikube service backend-service
   ```

### AWS Deployment

1. **Configure Terraform**
   ```bash
   cd devops-infra/terraform/environments/dev
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your AWS credentials
   ```

2. **Initialize and Apply**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. **Deploy via Jenkins**
   - Configure Jenkins with GitHub webhooks
   - Trigger pipeline from Jenkins UI or via webhook

## 📦 Components

### 1. Frontend Application

- **Repository**: `new-frontend`
- **Framework**: React/Vue.js
- **Deployment**: Kubernetes Deployment with 2 replicas
- **Health Check**: `/health` endpoint
- **Configuration**: ConfigMap for API URL

### 2. Backend Application

- **Repository**: `new-backend`
- **Framework**: Flask
- **Database**: PostgreSQL
- **Endpoints**:
  - `/health` - Basic health check
  - `/health/ready` - Readiness probe (DB connected)
  - `/health/live` - Liveness probe
  - `/metrics` - Prometheus metrics
  - `/api/*` - REST API endpoints

### 3. Database

- **Type**: PostgreSQL (StatefulSet)
- **Storage**: Persistent Volume Claim (10Gi)
- **Credentials**: Kubernetes Secrets

### 4. CI/CD Pipeline (Jenkins)

**Pipeline Stages:**
1. **Checkout** - Clone repositories
2. **Build** - Build Docker images
3. **Test** - Run unit tests
4. **Scan** - Security scanning (Trivy)
5. **Tag** - Tag images with build number and git SHA
6. **Push** - Push to container registry
7. **Deploy** - Deploy to Kubernetes using Helm
8. **Verify** - Health checks and integration tests

**Pipeline Files:**
- `Jenkinsfile` - Main orchestration pipeline
- `Jenkinsfile.frontend` - Frontend-specific pipeline
- `Jenkinsfile.backend` - Backend-specific pipeline

### 5. Monitoring Stack

#### Prometheus
- Scrapes metrics from all services
- 15-day retention
- Alert rules for:
  - High error rate
  - High latency
  - Pod restarts
  - Database connection failures
  - High CPU/Memory usage

#### Grafana
- Pre-configured dashboards:
  - Application metrics (request rate, latency, errors)
  - Kubernetes cluster health
  - Database performance

### 6. Helm Charts

**Features:**
- Environment awareness (dev/prod)
- Feature toggles
- Configurable scaling
- Resource limits

**Usage:**
```bash
# Deploy with Helm
helm install backend devops-infra/helm/backend \
  --set environment=prod \
  --set replicaCount=4 \
  --set features.showDatabaseInfo=true

helm install frontend devops-infra/helm/frontend \
  --set environment=prod \
  --set features.showEnvironment=true
```

## 🔧 Configuration

### Environment Variables

#### Frontend
```env
REACT_APP_API_URL=http://backend-service:5000/api
REACT_APP_ENV=production
```

#### Backend
```env
FLASK_ENV=production
DATABASE_URL=postgresql://user:pass@postgres-headless:5432/appdb
SECRET_KEY=your-secret-key
PROMETHEUS_MULTIPROC_DIR=/tmp
```

### Secrets Management

Secrets are stored in Kubernetes Secrets. To update:

```bash
# Update database password
kubectl create secret generic postgres-secrets \
  --from-literal=POSTGRES_PASSWORD='newpassword' \
  --dry-run=client -o yaml | kubectl apply -f -
```

## 📊 Monitoring

### Accessing Dashboards

**Prometheus:**
```bash
kubectl port-forward svc/prometheus-service 9090:9090
# Open http://localhost:9090
```

**Grafana:**
```bash
kubectl port-forward svc/grafana-service 3000:3000
# Open http://localhost:3000
# Default credentials: admin/admin123
```

### Key Metrics

- **Request Rate**: `rate(http_requests_total[5m])`
- **Error Rate**: `rate(http_requests_total{status=~"5.."}[5m])`
- **Latency**: `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))`
- **Active Connections**: `db_connections_active`

## 🔄 CI/CD Workflow

```
Developer → GitHub Push → Jenkins Webhook → Pipeline Execution
    ↓
Checkout Repos → Build Images → Run Tests → Security Scan
    ↓
Tag Images → Push to Registry → Deploy via Helm → Verify
    ↓
Health Checks → Integration Tests → Notify (Slack)
```

## 📝 Deployment Scripts

### Available Scripts

- `setup.sh` - Initial environment setup
- `deploy.sh` - Deploy application
- `cleanup.sh` - Teardown resources
- `run-local.sh` - Run locally with Minikube

### Usage

```bash
# Deploy to dev environment
./deploy.sh dev

# Deploy with monitoring
./deploy.sh dev true

# Deploy using Helm
./deploy.sh dev false true
```

## 🎯 Features

### Environment Awareness

Helm controls which environment the application runs in:

```yaml
# values.yaml
environment: "dev"  # or "prod"
```

The UI displays: `Environment: DEV` or `Environment: PROD`

### Scaling via Configuration

```yaml
# values.yaml
replicaCount: 2  # Scale to 4, 8, etc.
```

### Feature Toggles

```yaml
# values.yaml
features:
  showDatabaseInfo: false  # Toggle database info display
  enableAnalytics: false   # Toggle analytics
```

## 🛠️ Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl get pods

# Check pod logs
kubectl logs <pod-name>

# Describe pod for events
kubectl describe pod <pod-name>
```

### Database Connection Issues

```bash
# Check database pod
kubectl get pods -l app=postgres

# Check database logs
kubectl logs <postgres-pod-name>

# Test connection
kubectl exec -it <postgres-pod-name> -- psql -U appuser -d appdb
```

### Jenkins Pipeline Failures

```bash
# Check Jenkins logs
kubectl logs <jenkins-pod-name>

# Verify credentials
# Check Jenkins UI → Credentials
```

## 📚 Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## 📄 License

This project is licensed under the MIT License.

## 👥 Authors
DevOps Team

---

**Note**: This is a comprehensive DevOps infrastructure setup. Ensure all secrets are properly managed and never committed to version control.


 