#!/usr/bin/env bash
set -euo pipefail

# setup-local.sh - One-click local infrastructure setup (self-contained)
# - checks prerequisites (docker, kubectl, minikube, helm, git)
# - clones backend/frontend repos (uses GITHUB_PAT if provided)
# - starts minikube and points Docker to its daemon
# - builds all images (backend + data-structures + postgres + frontend)
# - applies Kubernetes manifests (namespaces, ingress-controller, db, backend, data-structures, frontend, ingress, monitoring)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_ROOT="$(dirname "$ROOT_DIR")"          # .../devops-infra
PROJECT_ROOT="$(dirname "$DEVOPS_ROOT")"       # .../new-devops-local
WORKSPACE_ROOT="$(dirname "$PROJECT_ROOT")"    # parent folder containing repos
MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-minikube}"
BRANCH_NAME="${BRANCH_NAME:-main}"

load_env_if_present() {
  local env_path="$1"
  if [ -f "$env_path" ]; then
    # shellcheck source=/dev/null
    . "$env_path"
  fi
}

# Load your repo env (single source of truth)
load_env_if_present "${PROJECT_ROOT}/driver/.env"

: "${BACKEND_REPO_URL:?BACKEND_REPO_URL must be set in .env}"
: "${FRONTEND_REPO_URL:?FRONTEND_REPO_URL must be set in .env}"
BACKEND_DIR="${BACKEND_DIR:-${WORKSPACE_ROOT}/new-backend}"
FRONTEND_DIR="${FRONTEND_DIR:-${WORKSPACE_ROOT}/new-frontend}"

print_status()  { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error()   { echo -e "${RED}✗${NC} $1"; }
print_step()    { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

check_prereq() {
  local bin="$1"
  if ! command -v "$bin" >/dev/null 2>&1; then
    print_warning "Missing prerequisite: $bin"
    return 1
  fi
  return 0
}

install_tool() {
  local tool="$1"
  local os="$2"
  case "$os" in
    Darwin)
      if ! command -v brew >/dev/null 2>&1; then
        print_error "Homebrew is required to install $tool on macOS. Please install Homebrew and rerun."
        exit 1
      fi
      case "$tool" in
        git) brew install git ;;
        docker) brew install --cask docker ;;
        kubectl) brew install kubectl ;;
        minikube) brew install minikube ;;
        helm) brew install helm ;;
        terraform) brew install terraform ;;
        *) print_warning "No installer mapping for $tool on macOS";;
      esac
      ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then
        case "$tool" in
          git) sudo apt-get update -y && sudo apt-get install -y git ;;
          docker) sudo apt-get update -y && sudo apt-get install -y docker.io ;;
          kubectl)
            curl -fsSLo /tmp/kubectl https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
            sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
            ;;
          minikube)
            curl -fsSLo /tmp/minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
            sudo install /tmp/minikube /usr/local/bin/minikube
            ;;
          helm)
            curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
            ;;
          terraform)
            sudo apt-get update -y && sudo apt-get install -y terraform || {
              curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
              sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
              sudo apt-get update -y && sudo apt-get install -y terraform
            }
            ;;
          *) print_warning "No installer mapping for $tool on Linux";;
        esac
      else
        print_error "Unsupported package manager on Linux; install $tool manually."
        exit 1
      fi
      ;;
    *)
      print_error "Unsupported OS for auto-install: $os"
      exit 1
      ;;
  esac
}

normalize_url() {
  local input="$1"
  if echo "$input" | grep -qiE '^git@github.com:'; then
    input=$(echo "$input" | sed -E 's|^git@github.com:|https://github.com/|')
  elif echo "$input" | grep -qiE '^ssh://git@github.com/'; then
    input=$(echo "$input" | sed -E 's|^ssh://git@github.com/|https://github.com/|')
  elif ! echo "$input" | grep -qiE '^https?://'; then
    input="https://$input"
  fi
  echo "$input"
}

