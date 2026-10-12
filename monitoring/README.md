# 모니터링 운영 가이드

BossPickSeoul과 홈서버 인프라를 관측하기 위한 Grafana, Prometheus, node_exporter, Loki, Promtail IaC 구성입니다.

## 서버별 역할 요약

모니터링은 중앙 서버가 모든 것을 직접 알아서 수집하는 구조가 아닙니다. 중앙 모니터링 서버에는 저장소와 대시보드가 있고, 각 애플리케이션 서버에는 메트릭/로그를 노출하거나 전달하는 에이전트가 필요합니다.

| 서버 역할 | 반드시 필요한 구성 | 선택 구성 | 설명 |
| --- | --- | --- | --- |
| monitoring 서버 | Grafana, Prometheus, node_exporter | Loki, Promtail | 메트릭 저장/조회와 대시보드 제공 |
| backend 서버 | node_exporter, Spring Actuator endpoint | Promtail | 호스트 메트릭과 백엔드 앱 메트릭 제공 |
| frontend 서버 | node_exporter | Promtail | 호스트 메트릭과 Next.js/Nginx 로그 제공 |
| DB/Redis 서버 | node_exporter | Promtail | DB/Redis 서버 리소스 관측, 로그 중앙화는 선택 |

## 구성요소 설명

### monitoring 서버에 있어야 하는 것

| 구성요소 | 필수 여부 | 역할 |
| --- | --- | --- |
| Grafana | 필수 | Prometheus/Loki 데이터를 시각화하는 대시보드 UI |
| Prometheus | 필수 | Spring Actuator와 node_exporter 메트릭을 주기적으로 scrape하고 저장 |
| node_exporter | 필수 | monitoring 서버 자신의 CPU/RAM/DISK/네트워크 메트릭 노출 |
| Loki | 선택 | 여러 서버의 Docker 로그를 중앙 저장 |
| Promtail | 선택 | monitoring 서버에서 발생한 Docker 로그를 Loki로 전송 |

### 각 애플리케이션 서버에 있어야 하는 것

| 목적 | 필요한 구성 | 이유 |
| --- | --- | --- |
| 호스트 CPU/RAM/DISK 수집 | node_exporter | Prometheus가 `서버IP:9100/metrics`를 scrape |
| Spring Boot 앱 메트릭 수집 | Actuator `/actuator/prometheus` | Prometheus가 앱 포트의 prometheus endpoint를 scrape |
| Docker 로그 수집 | Promtail | Docker 로그를 Loki push API로 전송 |

즉, **모든 서버의 CPU/RAM/DISK를 보고 싶으면 모든 서버에 node_exporter를 실행해야 합니다.**

## 최종 개념

모니터링 구성은 저장소와 수집 에이전트를 분리해서 이해하면 됩니다.

| 구성요소 | 위치 | 개념 |
| --- | --- | --- |
| Grafana | monitoring 서버 | Prometheus/Loki 데이터를 보여주는 대시보드 |
| Prometheus | monitoring 서버 | 각 서버와 앱의 metrics를 가져오는 중앙 수집기 |
| Loki | monitoring 서버 | 여러 서버의 logs를 저장하는 중앙 저장소 |
| node_exporter | 관측할 모든 서버 | 해당 서버의 CPU/RAM/DISK metrics를 노출 |
| Promtail | 로그를 수집할 모든 서버 | 해당 서버의 Docker logs를 Loki로 전송 |

즉, **Promtail은 로그가 발생하는 서버마다 하나씩 실행하고, Loki는 중앙 monitoring 서버에 하나만 실행합니다.**

```text
metrics: Prometheus가 각 서버의 node_exporter/Actuator를 가져옵니다.
logs: 각 서버의 Promtail이 중앙 Loki로 보냅니다.
view: Grafana가 Prometheus와 Loki를 보여줍니다.
```

## 권장 배치

```text
backend/frontend/db host
  node_exporter ────────────────┐
  promtail ────────────────┐    │
                             │    │
deploy monitoring server     │    │
  grafana <──────────────────┘    │
  prometheus <────────────────────┘
  loki
  node_exporter
  promtail
```

