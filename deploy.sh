#!/bin/bash
###############################################################################
# deploy.sh — Deploy the full monitoring stack to Kubernetes
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
# This script applies manifests in order and waits for each component
# to become ready before moving on.
###############################################################################

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

wait_for_deployment() {
  local namespace=$1
  local deployment=$2
  local timeout=${3:-120}
  info "Waiting for $deployment in $namespace to be ready (timeout: ${timeout}s)..."
  if kubectl rollout status deployment/"$deployment" -n "$namespace" --timeout="${timeout}s"; then
    info "$deployment is ready!"
  else
    warn "$deployment did not become ready within ${timeout}s — continuing anyway"
  fi
}

wait_for_daemonset() {
  local namespace=$1
  local daemonset=$2
  local timeout=${3:-120}
  info "Waiting for $daemonset DaemonSet in $namespace (timeout: ${timeout}s)..."
  if kubectl rollout status daemonset/"$daemonset" -n "$namespace" --timeout="${timeout}s"; then
    info "$daemonset is ready!"
  else
    warn "$daemonset did not become ready within ${timeout}s — continuing anyway"
  fi
}

echo "============================================="
echo "  Underdark Cluster Monitoring Stack Deploy"
echo "============================================="
echo ""

# --- Step 1: Metrics Server ---
info "Deploying metrics-server..."
kubectl apply -f "$SCRIPT_DIR/metrics-server/metrics-server.yaml"
wait_for_deployment kube-system metrics-server 120
echo ""

# --- Step 2: Monitoring Namespace ---
info "Creating monitoring namespace..."
kubectl apply -f "$SCRIPT_DIR/monitoring/00-namespace.yaml"
echo ""

# --- Step 3: Prometheus ---
info "Deploying Prometheus..."
kubectl apply -f "$SCRIPT_DIR/monitoring/01-prometheus.yaml"
wait_for_deployment monitoring prometheus 120
echo ""

# --- Step 4: Node Exporter ---
info "Deploying Node Exporter DaemonSet..."
kubectl apply -f "$SCRIPT_DIR/monitoring/02-node-exporter.yaml"
wait_for_daemonset monitoring node-exporter 120
echo ""

# --- Step 5: kube-state-metrics ---
info "Deploying kube-state-metrics..."
kubectl apply -f "$SCRIPT_DIR/monitoring/03-kube-state-metrics.yaml"
wait_for_deployment monitoring kube-state-metrics 120
echo ""

# --- Step 6: Grafana ---
info "Deploying Grafana..."
kubectl apply -f "$SCRIPT_DIR/monitoring/04-grafana.yaml"
wait_for_deployment monitoring grafana 180
echo ""

# --- Summary ---
echo "============================================="
echo "  Deployment Complete!"
echo "============================================="
echo ""

info "Checking pod status..."
echo ""
echo "--- kube-system (metrics-server) ---"
kubectl get pods -n kube-system -l k8s-app=metrics-server -o wide
echo ""
echo "--- monitoring namespace ---"
kubectl get pods -n monitoring -o wide
echo ""

# Get a node IP for access URLs
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "<node-ip>")

echo "============================================="
echo "  Access URLs"
echo "============================================="
echo ""
echo "  Prometheus:  http://${NODE_IP}:30090"
echo "  Grafana:     http://${NODE_IP}:30030"
echo ""
echo "  Grafana default login: admin / admin"
echo ""
echo "  Try these commands:"
echo "    kubectl top nodes"
echo "    kubectl top pods -A"
echo ""
echo "  Recommended Grafana dashboard imports:"
echo "    1860  — Node Exporter Full"
echo "    15760 — Kubernetes Cluster Overview"
echo "    13332 — kube-state-metrics v2"
echo "============================================="
