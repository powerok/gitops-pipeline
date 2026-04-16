#!/bin/bash
# =============================================================
# Step 06: Harbor 설치
# =============================================================
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  Step 06: Harbor                     ║"
echo "╚══════════════════════════════════════╝"

helm upgrade --install harbor harbor/harbor \
  --namespace harbor --create-namespace \
  -f infrastructure/harbor/values.yaml \
  --wait --timeout=15m

log_success "Step 06 완료: Harbor 설치 완료"
