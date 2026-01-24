# Cloud-Native Data Structures Platform on AWS

## Project Overview

This project demonstrates a full, production-oriented DevOps workflow for deploying and operating a cloud-native application on AWS using Kubernetes.  
The application exposes basic data structure implementations as independent microservices and focuses on automation, scalability, and observability.

The system is deployed using Infrastructure as Code, managed through CI/CD pipelines, configured via Helm, and monitored using Prometheus and Grafana.

---

## Architecture Summary

### Backend Microservices

The backend consists of three independent microservices, each implemented in a different programming language:

- **Stack Service** – C  
- **Linked List Service** – Java  
- **Tree Service** – Python  

Each service:
- Runs in its own Docker container
- Exposes a REST API
- Is deployed as a Kubernetes Deployment with two replicas
- Communicates internally using Kubernetes Services

### Backend Aggregation Layer

A central backend application (`app.py`) acts as an API aggregation layer:
- Receives requests from the frontend
- Routes requests to the appropriate microservice
- Aggregates responses when needed
- Exposes a single entry point to the UI

### Frontend

The frontend is a lightweight web UI that:
- Communicates only with the backend API
- Displays data structure operation results
- Provides a simple visual interface

### Database

- PostgreSQL is used for persistence
- Stores execution results and metadata
- Deployed inside the Kubernetes cluster

---

## Local Development

- The full system is implemented locally using **Minikube**
- A custom `manager.py` script orchestrates service startup
- This setup serves as the baseline before cloud deployment

---

## AWS Deployment

### Infrastructure as Code (Terraform)

All AWS resources are provisioned using Terraform, including:
- VPC and networking
- Subnets and routing
- Security groups
- IAM roles and policies
- EC2 instance hosting Kubernetes

The initial deployment targets a single EC2 instance for simplicity, with a scalable design.

### Kubernetes

Kubernetes is responsible for:
- Container orchestration
- Service discovery
- Scaling and health management

Each component is deployed as:
- Deployment (2 replicas)
- Service for internal communication

---

## CI/CD Pipeline (Jenkins)

### Repositories

- Frontend repository
- Backend repository
- DevOps repository (Terraform, Helm charts, Jenkins pipelines)

### Pipeline Stages

1. Source code checkout
2. Unit testing (before merge)
3. Docker image build
4. Image push to registry
5. Deployment using Helm
6. Post-deployment validation

Pipelines are triggered automatically via GitHub webhooks.

---
# DevOps Engineering Challenge
## Full-Stack Application with Complete CI/CD Pipeline

---

Build and deploy a full-stack web application with a complete DevOps infrastructure including containerization, CI/CD pipelines, orchestration, infrastructure as code, and monitoring.

---

## 🏗️ High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                                    INFRASTRUCTURE                                   │
│                                  (Terraform Managed)                                │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                     │
│   ┌──────────────────────────────────────────────────────────────────────────────┐  │
│   │                         KUBERNETES CLUSTER                                   │  │
│   │                                                                              │  │
│   │   ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐          │  │
│   │   │    FRONTEND     │    │    BACKEND      │    │    DATABASE     │          │  │
│   │   │    (React/Vue)  │───▶│    (Flask)      │───▶│  (PostgreSQL)   │         │  │
│   │   │                 │    │                 │    │                 │          │  │
│   │   │  ┌───────────┐  │    │  ┌───────────┐  │    │  ┌───────────┐  │          │  │
│   │   │  │ Container │  │    │  │ Container │  │    │  │ Container │  │          │  │
│   │   │  └───────────┘  │    │  └───────────┘  │    │  └───────────┘  │          │  │
│   │   │                 │    │                 │    │                 │          │  │
│   │   │  Deployment     │    │  Deployment     │    │  StatefulSet    │          │  │
│   │   │  Service        │    │  Service        │    │  Service        │          │  │
│   │   │  HPA            │    │  HPA            │    │  PVC            │          │  │
│   │   └─────────────────┘    └─────────────────┘    └─────────────────┘          │  │
│   │                                                                              │  │
│   │   ┌─────────────────────────────────────────────────────────────────────┐    │  │
│   │   │                      MONITORING STACK                               │    │  │
│   │   │                                                                     │    │  │
│   │   │   ┌─────────────────┐         ┌─────────────────┐                   │    │  │
│   │   │   │   PROMETHEUS    │────────▶│    GRAFANA      │                   │    │  │
│   │   │   │                 │         │                 │                   │    │  │
│   │   │   │  - Metrics      │         │  - Dashboards   │                   │    │  │
│   │   │   │  - Alerts       │         │  - Alerts       │                   │    │  │
│   │   │   │  - Scraping     │         │  - Visualize    │                   │    │  │
│   │   │   └─────────────────┘         └─────────────────┘                   │    │  │
│   │   │                                                                     │    │  │
│   │   └─────────────────────────────────────────────────────────────────────┘    │  │
│   │                                                                              │  │
│   │   ┌─────────────────┐                                                        │  │
│   │   │ INGRESS CTRL    │  ◀── External Traffic                                  │  │
│   │   │ (nginx/traefik) │                                                        │  │
│   │   └─────────────────┘                                                        │  │
│   │                                                                              │  │
│   └──────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘

                                        ▲
                                        │
                                        │ Deploy
                                        │
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              CI/CD PIPELINE (Jenkins)                               │
│                                                                                     │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐      │
│   │  Clone   │───▶│  Build   │───▶│  Test   │───▶│  Push   │───▶│  Deploy│        │
│   │  Repos   │    │  Images  │    │  Apps    │    │  to Reg  │    │  to K8s  │      │
│   └──────────┘    └──────────┘    └──────────┘    └──────────┘    └──────────┘      │
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘
                                        ▲
                                        │ Webhook Trigger
                                        │
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              GITHUB REPOSITORIES                                    │
│                                                                                     │
│   ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐                 │
│   │   FRONTEND      │    │   BACKEND       │    │   DEVOPS        │                 │
│   │   REPO          │    │   REPO          │    │   REPO          │                 │
│   │                 │    │                 │    │                 │                 │
│   │ - React/Vue     │    │ - Flask API     │    │ - Terraform     │                 │
│   │ - Dockerfile    │    │ - Dockerfile    │    │ - K8s manifests │                 │
│   │ - nginx.conf    │    │ - requirements  │    │ - *Jenkinsfile  │                 │
│   │                 │    │ - tests         │    │ - Helm charts   │                 │
│   │                 │    │ - *Jenkinsfil   │    │ - Monitoring    │                 │
│   └─────────────────┘    └─────────────────┘    └─────────────────┘                 │
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘

