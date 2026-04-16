#!/bin/bash
# =============================================================
# Step 04: Ingress-Nginx 설치
# =============================================================
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  Step 04: Ingress-Nginx              ║"
echo "╚══════════════════════════════════════╝"

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=80 \
  --set controller.service.nodePorts.https=443 \
  --wait --timeout=5m

log_success "Step 04 완료: Ingress-Nginx 설치 완료"
