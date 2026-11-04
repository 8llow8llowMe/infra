# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

커밋 메시지 형식, 코드 스타일, 기본 검증 명령, 비밀값 규칙은 `AGENTS.md`에 있습니다. 이 문서에서는 반복하지 않습니다. 문서와 이슈·PR은 한국어로 씁니다.

## 이 저장소가 동작하는 방식

- 빌드나 테스트 스위트가 없습니다. 각 호스트의 `~/infra`는 이 저장소의 git 작업 트리입니다(2026-11-04 손 복사본에서 전환, #55). 호스트에서 `git pull`한 뒤 해당 컴포넌트 디렉터리에서 `docker compose` 또는 `install-*.sh`를 실행해 반영합니다. 커밋은 운영에 바로 적용되지 않으며, 호스트별 적용 단계가 따로 필요합니다.
- **레포가 항상 정본은 아닙니다.** 서버에서 먼저 고친 설정이 레포보다 앞선 적이 있습니다(`dev.bosspickseoul.conf`). 호스트에 반영하기 전에 서버 판과 기능 diff를 보고, `git pull` 전에 `git status`로 호스트별 의도된 차이(루트 README 2절 "호스트의 `~/infra`" 표)를 확인합니다.
- `install-*.sh`는 `.env`가 없을 때만 `.env.example`을 복사합니다. 그래서 `.env.example`에 변수를 추가해도 이미 운영 중인 호스트의 `.env`에는 반영되지 않습니다. 새 변수를 추가하면 컴포넌트 README의 환경변수 표를 갱신하고, PR에 호스트 `.env` 수동 병합 절차를 적습니다.
- 작업용 Windows PC에는 Docker와 호스트 `.env`가 없습니다. 로컬에서는 YAML 파싱, `bash -n`, `git diff --check`까지만 확인할 수 있습니다. `docker compose ... config -q`와 `docker exec nginx nginx -t`는 대상 호스트에서 실행하고, 실행하지 못한 검증은 PR에 그대로 적습니다.
- monitoring 서버용 compose는 `monitoring/` 루트에서 `--project-directory .`와 함께 실행합니다. 애플리케이션 서버용 agent compose(`node-exporter/`, `promtail/`의 `docker-compose-agent.yml`)는 각 폴더에서 `.env.agent`로 실행합니다.

## 큰 구조

**배치의 정본은 루트 `README.md`입니다.** 호스트 인벤토리, 컴포넌트 배치, 배치 원칙, 프로젝트별 포트 표가 여기에 있습니다. 서비스 위치나 포트를 바꾸면 이 문서부터 갱신합니다. 반드시 지켜야 할 배치 원칙은 다음과 같습니다.

- `ollama-01`(`.10`, x86_64)은 인프라 전용입니다(AI, Jenkins, Vault, Kafka). 사용자 트래픽을 받는 앱은 두지 않습니다.
- `storage`(`.12`)에는 더 얹지 않습니다. 메모리 1.9Gi(swap 2Gi는 2026-10-12에야 켰음)이고, 전 도메인의 단일 인그레스입니다.
- dev(`.11`, `.13`)와 prod(백엔드 prod 전용 미니PC, 미세팅)는 호스트를 공유하지 않습니다.
- 프로젝트별 포트 대역은 호스트별이 아니라 **전체에서** 겹치지 않게 잡습니다.
- 빌더는 x86_64이고 배포 대상은 aarch64입니다. 네이티브 바이너리가 섞인 산출물은 빌더에서 그대로 내보내지 않습니다.

**네트워크:** 대부분의 compose가 `8llow8llowme-net` 브리지를 이름으로 선언합니다. Kafka만 `external: true`로 참조하므로 이 네트워크가 먼저 있어야 합니다. 이 브리지는 호스트마다 따로 생기므로 다른 호스트의 컨테이너명은 해석되지 않습니다. **호스트 간 통신(nginx upstream, Prometheus 대상, Jenkins URL)은 반드시 사설 IP:포트로 씁니다.**

**인그레스 흐름:** `.12`의 nginx가 `conf.d/*.conf`를 include해 각 호스트의 IP:포트로 프록시합니다. `ssl_certificate` 파일이 없는 conf가 하나라도 있으면 nginx가 뜨지 못하고, 전 도메인이 함께 내려갑니다. 그래서 새 도메인은 다음 순서로 추가합니다.

1. HTTPS 블록을 주석 처리한 상태로 커밋합니다.
2. reload합니다.
3. `certbot/init-cert-*.sh`로 인증서를 발급합니다.
4. 주석을 풉니다.
5. `nginx -t && nginx -s reload`를 실행합니다.

storage의 nginx는 `nginx/conf.d`를 **디렉터리째** 바인드 마운트합니다. 호스트 `~/infra/nginx/conf.d`에 파일이 생기는 순간 include 대상이 되므로, `git pull`·checkout 직후에는 reload 전에 반드시 `docker exec nginx nginx -t`부터 실행합니다. 레포에는 있지만 운영하지 않는 conf(`jamjamnow.conf`, `api-dev.sneezecast.conf`)는 storage에서 지우고 `skip-worktree`로 표시해 두었습니다.

갱신은 certbot 컨테이너가 Docker 소켓으로 nginx를 reload해 처리합니다. auth 직결 라우트 허용 여부는 프로젝트마다 다르므로(sneezecast는 게이트웨이만 허용) `nginx/README.md`의 도메인 맵을 확인합니다.

**시크릿 흐름:** `.10`의 Vault(KV v2 + AppRole)를 씁니다. 프로젝트마다 다음 파일을 둡니다.

- 정책 3종: `vault/policies/{jenkins,backend,ui}-<project>.hcl`
- 스크립트: `vault/scripts/bootstrap-<project>.sh`, `reset-kv-<project>.sh`

정책을 바꾸면 호스트에서 `git pull`한 뒤 `docker exec ... vault sh /vault/scripts/bootstrap-<project>.sh`로 다시 적용합니다. `install-vault.sh`로 컨테이너를 재생성하면 auto-unseal이 없어 sealed 상태로 뜨므로 정책 변경에는 쓰지 않습니다. 같은 프로젝트의 파이프라인이 늘어나면 AppRole을 새로 만들지 않고 `jenkins-<project>.hcl`에 경로 블록을 추가합니다.

**CI/CD:** 파이프라인 정의(Jenkinsfile)는 각 애플리케이션 저장소에 있고, 이 저장소는 실행 노드만 정의합니다. `.10`에서 controller와 공유 빌더 하나(노드명 `ai-host-builder`, 컨테이너명 `jenkins-builder-agent`)를 실행합니다. 2026-11-04 기준 backend-1(`.13`, arm64)에 commerce-foundry 프론트 dev용 `backend-1-builder`(라벨 `builder-frontend-arm64`)가 하나 더 있으며, x86 빌더 통합 뒤 내릴 예정입니다(#58). controller는 아직 레포에 없는 옛 `jenkins/docker-compose-jenkins.yml`로 떠 있어서 `docker-compose-jenkins-controller.yml`로 옮겨지지 않았습니다. deploy agent는 호스트·역할별로 둡니다(라벨 `deploy-{backend,frontend}-{dev,dev2,prod}`). 같은 `docker-compose-jenkins-deploy-agent.yml`을 env 파일만 바꿔 여러 번 띄우므로 compose `name`, `container_name`, workdir를 모두 다르게 둡니다. agent secret은 노드명에 묶여 있어 노드명을 바꾸면 secret을 다시 받아야 합니다.

**관측:** `.14`에서 Prometheus와 Grafana를 실행합니다. Prometheus는 `monitoring/prometheus/targets/*.yml`을 file_sd로 읽고, 대상 파일 이름은 `nodes.yml` 또는 `<project>-<group>-<env>.yml` 형식입니다. Grafana는 `monitoring/grafana/dashboards/<Project>/`를 폴더 구조 그대로 프로비저닝합니다. 데이터소스 uid `prometheus`/`loki`는 바꾸지 않습니다. 새 프로젝트 대시보드는 `dashboard-templates/spring-docker/`에서 시작합니다.

**`ollama-01` 자원 예산:** Ollama(`gpt-oss:20b`, 여러 프로젝트가 공유하는 API), Jenkins controller·builder, Kafka 3브로커가 RAM 32GB 한 대에 함께 있습니다. `ollama/`와 `jenkins/`의 `*_MEM_LIMIT`·`*_CPUS`는 `ollama/HOST-STABILITY.md`의 예산에 맞춘 값이므로 하나를 바꾸면 합계를 다시 확인합니다. ollama compose를 `install-*.sh` 없이 직접 올릴 때는 `.env`에 `AMD_GPU_RENDER_GROUP`(ollama-01은 `993`)이 있어야 합니다. 비어 있으면 "Unable to find group"으로 컨테이너가 뜨지 않습니다. 실행 중인 컨테이너의 상한만 바꿀 때는 재시작 없이 `docker update`를 씁니다.

## 반영 방식이 컴포넌트마다 다른 곳

- **fail2ban:** `jail.local` 등 설정이 이미지에 `COPY`됩니다. `fail2ban-client reload`로는 반영되지 않으므로 storage에서 `docker compose -f docker-compose-fail2ban.yml up -d --build`를 실행합니다.
- **공인 IP:** 집 회선은 동적 IP입니다. 바뀌었을 때 확인할 곳은 루트 README 10절 체크리스트에 있습니다. DNS 자동 갱신은 `ddns/`(Cloudflare DNS only, 무료 조건 유지)가 맡고, zone 이전 절차는 `ddns/README.md`에 있습니다(#59).

## 새 프로젝트를 붙일 때 함께 바뀌는 곳

새 프로젝트(sneezecast, hondigagae 등)를 추가하면 보통 다음 파일이 함께 바뀝니다. 기존 프로젝트의 같은 파일을 참고해 맞춥니다.

- 루트 README: 배치 요약과 포트 대역
- `nginx/conf.d/` 도메인 4개와 `nginx/README.md` 도메인 맵
- certbot 발급 절차
- `vault/policies/`, `vault/scripts/`, `vault/README.md`의 프로젝트 절
- `jenkins/README.md` 노드·라벨 표
- `monitoring/prometheus/targets/`와 Grafana 대시보드

## 문서 작성 관례

README에는 날짜를 붙인 실측값을 적습니다. "사용자 진술 기준, 미실측"처럼 실측 여부도 구분해 적습니다. 결론이 바뀌어도 당시 판단 기록은 지우지 않고, 지금도 유효한 근거를 표로 정리합니다. 이 관례를 유지하고, 측정하지 않은 값을 확정값처럼 쓰지 않습니다.

## 이슈·PR

`.github/ISSUE_TEMPLATE/`(feature·bug)과 `.github/PULL_REQUEST_TEMPLATE.md`를 따릅니다. 작성 절차는 `issue`·`pr` 스킬(`/issue`, `/pr`)에 있습니다. Claude Code용 `.claude/skills/`는 Codex·Cursor용 `.agents/skills/`와 내용이 같은 사본이므로, 한쪽을 고치면 다른 쪽도 같이 고칩니다. 기본 브랜치는 `main`이고 작업 브랜치는 `<type>/infra/<이슈번호>-<slug>` 형식입니다(예: `feature/infra/11-ollama-stability-collaboration`). 실행하지 못한 검증 항목은 체크하지 않고 이유를 적습니다.
