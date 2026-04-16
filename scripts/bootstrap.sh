#!/bin/bash
# =============================================================
# bootstrap.sh - Docker Compose 기반 GitOps 스택 구축
# 목적: docker-compose 의 step 서비스들을 순차적으로 실행한다.
#
# 사전 조건:
#   - Docker Desktop 실행 중
#   - /etc/hosts 설정 완료
#
# 사용법:
#   bash scripts/bootstrap.sh
# =============================================================

set -euo pipefail

# 색상 출력 헬퍼
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error()   { echo -e "${RED}❌ $1${NC}"; exit 1; }

echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║   GitOps Pipeline Bootstrap Script                ║"
echo "║   Gitea + Jenkins + Harbor + ArgoCD on K3s        ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# ── 사전 조건 확인 ────────────────────────────────────────────
log_info "사전 조건 확인 중..."

# Docker 확인
if ! command -v docker &> /dev/null; then
  log_error "Docker 가 설치되어 있지 않습니다."
fi

# Docker Compose 확인
if ! docker compose version &> /dev/null; then
  log_error "Docker Compose 가 설치되어 있지 않습니다."
fi

# /etc/hosts 확인 (Windows 는 건너뜀)
if [[ "$OSTYPE" != "msys" && "$OSTYPE" != "win32" ]]; then
  if ! grep -q "gitea.local" /etc/hosts 2>/dev/null; then
    log_warning "/etc/hosts 에 도메인 설정이 없습니다. 추가가 필요합니다."
    echo "   다음 명령을 실행하세요:"
    echo "   echo '127.0.0.1 gitea.local jenkins.local harbor.local argocd.local' | sudo tee -a /etc/hosts"
  fi
fi

log_success "사전 조건 확인 완료"

# ── Docker Compose 로 전체 Step 실행 ───────────────────────────
echo ""
log_info "Docker Compose 로 GitOps 스택 구축 시작..."
log_info "각 Step 이 순차적으로 실행됩니다. 실패한 Step 은 재시작 가능합니다."
echo ""

# docker-compose.yml 이 있는 디렉토리로 이동
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# 전체 서비스 실행 (의존 관계에 따라 순차 실행)
docker compose up -d

# ── Step 완료 대기 ────────────────────────────────────────────
echo ""
log_info "모든 Step 완료 대기 중..."

# step-10-apps 컨테이너가 완료될 때까지 대기
MAX_WAIT=1800  # 30 분
WAITED=0

while [ $WAITED -lt $MAX_WAIT ]; do
  # step-10 앱의 상태 확인
  STATUS=$(docker compose ps -q step-10-apps 2>/dev/null | xargs -r docker inspect -f '{{.State.Status}}' 2>/dev/null || echo "not_found")

  if [ "$STATUS" = "exited" ]; then
    EXIT_CODE=$(docker compose ps -q step-10-apps 2>/dev/null | xargs -r docker inspect -f '{{.State.ExitCode}}' 2>/dev/null || echo "1")
    if [ "$EXIT_CODE" = "0" ]; then
      log_success "Step-10 성공적으로 완료!"
      break
    else
      log_error "Step-10 이 실패했습니다. 로그를 확인하세요: docker compose logs step-10-apps"
    fi
  elif [ "$STATUS" = "not_found" ] || [ "$STATUS" = "created" ]; then
    log_info "Step-10 아직 시작 전... 대기 중"
  elif [ "$STATUS" = "running" ]; then
    log_info "Step-10 실행 중... (${WAITED}초 경과)"
  elif [ "$STATUS" = "dead" ] || [ "$STATUS" = "restarting" ]; then
    log_warning "Step-10 이상 상태: $STATUS"
  fi

  sleep 10
  WAITED=$((WAITED + 10))
done

if [ $WAITED -ge $MAX_WAIT ]; then
  log_warning "대기 시간 초과. 수동으로 상태를 확인하세요."
fi

# ── 최종 상태 확인 ────────────────────────────────────────────
echo ""
log_info "서비스 상태 확인 중..."
docker compose ps

# ── Kubeconfig 설정 ───────────────────────────────────────────
export KUBECONFIG="$PROJECT_ROOT/infrastructure/k3s/output/kubeconfig.yaml"

# K3s 서버 IP 확인
K3S_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' k3s-server 2>/dev/null || echo "N/A")

# ── 최종 완료 요약 ────────────────────────────────────────────
echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║  🎉 GitOps 스택 구축 완료!                          ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""
echo "📌 서비스 접속 주소:"
echo "   Gitea   : http://gitea.local   (gitea-admin / Gitea@Admin2024!)"
echo "   Jenkins : http://jenkins.local (admin / ㅁㅇ)"
echo "   Harbor  : http://harbor.local  (admin / Harbor12345)"
echo "   ArgoCD  : http://argocd.local  (admin / ArgoCD@Admin2024!)"
echo ""

# ArgoCD 비밀번호 출력
ARGOCD_PWD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "N/A")
echo "   ArgoCD admin 비밀번호: ${ARGOCD_PWD}"
echo ""

# Jenkins 빌드 상태 확인
log_info "Jenkins 빌드 상태 확인 중..."
if command -v kubectl &> /dev/null; then
  JENKINS_BUILD=$(kubectl get build -n jenkins 2>/dev/null | tail -n +2 | head -1 || echo "빌드 정보 없음")
  if [ -n "$JENKINS_BUILD" ] && [ "$JENKINS_BUILD" != "빌드 정보 없음" ]; then
    echo "   최신 빌드: ${JENKINS_BUILD}"
  else
    echo "   Jenkins 빌드 확인: http://jenkins.local"
  fi
fi

# ArgoCD 애플리케이션 상태
log_info "ArgoCD 애플리케이션 상태:"
if command -v argocd &> /dev/null; then
  argocd app list 2>/dev/null || echo "   ArgoCD CLI 가 설정되지 않았습니다."
else
  echo "   ArgoCD UI 에서 확인: http://argocd.local"
fi

echo ""
echo "📌 다음 단계:"
echo "   1. Jenkins 대시보드에서 'order-api-pipeline' 빌드 진행 확인"
echo "      → http://jenkins.local → 로그인 → 'Build Now' (수동 트리거 가능)"
echo ""
echo "   2. Harbor 에서 Docker 이미지 확인"
echo "      → http://harbor.local → 'gitops' 프로젝트 → 'order-api'"
echo ""
echo "   3. ArgoCD 에서 애플리케이션 동기화 확인"
echo "      → http://argocd.local → 'order-api-dev' → 'SYNC'"
echo ""
echo "   4. 애플리케이션 서비스 테스트"
echo "      curl -H 'Host: order.local' http://127.0.0.1/api/order"
echo ""

# 문제 발생 시 재시작 가이드
echo "📌 문제 해결:"
echo "   - 특정 Step 부터 재시작: docker compose up -d step-XX-<name>"
echo "   - Step 로그 확인: docker compose logs step-XX-<name>"
echo "   - 전체 초기화: docker compose down -v && bash scripts/teardown.sh"
echo ""
