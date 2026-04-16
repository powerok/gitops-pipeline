#!/bin/bash
# =============================================================
# Gitea → Jenkins Webhook 자동 등록 스크립트
# 파일 위치: scripts/setup-webhook.sh
#
# 목적: Gitea App 리포지토리에 Jenkins Webhook을 자동으로 등록한다.
#       코드 Push 이벤트 발생 시 Jenkins 파이프라인이 자동 트리거된다.
#
# 사전 조건:
#   - Gitea, Jenkins 모두 실행 중이어야 한다.
#   - Jenkins에 Gitea 플러그인이 설치되어 있어야 한다.
#
# 사용법: bash scripts/setup-webhook.sh
# =============================================================

set -euo pipefail

GITEA_URL="${GITEA_URL:-http://gitea.local}"
GITEA_ADMIN="${GITEA_ADMIN:-gitea-admin}"
GITEA_ADMIN_PASS="${GITEA_ADMIN_PASS:-Gitea@Admin2024!}"

JENKINS_URL="${JENKINS_URL:-http://jenkins.local}"
# Gitea(클러스터 내부)가 Jenkins에 신호를 보낼 때 사용하는 내부 주소
JENKINS_CLUSTER_URL="http://jenkins.jenkins.svc.cluster.local:8080"
JENKINS_WEBHOOK_PATH="/generic-webhook-trigger/invoke?token=order-api-token-2024"
# Webhook 시크릿 (Jenkins와 Gitea 양쪽에 동일하게 설정해야 함)
WEBHOOK_SECRET="GitopsWebhook@Secret2024!"

echo "🔗 Gitea Webhook 설정을 시작합니다..."

# ── order-api 리포지토리에 Webhook 등록 ───────────────────────
echo ""
echo "📌 order-api 리포지토리 Webhook 등록 (Standard)..."

RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${GITEA_URL}/api/v1/repos/gitops/order-api/hooks" \
  -u "${GITEA_ADMIN}:${GITEA_ADMIN_PASS}" \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"gitea\",
    \"config\": {
      \"url\": \"${JENKINS_CLUSTER_URL}${JENKINS_WEBHOOK_PATH}\",
      \"content_type\": \"json\",
      \"insecure_ssl\": \"1\"
    },
    \"events\": [
      \"push\",
      \"pull_request\",
      \"create\"
    ],
    \"branch_filter\": \"*\",
    \"active\": true
  }")

if [ "$RESPONSE" = "201" ]; then
  echo "✅ Webhook 등록 완료 (HTTP 201)"
else
  echo "⚠️  Webhook 응답 코드: ${RESPONSE} (이미 존재하거나 오류일 수 있음)"
fi

# ArgoCD의 클러스터 내부 주소
ARGOCD_CLUSTER_URL="http://argocd-server.argocd.svc.cluster.local"

RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${GITEA_URL}/api/v1/repos/gitops/order-ops/hooks" \
  -u "${GITEA_ADMIN}:${GITEA_ADMIN_PASS}" \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"gitea\",
    \"config\": {
      \"url\": \"${ARGOCD_CLUSTER_URL}/api/webhook\",
      \"content_type\": \"json\",
      \"secret\": \"${WEBHOOK_SECRET}\",
      \"insecure_ssl\": \"1\"
    },
    \"events\": [\"push\"],
    \"active\": true
  }")

if [ "$RESPONSE" = "201" ]; then
  echo "✅ ArgoCD Webhook 등록 완료 (HTTP 201)"
else
  echo "⚠️  ArgoCD Webhook 응답 코드: ${RESPONSE}"
fi

# ── 등록된 Webhook 목록 확인 ─────────────────────────────────
echo ""
echo "📋 등록된 Webhook 목록:"
echo "  [order-api]"
curl -s "${GITEA_URL}/api/v1/repos/gitops/order-api/hooks" \
  -u "${GITEA_ADMIN}:${GITEA_ADMIN_PASS}" | grep -o '"url":"[^"]*"' || echo "  (목록 출력 생략)"

echo ""
echo "  [order-ops]"
curl -s "${GITEA_URL}/api/v1/repos/gitops/order-ops/hooks" \
  -u "${GITEA_ADMIN}:${GITEA_ADMIN_PASS}" | grep -o '"url":"[^"]*"' || echo "  (목록 출력 생략)"

echo ""
echo "═══════════════════════════════════════════════"
echo "✅ Webhook 설정 완료!"
echo ""
echo "📌 Jenkins에서 추가로 설정해야 할 항목:"
echo "   1. Jenkins → Manage Jenkins → Configure System"
echo "   2. Gitea Servers 섹션에 Gitea URL 등록"
echo "   3. Webhook Secret: ${WEBHOOK_SECRET}"
echo ""
echo "📌 ArgoCD에서 Webhook Secret 설정:"
echo "   kubectl create secret generic argocd-secret \\"
echo "     --namespace argocd \\"
echo "     --from-literal=webhook.gitea.secret=${WEBHOOK_SECRET} \\"
echo "     --dry-run=client -o yaml | kubectl apply -f -"