deploy 서버가 Raspberry Pi 5 2GB라면 `Grafana + Prometheus + node_exporter`를 기본으로 켜고, `Loki + Promtail`은 로그 대시보드가 필요할 때부터 켜는 것을 권장합니다.

### deploy(.14) 자원 기준 (2026-10-12 실측)

메모리 1.9Gi · swap 6.0Gi · 디스크 235G(203G 여유)이고, 5개 컨테이너(grafana · prometheus · loki · promtail · node-exporter)가 모두 떠 있는 상태에서 사용량은 641Mi 입니다. Prometheus head series 는 1,543 개였습니다.

- 컨테이너마다 `mem_limit` 를 겁니다 (합계 1.6Gi, `.env` 의 `*_MEM_LIMIT`). 한 컨테이너가 폭주해도 나머지가 남게 하려는 것입니다.
- Loki 는 `max_query_parallelism` · `querier.max_concurrent` 를 낮춰 둡니다. 2GB 호스트에서 메모리가 튀는 건 수집보다 넓은 범위 LogQL 쿼리입니다.
- **available 이 500Mi 아래로 지속되면** 모니터링 스택을 `backend-1`(`.13`, 7.7Gi)로 옮기는 것을 다시 검토합니다. 설정은 모두 이 레포에 있어 옮길 때 바뀌는 것은 `nginx/conf.d/grafana.conf` upstream 과 각 서버 promtail 의 `LOKI_PUSH_URL` 입니다.

### deploy 서버의 `~/infra` 는 git 체크아웃이 아닙니다 (2026-10-12 확인)

다른 호스트와 달리 `git pull` 로 반영할 수 없습니다. 레포의 `monitoring/` 을 `.env` 와 `*-data` 를 제외하고 복사해 반영합니다. 덮어쓰기 전에 현재 디렉터리를 백업합니다.

```bash
# 작업 PC (레포 루트)에서
tar czf - --exclude='.env' --exclude='*-data' --exclude='promtail/data' monitoring   | ssh deploy 'cd ~/infra && tar czf ~/monitoring-backup-$(date +%Y%m%d%H%M).tgz --exclude="*-data" monitoring && tar xzf -'
```

## 파일/폴더 구조

```text
monitoring/
├── .env.example
├── install-monitoring.sh
├── install-monitoring-logs.sh
├── prometheus/
│   ├── docker-compose-prometheus.yml
│   └── prometheus.yml
├── grafana/
│   ├── docker-compose-grafana.yml
│   └── provisioning/datasources/
│       ├── prometheus.yml
│       └── loki.yml
├── loki/
│   ├── docker-compose-loki.yml
│   └── loki.yml
├── node-exporter/
│   ├── docker-compose-node-exporter.yml
│   ├── docker-compose-agent.yml
│   ├── .env.agent.example
│   └── README.md
└── promtail/
    ├── docker-compose-promtail.yml
    ├── docker-compose-agent.yml
    ├── .env.agent.example
    ├── promtail.yml
    └── README.md
```

## Docker Compose 파일 기준

모니터링 서버용 compose는 `monitoring` 루트에서 `--project-directory .` 옵션과 함께 실행합니다. 애플리케이션 서버용 agent compose는 각 agent 폴더에서 실행합니다.

| 파일 | 실행 위치 | 역할 |
| --- | --- | --- |
| `prometheus/docker-compose-prometheus.yml` | monitoring 서버 | Prometheus |
| `grafana/docker-compose-grafana.yml` | monitoring 서버 | Grafana |
| `node-exporter/docker-compose-node-exporter.yml` | monitoring 서버 | monitoring 서버 node_exporter |
| `loki/docker-compose-loki.yml` | monitoring 서버 | Loki |
| `promtail/docker-compose-promtail.yml` | monitoring 서버 | monitoring 서버 Promtail |
| `node-exporter/docker-compose-agent.yml` | 애플리케이션 서버 | node_exporter만 실행 |
| `promtail/docker-compose-agent.yml` | 애플리케이션 서버 | Promtail만 실행 |

## monitoring 서버 실행 순서

### 1. 환경변수 준비

