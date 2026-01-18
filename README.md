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
