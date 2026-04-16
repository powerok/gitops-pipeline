#!/bin/bash
# =============================================================
# Step 05: Gitea 설치
# =============================================================
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  Step 05: Gitea                      ║"
echo "╚══════════════════════════════════════╝"

helm upgrade --install gitea gitea-charts/gitea \
  --namespace gitea --create-namespace \
  -f infrastructure/gitea/values.yaml \
  --wait --timeout=10m

log_success "Step 05 완료: Gitea 설치 완료"