```bash
cd monitoring
cp .env.example .env
vi .env
```

최소 변경이 필요한 값:

| 변수 | 설명 |
| --- | --- |
| `GRAFANA_ADMIN_USER` | Grafana 관리자 계정 |
| `GRAFANA_ADMIN_PASSWORD` | Grafana 관리자 비밀번호 |
| `PROMETHEUS_RETENTION_TIME` | Prometheus 데이터 보관 기간 |
| `PROMETHEUS_RETENTION_SIZE` | Prometheus 데이터 최대 크기 |
| `LOKI_RETENTION_PERIOD` | Loki 로그 보관 기간 |
| `*_MEM_LIMIT` | 컨테이너 메모리 상한. 비우면 compose 기본값(prometheus 640m, grafana 320m, loki 384m, promtail 192m, node-exporter 64m) |
| `MONITORING_PROMTAIL_LOKI_PUSH_URL` | monitoring 서버 Promtail이 로그를 보낼 Loki push URL |
| `MONITORING_PROMTAIL_HOSTNAME` | monitoring 서버 로그에 붙일 host 라벨 |
| `MONITORING_PROMTAIL_PROJECT` | monitoring 서버 로그에 붙일 project 라벨 |

### 2. 기본 스택 실행

```bash
sh install-monitoring.sh
```

직접 실행하려면:

```bash
docker compose --project-directory . --env-file .env \
  -f prometheus/docker-compose-prometheus.yml \
  -f node-exporter/docker-compose-node-exporter.yml \
  -f grafana/docker-compose-grafana.yml \
  up -d
```

기본 스택에 포함되는 서비스:

| 서비스 | 포트 | 설명 |
| --- | --- | --- |
| Grafana | `3001 -> 3000` | 대시보드 UI |
| Prometheus | `9090 -> 9090` | 메트릭 수집/저장 |
| node_exporter | `9100 -> 9100` | monitoring 서버 host metric |

### 3. Loki/Promtail 로그 스택 실행

로그까지 중앙화할 때만 실행합니다.

```bash
sh install-monitoring-logs.sh
```

직접 실행하려면:

```bash
docker compose --project-directory . --env-file .env \
  -f loki/docker-compose-loki.yml \
  -f promtail/docker-compose-promtail.yml \
  up -d
```

로그 스택에 포함되는 서비스:

| 서비스 | 포트 | 설명 |
| --- | --- | --- |
| Loki | `3100 -> 3100` | 로그 저장소 |
| Promtail | 내부 전송 | monitoring 서버의 Docker 로그를 Loki로 전송 |

Loki/Promtail만 중지:

```bash
docker compose --project-directory . --env-file .env \
  -f loki/docker-compose-loki.yml \
  -f promtail/docker-compose-promtail.yml \
  stop loki promtail
```

## 애플리케이션 서버에서 node_exporter만 실행

host CPU/RAM/DISK를 수집하려면 해당 서버에서 실행합니다.

```bash
cd monitoring/node-exporter
cp .env.agent.example .env.agent
vi .env.agent
sh install-node-exporter.sh
```

이후 monitoring 서버의 `prometheus/targets/nodes.yml`에 해당 서버 target을 추가합니다.

```yaml
- targets:
    - 192.168.0.13:9100
  labels:
    host: backend-1
    role: backend
    project: bosspickseoul
```

설정 반영:

```bash
docker exec prometheus promtool check config /etc/prometheus/prometheus.yml
curl -X POST http://localhost:9090/-/reload
```

## 애플리케이션 서버에서 Promtail만 실행

Docker 컨테이너 로그를 Loki로 보내고 싶은 서버에서 실행합니다.

**Grafana(monitoring 서버)와 백엔드 서버가 분리되어 있어도 로그는 백엔드 서버에 Promtail을 띄워야 합니다.** Loki는 push 방식이라 원격 서버의 로그를 스스로 읽어올 수 없습니다. 반면 백엔드 앱 메트릭은 Prometheus가 pull로 가져가므로 agent가 필요 없습니다.

```bash
# 백엔드 서버에서
cd monitoring/promtail
cp .env.agent.example .env.agent
vi .env.agent
sh install-promtail.sh
```

