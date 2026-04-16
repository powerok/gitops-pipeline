#!/bin/bash
# =============================================================
# Step 02: CoreDNS 커스텀 도메인 설정
# gitea.local, harbor.local, jenkins.local, argocd.local → K3s IP
# =============================================================
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  Step 02: CoreDNS Custom DNS         ║"
echo "╚══════════════════════════════════════╝"

K3S_IP=$(get_k3s_ip)
log_info "K3s 서버 IP: ${K3S_IP}"

kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  gitops.server: |
    gitea.local harbor.local argocd.local jenkins.local {
        hosts {
            ${K3S_IP} gitea.local
            ${K3S_IP} harbor.local
            ${K3S_IP} argocd.local
            ${K3S_IP} jenkins.local
            fallthrough
        }
    }
EOF

kubectl rollout restart deployment coredns -n kube-system
log_info "CoreDNS rollout 완료 대기 중..."
kubectl rollout status deployment coredns -n kube-system --timeout=120s

log_success "Step 02 완료: CoreDNS 도메인 매핑 완료 (IP: ${K3S_IP})"
