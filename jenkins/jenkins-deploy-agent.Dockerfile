# Jenkins deploy agent 이미지입니다.
# Jenkins controller/remoting 클래스 버전에 맞추기 위해 Java 21을 사용합니다.
# builder agent보다 가볍게 유지하기 위해 Node.js, pnpm, yarn, Gradle 캐시는 포함하지 않습니다.

FROM eclipse-temurin:21-jdk-jammy AS jdk
FROM docker:27.3.1-cli AS docker-cli

FROM jenkins/inbound-agent:latest-jdk17

USER root

COPY --from=jdk /opt/java/openjdk /opt/java/openjdk21
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins

ENV JAVA_HOME=/opt/java/openjdk21
ENV PATH="${JAVA_HOME}/bin:${PATH}"

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gnupg \
    gosu \
    jq \
    lsb-release \
    openssh-client \
    rsync \
    tini \
    unzip \
    wget \
 && command -v docker \
 && docker --version \
 && docker compose version \
 && mkdir -p /home/jenkins/.ssh \
 && chown -R jenkins:jenkins /home/jenkins \
 && rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint-jenkins-agent.sh /usr/local/bin/docker-entrypoint-jenkins-agent.sh
RUN chmod +x /usr/local/bin/docker-entrypoint-jenkins-agent.sh

# builder agent 와 같은 이유로 tini 를 PID 1 로 둡니다 (jenkins-builder-agent.Dockerfile 참고).
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint-jenkins-agent.sh"]
