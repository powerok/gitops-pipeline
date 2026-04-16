#!/bin/bash
# =============================================================
# Harbor 초기 설정 스크립트
# 목적: Harbor 프로젝트 생성, Trivy 스캔 활성화,
#       K8s imagePullSecrets 생성을 자동화한다.
#
# 사전 조건:
#   - Harbor가 정상 실행 중이어야 한다.
#   - kubectl이 K3s 클러스터에 연결되어 있어야 한다.
#
# 사용법: bash scripts/harbor-setup.sh
# =============================================================

set -euo pipefail

# ── 설정 변수 ─────────────────────────────────────────────────
HARBOR_URL="${HARBOR_URL:-http://harbor.local}"
HARBOR_USER="${HARBOR_USER:-admin}"
HARBOR_PASS="${HARBOR_PASS:-Harbor12345}"
PROJECT_NAME="gitops"

echo "🚀 Harbor 초기 설정을 시작합니다..."
echo "   Harbor URL: ${HARBOR_URL}"

# ── 헬스체크: Harbor 응답 대기 ────────────────────────────────
echo ""
echo "⏳ Harbor 응답 대기 중..."
for i in $(seq 1 30); do
  if curl -sf "${HARBOR_URL}/api/v2.0/ping" > /dev/null 2>&1; then
    echo "✅ Harbor 응답 확인"
    break
  fi
  echo "   대기 중... (${i}/30)"
  sleep 10
done

# ── Harbor 프로젝트 생성 ──────────────────────────────────────
echo ""
echo "📦 Harbor 프로젝트 생성: ${PROJECT_NAME}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${HARBOR_URL}/api/v2.0/projects" \
  -u "${HARBOR_USER}:${HARBOR_PASS}" \
  -H "Content-Type: application/json" \
  -d "{
    \"project_name\": \"${PROJECT_NAME}\",
    \"metadata\": {
      \"public\": \"true\",
      \"enable_content_trust\": \"false\",
      \"prevent_vul\": \"false\",
      \"severity\": \"high\",
      \"auto_scan\": \"true\"
    }
  }")

if [ "$HTTP_CODE" = "201" ]; then
  echo "✅ 프로젝트 생성 완료"
elif [ "$HTTP_CODE" = "409" ]; then
  echo "ℹ️  프로젝트가 이미 존재합니다. 계속 진행합니다."
else
  echo "❌ 프로젝트 생성 실패 (HTTP: ${HTTP_CODE})"
fi

# ── Trivy 스캔 정책 설정 ──────────────────────────────────────
echo ""
echo "🔍 Trivy 취약점 스캔 정책 설정..."

# 프로젝트 ID 조회
PROJECT_ID=$(curl -s \
  "${HARBOR_URL}/api/v2.0/projects?name=${PROJECT_NAME}" \
  -u "${HARBOR_USER}:${HARBOR_PASS}" | \
  jq '.[0].id')

echo "   프로젝트 ID: ${PROJECT_ID}"

# 스캔 정책 업데이트 (이미지 push 시 자동 스캔)
curl -sf \
  -X PUT "${HARBOR_URL}/api/v2.0/projects/${PROJECT_ID}" \
  -u "${HARBOR_USER}:${HARBOR_PASS}" \
  -H "Content-Type: application/json" \
  -d '{
    "metadata": {
      "auto_scan": "true",
      "prevent_vul": "false",
      "severity": "critical",
      "reuse_sys_cve_allowlist": "true"
    }
  }' && echo "✅ 자동 스캔 정책 설정 완료"

# ── K8s 네임스페이스에 imagePullSecrets 생성 ─────────────────
echo ""
echo "🔐 K8s imagePullSecrets 생성..."

# 생성할 네임스페이스 목록
NAMESPACES=("default" "order-dev" "order-prod" "argocd")

for NS in "${NAMESPACES[@]}"; do
  echo "   네임스페이스: ${NS}"

  # 네임스페이스 생성 (이미 존재하면 무시)
  kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true

  # imagePullSecrets 생성
  kubectl create secret docker-registry harbor-credentials \
    --namespace="${NS}" \
    --docker-server="${HARBOR_URL}" \
    --docker-username="${HARBOR_USER}" \
    --docker-password="${HARBOR_PASS}" \
    --docker-email="admin@harbor.local" \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "   ✅ ${NS} 네임스페이스 시크릿 생성 완료"
done

# ── Trivy DB 초기 업데이트 트리거 ────────────────────────────
echo ""
echo "🔄 Trivy 취약점 DB 업데이트 트리거..."
curl -sf \
  -X POST "${HARBOR_URL}/api/v2.0/system/scanAll/schedule" \
  -u "${HARBOR_USER}:${HARBOR_PASS}" \
  -H "Content-Type: application/json" \
  -d '{"schedule": {"type": "Manual"}}' > /dev/null \
  && echo "✅ Trivy DB 업데이트 시작" \
  || echo "ℹ️  스캔 스케줄 설정 (이미 설정된 경우 무시)"

# ── 완료 요약 ─────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
echo "✅ Harbor 초기 설정 완료!"
echo "═══════════════════════════════════════════════════"
echo ""
echo "📌 접속 정보:"
echo "   Harbor URL  : ${HARBOR_URL}"
echo "   Admin 계정  : ${HARBOR_USER} / ${HARBOR_PASS}"
echo ""
echo "📌 이미지 Push/Pull 예시:"
echo "   Push: docker push harbor.local/gitops/order-api:latest"
echo "   Pull: docker pull harbor.local/gitops/order-api:latest"
echo ""
echo "📌 K8s imagePullSecrets 사용 예시 (Deployment에 추가):"
echo "   imagePullSecrets:"
echo "     - name: harbor-credentials"
