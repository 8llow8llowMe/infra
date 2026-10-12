# Spring Docker Grafana 대시보드 템플릿

이 디렉터리는 Grafana에 마운트되지 않습니다. Spring Boot Actuator 메트릭과 Docker 로그를 노출하는 프로젝트를 위한 원본(source) 템플릿입니다.

## 필수 라벨

| 라벨 | 예시 | 설명 |
| --- | --- | --- |
| project | bosspickseoul | 전역에서 고유한 프로젝트 이름 |
| job | bosspickseoul-service | Prometheus scrape job |
| service_group | service | service 또는 cloud |
| env | dev | dev 또는 prod |
| host | backend-1 | Docker 호스트 이름 |
| service | auth-service | 논리적 서비스 이름 |
| application | auth-service | Spring 애플리케이션 및 서비스 디스커버리 이름 |
| deployment | bosspickseoul-auth-service-dev | 배포된 Docker 단위 |
| container | bosspickseoul-auth-service-dev | Docker 컨테이너 이름 |
| instance | 192.168.0.13:6081 | Prometheus scrape 엔드포인트 |

Prometheus 메트릭과 Loki 로그는 project, service_group, env, host, service를 공유합니다. Prometheus는 추가로 instance를, Loki는 추가로 container와 deployment를 사용합니다.

## 데이터소스 참조

패널과 템플릿 변수는 `${DS_*}` 변수가 아니라 고정 uid로 데이터소스를 참조합니다. 프로비저닝된 uid는 `prometheus`와 `loki`입니다(`grafana/provisioning/datasources` 참고). 이 uid는 바꾸지 않습니다. 바꾸면 모든 대시보드가 깨집니다.

## 프로젝트 대시보드 만들기

템플릿은 `NN-<이름>.template.json` 6종(개요 · 로그 · JPA · HTTP · JVM · Executor)입니다. BossPickSeoul 대시보드에서 `bosspickseoul` → `__PROJECT__`, `BossPickSeoul` → `__PROJECT_TITLE__` 만 바꿔 만든 것이라, 쿼리는 모두 라벨로만 동작하고 호스트·IP 를 하드코딩하지 않습니다.

```bash
cd monitoring/grafana
sh render-dashboards.sh hondigagae Hondigagae   # dashboards/Hondigagae/*.json 생성
```

1. 위 스크립트로 `dashboards/<Folder>/` 를 만듭니다. uid 는 `<project>-...` 라 프로젝트끼리 겹치지 않습니다.
2. 데이터소스 uid는 `prometheus` / `loki`로 유지합니다.
3. `<project>-<group>-<env>.yml` 형식의 Prometheus target 파일과 `prometheus.yml` job 을 추가합니다.
4. Grafana 30초 프로비저닝 폴링을 기다리거나 재시작합니다.

템플릿을 고친 뒤에는 렌더링된 모든 프로젝트 폴더를 다시 만듭니다. `sh render-dashboards.sh bosspickseoul BossPickSeoul` 결과가 커밋된 BossPickSeoul JSON 과 같아야 합니다(2026-10-12 확인).

템플릿은 접이식 row 패널, KPI 요약 row, `env` 전환 변수, 대시보드 드롭다운 링크를 갖춘 classic 스키마(schemaVersion 40)를 사용합니다. 이 구성은 Grafana 12에서 안정적으로 프로비저닝됩니다. 탭 / auto-grid(v2 스키마)는 선택 사항이며 `kubernetesDashboards,dashboardNewLayouts` 피처 토글이 필요합니다.

모니터링만을 위해 spring.application.name을 바꾸지 않습니다. Spring Cloud가 이 값을 서비스 디스커버리 식별자로 사용하기 때문입니다. Docker 런타임 이름은 container 또는 deployment를 사용합니다.
