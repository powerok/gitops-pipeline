#!/bin/bash
# =============================================================
# Gitea 초기 설정 스크립트
# 목적: Jenkins 연동을 위한 계정, 토큰, 리포지토리를 자동 생성한다.
#
# 사전 조건:
#   - Gitea가 정상 실행 중이어야 한다.
#   - curl, jq 가 설치되어 있어야 한다.
#
# 사용법: bash scripts/gitea-setup.sh
# =============================================================

set -euo pipefail

# ── 설정 변수 ─────────────────────────────────────────────────
GITEA_URL="${GITEA_URL:-http://gitea.local}"
ADMIN_USER="${ADMIN_USER:-gitea-admin}"
ADMIN_PASS="${ADMIN_PASS:-Gitea@Admin2024!}"

# 색상 출력 헬퍼
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error()   { echo -e "${RED}❌ $1${NC}"; exit 1; }

# Jenkins 전용 서비스 계정
JENKINS_USER="jenkins-bot"
JENKINS_PASS="JenkinsBot2024"
JENKINS_EMAIL="jenkins@gitea.local"

echo "🚀 Gitea 초기 설정을 시작합니다..."
echo "   Gitea URL: ${GITEA_URL}"

# ── 헬스체크: Gitea 응답 대기 ─────────────────────────────────
echo ""
echo "⏳ Gitea 응답 대기 중..."
for i in $(seq 1 30); do
  if curl -sf --max-time 5 "${GITEA_URL}/api/v1/version" > /dev/null 2>&1; then
    echo "✅ Gitea 응답 확인"
    break
  fi
  echo "   대기 중... (${i}/30)"
  sleep 5
done

# ── Jenkins 전용 계정 생성 (관리자 권한 부여) ───────────────
echo ""
log_info "👤 Jenkins 서비스 계정 생성: ${JENKINS_USER}"
# 신규 가입 시 관리자 권한 부여
curl -s --max-time 30 \
  -X POST "${GITEA_URL}/api/v1/admin/users" \
  -u "${ADMIN_USER}:${ADMIN_PASS}" \
  -H "Content-Type: application/json" \
  -d "{
    \"login_name\": \"${JENKINS_USER}\",
    \"username\": \"${JENKINS_USER}\",
    \"email\": \"${JENKINS_EMAIL}\",
    \"password\": \"${JENKINS_PASS}\",
    \"must_change_password\": false,
    \"send_notify\": false,
    \"active\": true,
    \"is_admin\": true
  }" > /dev/null 2>&1 || true

# 기존 계정일 경우 관리자 권한 및 비밀번호 강제 업데이트 (인증 성공률 향상)
log_info "   계정 권한 및 비밀번호 업데이트 중..."
curl -s --max-time 30 -X PATCH "${GITEA_URL}/api/v1/admin/users/${JENKINS_USER}" \
  -u "${ADMIN_USER}:${ADMIN_PASS}" \
  -H "Content-Type: application/json" \
  -d "{
    \"admin\": true,
    \"password\": \"${JENKINS_PASS}\",
    \"must_change_password\": false
  }" > /dev/null 2>&1

# ── Jenkins API 토큰 생성 ──────────────────────────────────────
echo ""
log_info "🔑 Jenkins API 토큰 생성 (강제 갱신)..."

# 기존에 동일한 이름의 토큰이 있다면 먼저 삭제 (정합성 보장)
curl -s --max-time 30 \
    -X DELETE "${GITEA_URL}/api/v1/users/${JENKINS_USER}/tokens/jenkins-webhook-token" \
    -u "${JENKINS_USER}:${JENKINS_PASS}" > /dev/null 2>&1 || true

TOKEN_RESPONSE=$(curl -s --max-time 30 \
  -X POST "${GITEA_URL}/api/v1/users/${JENKINS_USER}/tokens" \
  -u "${JENKINS_USER}:${JENKINS_PASS}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "jenkins-webhook-token",
    "scopes": ["all"]
  }')

JENKINS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.sha1 // empty')
if [ -z "$JENKINS_TOKEN" ] || [ "$JENKINS_TOKEN" = "null" ]; then
  log_warning "토큰 생성에 실패했습니다. 기존 설정(.jenkins-gitea-token) 사용을 시도합니다."
  if [ ! -f ".jenkins-gitea-token" ]; then
    log_error "사용 가능한 토큰이 없습니다. 설정을 중단합니다."
  fi
  JENKINS_TOKEN=$(cat .jenkins-gitea-token)
