# Redis 운영 가이드

Redis master 1 + replica 2 + Sentinel 3노드 구성입니다.

## 실제 배치 토폴로지

| 노드 | 서버 | compose 파일 |
| --- | --- | --- |
| `redis-node1` + `redis-sentinel-node1` (master) | main-server (192.168.0.11) | `docker-compose-redis-master.yml` |
| `redis-node2` + `redis-sentinel-node2` (replica) | backend-1 (192.168.0.13) | `docker-compose-redis-slave.yml` |
| `redis-node3` + `redis-sentinel-node3` (replica) | storage (192.168.0.12) | `docker-compose-redis-slave.yml` (storage 실제 기동 파일) |

- Sentinel quorum 은 `2` (`sentinel.conf`) — 3노드 중 2노드 합의로 failover 가 성립합니다.
- master/replica 주소는 `redis-slave.conf` 의 `replicaof` 와 `sentinel.conf` 의 `sentinel monitor` 가 기준입니다.
  **서버 IP 를 바꾸면 이 두 파일을 함께 수정해야 합니다.**
- 컨테이너가 Docker bridge(`8llow8llowme-net`) 안에 있으므로 Sentinel 은 `sentinel announce-ip` 로 **호스트 IP** 를 알려야
  서로를 찾는다(지정하지 않으면 172.18.x 를 알려 `num-other-sentinels 0` 이 된다). 값은 호스트별 `.env` 의
  `REDIS_ANNOUNCE_IP` 다. replica 는 master 가 호스트 IP 로 보지만 failover 뒤를 위해 `replica-announce-ip` 도 같은 값으로 둔다.
- Sentinel 은 렌더링한 설정을 컨테이너 `/tmp` 에 쓰므로, 재시작하면 템플릿(`sentinel.conf`)에서 다시 시작한다.
  런타임으로 바꾼 감시 대상은 템플릿에도 반영해 두어야 재시작 뒤에 되돌아가지 않는다.

## 파일 구조

```text
redis/
├── docker-compose-redis-master.yml   # node1 + sentinel1 (master 호스트)
├── docker-compose-redis-slave.yml    # node2 + sentinel2
├── docker-compose-redis-slave2.yml   # node3 + sentinel3
├── redis.Dockerfile
├── redis-master.conf / redis-slave.conf / sentinel.conf
├── docker-entrypoint-redis.sh / docker-entrypoint-sentinel.sh
├── .env.example                      # 비밀번호 템플릿 (.env 는 커밋 금지)
└── .gitignore
```

## 실행

각 서버에서 자기 역할의 compose 만 실행합니다.

```bash
cd redis
cp .env.example .env   # REDIS_MASTER_PASSWORD 실제 값 입력
docker compose -f docker-compose-redis-master.yml up -d --build   # master 호스트
docker compose -f docker-compose-redis-slave.yml up -d --build    # replica 호스트 (backend-1)
docker compose -f docker-compose-redis-slave2.yml up -d --build   # replica 호스트 (storage)
```

## 상태 확인

```bash
# 복제 상태 (master 에서)
docker exec -it redis-node1 redis-cli -a "$REDIS_MASTER_PASSWORD" info replication

# Sentinel 이 보는 master
docker exec -it redis-sentinel-node1 redis-cli -p 26379 sentinel get-master-addr-by-name master-redis
```

## 감시 대상을 무중단으로 바로잡기 (#23)

2026-10-11 — 세 센티널과 replica 가 사라진 `192.168.0.26` 을 보고 있던 것을 **컨테이너 재시작 없이** 고쳤다.
템플릿 · `.env` 를 먼저 고친 뒤 런타임으로 맞춘다.

```bash
# replica 두 대에서
redis-cli -a "$REDIS_MASTER_PASSWORD" replicaof 192.168.0.11 6379

# sentinel 세 대에서 (announce-ip 는 그 호스트 IP)
redis-cli -p 26379 sentinel remove master-redis
redis-cli -p 26379 sentinel config set announce-ip 192.168.0.x
redis-cli -p 26379 sentinel config set announce-port 26379
redis-cli -p 26379 sentinel monitor master-redis 192.168.0.11 6379 2
redis-cli -p 26379 sentinel set master-redis auth-pass "$REDIS_MASTER_PASSWORD"
redis-cli -p 26379 sentinel set master-redis down-after-milliseconds 5000
redis-cli -p 26379 sentinel set master-redis failover-timeout 10000
redis-cli -p 26379 sentinel set master-redis parallel-syncs 1

# 확인 — 세 대 모두 192.168.0.11, num-slaves 2, num-other-sentinels 2
redis-cli -p 26379 sentinel master master-redis
redis-cli -p 26379 sentinel ckquorum master-redis
```

## 비밀번호 관리 주의

- `.env` 는 커밋하지 않습니다 (`.gitignore` 처리됨).
- 과거에 `.env` 가 저장소에 커밋된 이력이 있으므로, **비밀번호를 교체(rotate)하는 것을 권장**합니다.
  git 이력에서 완전히 지우려면 history rewrite 가 필요하지만, 사설망 전용이므로 교체가 현실적입니다.
