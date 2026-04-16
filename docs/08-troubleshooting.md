# 08. 트러블슈팅 가이드

## 자주 발생하는 문제 및 해결 방법

---

### 1. Harbor 이미지 Pull 실패 (인증서 오류)

**증상**
```
Failed to pull image "harbor.local/gitops/order-api:latest":
  rpc error: x509: certificate signed by unknown authority
```

**원인**: K3s가 Harbor의 Self-signed 인증서를 신뢰하지 않음

**해결 방법**

```bash
# 1. registries.yaml을 K3s 컨테이너에 복사
docker cp infrastructure/k3s/registries.yaml \
  k3s-server:/etc/rancher/k3s/registries.yaml

# 2. K3s 재시작
docker exec k3s-server systemctl restart k3s

# 3. 동작 확인
kubectl run test-pull --image=harbor.local/gitops/order-api:latest \
  --restart=Never --rm -it -- echo "Pull 성공"
```

---

### 2. Init Container가 무한 대기 상태

**증상**
```
$ kubectl get pods -n order-dev
NAME                      READY   STATUS     RESTARTS
order-system-xxx          0/2     Init:0/1   0
```

**원인**: PostgreSQL이 아직 준비되지 않았거나, StatefulSet 이름이 다름

**해결 방법**

```bash
# Init Container 로그 확인
kubectl logs order-system-xxx -c wait-for-postgresql -n order-dev

# PostgreSQL 서비스 이름 확인
kubectl get svc -n order-dev | grep postgres

# StatefulSet 상태 확인
kubectl get statefulset -n order-dev
kubectl describe statefulset order-postgresql -n order-dev
```

---

### 3. Jenkins Webhook이 동작하지 않음

**증상**: Gitea에 Push해도 Jenkins 빌드가 트리거되지 않음

**해결 방법**

```bash
# 1. Gitea → Webhook → 최근 요청 이력 확인
# Gitea Web UI: Settings → Webhooks → 테스트 버튼 클릭

# 2. Jenkins 로그 확인
kubectl logs -l app.kubernetes.io/name=jenkins \
  -n jenkins -c jenkins --tail=100 | grep -i webhook

# 3. Jenkins에서 Gitea 플러그인 설정 확인
# Manage Jenkins → Configure System → Gitea Servers

# 4. Webhook 재등록
bash scripts/setup-webhook.sh
```

---

### 4. ArgoCD OutOfSync 무한 반복

**증상**: ArgoCD가 계속 OutOfSync 상태로 표시되며 Sync가 반복됨

**원인**: Deployment의 replicas를 HPA가 변경하면 ArgoCD가 차이를 감지

**해결 방법**: `ignoreDifferences` 설정 확인

```yaml
# argocd/applications/dev/order-api-dev.yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas  # HPA가 변경하는 필드 무시
```

---

### 5. Trivy 스캔 타임아웃

**증상**
```
❌ 취약점 스캔 실패: 타임아웃
```

**원인**: Harbor Trivy DB 업데이트가 느리거나 네트워크 문제

**해결 방법**

```bash
# Trivy 어댑터 Pod 재시작
kubectl rollout restart deployment harbor-trivy -n harbor

# Trivy DB 업데이트 트리거 (Harbor UI)
# Administration → Interrogation Services → SCAN NOW

# 또는 스캔 타임아웃 값 증가 (pipelineUtils.groovy)
# scanTimeout: 600  # 10분으로 늘리기
```

---

### 6. Helm 배포 실패 (PVC Pending)

**증상**
```
Error: INSTALLATION FAILED: PersistentVolumeClaim "order-postgresql-pvc" is pending
```

**원인**: local-path-provisioner가 동작하지 않음

**해결 방법**

```bash
# StorageClass 확인
kubectl get storageclass

# local-path-provisioner Pod 상태 확인
kubectl get pods -n kube-system | grep local-path

# 재시작
kubectl rollout restart deployment local-path-provisioner -n kube-system
```

---

## 유용한 진단 명령어 모음

```bash
# ── 전체 파드 상태 한눈에 보기 ──────────────────────────────
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed

# ── 이벤트 확인 (오류 우선) ─────────────────────────────────
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -30

# ── ArgoCD 앱 상태 ───────────────────────────────────────────
argocd app list
argocd app get order-api-dev --show-operation

# ── Harbor API 직접 조회 ─────────────────────────────────────
curl -u admin:Harbor12345 http://harbor.local/api/v2.0/projects \
  | jq '.[].name'

# ── Jenkins 빌드 로그 스트리밍 ───────────────────────────────
kubectl logs -f -l app.kubernetes.io/component=jenkins-controller \
  -n jenkins -c jenkins
```
