#!/bin/bash
JENKINS_POD=$(kubectl get pods -n jenkins -l app.kubernetes.io/instance=jenkins -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$JENKINS_POD" ]; then
    JENKINS_POD=$(kubectl get pods -n jenkins -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
fi
echo "Pod: $JENKINS_POD"

# CSRF crumb 획득
CRUMB_JSON=$(kubectl exec -n jenkins "$JENKINS_POD" -c jenkins -- \
    curl -s -c /tmp/cookies.txt -u admin:Jenkins@Admin2024! \
    "http://localhost:8080/crumbIssuer/api/json" 2>/dev/null || echo "")
CRUMB=$(echo "$CRUMB_JSON" | grep -o '"crumb":"[^"]*"' | cut -d'"' -f4 || echo "")
echo "Crumb: ${CRUMB:0:30}..."

# 빌드 트리거
RESP=$(kubectl exec -n jenkins "$JENKINS_POD" -c jenkins -- \
    curl -s -w "\n%{http_code}" -X POST -u admin:Jenkins@Admin2024! \
    -b /tmp/cookies.txt \
    -H "Jenkins-Crumb: $CRUMB" \
    "http://localhost:8080/job/order-api-pipeline/build" 2>/dev/null || echo "")
echo "HTTP Response: $(echo "$RESP" | tail -1)"

sleep 5
# 빌드 상태 확인
BUILD=$(kubectl exec -n jenkins "$JENKINS_POD" -c jenkins -- \
    curl -s -u admin:Jenkins@Admin2024! \
    "http://localhost:8080/job/order-api-pipeline/lastBuild/api/json" 2>/dev/null || echo "")
echo "Last build: $(echo "$BUILD" | grep -o '"number":[0-9]*' | head -1)"
echo "Building: $(echo "$BUILD" | grep -o '"building":true' || echo "false")"
echo "Result: $(echo "$BUILD" | grep -o '"result":"[^"]*"' | cut -d'"' -f4 || echo "N/A")"
