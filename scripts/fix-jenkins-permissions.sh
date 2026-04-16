#!/bin/bash
# =============================================================
# fix-jenkins-permissions.sh
# 목적: jenkins-bot 계정에 gitops 조직 Owners 팀 쓰기 권한 부여
#       (bootstrap.sh 중단 후 권한이 누락된 경우 단독 실행)
#
# 사용법: bash scripts/fix-jenkins-permissions.sh
# =============================================================

set -euo pipefail

GITEA_URL="${GITEA_URL:-http://localhost:30001}"
ADMIN_USER="${ADMIN_USER:-gitea-admin}"
ADMIN_PASS="${ADMIN_PASS:-Gitea@Admin2024!}"
JENKINS_USER="jenkins-bot"

echo ""
echo "🔐 jenkins-bot Gitea 권한 복구 시작..."
echo "   Gitea URL: ${GITEA_URL}"
echo ""

# ── Gitea 응답 확인 ──────────────────────────────────────────
echo "⏳ Gitea 응답 확인..."
for i in $(seq 1 10); do
  if curl -sf --max-time 5 "${GITEA_URL}/api/v1/version" > /dev/null 2>&1; then
    echo "✅ Gitea 응답 확인"
    break
  fi
  echo "   대기 중... (${i}/10)"
  sleep 3
done

# ── 1. 조직 멤버로 추가 ───────────────────────────────────────
echo ""
echo "👤 조직 멤버 추가: ${JENKINS_USER} → gitops"
curl -s --max-time 30 \
  -X PUT "${GITEA_URL}/api/v1/orgs/gitops/members/${JENKINS_USER}" \
  -u "${ADMIN_USER}:${ADMIN_PASS}" > /dev/null 2>&1 \
  && echo "✅ 조직 멤버 추가 완료" \
  || echo "⚠️  조직 멤버 추가 실패 (이미 존재하거나 무시 가능)"

# ── 2. Owners 팀 ID 동적 조회 ─────────────────────────────────
echo ""
echo "🔍 Owners 팀 ID 조회..."
TEAM_ID=$(curl -s --max-time 30 \
  -u "${ADMIN_USER}:${ADMIN_PASS}" \
  "${GITEA_URL}/api/v1/orgs/gitops/teams" 2>/dev/null \
  | jq -r '.[] | select(.name=="Owners") | .id' 2>/dev/null || true)

if [ -z "$TEAM_ID" ] || [ "$TEAM_ID" = "null" ]; then
  echo "❌ Owners 팀을 찾을 수 없습니다."
  echo "   Gitea UI에서 gitops 조직 > Teams > Owners > Members에 ${JENKINS_USER}를 수동 추가하세요."
  exit 1
fi
echo "   Owners Team ID: ${TEAM_ID}"

# ── 3. Owners 팀에 jenkins-bot 추가 ──────────────────────────
echo ""
echo "🔑 Owners 팀 권한 부여: ${JENKINS_USER}"
HTTP_CODE=$(curl -s --max-time 30 -o /dev/null -w "%{http_code}" \
  -X PUT "${GITEA_URL}/api/v1/teams/${TEAM_ID}/members/${JENKINS_USER}" \
  -u "${ADMIN_USER}:${ADMIN_PASS}")

if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "200" ]; then
  echo "✅ jenkins-bot → GitOps Owners 팀 권한 부여 완료"
else
  echo "❌ 권한 부여 실패 (HTTP: ${HTTP_CODE})"
  exit 1
fi

# ── 4. 결과 확인: 팀 멤버 목록 ───────────────────────────────
echo ""
echo "📋 Owners 팀 멤버 목록 확인:"
curl -s --max-time 30 \
  -u "${ADMIN_USER}:${ADMIN_PASS}" \
  "${GITEA_URL}/api/v1/teams/${TEAM_ID}/members" \
  | jq -r '.[].login' 2>/dev/null || echo "   (jq 조회 실패)"

echo ""
echo "═══════════════════════════════════════════════════"
echo "✅ 권한 복구 완료! Jenkins 파이프라인을 재빌드하세요."
echo "═══════════════════════════════════════════════════"