중요 환경변수:

```env
LOKI_PUSH_URL=http://192.168.0.14:3100/loki/api/v1/push
PROMTAIL_HOSTNAME=backend-1
PROMTAIL_PROJECT=bosspickseoul
```

| 변수 | 설명 |
| --- | --- |
| `LOKI_PUSH_URL` | monitoring 서버의 Loki push API |
| `PROMTAIL_HOSTNAME` | 로그가 발생한 서버명. 서버마다 다른 값을 넣어야 Grafana에서 구분됩니다 |
| `PROMTAIL_PROJECT` | Loki/Grafana에서 필터링할 프로젝트명 |

선행 조건 2가지를 확인합니다.

```bash
# 1. 백엔드 서버에서 monitoring 서버 3100 도달 확인
curl http://192.168.0.14:3100/ready
```

2. Loki push API에는 인증이 없으므로 **사설망 주소를 사용하고 공개망에 노출하지 않습니다.** 불가피하면 Nginx basic auth + HTTPS로 감쌉니다.

Promtail은 Docker socket을 읽어 컨테이너를 자동 탐색하므로 서비스를 새로 띄워도 설정을 고칠 필요가 없습니다. 라벨 구성 규칙, LogQL 쿼리 예시, 로그가 보이지 않을 때의 진단 순서는 `promtail/README.md`에 정리했습니다.

## 애플리케이션 서버에서 node_exporter + Promtail 같이 실행

두 agent를 모두 켤 때도 각 폴더에서 하나씩 실행하는 방식을 권장합니다. 실행 위치가 분리되어 있어 어떤 agent를 설정하는지 명확합니다.

```bash
cd monitoring/node-exporter
cp .env.agent.example .env.agent
vi .env.agent
sh install-node-exporter.sh

cd ../promtail
cp .env.agent.example .env.agent
vi .env.agent
sh install-promtail.sh
```

## BossPickSeoul 백엔드 메트릭 수집

백엔드 서비스는 Spring Actuator의 `/actuator/prometheus` 엔드포인트를 Prometheus가 scrape합니다.

백엔드 배포 호스트는 환경별로 분리되어 있습니다. dev는 main-server(`192.168.0.11`, hostname `raspberrypi`, MySQL/Redis master 동거), prod는 backend-1(`192.168.0.13`)입니다. cloud/service와 dev/prod를 각각 별도 target 파일로 관리하며 파일명은 `<project>-<service_group>-<env>.yml` 형식입니다.

| target 파일 | Prometheus job | 환경 |
| --- | --- | --- |
| `bosspickseoul-cloud-dev.yml` | `bosspickseoul-cloud` | dev |
| `bosspickseoul-cloud-prod.yml` | `bosspickseoul-cloud` | prod |
| `bosspickseoul-service-dev.yml` | `bosspickseoul-service` | dev |
| `bosspickseoul-service-prod.yml` | `bosspickseoul-service` | prod |

`instance`는 Prometheus 기본값인 `IP:port`를 유지합니다. Spring Cloud가 `spring.application.name`을 서비스 탐색 ID로 사용하므로 Docker 실행 단위는 `application`이 아니라 `container`과 `deployment`로 조회합니다.

| 서비스 | dev scrape target (main-server) |
| --- | --- |
| service-discovery | `192.168.0.11:6761/actuator/prometheus` |
| api-gateway | `192.168.0.11:6000/actuator/prometheus` |
| auth-service | `192.168.0.11:6081/actuator/prometheus` |
| district-service | `192.168.0.11:6082/actuator/prometheus` |
| commercial-service | `192.168.0.11:6083/actuator/prometheus` |
| ai-service | `192.168.0.11:6085/actuator/prometheus` |
| community-service | `192.168.0.11:6086/actuator/prometheus` |
| batch-service | `192.168.0.11:6080/actuator/prometheus` |

prod는 backend-1(`192.168.0.13`)의 `9xxx` 포트를 사용합니다. 실행하지 않는 서비스는 Prometheus와 Grafana에서 `DOWN`으로 표시됩니다.

