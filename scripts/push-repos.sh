#!/bin/bash
set -euo pipefail

GITEA_URL="http://gitea.local"
ADMIN_USER="gitea-admin"
ADMIN_PASS_URL="Gitea%40Admin2024!"

push_repo() {
    local DIR="$1"
    local REMOTE_PATH="$2"
    local COMMIT_MSG="$3"

    echo "🚀 Pushing ${DIR} to Gitea (${REMOTE_PATH})..."
    cd "${DIR}"

    # 이미 .git 이 있으면 init 생략, 없으면 초기화
    if [ ! -d ".git" ]; then
        git init
        git checkout -b main
    else
        # 브랜치가 main 인지 확인, 아니면 전환
        git checkout main 2>/dev/null || git checkout -b main
    fi

    git add .
    git config user.email "admin@gitea.local"
    git config user.name "gitea-admin"

    # 변경사항이 있을 때만 커밋
    if ! git diff --cached --quiet 2>/dev/null || ! git diff --quiet 2>/dev/null; then
        git commit -m "${COMMIT_MSG}" 2>/dev/null || true
    else
        git commit -m "${COMMIT_MSG}" 2>/dev/null || echo "  (이미 커밋된 상태, 건너뜀)"
    fi

    git push -f "http://${ADMIN_USER}:${ADMIN_PASS_URL}@gitea.local/${REMOTE_PATH}.git" main
    cd - > /dev/null
    echo "  ✅ ${DIR} push 완료"
}

push_repo "apps/order-api"          "gitops/order-api"               "Initial commit for order-api"
push_repo "apps/order-ops"          "gitops/order-ops"               "Initial commit for order-ops"
push_repo "jenkins/shared-library"  "gitops/jenkins-shared-library"  "Initial commit for Jenkins shared library"

echo ""
echo "✅ Repositories pushed successfully!"
