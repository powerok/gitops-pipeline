# 08. 트러블슈팅 가이드

## 🚨 자주 발생하는 문제 및 해결 방법

---

### 1. Jenkins SSH 연동 실패 (libcrypto / Permission denied)

**증상**
- Jenkins 빌드 로그에 `Host key verification failed` 또는 `libcrypto.so.1.1: cannot open shared object file` 오류 발생.
- `git clone` 시 `Permission denied (publickey)` 오류 발생.

**원인**
- Jenkins Agent Pod 내의 SSH 관련 라이브러리 충돌 또는 `/var/jenkins_home/.ssh`의 권한(0700) 이슈.

**해결 방법**
- **마운트 방식 사용**: 본 프로젝트는 SSH 키를 `/var/jenkins_ssh` 경로에 0400 권한으로 마운트하여 권한 충돌을 방지합니다.
- **Service Name 사용**: Gitea 접근 시 IP 대신 내부 서비스 도메인을 사용하는지 확인하세요.
  `ssh://git@gitea-ssh.gitea.svc.cluster.local:2222/gitops/order-api.git`

---

### 2. Jenkins Webhook 401 Unauthorized / 403 Forbidden

**증상**
- Gitea → Webhook 전송 이력에 `401` 또는 `403` 상태 코드가 표시됨.
- Jenkins 로그에 `CrumbIssuer` 또는 `Anonymous ignore` 관련 메시지 출력.

**원인**
- Jenkins의 CSRF 보호 기능이 외부 Webhook 요청을 차단함.

**해결 방법**
- **CSRF 토큰 체크 해제 (JVM 옵션)**: `values.yaml`의 `javaOpts`에 `-Dhudson.plugins.git.GitStatus.NOTIFY_COMMIT_TOKEN_REQUIRED=false`가 포함되어 있는지 확인하세요.
- **익명 읽기 권한**: JCasC 설정에서 `Job/Build` 및 `Job/Read` 권한이 `anonymous`에게 부여되어 있는지 확인하세요.

---

### 3. Gitea/Harbor 도메인 인식 불가 (Internal DNS)

**증상**
- Jenkins 또는 ArgoCD 로그에 `dial tcp: lookup gitea.local: no such host` 오류 발생.

**원인**
- K3s 클러스터 내부의 Pod들이 로컬 `/etc/hosts`에 등록된 `.local` 도메인을 알지 못함.

**해결 방법**
- **hostAliases 설정**: Helm `values.yaml`의 `hostAliases` 섹션에 K3s 서버의 IP와 `.local` 도메인들을 수동으로 추가해야 합니다.
  (`scripts/steps/step-07-jenkins.sh` 가 설치 시 자동으로 주입합니다.)

---

### 4. JCasC 설정이 반영되지 않음

**증상**
- `values.yaml`을 수정하고 `helm upgrade`를 했으나 Jenkins 설정이 변하지 않음.

**원인**
- JCasC는 기본적으로 설정 파일의 변경을 감지하여 리로드하지만, 때때로 수동 트리거가 필요할 수 있습니다.

**해결 방법**
```bash
# Jenkins 관리자 권한으로 설정 리로드 시도
curl -X POST -u admin:Jenkins@Admin2024! http://jenkins.local/configuration-as-code/reload

# 또는 Pod 재시작 (가장 확실함)
kubectl rollout restart deployment jenkins -n jenkins
```

---

### 5. ArgoCD OutOfSync (Resource Excluded)

**증상**
- ArgoCD에서 특정 리소스가 무한히 `OutOfSync` 상태이거나 무시됨.

**해결 방법**
- `argocd/applications/dev/order-api-dev.yaml` 내 `ignoreDifferences`를 확인하세요.
- 특히 `replicas`를 HPA가 제어하는 경우 ArgoCD가 이를 차이로 인식하지 않도록 설정해야 합니다.

---

## 🔍 유용한 진단 명령어 모음 (Stabilized)

```bash
# ── Jenkins Webhook 트리거 강제 실행 ────────────────────────
curl -X POST "http://jenkins.local/generic-webhook-trigger/invoke?token=order-api-token-2024"

# ── Gitea 내부 SSH 연결 테스트 (Jenkins Pod 안에서) ─────────
JENKINS_POD=$(kubectl get pods -n jenkins -l app.kubernetes.io/instance=jenkins -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it -n jenkins "$JENKINS_POD" -- ssh -v -p 2222 git@gitea-ssh.gitea.svc.cluster.local

# ── JCasC 설정 내용 전체 보기 ──────────────────────────────
# Jenkins UI: Manage Jenkins -> Configuration as Code -> View Configuration

# ── Webhook 수신 상세 로그 확인 ─────────────────────────────
# Jenkins UI: Manage Jenkins -> System Log -> New Log Recorder
# Logger 추가: "org.jenkinsci.plugins.gwt" (Level: ALL)
```