## 📁 Repository Structure

### Repository 1: `frontend-app`
### Repository 2: `backend-api`
### Repository 3: `devops-infra`
### 5. Jenkins CI/CD Pipeline
# Jenkins – GitHub Integration (Generic Webhook Trigger)

This section captures the **exact Jenkins job configuration** used to integrate **GitHub → smee.io → Jenkins** for the CloudRift project.

This file exists so the setup can be **recreated after a Jenkins / EC2 / PC reset** with zero guesswork.

---

## Job Overview

- **Job name:** `backend-pipeline`
- **Job type:** Pipeline
- **Pipeline definition:** *Pipeline script pasted directly in Jenkins UI*
- **Trigger mechanism:** Generic Webhook Trigger (token-based, CSRF-safe)

---

## General

- **Discard old builds:** Enabled
  - **Max # of builds to keep:** `30`
- **Do not allow concurrent builds:** Enabled
- **Abort previous builds:** Disabled
- **Do not allow pipeline to resume if controller restarts:** Disabled
- **GitHub project:** Not required
- **Pipeline speed/durability override:** Default

---

## Triggers

### Generic Webhook Trigger

This job is triggered by HTTP requests sent to:

```
http://JENKINS_URL/generic-webhook-trigger/invoke
```

In practice, the request arrives via **smee.io**, not directly from GitHub.

---

### Post Content Parameters

These values are extracted from the incoming GitHub webhook payload.

| Variable name | Type     | Expression |
|--------------|----------|------------|
| `repo_full_name` | JSONPath | `$.repository.full_name` |

Purpose:
- Extracts the GitHub repository full name (e.g. `AlexBoyev/CloudRift-backend`)
- Used later for filtering

---

### Token (Mandatory)

```
cloudrift-backend
```

- Passed as a **query parameter** by smee:
  ```
  ?token=cloudrift-backend
  ```
- Allows triggering **without Jenkins CSRF crumb**
- Must match the value used by smee-client

---

### Cause

- **Generic Cause**
- Used only for display purposes in build history

---

### Optional Filter (Critical)

This filter ensures **only the intended repository** can trigger the job.

- **Expression:**
  ```
  ^AlexBoyev/CloudRift-backend$
  ```

- **Text:**
  ```
  $repo_full_name
  ```

If this does not match, the webhook is accepted but **the job will not trigger**.

---

## Pipeline Configuration

### Definition

- **Pipeline script**
- The Groovy pipeline is **pasted directly in the Jenkins UI**
- No `Jenkinsfile` is used by the job

> ⚠️ Because the pipeline lives in the UI, it **must be backed up manually** (recommended: store a copy in Git).

---

## Disabled / Not Used Triggers

The following Jenkins trigger mechanisms are **not enabled**:

- GitHub hook trigger for GITScm polling
- Poll SCM
- Build periodically
- Trigger builds remotely
- GitHub branches / pull requests

All triggering is handled **exclusively** by Generic Webhook Trigger.

---

## End-to-End Trigger Flow

```
GitHub Push
   ↓
GitHub Webhook → https://smee.io/3kEdRwsh19vXOgv
   ↓
EC2 smee-client (systemd)
   ↓
http://127.0.0.1:8080/generic-webhook-trigger/invoke?token=cloudrift-backend
   ↓
Generic Webhook Trigger
   ↓
backend-pipeline
```

---

## Validation Command

Used locally to confirm Jenkins accepts and evaluates a webhook correctly:

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"repository":{"full_name":"AlexBoyev/CloudRift-backend"}}' \
  "http://127.0.0.1:8080/generic-webhook-trigger/invoke?token=cloudrift-backend"
```

Expected result:

```json
"triggered": true
```

---

## Reset Checklist

After a reset, ensure:

1. Jenkins plugins reinstalled
2. `backend-pipeline` job recreated
3. Pipeline script pasted back
4. Generic Webhook Trigger configured as above
5. Token matches smee `.env`
6. SSH credential `ec2-ssh-key` restored
7. smee systemd service running

---

## Final Notes

- GitHub does **not** talk directly to Jenkins
- Jenkins does **not** expose itself publicly
- smee.io acts as a secure relay
- Token-based triggering avoids CSRF issues
- This configuration is production-grade, just UI-driven


