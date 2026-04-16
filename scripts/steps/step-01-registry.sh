#!/bin/bash
# =============================================================
# Step 01: Harbor 레지스트리 신뢰 설정 + K3s 재시작
# =============================================================
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  Step 01: Registry & Kubeconfig      ║"
echo "╚══════════════════════════════════════╝"

# kubeconfig 패치 (컨테이너 내부 → k3s-server 호스트명)
patch_kubeconfig

# API 서버 대기
wait_for_api 30

# registries.yaml 복사 후 K3s 재시작
log_info "registries.yaml 적용 중..."
docker cp infrastructure/k3s/registries.yaml k3s-server:/etc/rancher/k3s/registries.yaml

log_info "K3s 재시작 중 (Harbor 신뢰 적용)..."
docker restart k3s-server

log_info "K3s 재기동 대기 중 (30초)..."
sleep 30

# 재시작 후 kubeconfig 재패치 (파일이 초기화됨)
patch_kubeconfig
export KUBECONFIG="${KUBECONFIG}"

# API 서버 재연결 대기
wait_for_api 15

kubectl get nodes
log_success "Step 01 완료: Harbor 레지스트리 신뢰 설정 완료"
