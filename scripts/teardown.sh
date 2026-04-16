#!/bin/bash
# =============================================================
# teardown.sh - 완전 초기화 스크립트
# 목적: K3s 클러스터 및 볼륨, 생성된 토큰, 로컬 Git 데이터를 모두 삭제하여
# 처음부터(bootstrap.sh) 다시 테스트할 수 있는 깨끗한 상태로 되돌립니다.
#
# 사용법: bash scripts/teardown.sh
# =============================================================

set -e

# 색상 출력 헬퍼
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }

echo "⚠️  주의: 이 작업은 K3s 클러스터, 데이터베이스 볼륨, 설정 파일들을 모두 삭제합니다."
read -p "계속 진행하시겠습니까? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "초기화를 취소합니다."
  exit 0
fi

echo ""
log_info "Step 1: K3s 클러스터 및 Docker Volumes 삭제 중..."
docker compose down -v --remove-orphans
log_success "K3s 클러스터 및 볼륨 삭제 완료"

log_info "Step 2: 생성된 임시 데이터 및 시크릿 삭제 중..."
rm -f infrastructure/k3s/output/kubeconfig.yaml || true
rm -f .jenkins-gitea-token || true
rm -f id_ed25519_jenkins id_ed25519_jenkins.pub || true
rm -f values-temp.yaml || true
log_success "임시 데이터 삭제 완료"

log_info "Step 3: 로컬 App 레포지토리 Git 히스토리 초기화 중..."
rm -rf apps/order-api/.git || true
rm -rf apps/order-ops/.git || true
rm -rf jenkins/shared-library/.git || true
log_success "로컬 Git 레포지토리 초기화 완료"

echo ""
echo "================================================================="
echo "🎉 모든 환경이 완벽하게 초기화되었습니다!"
echo "이제 다음 명령어를 통해 백지 상태에서 파이프라인을 구축해볼 수 있습니다:"
echo "👉 bash scripts/bootstrap.sh"
echo "================================================================="
