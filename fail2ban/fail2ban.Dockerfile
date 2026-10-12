# Fail2Ban Dockerfile (#37)
# - nginx access.log 를 읽어 호스트 iptables DOCKER-USER 체인에 차단을 겁니다.
# - 호스트(Ubuntu)와 같은 iptables nf_tables 백엔드여야 규칙이 같은 테이블에 들어갑니다.
#   alpine 3.22 의 iptables 1.8.11 (nf_tables) 로 맞춰 두었고, 올릴 때는 `iptables --version` 을 호스트와 비교합니다.
# - tzdata 가 있어야 TZ=Asia/Seoul 이 먹어 fail2ban.log 시각이 KST 로 남습니다.

FROM alpine:3.22

RUN apk add --no-cache fail2ban iptables ip6tables bash coreutils tzdata

# 설정 복사 (패키지 기본 jail.d/alpine-ssh 등은 지워 우리 jail 만 남깁니다)
RUN rm -f /etc/fail2ban/jail.d/*
COPY fail2ban.local /etc/fail2ban/fail2ban.local
COPY jail.local /etc/fail2ban/jail.local
COPY filter.d/ /etc/fail2ban/filter.d/
COPY docker-entrypoint-fail2ban.sh /docker-entrypoint-fail2ban.sh
COPY fail2ban-healthcheck.sh /fail2ban-healthcheck.sh

RUN chmod +x /docker-entrypoint-fail2ban.sh /fail2ban-healthcheck.sh

ENTRYPOINT ["/docker-entrypoint-fail2ban.sh"]
