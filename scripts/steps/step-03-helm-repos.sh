#!/bin/bash
# =============================================================
# Step 03: Helm 리포지토리 추가 및 업데이트
# =============================================================
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  Step 03: Helm Repositories          ║"
echo "╚══════════════════════════════════════╝"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx  || true
helm repo add gitea-charts   https://dl.gitea.io/charts/                || true
helm repo add jenkins        https://charts.jenkins.io                  || true
helm repo add harbor         https://helm.goharbor.io                  || true
helm repo add argo           https://argoproj.github.io/argo-helm      || true
helm repo update

log_success "Step 03 완료: Helm 리포지토리 추가 완료"
