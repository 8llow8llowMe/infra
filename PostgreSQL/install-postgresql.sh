#!/usr/bin/env bash
# PostgreSQL 기동. 대상 호스트(dev: main-server)에서 이 디렉터리로 들어가 실행한다.
#   sh install-postgresql.sh
# 이미 떠 있으면 설정만 다시 맞춘다(데이터 볼륨은 그대로).
set -eu

cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo ".env 가 없습니다. cp .env.example .env 후 POSTGRES_SUPERUSER_PASSWORD 를 채우세요." >&2
  exit 1
fi
chmod 600 .env

if ! docker network inspect 8llow8llowme-net >/dev/null 2>&1; then
  docker network create 8llow8llowme-net
fi

docker compose --env-file .env -f docker-compose-postgresql.yml config -q
docker compose --env-file .env -f docker-compose-postgresql.yml up -d

echo "healthy 를 기다립니다..."
for _ in $(seq 1 30); do
  status=$(docker inspect -f '{{.State.Health.Status}}' postgresql 2>/dev/null || echo none)
  if [ "$status" = healthy ]; then
    echo "postgresql healthy"
    exit 0
  fi
  sleep 2
done
echo "postgresql 이 healthy 가 되지 않았습니다. docker logs postgresql 를 확인하세요." >&2
exit 1
