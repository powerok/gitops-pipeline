#!/bin/bash
# =============================================================
# Step 08: ArgoCD 설치 + Default AppProject 생성
# =============================================================
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  Step 08: ArgoCD                     ║"
echo "╚══════════════════════════════════════╝"

K3S_IP=$(get_k3s_ip)
log_info "K3s 서버 IP: ${K3S_IP}"

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  -f infrastructure/argocd/values.yaml \
  --set "repoServer.hostAliases[0].ip=${K3S_IP}" \
  --set "repoServer.hostAliases[0].hostnames[0]=gitea.local" \
  --set "repoServer.hostAliases[0].hostnames[1]=harbor.local" \
  --wait --timeout=10m

log_info "ArgoCD Default AppProject 생성 중..."
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: default
  namespace: argocd
spec:
  description: Default project
  destinations:
  - namespace: '*'
    server: '*'
  sourceRepos:
  - '*'
EOF

log_success "Step 08 완료: ArgoCD 설치 완료"
