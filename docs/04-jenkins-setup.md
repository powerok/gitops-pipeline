# 04. Jenkins 설정 가이드

## 설치

```bash
helm repo add jenkins https://charts.jenkins.io
helm repo update

# 시크릿 먼저 생성 (Gitea 토큰을 스크립트 실행 후 넣어야 한다)
GITEA_TOKEN=$(cat .jenkins-gitea-token)
kubectl create namespace jenkins --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic jenkins-secrets \
  --namespace jenkins \
  --from-literal=gitea-token="${GITEA_TOKEN}" \
  --from-literal=harbor-password="Harbor12345" \
  --dry-run=client -o yaml | kubectl apply -f -

# Jenkins 설치
helm upgrade --install jenkins jenkins/jenkins \
  --namespace jenkins \
  --create-namespace \
  -f infrastructure/jenkins/values.yaml \
  --wait --timeout=15m
```

---

## Shared Library 구조

```mermaid
graph TB
    subgraph SharedLib["jenkins-shared-library 리포지토리"]
        VARS["vars/\n전역 함수 (DSL 방식)"]
        SRC["src/\n클래스 (고급 로직)"]

        subgraph VARS_FILES["vars/ 파일"]
            PU["pipelineUtils.groovy\n├ buildAndPushImage()\n├ checkVulnerabilities()\n├ updateOpsRepo()\n└ notifySlack()"]
        end
    end

    subgraph Jenkinsfile["Jenkinsfile (App Repo)"]
        CALL["@Library('gitops-shared-lib') _\n\npipelineUtils.buildAndPushImage(...)"]
    end

    PU -->|import| CALL
```

### 주요 함수 설명

| 함수 | 역할 |
|------|------|
| `buildAndPushImage()` | Docker 빌드 → Harbor Push (latest + 버전 태그) |
| `checkVulnerabilities()` | Trivy 스캔 완료 대기 → CRITICAL 취약점 확인 |
| `updateOpsRepo()` | Ops 리포지토리 `sed` 태그 업데이트 → git push |
| `notifySlack()` | Slack 채널 알림 (선택적) |

---

## DooD (Docker-outside-of-Docker) 방식

```mermaid
graph LR
    subgraph JenkinsPod["Jenkins Agent Pod"]
        DOCKER_CLI["Docker CLI\n(docker build/push)"]
    end

    subgraph Host["K3s 호스트"]
        DOCKER_SOCK["/var/run/docker.sock"]
        DOCKER_DAEMON["Docker Daemon\n(실제 빌드 실행)"]
    end

    subgraph Harbor["Harbor Registry"]
        IMG["gitops/order-api:tag"]
    end

    DOCKER_CLI -->|소켓 마운트| DOCKER_SOCK
    DOCKER_SOCK --> DOCKER_DAEMON
    DOCKER_DAEMON -->|이미지 Push| IMG
```

> **DooD 주의사항**: 호스트의 Docker Daemon을 공유하므로 보안에 유의해야 한다. 운영 환경에서는 `kaniko`를 사용하는 것을 권장한다.

---

## 파이프라인 흐름 다이어그램

```mermaid
flowchart TD
    A[🔍 Checkout\nGitea에서 코드 Pull] --> B
    B[🧪 Unit Test\nmvn clean test] --> C{테스트 통과?}
    C -->|실패| FAIL[❌ 파이프라인 종료\nSlack 알림]
    C -->|성공| D[🔨 Build\nmvn package -DskipTests]
    D --> E[🐳 Build & Push\ndocker build + push to Harbor]
    E --> F[🔍 Vulnerability Scan\nTrivy 스캔 대기 및 결과 확인]
    F --> G{CRITICAL 취약점?}
    G -->|발견| FAIL
    G -->|없음| H{main/release 브랜치?}
    H -->|No| SKIP[ℹ️ Ops 업데이트 건너뜀]
    H -->|Yes| I[🔄 Update Ops Repo\nsed로 이미지 태그 교체\ngit commit & push]
    I --> J[📢 Notify\n완료 알림]
    SKIP --> J
    J --> SUCCESS[✅ 완료]
```

---

## Maven 빌드 캐시 PVC 생성

```bash
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
```
