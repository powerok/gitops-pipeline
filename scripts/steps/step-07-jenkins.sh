#!/bin/bash
# =============================================================
# Step 07: Jenkins 설치 (Secrets 선 생성 포함)
# =============================================================
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  Step 07: Jenkins                    ║"
echo "╚══════════════════════════════════════╝"

K3S_IP=$(get_k3s_ip)
log_info "K3s 서버 IP: ${K3S_IP}"

# Namespace 생성
kubectl create namespace jenkins --dry-run=client -o yaml | kubectl apply -f -

# Jenkins Secrets 초기 생성 (Placeholder — Step 09에서 실제 값으로 업데이트됨)
kubectl create secret generic jenkins-secrets \
  --namespace jenkins \
  --from-literal=gitea-token="PLACEHOLDER_REPLACE_AFTER_GITEA_SETUP" \
  --from-literal=gitea-password="PLACEHOLDER" \
  --from-literal=gitea-ssh-key="PLACEHOLDER" \
  --from-literal=harbor-password="Harbor12345" \
  --dry-run=client -o yaml | kubectl apply -f -

log_info "Jenkins Helm 설치 중..."
helm upgrade --install jenkins jenkins/jenkins \
  --namespace jenkins --create-namespace \
  -f infrastructure/jenkins/values.yaml \
  --set "controller.hostAliases[0].ip=${K3S_IP}" \
  --set "controller.hostAliases[0].hostnames[0]=gitea.local" \
  --set "controller.hostAliases[0].hostnames[1]=harbor.local" \
  --set "controller.hostAliases[0].hostnames[2]=argocd.local" \
  --set "agent.hostAliases[0].ip=${K3S_IP}" \
  --set "agent.hostAliases[0].hostnames[0]=gitea.local" \
  --set "agent.hostAliases[0].hostnames[1]=harbor.local" \
  --set "agent.hostAliases[0].hostnames[2]=argocd.local" \
  --wait --timeout=15m

log_success "Step 07 완료: Jenkins 설치 완료"
