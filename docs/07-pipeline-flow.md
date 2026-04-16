# 07. 파이프라인 흐름 및 Order System 배포 상세

## Order System 컴포넌트 구성

```mermaid
graph TB
    subgraph Pod["📦 Kubernetes Pod (order-dev / order-prod)"]

        subgraph InitPhase["⏳ Init Phase (순서 보장)"]
            INIT["Init Container\nwait-for-postgresql\n\nbusybox nc -z postgresql 5432\n5초마다 재시도"]
        end

        subgraph RunPhase["▶️ Run Phase (동시 실행)"]
            API["Main: Order API\nSpring Boot :8080\n\n• Liveness: /actuator/health/liveness\n• Readiness: /actuator/health/readiness\n• DB: Secret 환경변수\n• Cache: localhost:6379"]

            REDIS["Sidecar: Redis\n:6379\n\n• maxmemory: 200mb\n• policy: allkeys-lru\n• RDB 저장 비활성화"]
        end

        INIT -->|"✅ 포트 응답 확인 후 종료"| API
        API <-->|"localhost\n(같은 Pod 내)"|REDIS
    end

    subgraph StatefulSet["💾 StatefulSet"]
        PG["PostgreSQL\n:5432\n\nPVC: 5Gi\nlocal-path"]
    end

    subgraph Secret["🔐 K8s Secret"]
        S["order-db-secret\n• username\n• password\n• postgres-password"]
    end

    API -->|"ClusterIP\norder-postgresql:5432"| PG
    S -->|"envFrom secretKeyRef"| API
```

---

## Init Container 동작 원리

```mermaid
sequenceDiagram
    participant K8s as Kubernetes
    participant Init as Init Container<br/>(busybox)
    participant PG as PostgreSQL<br/>(StatefulSet)
    participant API as Order API<br/>(Spring Boot)

    K8s->>Init: Pod 시작 → Init Container 실행
    loop PostgreSQL 준비 대기
        Init->>PG: nc -z -w3 order-postgresql 5432
        PG-->>Init: Connection refused (아직 준비 안됨)
        Note over Init: sleep 5초
    end
    PG-->>Init: Connection OK ✅
    Init->>K8s: 종료 (exit 0)
    K8s->>API: Main Container 시작
    K8s->>API: Sidecar Container 시작 (Redis)
    Note over API: Spring Boot 기동\nDB 연결 성공
```

---

## 무중단 배포 흐름 (RollingUpdate)

```mermaid
sequenceDiagram
    participant CD as ArgoCD
    participant K8s as Kubernetes
    participant Old as 구 버전 Pod (v1)
    participant New as 신 버전 Pod (v2)
    participant SVC as Service

    CD->>K8s: 새 이미지 태그로 Deployment 업데이트
    K8s->>New: Init Container 실행 (DB 대기)
    New->>K8s: Init 완료
    K8s->>New: Order API + Redis 시작
    loop Readiness 체크
        K8s->>New: GET /actuator/health/readiness
        New-->>K8s: 503 (아직 준비 안됨)
    end
    New-->>K8s: 200 OK ✅ (Readiness 통과)
    K8s->>SVC: 신 버전 Pod를 Endpoints에 추가
    Note over SVC: 트래픽이 v1, v2 동시 처리
    K8s->>Old: SIGTERM 전송 (종료 신호)
    Note over Old: 60초 grace period\n진행 중인 요청 완료
    Old->>K8s: 종료 완료
    K8s->>SVC: 구 버전 Pod Endpoints에서 제거
    Note over SVC: 트래픽이 v2만 처리 ✅
```

---

## 헬스체크 엔드포인트 (Spring Boot Actuator)

| 엔드포인트 | 프로브 | 실패 시 동작 |
|-----------|--------|------------|
| `/actuator/health/liveness` | Liveness | Pod 재시작 |
| `/actuator/health/readiness` | Readiness | Service에서 제외 |

### Spring Boot 설정 (application-k8s.yml)

```yaml
management:
  endpoint:
    health:
      probes:
        enabled: true
      show-details: always
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  health:
    livenessState:
      enabled: true
    readinessState:
      enabled: true
```

---

## Secret 관리 흐름

```mermaid
graph LR
    subgraph K8s["K8s Secret (order-db-secret)"]
        U["username: orderuser"]
        P["password: ****"]
        PP["postgres-password: ****"]
    end

    subgraph ENV["Pod 환경변수 주입"]
        E1["SPRING_DATASOURCE_USERNAME"]
        E2["SPRING_DATASOURCE_PASSWORD"]
    end

    subgraph PG["PostgreSQL StatefulSet"]
        PG_ENV["POSTGRES_PASSWORD\nPOSTGRES_USER\nPOSTGRES_DB"]
    end

    U -->|secretKeyRef| E1
    P -->|secretKeyRef| E2
    PP -->|secretKeyRef| PG_ENV
```

---

## 전체 배포 타임라인 (예상 소요 시간)

```mermaid
gantt
    title 파이프라인 실행 타임라인
    dateFormat mm:ss
    axisFormat %M:%S

    section Jenkins CI
    코드 체크아웃        : 00:00, 10s
    유닛 테스트          : 00:10, 60s
    Maven 빌드           : 01:10, 60s
    Docker 빌드 & Push   : 02:10, 120s
    Trivy 스캔 대기      : 04:10, 120s

    section GitOps
    Ops Repo 태그 업데이트 : 06:10, 20s
    ArgoCD 감지 (폴링)   : 06:30, 180s
    Init Container 대기  : 09:30, 30s
    Rolling Update       : 10:00, 60s
    배포 완료            : 11:00, 5s
```
