# Jenkins builder agent 이미지입니다.
# Java 21, Docker CLI/Compose, Git, Node.js 22, yarn, pnpm, Gradle 캐시를 포함합니다.

FROM eclipse-temurin:21-jdk-jammy AS jdk

FROM jenkins/inbound-agent:latest-jdk17

USER root

COPY --from=jdk /opt/java/openjdk /opt/java/openjdk21

ENV JAVA_HOME=/opt/java/openjdk21
ENV PATH="${JAVA_HOME}/bin:${PATH}"
ENV GRADLE_USER_HOME=/home/jenkins/.gradle

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    docker.io \
    git \
    gnupg \
    gosu \
    lsb-release \
    tini \
    unzip \
    wget \
 && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && npm install -g yarn pnpm \
 && mkdir -p /usr/libexec/docker/cli-plugins \
 && arch="$(uname -m)" \
 && case "$arch" in \
      x86_64) buildx_arch="amd64"; compose_arch="x86_64" ;; \
      aarch64|arm64) buildx_arch="arm64"; compose_arch="aarch64" ;; \
      armv7l) buildx_arch="arm-v7"; compose_arch="armv7" ;; \
      *) echo "Unsupported architecture: $arch"; exit 1 ;; \
    esac \
 && curl -fsSL "https://github.com/docker/buildx/releases/download/v0.17.1/buildx-v0.17.1.linux-${buildx_arch}" \
    -o /usr/libexec/docker/cli-plugins/docker-buildx \
 && curl -fsSL "https://github.com/docker/compose/releases/download/v2.30.3/docker-compose-linux-${compose_arch}" \
    -o /usr/libexec/docker/cli-plugins/docker-compose \
 && chmod +x /usr/libexec/docker/cli-plugins/docker-buildx /usr/libexec/docker/cli-plugins/docker-compose \
 && mkdir -p /home/jenkins/.gradle /home/jenkins/.npm /home/jenkins/.local/share/pnpm \
 && chown -R jenkins:jenkins /home/jenkins \
 && rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint-jenkins-agent.sh /usr/local/bin/docker-entrypoint-jenkins-agent.sh
RUN chmod +x /usr/local/bin/docker-entrypoint-jenkins-agent.sh

# tini 를 PID 1 로 둡니다. entrypoint 가 jenkins-agent(java) 로 exec 하므로, tini 가 없으면
# java 가 PID 1 이 되어 빌드가 남긴 고아 프로세스를 거두지 않습니다. 좀비가 쌓여 pids.max 에
# 닿으면 git 조차 띄우지 못하고 checkout 이 "unable to create native thread" 로 실패합니다.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint-jenkins-agent.sh"]
