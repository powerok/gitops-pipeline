# 06. ArgoCD 설정 가이드

## 설치

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f infrastructure/argocd/values.yaml \
  --wait --timeout=10m

# admin 초기 비밀번호 조회
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

---

## App-of-Apps 패턴

```mermaid
graph TB
    subgraph ArgoCD["ArgoCD"]
        ROOT["root-app\n(App-of-Apps 루트)\nOps Repo: argocd/app-of-apps/"]

        subgraph Apps["하위 Application"]
            DEV["order-api-dev\nNamespace: order-dev\n자동 동기화"]
            PROD["order-api-prod\nNamespace: order-prod\n수동 승인"]
        end
    end

    subgraph OpsRepo["Ops Repo (gitea.local)"]
        ROOT_YAML["argocd/app-of-apps/root-app.yaml"]
        DEV_YAML["argocd/applications/dev/\norder-api-dev.yaml"]
        PROD_YAML["argocd/applications/prod/\norder-api-prod.yaml"]
        HC["helm-charts/order-system/"]
    end

    ROOT_YAML -->|"감시"| ROOT
    ROOT -->|"생성"| DEV
    ROOT -->|"생성"| PROD
    DEV_YAML -->|"참조"| DEV
    PROD_YAML -->|"참조"| PROD
    DEV -->|"Helm 배포"| HC
    PROD -->|"Helm 배포"| HC
```

---

## App-of-Apps 등록 및 확인

```bash
# root-app 등록 (최초 1회)
kubectl apply -f argocd/app-of-apps/root-app.yaml -n argocd

# ArgoCD CLI로 상태 확인 (선택적)
argocd login argocd.local --username admin --insecure
argocd app list
argocd app get root-app
argocd app get order-api-dev
```

---

## Dev vs Prod 동기화 전략

```mermaid
flowchart LR
    subgraph OpsRepo["Ops Repo 변경"]
        COMMIT["values-dev.yaml\n또는\nvalues-prod.yaml\n이미지 태그 업데이트"]
    end

    subgraph Dev["Dev (order-dev)"]
        D_ARGOCD["ArgoCD 자동 감지\n(3분 주기 폴링)"]
        D_SYNC["자동 동기화\nautomatic sync"]
        D_K8S["K8s 배포"]
    end

    subgraph Prod["Prod (order-prod)"]
        P_ARGOCD["ArgoCD 감지\n(변경 감지)"]
        P_APPROVE["수동 승인 필요\n(ArgoCD UI / CLI)"]
        P_SYNC["수동 동기화\nargocd app sync order-api-prod"]
        P_K8S["K8s 배포"]
    end

    COMMIT --> D_ARGOCD
    D_ARGOCD --> D_SYNC --> D_K8S

    COMMIT --> P_ARGOCD
    P_ARGOCD --> P_APPROVE --> P_SYNC --> P_K8S
```

### Prod 수동 배포 명령어

```bash
# ArgoCD UI에서 "Sync" 버튼 클릭, 또는:
argocd app sync order-api-prod --prune
```

---

## 동기화 상태 다이어그램

```mermaid
stateDiagram-v2
    [*] --> Synced : 초기 배포
    Synced --> OutOfSync : Ops Repo 변경 감지
    OutOfSync --> Syncing : 자동/수동 동기화 시작
    Syncing --> Synced : 동기화 성공
    Syncing --> Degraded : 배포 실패
    Degraded --> Syncing : 재시도 (retry)
    Degraded --> [*] : 수동 롤백
```
