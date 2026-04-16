#!/bin/bash
# =============================================================
# common.sh - 공통 헬퍼 함수 모음
# 모든 step 스크립트에서 source로 로드한다.
# =============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error()   { echo -e "${RED}❌ $1${NC}"; exit 1; }

# 동적 경로 해석 (Docker 컨테이너와 로컬 환경 모두 호환)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# KUBECONFIG 경로를 프로젝트 루트 기준으로 동적 할당
export KUBECONFIG="${KUBECONFIG:-${PROJECT_ROOT}/infrastructure/k3s/output/kubeconfig.yaml}"

patch_kubeconfig() {
  log_info "Kubeconfig 엔드포인트 패치 중 (localhost → k3s-server)..."
  sed -i 's/127.0.0.1:6443/k3s-server:6443/g' "$KUBECONFIG"
  sed -i 's/localhost:6443/k3s-server:6443/g'  "$KUBECONFIG"
}

wait_for_api() {
  local max="${1:-30}"
  log_info "API 서버 대기 중..."
  for i in $(seq 1 "$max"); do
    kubectl get nodes &>/dev/null && return 0
    log_info "API 서버 대기 중... (${i}/${max})"
    sleep 5
  done
  log_error "API 서버가 응답하지 않습니다."
}

get_k3s_ip() {
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' k3s-server
}
