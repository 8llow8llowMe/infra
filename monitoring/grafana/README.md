# Grafana 대시보드 코드 관리

`dashboards` 아래 JSON 파일은 Grafana 시작 시 파일시스템 경로와 같은 폴더에 자동 프로비저닝됩니다. 예를 들어 `dashboards/BossPickSeoul`은 Grafana의 `BossPickSeoul` 폴더가 됩니다.

프로비저닝된 대시보드는 Grafana UI가 아니라 Git의 JSON을 원본으로 관리합니다. 변경 파일은 최대 30초 안에 다시 읽히며, 반영되지 않으면 Grafana 컨테이너만 재시작합니다.

## 실행 기준 (Grafana 12)

- 이미지는 `grafana/grafana:12.x`를 사용합니다. Grafana는 12.4.0부터 `grafana/grafana-oss` 저장소 업데이트를 중단하고 동일한 OSS 이미지를 `grafana/grafana`로 배포합니다.
- 대시보드는 **classic 스키마(schemaVersion 40)** + 접이식 row 패널 구조입니다. 파일 프로비저닝으로 안정적으로 로드됩니다. 탭/auto-grid 같은 v2 동적 대시보드는 experimental이며 `kubernetesDashboards,dashboardNewLayouts` 피처 토글이 필요합니다(`grafana/docker-compose-grafana.yml`에 주석으로 준비되어 있습니다).
- datasource는 이름이 아니라 **고정 uid로 참조**합니다. 프로비저닝된 uid는 `prometheus`, `loki`입니다(`grafana/provisioning/datasources`). 이 uid는 바꾸지 않습니다. 바꾸면 모든 대시보드가 깨집니다.

### 기존 Grafana 를 고정 uid datasource 로 올릴 때 (2026-10-12, deploy 11.3.0 → 12.4.0)

uid 없이 프로비저닝됐던 옛 `Prometheus`/`Loki` datasource 가 DB 에 남아 있으면 Grafana 가 `Datasource provisioning error: data source not found` 로 기동에 실패하고 재시작을 반복합니다. 한 번만 옛 항목을 지우고 다시 만듭니다.

```bash
cd ~/infra/monitoring
cat > grafana/provisioning/datasources/00-migrate-delete-legacy.yml <<'YML'
apiVersion: 1
deleteDatasources:
  - name: Prometheus
    orgId: 1
  - name: Loki
    orgId: 1
YML
docker restart grafana            # 로그에 inserting datasource ... uid=prometheus / uid=loki 확인
rm grafana/provisioning/datasources/00-migrate-delete-legacy.yml
docker restart grafana            # 이 파일 없이도 정상 기동하는지 확인
```

업그레이드 전에는 `docker exec grafana tar czf - -C /var/lib/grafana --exclude=plugins . > grafana-data-backup.tgz` 로 DB 를 백업합니다. `grafana-data` 는 UID 472 소유라 호스트 계정으로는 바로 읽을 수 없습니다.

## 대시보드 공통 구조

모든 대시보드는 동일한 규칙을 따릅니다.

- 상단 우측 **대시보드 드롭다운 링크**로 `bosspickseoul` 태그 대시보드 사이를 변수·시간 범위를 유지한 채 이동합니다.
- 첫 번째 **요약 row**에 KPI stat 패널(상태/처리량/오류율 등)을 배치하고, 이후 접이식 row로 세부 패널을 그룹화합니다.
- **개발/운영은 대시보드를 복제하지 않고 `env` 변수로 전환**합니다. 요약 row 제목에 현재 `$env`가 표시됩니다.
- 개요의 서비스 상태 카드와 처리량 그래프에는 **드릴다운 data link**가 있어, 서비스를 클릭하면 해당 서비스로 필터링된 HTTP·JVM 상세 대시보드로 이동합니다.

## BossPickSeoul 대시보드

