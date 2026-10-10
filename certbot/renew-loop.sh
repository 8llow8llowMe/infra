#!/bin/sh
set -eu

# 1. 실행 기본값을 설정합니다.
WEBROOT="${CERTBOT_WEBROOT:-/var/www/certbot}"
RENEW_INTERVAL="${CERTBOT_RENEW_INTERVAL:-12h}"
NGINX_CONTAINER="${NGINX_CONTAINER:-nginx}"
DH_BITS="${STRONG_DH:+4096}"
DH_BITS="${DH_BITS:-2048}"

# 2. 인증서가 실제로 갱신되면 Nginx를 reload합니다.
reload_nginx() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "[certbot] docker CLI not found; nginx reload skipped" >&2
    return 1
  fi

  echo "[certbot] reloading nginx container: ${NGINX_CONTAINER}"
  docker exec "${NGINX_CONTAINER}" nginx -s reload
}

# 3. Certbot deploy-hook에서 호출되는 진입점입니다.
if [ "${1:-}" = "reload" ]; then
  reload_nginx
  exit $?
fi

# 4. Nginx SSL server block에 필요한 TLS 보조 파일을 생성합니다.
ensure_tls_defaults() {
  if [ ! -f /etc/letsencrypt/options-ssl-nginx.conf ]; then
    echo "[certbot] creating options-ssl-nginx.conf"
    curl -fsSL \
      https://raw.githubusercontent.com/certbot/certbot/main/certbot-nginx/src/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf \
      -o /etc/letsencrypt/options-ssl-nginx.conf
  fi

  if [ ! -f /etc/letsencrypt/ssl-dhparams.pem ]; then
    echo "[certbot] creating ssl-dhparams.pem (${DH_BITS}bit)"
    openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem "${DH_BITS}"
  fi
}

# 5. Docker가 컨테이너 종료를 요청하면 안전하게 종료합니다.
trap 'echo "[certbot] stopping"; exit 0' TERM INT

# 6. Certbot 인증서 갱신 확인을 주기적으로 실행합니다.
while :; do
  ensure_tls_defaults

  # 갱신 실패로 스크립트가 종료되면 restart: always 로 즉시 재시작되어
  # Let's Encrypt 요청이 폭주하고 계정이 rate limit 에 걸립니다.
  # 실패해도 로그만 남기고 다음 주기까지 대기합니다.
  echo "[certbot] renewal check started"
  if certbot renew \
    --webroot -w "${WEBROOT}" \
    --quiet \
    --disable-hook-validation \
    --deploy-hook "/usr/local/bin/renew-loop.sh reload"; then
    echo "[certbot] renewal check finished; sleeping ${RENEW_INTERVAL}"
  else
    echo "[certbot] renewal check failed (exit $?); retry after ${RENEW_INTERVAL}" >&2
  fi

  # 7. 종료 신호를 받을 수 있도록 sleep을 별도 프로세스로 실행합니다.
  sleep "${RENEW_INTERVAL}" &
  wait "$!"
done