else
  log_success "Jenkins API 토큰 생성 완료"
  echo "${JENKINS_TOKEN}" > .jenkins-gitea-token
  log_info "   새로운 토큰이 .jenkins-gitea-token 파일에 저장되었습니다."
fi

# ── 조직(Organization) 생성 ──────────────────────────────────
echo ""
echo "🏢 GitOps 조직 생성..."
curl -sf --max-time 30 \
  -X POST "${GITEA_URL}/api/v1/orgs" \
  -u "${ADMIN_USER}:${ADMIN_PASS}" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "gitops",
    "full_name": "GitOps Organization",
    "description": "GitOps 파이프라인 조직",
    "visibility": "public"
  }' > /dev/null && echo "✅ 조직 생성 완료" || echo "ℹ️  조직이 이미 존재합니다."

# ── App 리포지토리 생성 (소스 코드) ──────────────────────────
echo ""
echo "📦 App 리포지토리 생성: order-api (소스 코드)..."
curl -sf --max-time 30 \
  -X POST "${GITEA_URL}/api/v1/orgs/gitops/repos" \
  -u "${ADMIN_USER}:${ADMIN_PASS}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "order-api",
    "description": "Order API 소스 코드 리포지토리",
    "private": false,
    "auto_init": true,
    "default_branch": "main"
  }' > /dev/null && echo "✅ order-api 리포지토리 생성 완료" || echo "ℹ️  리포지토리가 이미 존재합니다."

# ── Ops 리포지토리 생성 (Helm Manifest) ──────────────────────
echo ""
echo "📦 Ops 리포지토리 생성: order-ops (Helm Manifest)..."
curl -sf --max-time 30 \
  -X POST "${GITEA_URL}/api/v1/orgs/gitops/repos" \
  -u "${ADMIN_USER}:${ADMIN_PASS}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "order-ops",
    "description": "Order System Ops 리포지토리 (Helm Charts, ArgoCD Application)",
    "private": false,
    "auto_init": true,
    "default_branch": "main"
  }' > /dev/null && echo "✅ order-ops 리포지토리 생성 완료" || echo "ℹ️  리포지토리가 이미 존재합니다."

# ── Shared Library 리포지토리 생성 ──────────────────────────
echo ""
echo "📦 Shared Library 리포지토리 생성: jenkins-shared-library..."
curl -sf --max-time 30 \
  -X POST "${GITEA_URL}/api/v1/orgs/gitops/repos" \
  -u "${ADMIN_USER}:${ADMIN_PASS}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "jenkins-shared-library",
    "description": "Jenkins Shared Library 리포지토리",
    "private": false,
    "auto_init": true,
    "default_branch": "main"
  }' > /dev/null && echo "✅ jenkins-shared-library 리포지토리 생성 완료" || echo "ℹ️  리포지토리가 이미 존재합니다."

# ── Jenkins 계정에 조직 멤버 권한 부여 및 Owners 팀 자동 등록 ──
echo ""
echo "🔐 Jenkins 계정 권한 설정..."
# 1. 조직 멤버로 추가 (204 No Content 정상, 실패해도 계속 진행)
curl -s --max-time 30 \
  -X PUT "${GITEA_URL}/api/v1/orgs/gitops/members/${JENKINS_USER}" \
  -u "${ADMIN_USER}:${ADMIN_PASS}" > /dev/null 2>&1 \
  && echo "✅ 조직 멤버 추가 완료" || echo "⚠️  조직 멤버 추가 실패 (계속 진행)"

# 2. Owners 팀에 추가하여 리포지토리 쓰기 권한 확보
# Gitea 버전에 따라 'Owners' 또는 한국어 '소유자'로 되어 있을 수 있음
TEAM_ID=$(curl -s --max-time 30 -u "${ADMIN_USER}:${ADMIN_PASS}" \
  "${GITEA_URL}/api/v1/orgs/gitops/teams" 2>/dev/null | jq -r '.[] | select(.name=="Owners" or .name=="소유자") | .id' 2>/dev/null || true)

