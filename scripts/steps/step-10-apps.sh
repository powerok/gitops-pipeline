#!/bin/bash
# =============================================================
# Step 10: Gitea Webhook 등록 + Source Code Push + Jenkins Build + ArgoCD App-of-Apps
# =============================================================
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  Step 10: Apps & ArgoCD Registration ║"
echo "╚══════════════════════════════════════╝"

# ── 1. Gitea Webhook 등록 ──────────────────────────────────────
log_info "Gitea Webhook 등록 중..."
bash scripts/setup-webhook.sh

# ── Webhook 등록 확인 ──────────────────────────────────────────
log_info "Webhook 등록 상태 확인 중..."
GITEA_URL="http://gitea.local"
GITEA_ADMIN="gitea-admin"
GITEA_ADMIN_PASS="Gitea@Admin2024!"

WEBHOOK_INFO=$(curl -s "${GITEA_URL}/api/v1/repos/gitops/order-api/hooks" \
    -u "${GITEA_ADMIN}:${GITEA_ADMIN_PASS}" 2>/dev/null || echo "")

if [ -n "$WEBHOOK_INFO" ]; then
    WEBHOOK_URL=$(echo "$WEBHOOK_INFO" | grep -o '"url":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
    WEBHOOK_ACTIVE=$(echo "$WEBHOOK_INFO" | grep -o '"active":true' || echo "")

    if [ -n "$WEBHOOK_ACTIVE" ]; then
        log_success "Gitea Webhook 활성 상태 확인"
        log_info "  Webhook URL: ${WEBHOOK_URL:-확인불가}"
    else
        log_warning "Gitea Webhook 이 비활성 상태입니다!"
    fi
else
    log_error "Gitea Webhook 정보를 가져올 수 없습니다."
fi

# (Code push is moved to after Jenkins Job readiness check to prevent webhook failure)

# ── 3. Jenkins Webhook 수신 설정 진단 ──────────────────────────
log_info "Jenkins Webhook 수신 설정 진단 중..."

JOB_NAME="order-api-pipeline"

# Jenkins Pod 이름 동적으로 찾기
JENKINS_POD=$(kubectl get pods -n jenkins -l app.kubernetes.io/instance=jenkins -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$JENKINS_POD" ]; then
    # 대체 레이블 시도
    JENKINS_POD=$(kubectl get pods -n jenkins -l app=jenkins -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
fi

if [ -z "$JENKINS_POD" ]; then
    log_error "Jenkins Pod 를 찾을 수 없습니다."
    exit 1
fi

log_info "Jenkins Pod 발견: ${JENKINS_POD}"

# Jenkins Pod 에서 Gitea 플러그인 설정 확인
log_info "Jenkins Gitea 플러그인 설정 확인..."

# Gitea 서버 설정 확인
GITEA_CONFIG=$(kubectl exec -n jenkins "${JENKINS_POD}" -- \
    curl -s -u admin:Jenkins@Admin2024! \
    "http://localhost:8080/descriptorByName/org.jenkinsci.plugin.gitea.GiteaServer/checkUrl" \
    -d "value=http://gitea.local" 2>/dev/null || echo "")

if echo "$GITEA_CONFIG" | grep -q "ok\|success" 2>/dev/null; then
    log_success "Jenkins-Gitea 연결 정상"
else
    log_warning "Jenkins-Gitea 연결 설정 확인 필요"
fi

# Job 이 존재하는지 확인 — Job DSL 초기화 완료까지 최대 2 분 대기
JOB_WAIT=0
JOB_MAX=120
JOB_EXISTS=""
while [ $JOB_WAIT -lt $JOB_MAX ]; do
    JOB_EXISTS=$(kubectl exec -n jenkins "${JENKINS_POD}" -- \
        curl -s -u admin:Jenkins@Admin2024! \
        "http://localhost:8080/job/${JOB_NAME}/api/json" 2>/dev/null | \
        grep -o '"displayName":"[^"]*"' || echo "")
    if [ -n "$JOB_EXISTS" ]; then
        log_success "Jenkins Job '${JOB_NAME}' 존재 확인"
        break
    fi
    log_info "Jenkins Job '${JOB_NAME}' 초기화 대기 중... (${JOB_WAIT}초 / ${JOB_MAX}초)"
    sleep 10
    JOB_WAIT=$((JOB_WAIT + 10))
done

if [ -z "$JOB_EXISTS" ]; then
    log_error "Jenkins Job '${JOB_NAME}' 이 ${JOB_MAX}초 내에 생성되지 않았습니다!"
    log_info "Jenkins JCasC / Job DSL 초기화 로그를 확인하세요:"
    log_info "  kubectl logs -n jenkins ${JENKINS_POD} --tail=100"
    exit 1
fi

# ── 4. Source Code Push (app + ops 레포) ───────────────────────
log_info "앱 및 Ops Source Code 를 Gitea 에 푸시 중..."
bash scripts/push-repos.sh
log_success "Source Code Push 완료 / Webhook 전송"

# ── 5. Jenkins 빌드 대기 (Webhook 자동 트리거) ────────────────
log_info "Jenkins Webhook 자동 빌드 대기 중 (최대 90초)..."
log_info "Source Code Push → Gitea Webhook → Jenkins 자동 빌드 흐름"

WEBHOOK_WAIT=90
WAITED=0
BUILD_TRIGGERED=false

while [ $WAITED -lt $WEBHOOK_WAIT ]; do
    LAST_BUILD=$(kubectl exec -n jenkins "${JENKINS_POD}" -- \
        curl -s -u admin:Jenkins@Admin2024! \
        "http://localhost:8080/job/${JOB_NAME}/lastBuild/api/json" 2>/dev/null || echo "")

    IS_BUILDING=$(echo "$LAST_BUILD" | grep -o '"building":true' || echo "")
    BUILD_STATUS=$(echo "$LAST_BUILD" | grep -o '"result":"[^"]*"' | cut -d'"' -f4 || echo "")

    if [ -n "$IS_BUILDING" ]; then
        log_success "✅ Webhook 자동 빌드 시작됨! (${WAITED}초)"
        BUILD_TRIGGERED=true
        break
    elif [ "$BUILD_STATUS" = "SUCCESS" ] || [ "$BUILD_STATUS" = "FAILURE" ]; then
        log_success "✅ Webhook 자동 빌드 완료: $BUILD_STATUS (${WAITED}초)"
        BUILD_TRIGGERED=true
        break
    fi

    log_info "Webhook 대기 중... (${WAITED}초 / ${WEBHOOK_WAIT}초)"
    sleep 10
    WAITED=$((WAITED + 10))
done

# Webhook 실패 시 - CSRF crumb 방식으로 직접 트리거 (fallback)
if [ "$BUILD_TRIGGERED" = false ]; then
    log_warning "Webhook 자동 트리거 실패. CSRF crumb 방식으로 직접 트리거합니다..."
    CRUMB_JSON=$(kubectl exec -n jenkins "${JENKINS_POD}" -- \
        curl -s -c /tmp/cookies.txt -u admin:Jenkins@Admin2024! \
        "http://localhost:8080/crumbIssuer/api/json" 2>/dev/null || echo "")
    CRUMB=$(echo "$CRUMB_JSON" | grep -o '"crumb":"[^"]*"' | cut -d'"' -f4 || echo "")
    if [ -n "$CRUMB" ]; then
        kubectl exec -n jenkins "${JENKINS_POD}" -- \
            curl -s -X POST -u admin:Jenkins@Admin2024! \
            -b /tmp/cookies.txt -H "Jenkins-Crumb: ${CRUMB}" \
            "http://localhost:8080/job/${JOB_NAME}/build" 2>/dev/null || true
        log_info "빌드 수동 트리거 완료 (fallback)"
    fi
    sleep 5
fi

# ── 5. Jenkins 빌드 완료 대기 (최대 15 분) ─────────────────────
log_info "Jenkins 빌드 완료 대기 중... (최대 15 분)"
log_info "빌드가 시작되지 않았다면 http://jenkins.local 에서 'Build Now' 를 수동으로 클릭하세요."
MAX_WAIT=900
WAITED=0

# Jenkins Pod 이름 동적으로 찾기
JENKINS_POD=$(kubectl get pods -n jenkins -l app.kubernetes.io/instance=jenkins -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$JENKINS_POD" ]; then
    # 대체 레이블 시도
    JENKINS_POD=$(kubectl get pods -n jenkins -l app=jenkins -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
fi

if [ -z "$JENKINS_POD" ]; then
    log_warning "Jenkins Pod 를 찾을 수 없습니다. 수동으로 확인하세요."
else
    log_info "Jenkins Pod 발견: ${JENKINS_POD}"
fi

while [ $WAITED -lt $MAX_WAIT ]; do
    if [ -n "$JENKINS_POD" ]; then
        BUILD_STATUS=$(kubectl exec -n jenkins "${JENKINS_POD}" -- \
            curl -s -u admin:Jenkins@Admin2024! \
            "http://localhost:8080/job/${JOB_NAME}/lastBuild/api/json" 2>/dev/null | \
            grep -o '"result":"[^"]*"' | cut -d'"' -f4 || echo "")

        IS_BUILDING=$(kubectl exec -n jenkins "${JENKINS_POD}" -- \
            curl -s -u admin:Jenkins@Admin2024! \
            "http://localhost:8080/job/${JOB_NAME}/lastBuild/api/json" 2>/dev/null | \
            grep -o '"building":true' || echo "")

        if [ -n "$IS_BUILDING" ]; then
            log_info "Jenkins 빌드 실행 중... (${WAITED}초 경과)"
        elif [ "$BUILD_STATUS" = "SUCCESS" ]; then
            log_success "Jenkins 빌드 완료!"
            break
        elif [ "$BUILD_STATUS" = "FAILURE" ]; then
            log_warning "Jenkins 빌드 실패. 수동 확인 필요: http://jenkins.local"
            break
        else
            log_info "Jenkins 빌드 대기 중... (${WAITED}초 / ${MAX_WAIT}초)"
        fi
    else
        log_info "Jenkins 빌드 대기 중... (${WAITED}초 / ${MAX_WAIT}초)"
    fi

    sleep 10
    WAITED=$((WAITED + 10))
done



if [ $WAITED -ge $MAX_WAIT ]; then
    log_warning "Jenkins 빌드 대기 시간 초과."
    log_info "수동으로 빌드를 실행하세요: http://jenkins.local → 'Build Now'"
fi

# ── 6. Harbor 이미지 확인 ──────────────────────────────────────
log_info "Harbor 레지스트리에 이미지 확인 중..."
# harbor 네임스페이스에 설치된 서비스 내부 주소 (port 80)
HARBOR_SVC_URL="http://harbor.harbor.svc.cluster.local:80"

HARBOR_RESP=$(kubectl exec -n jenkins "${JENKINS_POD}" -- \
    curl -s -o /dev/null -w "%{http_code}" \
    -u "admin:Harbor12345" \
    "${HARBOR_SVC_URL}/api/v2.0/projects/gitops/repositories/order-api/artifacts" 2>/dev/null || echo "")

if [ "$HARBOR_RESP" = "200" ]; then
    log_success "Harbor 에 이미지가 Push 되었습니다."
elif [ "$HARBOR_RESP" = "404" ]; then
    log_warning "Harbor 에 이미지가 아직 없습니다. Jenkins 빌드가 완료되어야 합니다."
else
    log_warning "Harbor 이미지 확인 실패 (HTTP ${HARBOR_RESP}). Jenkins 빌드를 확인하세요."
fi

# ── 7. ArgoCD App-of-Apps 등록 ─────────────────────────────────
log_info "ArgoCD App-of-Apps 등록 중..."
kubectl apply -f argocd/app-of-apps/root-app.yaml -n argocd
log_success "ArgoCD App-of-Apps 등록 완료"

# ── 최종 완료 요약 ─────────────────────────────────────────────
echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║  🎉 GitOps 스택 구축 완료!                          ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""
echo "📌 서비스 접속 주소:"
echo "   Gitea   : http://gitea.local   (gitea-admin / Gitea@Admin2024!)"
echo "   Jenkins : http://jenkins.local (admin / Jenkins@Admin2024!)"
echo "   Harbor  : http://harbor.local  (admin / Harbor12345)"
echo "   ArgoCD  : http://argocd.local  (admin / ArgoCD@Admin2024!)"
echo ""
ARGOCD_PWD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "N/A")
echo "   ArgoCD admin 비밀번호: ${ARGOCD_PWD}"
echo ""
echo "📌 다음 단계:"
echo "   1. Jenkins 에서 빌드 확인: http://jenkins.local → 'Build Now'"
echo "   2. Harbor 에서 이미지 확인: http://harbor.local"
echo "   3. ArgoCD 에서 SYNC: http://argocd.local → 'SYNC'"
echo "   4. 서비스 테스트: curl -H 'Host: order.local' http://127.0.0.1/api/order"
echo ""
echo "📌 문제 해결:"
echo "   - 재시작: docker compose up -d step-10-apps"
echo "   - 로그: docker compose logs step-10-apps"
echo ""