| 파일 | 운영 관점 | KPI 요약 row | 세부 패널 |
| --- | --- | --- | --- |
| `01-backend-overview.json` | MSA 개요 / RED | 환경 배지, 정상 서비스 수, 처리량, 5xx율, 최대 힙 | 서비스 UP/DOWN(드릴다운), 요청량, p95, 힙, 5xx 비율 |
| `02-backend-logs.json` | 서비스 로그 | 서비스 상태, 전체·오류 로그 유입률 | Loki 유입률, WARN/ERROR, 실시간 로그 |
| `03-jpa-repository.json` | Spring Data | 전체 호출률, 평균 응답시간, 오류 호출률 | 호출률, 평균 응답시간, 오류 발생률 |
| `04-http-performance.json` | HTTP RED | 처리량, 4xx율, 5xx율, p95 | URI 처리량, p50/p95/p99, 상태 코드 분포 |
| `05-jvm.json` | JVM / 런타임 | 가동시간, 힙, CPU, 스레드 | 힙·Non-Heap 메모리, 시스템/프로세스 CPU, load average, 스레드 상태, GC, HikariCP |
| `06-executor-threadpool.json` | Executor / 스레드 풀 | Active 스레드, Queue 적재량, Pool 사용률 | Pool 사용률(active/pool_size), Pool 크기(core/current/max), Active vs Queue, 완료 처리율, 실행시간 |

프로젝트는 숨겨진 상수로 고정하고, 운영자가 자주 바꾸는 변수는 `서비스 그룹 → 환경 → 호스트/서비스 → 인스턴스 또는 컨테이너` 순서로 배치합니다. `All` 값은 정규식 `.*`로 확장합니다.

### Executor 이름 규약

`06-executor-threadpool.json`의 `Executor` 변수와 범례는 Micrometer `executor_*` 메트릭의 `name` 태그를 사용하며, 이 값은 **Spring `ThreadPoolTaskExecutor` 빈 이름**입니다. 백엔드는 `{도메인}{용도}TaskExecutor` 규약(`backend/docs/api-design-guide.md` §7)을 따르므로 빈 이름만으로 서비스·용도가 드러납니다. `applicationTaskExecutor`, `taskScheduler`는 Spring 기본 풀이며, 애플리케이션 워커는 전용 빈으로 분리합니다. 빈 이름을 바꾸면 이 대시보드의 범례도 함께 바뀝니다.

## Infra 대시보드 (#31)

`dashboards/Infra` 는 프로젝트가 아니라 호스트·공용 인프라를 봅니다. 상단 드롭다운은 `infra` 태그로 묶입니다.

| 파일 | 데이터소스 | 핵심 패널 |
| --- | --- | --- |
| `01-hosts.json` | Prometheus (`job="node"`) | 호스트 UP, CPU · 메모리 · 루트 디스크 · swap 사용률, available, load/코어, 디스크 I/O, 네트워크 |
| `02-ollama.json` | Loki + Prometheus | 추론 요청 수 · p50/p95 지연 · 5xx · 호출 호스트별 · 상태 코드, GPU 사용률 · GTT/VRAM, ollama-01 CPU/메모리, 원본 로그 |

- **Ollama 는 `/metrics` 가 없습니다(404).** 그래서 요청 지표는 GIN 요청 로그 `[GIN] ... | 200 | 41.5s | 192.168.0.11 | POST "/api/chat"` 를 LogQL `regexp` 로 파싱하고 `unwrap duration(latency)` 로 지연을 구합니다. 로그 형식이 바뀌면 이 대시보드가 비게 됩니다.
- `/api/ps` · `/api/tags` · `/metrics` 같은 상태 조회는 요청 지표에서 뺍니다. **LogQL 라벨 필터 정규식은 전체 일치가 아니므로** `^(...)$` 앵커를 직접 답니다. 앵커가 없으면 `|/` 갈래가 모든 경로와 맞아 패널이 비었습니다(2026-10-12).
- GPU 는 node_exporter `--collector.drm`(amdgpu)입니다. 2026-10-12 실측: VRAM 512MiB, GTT 15.3GiB 중 11.8GiB 사용(`gpt-oss:20b` 로드 상태).

## 공개 대시보드 적용 기준