if [ -n "$TEAM_ID" ] && [ "$TEAM_ID" != "null" ]; then
  log_info "   팀 ID 확인: ${TEAM_ID} (jenkins-bot 추가 중...)"
  curl -s --max-time 30 -X PUT "${GITEA_URL}/api/v1/teams/${TEAM_ID}/members/${JENKINS_USER}" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" > /dev/null 2>&1 \
    && echo "✅ Jenkins 계정에 GitOps Owners 권한 부여 완료" \
    || echo "⚠️  Owners 팀 권한 부여 실패 (계속 진행)"
else
  # 만약 ID를 찾지 못했다면 첫 번째 팀이라도 시도하거나 경고 출력
  log_warning "Owners 또는 소유자 팀을 찾을 수 없습니다. 수동 권한 확인이 필요합니다."
  # 팁: Gitea API로 직접 팀을 생성하거나 조인하는 구문을 보강할 수 있음
fi

# ── Gitea Webhook 등록 (Jenkins 트리거용) ──────────────────────
echo ""
echo "🔗 Gitea Webhook 등록은 step-10 (setup-webhook.sh) 에서 통합하여 진행합니다..."
# 기존 gitea-webhook/post 중복 등록 기능 제거

# ── SSH 키 생성 및 등록 ──────────────────────────────────────
echo ""
log_info "🔑 Jenkins용 SSH 키 생성 및 Gitea 등록..."

# SSH 키 생성 (이미 있으면 건너뜀)
if [ ! -f "id_ed25519_jenkins" ]; then
    log_info "   새로운 SSH 키 쌍 생성 중 (ED25519)..."
    # ED25519 포맷으로 생성 (단순하고 강력함)
    ssh-keygen -t ed25519 -f id_ed25519_jenkins -N "" -q
    log_success "   SSH 키 생성 완료 (ED25519)"
fi

# Gitea에 기존 키가 있는지 확인하고 삭제 (정합성 보장)
KEY_ID=$(curl -s --max-time 30 -u "${JENKINS_USER}:${JENKINS_PASS}" \
  "${GITEA_URL}/api/v1/user/keys" | jq -r '.[] | select(.title=="jenkins-agent-key") | .id' || true)

if [ -n "$KEY_ID" ] && [ "$KEY_ID" != "null" ]; then
    log_info "   기존 SSH 키 삭제 중 (ID: ${KEY_ID})..."
    curl -s --max-time 30 -X DELETE "${GITEA_URL}/api/v1/user/keys/${KEY_ID}" \
      -u "${JENKINS_USER}:${JENKINS_PASS}" > /dev/null 2>&1
fi

# Gitea에 공개키 등록
PUB_KEY=$(cat id_ed25519_jenkins.pub)
log_info "   Gitea 서버에 공개키 등록 중..."
curl -s --max-time 30 -X POST "${GITEA_URL}/api/v1/user/keys" \
  -u "${JENKINS_USER}:${JENKINS_PASS}" \
  -H "Content-Type: application/json" \
  -d "{
    \"title\": \"jenkins-agent-key\",
    \"key\": \"${PUB_KEY}\",
    \"read_only\": false
  }" > /dev/null 2>&1 \
  && log_success "   SSH 공개키 등록 완료" \
  || log_warning "   SSH 공개키 등록 실패 (이미 존재할 수 있음)"

# ── 완료 요약 ─────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
log_success "✅ Gitea 초기 설정 완료!"
echo "═══════════════════════════════════════════════════"
echo ""
echo "📌 접속 정보:"
echo "   Admin URL  : ${GITEA_URL}"
echo "   Admin 계정 : ${ADMIN_USER} / ${ADMIN_PASS}"
echo "   Jenkins 봇 : ${JENKINS_USER} / ${JENKINS_PASS}"
echo ""
echo "📌 Jenkins에 등록할 정보:"
echo "   Gitea Token : ${JENKINS_TOKEN}"
echo "   App Repo    : ${GITEA_URL}/gitops/order-api.git"
echo "   Ops Repo    : ${GITEA_URL}/gitops/order-ops.git"
echo ""
echo "⚠️  주의: id_rsa_jenkins 파일과 .jenkins-gitea-token 파일을 안전하게 보관하세요."