clone_repo() {
  local url="$1" dest="$2" branch="$3"
  local normalized auth_url
  normalized="$(normalize_url "$url")"

  if [ -d "$dest/.git" ]; then
    print_status "Repo exists: $dest"
    git -C "$dest" fetch --all --tags || true
    git -C "$dest" checkout "$branch" || true
    git -C "$dest" pull --ff-only || true
    return
  fi

  if [ -n "${GITHUB_PAT:-}" ]; then
    auth_url="https://${GITHUB_PAT}@${normalized#https://}"
  else
    print_warning "GITHUB_PAT not set; attempting clone without PAT"
    auth_url="$normalized"
  fi

  mkdir -p "$(dirname "$dest")"
  git clone -b "$branch" "$auth_url" "$dest"
  git -C "$dest" remote set-url origin "$normalized" >/dev/null 2>&1 || true
  print_status "Cloned repo into $dest"
}

echo -e "${BLUE}==============================================================${NC}"
echo -e "${BLUE}  Local DevOps Setup - Complete Local Infrastructure Deploy  ${NC}"
echo -e "${BLUE}==============================================================${NC}"

print_step "Step 1: Checking prerequisites"
OS_TYPE="$(uname -s)"
for b in git docker kubectl minikube helm terraform; do
  if ! check_prereq "$b"; then
    print_step "Installing $b (detected OS: $OS_TYPE)"
    install_tool "$b" "$OS_TYPE"
    check_prereq "$b" || { print_error "$b installation failed; please install manually and rerun."; exit 1; }
  fi
done
print_status "All prerequisites present (git, docker, kubectl, minikube, helm, terraform)"

print_step "Step 2: Ensuring repositories"
echo "Backend:  $BACKEND_REPO_URL -> $BACKEND_DIR"
echo "Frontend: $FRONTEND_REPO_URL -> $FRONTEND_DIR"
clone_repo "$BACKEND_REPO_URL" "$BACKEND_DIR" "$BRANCH_NAME"
clone_repo "$FRONTEND_REPO_URL" "$FRONTEND_DIR" "$BRANCH_NAME"

print_step "Step 3: Starting Minikube (profile: $MINIKUBE_PROFILE)"
if ! minikube status -p "$MINIKUBE_PROFILE" >/dev/null 2>&1; then
  minikube start -p "$MINIKUBE_PROFILE"
else
  print_status "Minikube already running"
fi

print_step "Step 4: Point Docker to Minikube daemon"
eval "$(minikube -p "$MINIKUBE_PROFILE" docker-env)"

print_step "Step 5: Building Docker images"
pushd "$BACKEND_DIR" >/dev/null
  docker build -t backend-service:latest -f backend/Dockerfile backend/
  docker build -t stack-service:latest -f stack/Dockerfile ./
  docker build -t linkedlist-service:latest -f linkedlist/Dockerfile ./
  docker build -t graph-service:latest -f graph/Dockerfile ./
  docker build -t postgres-db:latest -f database/Dockerfile ./
popd >/dev/null

pushd "$FRONTEND_DIR" >/dev/null
  docker build -t frontend-service:latest -f Dockerfile .
popd >/dev/null
print_status "Images built: backend/stack/linkedlist/graph/postgres/frontend"

print_step "Step 6: Applying Kubernetes manifests"
pushd "$DEVOPS_ROOT/kubernetes" >/dev/null
  kubectl apply -f namespaces || true
  kubectl apply -f ingress-controller || true
  kubectl apply -f database
  kubectl apply -f backend
  kubectl apply -f data-structures
  kubectl apply -f frontend
  kubectl apply -f ingress
  kubectl apply -f monitoring || true
popd >/dev/null

print_step "Step 7: Status"
minikube service list -p "$MINIKUBE_PROFILE" || true
kubectl get pods -A || true

print_status "Local setup completed via setup-local.sh"
