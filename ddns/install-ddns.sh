#!/usr/bin/env sh
# Cloudflare DDNS 를 시작합니다 (#59). 토큰 파일이 없으면 시작하지 않습니다.

set -eu

if [ ! -f ./.env ]; then
  cp ./.env.example ./.env
  echo ".env.example 을 복사해 .env 를 만들었습니다. DDNS_DOMAINS 를 Cloudflare 로 옮긴 zone 기준으로 확인하세요."
fi

TOKEN_FILE=./secrets/cloudflare-api-token
if [ ! -s "$TOKEN_FILE" ]; then
  echo "$TOKEN_FILE 이 없습니다. Cloudflare 에서 'Zone - DNS - Edit'(대상 zone 만) 토큰을 만들어 저장합니다:"
  echo "  mkdir -p secrets && chmod 700 secrets"
  echo "  (umask 077; printf '%s' '<token>' > $TOKEN_FILE)"
  echo "같은 값은 Vault kv/infra/ddns 에도 백업합니다(ddns/README.md)."
  exit 1
fi
chmod 600 "$TOKEN_FILE"

docker compose --env-file .env -f docker-compose-ddns.yml config -q
docker compose --env-file .env -f docker-compose-ddns.yml up -d

echo "cloudflare-ddns 를 시작했습니다. 로그: docker logs -f cloudflare-ddns"
