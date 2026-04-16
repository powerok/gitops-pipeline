FROM alpine:3.19

# Install dependencies: bash, curl, jq, sed, docker-cli
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    sed \
    docker-cli \
    openssl \
    openssh-client \
    git

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/v1.29.4/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# Install Helm
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

WORKDIR /workspace