현재 JSON은 공개 대시보드를 그대로 복사하지 않고 다음 대시보드의 운영 관점을 BossPickSeoul 라벨 계약에 맞게 적용했습니다.

| 대시보드 | 적용 내용 | 그대로 import하지 않은 이유 |
| --- | --- | --- |
| Spring Boot Application `9845` | HTTP 요청량, 느린 요청, Controller 관점 | 단일 application 중심이며 불필요한 Chaos Monkey 패널이 포함될 수 있음 |
| JVM (Micrometer) `4701` | JVM 메모리, CPU, 스레드, GC, HikariCP | 구형 Graph/Singlestat 패널과 application 중심 변수를 현재 Grafana와 MSA 라벨에 맞춰야 함 |
| OpenTelemetry JVM Micrometer `20352` | RED/USE 화면 구성 참고 | 현재 수집 경로가 OTLP가 아니라 Prometheus/Loki이므로 직접 호환되지 않음 |
| Spring Boot 2.1 System Monitor `11378` | 참고만 함 | Spring Boot 2.1과 구형 패널 기반이며 현재 Grafana 카탈로그에서 직접 조회되지 않음 |

## 로그 대시보드 설계

실행 중인 컨테이너라도 선택한 시간 범위에 stdout/stderr 로그를 출력하지 않으면 Loki에는 조회할 로그 스트림이 없습니다. 따라서 로그 대시보드는 다음처럼 데이터소스를 분리합니다.

- 서비스 그룹, 환경, 호스트, 서비스, 컨테이너 목록: Prometheus `up` 라벨
- 서비스 실행 상태: Prometheus
- 실제 로그 유입률과 로그 본문: Loki

서비스 상태가 `UP`이고 로그 유입률만 비어 있다면 수집 장애라고 단정하지 않습니다. 해당 시간에 애플리케이션 로그가 발생했는지 먼저 확인합니다.

## backend-1 로그 진단

최근 한 시간 동안 컨테이너별 로그 수를 확인합니다.

```bash
for container in $(docker ps --filter name=bosspickseoul --format '{{.Names}}'); do
  printf '%-50s ' "$container"
  docker logs --since 1h "$container" 2>&1 | wc -l
done
```

service-discovery만 값이 크다면 Eureka가 주기 로그를 출력하고 다른 서비스는 최근 요청이나 이벤트가 없어 조용한 상태일 가능성이 큽니다.

관측 라벨과 Compose fallback 라벨을 확인합니다.

```bash
docker inspect bosspickseoul-auth-service-dev \
  --format 'driver={{.HostConfig.LogConfig.Type}} compose={{index .Config.Labels "com.docker.compose.service"}} project={{index .Config.Labels "observability.project"}} service={{index .Config.Labels "observability.service"}} env={{index .Config.Labels "observability.env"}}'
```

정상 기대값은 `compose=auth-service-dev`, `project=bosspickseoul`, `service=auth-service`, `env=dev`입니다. `observability.*`가 비어 있으면 최신 Compose 설정으로 컨테이너를 재생성합니다. 단순 `docker restart`는 라벨을 갱신하지 않습니다.

Promtail 전송 오류를 확인합니다.

```bash
docker logs --since 30m promtail 2>&1 | grep -Ei 'error|warn|status=4|status=5'
```

Grafana Explore에서 범위를 넓혀 직접 확인합니다.

```logql
{project="bosspickseoul", host="backend-1"}
```

```logql
{project="bosspickseoul", service="auth-service", env="dev"}
```

## Promtail 수명주기

Promtail은 Loki 3.0부터 deprecated 상태이며 최신 Loki 계열에서는 Grafana Alloy가 권장 수집기입니다. 현재 Promtail 3.2.1 구성은 즉시 중단되는 것은 아니지만 신규 기능과 장기 유지보수를 위해 별도 변경에서 `discovery.docker + loki.source.docker + loki.write` 기반 Alloy로 전환합니다. 대시보드의 Loki 라벨 계약은 유지해 수집기 교체가 화면에 영향을 주지 않도록 합니다.
