#!/bin/bash
# =============================================================
# Step 09: 초기 설정 (Gitea 봇 계정/토큰, Harbor 프로젝트,
#           Jenkins Secrets 업데이트, ArgoCD Webhook)
# =============================================================
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  Step 09: Initial Setup              ║"
echo "╚══════════════════════════════════════╝"

# Gitea 설정 (봇 계정, 토큰, 리포지토리 생성)
log_info "Gitea 초기 설정 중..."
bash scripts/gitea-setup.sh

# Harbor 설정 (프로젝트 생성 등)
log_info "Harbor 초기 설정 중..."
bash scripts/harbor-setup.sh

# ── Jenkins Secrets 업데이트 (실제 토큰/비밀번호/SSH 키로 교체) ──
if [ -f ".jenkins-gitea-token" ]; then
  GITEA_TOKEN=$(cat .jenkins-gitea-token)
  log_info "Jenkins Secrets 실제 값으로 업데이트 중..."
  kubectl create secret generic jenkins-secrets \
    --namespace jenkins \
    --from-literal=gitea-token="${GITEA_TOKEN}" \
    --from-literal=gitea-password="JenkinsBot2024" \
    --from-file=gitea-ssh-key=id_ed25519_jenkins \
    --from-literal=harbor-password="Harbor12345" \
    --dry-run=client -o yaml | kubectl apply -f -
  # Jenkins 파드를 재시작하여 환경변수(GITEA_SSH_KEY 등)를 다시 로드하게 함
  log_info "  Jenkins 파드 재시작 중 (신규 Secret 적용)..."
  kubectl delete pod -n jenkins -l app.kubernetes.io/instance=jenkins
  log_success "  Jenkins Secrets 업데이트 및 파드 재시작 완료"
else
  log_warning ".jenkins-gitea-token 파일 없음 — Jenkins Secrets를 갱신하지 않습니다."
fi

# ── ArgoCD에 Gitea 토큰 주입 ─────────────────────────────────────
if [ -f ".jenkins-gitea-token" ]; then
  GITEA_TOKEN=$(cat .jenkins-gitea-token)
  K3S_IP=$(get_k3s_ip)
  log_info "ArgoCD 설정에 Gitea 토큰 주입 및 재설치 중..."
  # 특정 리포지토리(order-ops) 아래의 password 필드를 정확하게 찾아 교체 (이미 토큰이 있는 경우에도 대응)
  sed -i "/order-ops:/,/password:/ s/password: .*/password: \"${GITEA_TOKEN}\"/" infrastructure/argocd/values.yaml
  helm upgrade --install argocd argo/argo-cd \
    --namespace argocd --create-namespace \
    -f infrastructure/argocd/values.yaml \
    --set "repoServer.hostAliases[0].ip=${K3S_IP}" \
    --set "repoServer.hostAliases[0].hostnames[0]=gitea.local" \
    --set "repoServer.hostAliases[0].hostnames[1]=harbor.local" \
    --wait --timeout=10m
  log_success "  ArgoCD Gitea 토큰 적용 완료"
fi

# ── ArgoCD Webhook Secret 설정 ────────────────────────────────────
WEBHOOK_SECRET="GitopsWebhook@Secret2024!"
log_info "ArgoCD Webhook Secret 설정 중..."
kubectl patch secret argocd-secret \
  -n argocd \
  --patch "{\"data\":{\"webhook.gitea.secret\":\"$(echo -n "${WEBHOOK_SECRET}" | base64)\"}}"

# ── Maven Cache PVC 생성 ──────────────────────────────────────────
log_info "Maven Cache PVC 생성 중..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: maven-cache-pvc
  namespace: jenkins
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: local-path
  resources:
    requests:
      storage: 5Gi
EOF

log_success "Step 09 완료: 초기 설정 완료"