## Grafana 대시보드 프로비저닝

`grafana/dashboards/BossPickSeoul`의 JSON은 Grafana의 BossPickSeoul 폴더로 자동 프로비저닝됩니다.

| 대시보드 | 데이터소스 | 핵심 패널 |
| --- | --- | --- |
| Backend Overview | Prometheus | 서비스 UP/DOWN, 처리량, p95, heap, 5xx |
| Backend Logs | Loki | 로그 수집량, WARN/ERROR, 실시간 로그 |
| JPA Repository | Prometheus | Repository 호출률, 평균 응답시간, 오류 |
| HTTP Performance | Prometheus | URI 처리량, p50/p95/p99, 상태 코드 |
| JVM / 런타임 | Prometheus | heap·non-heap, 시스템/프로세스 CPU, load, thread, GC, HikariCP |
| Executor / Thread Pool | Prometheus | active/queued, pool core·current·max, 완료 처리율, 실행시간 |

다른 프로젝트는 `grafana/dashboard-templates/spring-docker`의 JSON을 복사해 `__PROJECT__`, title, uid를 변경합니다. 프로비저닝된 대시보드는 Grafana UI가 아니라 Git의 JSON을 원본으로 관리합니다.

Grafana는 `grafana/grafana:12.x`를 사용하며, 대시보드는 classic 스키마(schemaVersion 40) + 접이식 row 구조입니다. datasource는 고정 uid `prometheus`, `loki`로 참조합니다. 대시보드 구조와 Grafana 12 전환 세부 사항은 `grafana/README.md`를 참고합니다.

### 실행 중인데 로그 대시보드에 보이지 않는 경우

Prometheus와 Loki는 서로 다른 사실을 보여줍니다.

- Prometheus `up=1`: Actuator scrape가 성공해 서비스 프로세스를 관측할 수 있음
- Loki 로그 존재: 선택한 시간 범위에 컨테이너가 stdout/stderr 로그를 실제로 출력함

service-discovery는 Eureka 유지보수 로그를 주기적으로 출력하므로 요청이 없어도 계속 보입니다. 반면 일반 API 서비스는 최근 요청이나 이벤트가 없으면 로그가 없을 수 있습니다. `JVM 상세`에서 서비스가 보이는데 `백엔드 로그`에만 없다면 `grafana/README.md`의 backend-1 로그 진단 절차로 최근 로그 수, Docker 라벨, Promtail 오류 순서로 확인합니다.

로그 대시보드의 서비스 선택 목록은 Loki가 아니라 Prometheus `up` 라벨에서 가져옵니다. 따라서 최근 로그가 없는 서비스도 선택할 수 있고, 상단 상태 패널에서 실행 상태와 로그 유입 여부를 구분할 수 있습니다.

## 운영 기준

- 모든 서버의 host metric을 보려면 모든 서버에 node_exporter를 둡니다.
- 모든 서버의 Docker 로그를 보려면 모든 서버에 Promtail을 둡니다.
- Prometheus scrape interval은 30초로 시작합니다.
- Prometheus retention은 `15d`, `8GB`로 시작하되 라즈베리파이 메모리/디스크 상태를 보고 줄입니다.
- Loki retention은 `72h`로 시작합니다.
- Grafana와 Prometheus는 공개망에 직접 노출하지 말고 Nginx 인증, VPN, 내부망으로 보호합니다.
- Loki push API(3100)에는 인증이 없습니다. agent와 Loki 사이는 사설망 통신으로 유지합니다.
- Promtail은 2026-02-28로 지원이 종료되었습니다. 신규 서버는 Grafana Alloy 전환을 검토합니다. (`promtail/README.md` 참고)

## 빠른 점검

Prometheus target:

```bash
curl http://localhost:9090/api/v1/targets
```

node_exporter:

```bash
curl http://localhost:9100/metrics
```

Spring Actuator:

```bash
curl http://192.168.0.11:6081/actuator/prometheus
```

Loki:

```bash
curl http://localhost:3100/ready
```

디스크 사용량:

```bash
du -sh prometheus-data grafana-data loki-data promtail-data promtail/data
```
