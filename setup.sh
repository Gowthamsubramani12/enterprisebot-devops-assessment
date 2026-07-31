#!/usr/bin/env bash
# =============================================================================
# setup.sh — EnterpriseBot local Kubernetes environment bootstrapper
#
# Usage:  ./setup.sh
#
# What it does (idempotent):
#   1. Validates required CLI tools
#   2. Creates (or reuses) a Kind cluster named "demo"
#   3. Installs ingress-nginx (skips if already present)
#   4. Waits for ingress-nginx to become ready
#   5. Builds the Docker image from service/
#   6. Loads the image into the Kind cluster
#   7. Ensures the "demo" namespace exists
#   8. Deploys the Helm chart with helm upgrade --install
#   9. Waits for the Deployment to become Available
#  10. Prints a verification cheatsheet
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
readonly CLUSTER_NAME="demo"
readonly NAMESPACE="demo"
readonly IMAGE_NAME="enterprisebot"
readonly IMAGE_TAG="1.0.0"
readonly FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
readonly HELM_RELEASE="demo"
readonly CHART_DIR="chart"
readonly SERVICE_DIR="service"
readonly INGRESS_NGINX_MANIFEST="https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml"
readonly INGRESS_NGINX_NAMESPACE="ingress-nginx"
readonly INGRESS_NGINX_DEPLOYMENT="ingress-nginx-controller"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
info()    { echo "[INFO]    $*"; }
success() { echo "[SUCCESS] $*"; }
warn()    { echo "[WARN]    $*"; }
error()   { echo "[ERROR]   $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# check_prerequisites
#
# Validates that every required CLI tool is installed and on PATH.
# Exits with a friendly message if anything is missing.
# ---------------------------------------------------------------------------
check_prerequisites() {
  info "Checking required tools..."

  local missing=0
  for cmd in docker kind kubectl helm; do
    if ! command -v "${cmd}" &>/dev/null; then
      warn "'${cmd}' not found. Please install it before running this script."
      missing=1
    fi
  done

  if [[ "${missing}" -eq 1 ]]; then
    error "One or more required tools are missing. Aborting."
  fi

  success "All required tools are present."
}

# ---------------------------------------------------------------------------
# ensure_kind_cluster
#
# Creates a Kind cluster named $CLUSTER_NAME if it does not already exist.
# If it exists, the existing cluster is reused — the script will never fail
# because of a pre-existing cluster.
# ---------------------------------------------------------------------------
ensure_kind_cluster() {
  info "Checking Kind cluster '${CLUSTER_NAME}'..."

  if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    info "Kind cluster '${CLUSTER_NAME}' already exists. Reusing it."
  else
    info "Creating Kind cluster '${CLUSTER_NAME}'..."
    kind create cluster --name "${CLUSTER_NAME}"
    success "Kind cluster '${CLUSTER_NAME}' created."
  fi

  # Point kubectl at the new/existing cluster
  kubectl cluster-info --context "kind-${CLUSTER_NAME}" &>/dev/null
  info "kubectl context set to 'kind-${CLUSTER_NAME}'."
}

# ---------------------------------------------------------------------------
# install_ingress_nginx
#
# Applies the official Kind ingress-nginx manifest.
# Detects whether the ingress-nginx namespace already exists; if so, skips
# the apply step to remain idempotent.
# Waits until the controller Deployment is Available before returning.
# ---------------------------------------------------------------------------
install_ingress_nginx() {
  info "Checking ingress-nginx installation..."

  if kubectl get namespace "${INGRESS_NGINX_NAMESPACE}" &>/dev/null; then
    info "ingress-nginx namespace already exists. Skipping installation."
  else
    info "Installing ingress-nginx from official Kind manifest..."
    kubectl apply -f "${INGRESS_NGINX_MANIFEST}"
    success "ingress-nginx manifest applied."
  fi

  info "Waiting for ingress-nginx controller to become ready..."
  kubectl wait \
    --namespace "${INGRESS_NGINX_NAMESPACE}" \
    --for=condition=Available \
    deployment/"${INGRESS_NGINX_DEPLOYMENT}" \
    --timeout=120s

  success "ingress-nginx is ready."
}

# ---------------------------------------------------------------------------
# build_docker_image
#
# Builds the Docker image from the service/ directory using the pinned
# tag $FULL_IMAGE.  Docker layer caching makes re-runs fast.
# ---------------------------------------------------------------------------
build_docker_image() {
  info "Building Docker image '${FULL_IMAGE}' from '${SERVICE_DIR}/'..."

  if [[ ! -f "${SERVICE_DIR}/Dockerfile" ]]; then
    error "Dockerfile not found at '${SERVICE_DIR}/Dockerfile'. Aborting."
  fi

  docker build --tag "${FULL_IMAGE}" "${SERVICE_DIR}/"
  success "Docker image '${FULL_IMAGE}' built successfully."
}

# ---------------------------------------------------------------------------
# load_image_into_kind
#
# Loads the locally built image into the Kind cluster so that pods can use
# it without a registry.  Kind's load command is safe to run multiple times.
# ---------------------------------------------------------------------------
load_image_into_kind() {
  info "Loading image '${FULL_IMAGE}' into Kind cluster '${CLUSTER_NAME}'..."
  kind load docker-image "${FULL_IMAGE}" --name "${CLUSTER_NAME}"
  success "Image '${FULL_IMAGE}' loaded into Kind cluster."
}

# ---------------------------------------------------------------------------
# ensure_namespace
#
# Creates the $NAMESPACE Kubernetes namespace if it does not already exist.
# Uses --dry-run=client + apply for a fully idempotent operation.
# ---------------------------------------------------------------------------
ensure_namespace() {
  info "Ensuring namespace '${NAMESPACE}' exists..."

  kubectl create namespace "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -

  success "Namespace '${NAMESPACE}' is ready."
}

# ---------------------------------------------------------------------------
# deploy_helm_chart
#
# Uses helm upgrade --install so the command is always idempotent:
#   - First run:  installs the release.
#   - Subsequent runs:  upgrades to the current chart state.
# ---------------------------------------------------------------------------
deploy_helm_chart() {
  info "Deploying Helm chart from '${CHART_DIR}/' as release '${HELM_RELEASE}'..."

  if [[ ! -f "${CHART_DIR}/Chart.yaml" ]]; then
    error "Chart.yaml not found at '${CHART_DIR}/Chart.yaml'. Aborting."
  fi

  helm upgrade --install "${HELM_RELEASE}" "${CHART_DIR}/" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --set image.repository="${IMAGE_NAME}" \
    --set image.tag="${IMAGE_TAG}" \
    --wait \
    --timeout 120s

  success "Helm release '${HELM_RELEASE}' deployed in namespace '${NAMESPACE}'."
}

# ---------------------------------------------------------------------------
# wait_for_deployment
#
# Waits until the Deployment rollout is complete and all pods are Available.
# This is a safety net on top of `helm --wait`.
# ---------------------------------------------------------------------------
wait_for_deployment() {
  local deployment_name
  deployment_name="${HELM_RELEASE}-enterprisebot"

  info "Waiting for Deployment '${deployment_name}' to be Available..."

  kubectl wait \
    --namespace "${NAMESPACE}" \
    --for=condition=Available \
    deployment/"${deployment_name}" \
    --timeout=120s

  success "Deployment '${deployment_name}' is fully Available."
}

# ---------------------------------------------------------------------------
# print_verification
#
# Prints a final summary of verification commands and runs them so the
# operator can see the cluster state at a glance.
# ---------------------------------------------------------------------------
print_verification() {
  echo ""
  echo "============================================================"
  success "Deployment completed successfully."
  echo "============================================================"
  echo ""
  echo "--- Cluster Nodes ---"
  kubectl get nodes
  echo ""
  echo "--- Pods in namespace '${NAMESPACE}' ---"
  kubectl get pods -n "${NAMESPACE}"
  echo ""
  echo "--- Services in namespace '${NAMESPACE}' ---"
  kubectl get svc -n "${NAMESPACE}"
  echo ""
  echo "--- Ingress in namespace '${NAMESPACE}' ---"
  kubectl get ingress -n "${NAMESPACE}"
  echo ""
  echo "--- Deployments in namespace '${NAMESPACE}' ---"
  kubectl get deployments -n "${NAMESPACE}"
  echo ""
  echo "--- Helm releases in namespace '${NAMESPACE}' ---"
  helm list -n "${NAMESPACE}"
  echo ""
  echo "Verification commands you can run manually:"
  echo "  kubectl get nodes"
  echo "  kubectl get pods -n ${NAMESPACE}"
  echo "  kubectl get svc -n ${NAMESPACE}"
  echo "  kubectl get ingress -n ${NAMESPACE}"
  echo "  kubectl get deployments -n ${NAMESPACE}"
  echo "  helm list -n ${NAMESPACE}"
  echo ""
  echo "Test the service (add 'demo.local' to /etc/hosts → 127.0.0.1 first):"
  echo "  curl http://demo.local/"
  echo "  curl http://demo.local/healthz"
}

# ---------------------------------------------------------------------------
# main — orchestrates all steps in order
# ---------------------------------------------------------------------------
main() {
  echo "============================================================"
  echo "  EnterpriseBot — Local Kubernetes Bootstrap"
  echo "============================================================"
  echo ""

  check_prerequisites
  ensure_kind_cluster
  install_ingress_nginx
  build_docker_image
  load_image_into_kind
  ensure_namespace
  deploy_helm_chart
  wait_for_deployment
  print_verification
}

main "$@"
