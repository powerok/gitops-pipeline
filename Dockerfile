# =============================================================
# Order API Dockerfile
# 멀티 스테이지 빌드: 빌드 환경과 런타임 환경을 분리한다.
# 최종 이미지 크기 최소화 + 보안 강화
# =============================================================

# ──────────────────────────────────────────────
# Stage 1: 빌드 스테이지 (Maven + JDK 21)
# ──────────────────────────────────────────────
FROM maven:3.9.6-eclipse-temurin-21 AS builder

WORKDIR /build

# pom.xml만 먼저 복사 → 의존성 레이어 캐시 활용
# 소스 코드가 바뀌어도 의존성은 재다운로드하지 않는다.
COPY pom.xml .
RUN mvn dependency:go-offline -B -q

# 소스 코드 복사 및 빌드
COPY src ./src
RUN mvn clean package -DskipTests -B -q

# 빌드된 JAR 이름 정규화 (버전 무관하게 app.jar로 통일)
RUN cp target/*.jar target/app.jar

# Spring Boot Layered JAR 분리 (레이어 캐시 최적화)
RUN java -Djarmode=layertools -jar target/app.jar extract --destination target/extracted

# ──────────────────────────────────────────────
# Stage 2: 런타임 스테이지 (JRE only)
# ──────────────────────────────────────────────
FROM eclipse-temurin:21-jre-jammy AS runtime

# ── 보안 설정 ─────────────────────────────────
# 전용 그룹/유저 생성 (root 권한 제거)
RUN groupadd --system --gid 1000 appgroup && \
    useradd --system --uid 1000 --gid appgroup --no-create-home appuser

WORKDIR /app

# ── Layered JAR 복사 (캐시 효율 극대화) ────────
# 의존성(잘 변하지 않는 레이어)을 먼저 복사
COPY --from=builder --chown=appuser:appgroup /build/target/extracted/dependencies/ ./
COPY --from=builder --chown=appuser:appgroup /build/target/extracted/spring-boot-loader/ ./
COPY --from=builder --chown=appuser:appgroup /build/target/extracted/snapshot-dependencies/ ./
# 애플리케이션 클래스(자주 변하는 레이어)는 마지막에 복사
COPY --from=builder --chown=appuser:appgroup /build/target/extracted/application/ ./

# ── 임시 디렉토리 생성 (Spring 파일 업로드 등) ─
RUN mkdir -p /tmp/app && chown appuser:appgroup /tmp/app

# root가 아닌 전용 유저로 실행
USER appuser

# ── 포트 노출 ─────────────────────────────────
EXPOSE 8080 8081

# ── 환경 변수 기본값 ──────────────────────────
ENV JAVA_OPTS="-Xmx768m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0" \
    SPRING_PROFILES_ACTIVE="k8s" \
    SERVER_PORT="8080" \
    TZ="Asia/Seoul"

# ── 헬스체크 (Docker 레벨) ────────────────────
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
  CMD curl -sf http://localhost:8080/actuator/health || exit 1

# ── 앱 실행 ───────────────────────────────────
# Spring Boot Layered JAR 실행 엔트리포인트
ENTRYPOINT ["sh", "-c", \
  "exec java ${JAVA_OPTS} org.springframework.boot.loader.launch.JarLauncher"]
