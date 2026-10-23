#!/usr/bin/env bash
# 프로젝트 데이터베이스 · 계정 · 스키마를 만든다. 몇 번 실행해도 같은 결과다(멱등).
#
#   PROJECT_DB_PASSWORD='<비밀번호>' sh scripts/create-project-db.sh <database> <user> [schema ...]
#
# 예) commerce-foundry dev
#   PROJECT_DB_PASSWORD="$(openssl rand -base64 24)" \
#     sh scripts/create-project-db.sh commerce_foundry commerce_dev auth product orders payment delivery operations
#
# - 비밀번호는 환경 변수로만 받고 psql 안에서 \getenv 로 읽는다 — 명령줄 인자 · 셸 이력에 남지 않게 한다.
#   이미 있는 계정이면 비밀번호를 그 값으로 다시 맞춘다.
# - 데이터베이스 소유자는 그 계정이고, PUBLIC 의 CONNECT 를 거둔다(다른 프로젝트 계정이 붙지 못하게).
# - 스키마는 계정 소유로 만든다. public 스키마는 쓰지 않는다.
# - 슈퍼유저 이름은 같은 디렉터리의 .env(POSTGRES_SUPERUSER, 기본 postgres)를 따른다.
set -eu

if [ $# -lt 2 ]; then
  echo "사용: PROJECT_DB_PASSWORD=... sh $0 <database> <user> [schema ...]" >&2
  exit 1
fi
: "${PROJECT_DB_PASSWORD:?PROJECT_DB_PASSWORD 환경 변수에 비밀번호를 넣으세요}"

db="$1"
user="$2"
shift 2

cd "$(dirname "$0")/.."
superuser=postgres
if [ -f .env ]; then
  superuser=$(sed -n 's/^POSTGRES_SUPERUSER=//p' .env | tail -1)
  superuser=${superuser:-postgres}
fi

export PROJECT_DB_PASSWORD
docker exec -i -e PROJECT_DB_PASSWORD postgresql \
  psql -v ON_ERROR_STOP=1 -U "$superuser" -d postgres -v db="$db" -v usr="$user" <<'SQL'
\getenv pw PROJECT_DB_PASSWORD
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'usr', :'pw')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'usr') \gexec
SELECT format('ALTER ROLE %I LOGIN PASSWORD %L', :'usr', :'pw') \gexec
SELECT format('CREATE DATABASE %I OWNER %I ENCODING ''UTF8'' TEMPLATE template0', :'db', :'usr')
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db') \gexec
SELECT format('REVOKE CONNECT, TEMPORARY ON DATABASE %I FROM PUBLIC', :'db') \gexec
SELECT format('GRANT CONNECT, TEMPORARY ON DATABASE %I TO %I', :'db', :'usr') \gexec
SQL

for schema in "$@"; do
  docker exec -i postgresql \
    psql -v ON_ERROR_STOP=1 -U "$superuser" -d "$db" -v sch="$schema" -v usr="$user" <<'SQL'
SELECT format('CREATE SCHEMA IF NOT EXISTS %I AUTHORIZATION %I', :'sch', :'usr') \gexec
SQL
done

docker exec -i postgresql psql -U "$superuser" -d "$db" -c '\dn'
echo "완료: database=$db user=$user schemas=$*"
