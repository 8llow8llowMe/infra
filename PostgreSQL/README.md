# PostgreSQL

PostgreSQL 을 쓰는 프로젝트의 DB 인스턴스입니다. 공용 dev DB 호스트에는 MySQL 이 이미 있지만, PostgreSQL 전용으로 만든 앱(commerce-foundry)은 MySQL 에 붙일 수 없어 같은 호스트에 따로 둡니다(2026-10-23).

| 환경 | 호스트 | 포트 | 상태 |
| --- | --- | --- | --- |
| dev | `main-server` (`192.168.0.11`) | 5432 | 기동 중 (2026-10-23, `postgres:17-alpine`, 메모리 상한 768m) |
| prod | 운영 DB 전용 서버(신설 예정) | 5432 | 미정 — 루트 `README.md` 8절 |

## 파일

| 파일 | 내용 |
| --- | --- |
| `docker-compose-postgresql.yml` | 인스턴스 하나. 메모리 상한 · `shared_buffers` 를 작게 둔다(main-server 는 MySQL · dev 백엔드와 동거) |
| `.env.example` | 슈퍼유저 비밀번호 · 메모리 설정 템플릿. `.env` 로 복사해 채운다(커밋 금지) |
| `install-postgresql.sh` | `.env` 확인 → `8llow8llowme-net` 보장 → `compose config -q` → `up -d` → healthy 대기 |
| `scripts/create-project-db.sh` | 프로젝트 DB · 계정 · 스키마 생성(멱등). 비밀번호는 환경 변수로만 받는다 |

## 설치 (dev, main-server)

```bash
cd ~/infra/PostgreSQL
cp .env.example .env                      # POSTGRES_SUPERUSER_PASSWORD 채우기 (openssl rand -base64 32)
sh install-postgresql.sh
```

## 프로젝트 DB 만들기

프로젝트마다 데이터베이스 · 계정을 따로 둡니다. 데이터베이스의 `PUBLIC` CONNECT 를 거둬 다른 프로젝트 계정이 붙지 못하게 합니다.

```bash
# commerce-foundry dev (2026-10-23 생성)
PROJECT_DB_PASSWORD='<Vault 의 DB_PASSWORD 와 같은 값>' \
  sh scripts/create-project-db.sh commerce_foundry commerce_dev auth product orders payment delivery operations
```

- 스키마를 추가하면 같은 명령에 이름을 더해 다시 실행합니다(이미 있는 것은 건너뜀).
- 같은 명령을 다른 비밀번호로 실행하면 계정 비밀번호가 그 값으로 바뀝니다 — 비밀번호 교체 절차입니다.
- main-server 의 `~/infra/PostgreSQL/.env.commerce-foundry-dev`(권한 600)에 접속 값(DB_URL · DB_USERNAME · DB_PASSWORD)을 두었습니다. **Vault `kv/commerce-foundry/backend/dev/env` 에 옮긴 뒤 지워도 됩니다.**

## 접속

- 앱(다른 호스트): `jdbc:postgresql://192.168.0.11:5432/commerce_foundry` — 호스트 간 통신은 사설 IP(루트 README 4절 4번).
- 운영자: `docker exec -it postgresql psql -U postgres`

## 백업 (dev)

dev 는 정기 백업을 두지 않습니다. 필요하면 `docker exec postgresql pg_dump -U postgres -Fc commerce_foundry > commerce_foundry.dump`.
prod 는 전용 서버를 들일 때 일일 `pg_dump` → `storage` MinIO 를 둡니다.
