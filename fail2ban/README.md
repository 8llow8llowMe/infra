# Fail2Ban

storage(`192.168.0.12`) nginx 의 `access.log` 를 읽어 스캐너 · 공격 도구 IP 를 호스트 방화벽에서 막습니다 (#37).

## 구조

```text
요청 → nginx ── 스캐너 경로면 444 (nginx.conf map $scanner_probe)
          └─ access.log (main 포맷)
                 └─ fail2ban (network_mode: host)
                        ├─ 탐지 · 차단 → 호스트 iptables DOCKER-USER 체인 (80/443)
                        └─ ./logs/fail2ban.log → promtail(storage) → Loki → Grafana Infra/03-security
```

- **차단은 호스트 `DOCKER-USER` 체인에 겁니다.** nginx 는 docker 가 publish 한 80/443 이라 패킷이 `INPUT` 이 아니라 `FORWARD → DOCKER-USER` 를 지납니다. `DOCKER-USER` 는 docker publish 포트에만 걸리므로 SSH 는 영향이 없습니다.
- **컨테이너는 `network_mode: host` 입니다.** #37 전에는 브리지 네트워크라 규칙 1,693개가 컨테이너 자신의 네트워크 네임스페이스에만 들어가 **아무것도 막지 못했습니다.**
- 이미지의 iptables 는 호스트와 같은 nf_tables 백엔드여야 합니다. 2026-10-12 기준 둘 다 `iptables v1.8.11 (nf_tables)` 이고 이미지는 `alpine:3.22` 로 고정했습니다. 올릴 때는 `iptables --version` 을 호스트와 비교합니다.

## 규칙

| jail | 판정 | maxretry / findtime | 비고 |
| --- | --- | --- | --- |
| `nginx-scanner` | 상태 코드 `444` (nginx 가 스캐너 경로로 끊은 요청) | 2 / 10분 | 경로 목록은 `nginx/nginx.conf` 한 곳에만 있습니다 |
| `nginx-badbots` | 공격 도구 UA (sqlmap · nikto · nuclei · nmap · masscan · zgrab · wpscan · gobuster · ffuf 등) | 1 / 10분 | |
| `nginx-errburst` | 400 · 404 · 405 다발 | 30 / 1분 | 401 · 403 과 `/api/` · `/_next/` 는 세지 않습니다 |
| `recidive` | 하루에 3번 이상 차단된 IP | 3 / 1일 | docker publish 포트 전체를 7일 |

- 차단 시간은 **첫 1시간, 다시 걸릴 때마다 두 배(모든 jail 합산), 최대 30일** 입니다(`bantime.increment`). 이력은 `./fail2ban-data` 의 DB 에 30일 남습니다.
- **막지 않는 것:** 검색엔진 · AI 크롤러 · `curl` 같은 일반 UA, `login` · `admin` · `dashboard` 같은 일반 단어 경로, 200 응답. #37 전에는 이것들로 Googlebot 37 · Meta 156 · OpenAI 40 개 IP 가 7일씩 차단 목록에 있었고, 혼디가개 `/login` 을 연 사용자도 1번에 7일 막혔습니다.
- **예외(`ignoreip`):** 내부망 `10/8` · `172.16/12`(docker 브리지) · `192.168/16`, 공인 IP `1.235.23.72`, Cloudflare 대역.

### Cloudflare

Cloudflare 는 우리 앞단 프록시가 **아닙니다.** DNS 가 공인 IP 를 직접 가리키고, Cloudflare 대역에서 오는 요청은 Workers 에서 나온 스캐너(`/wp-admin/install.php` · `/.git/config`)입니다.

- 여러 사용자가 같이 쓰는 출구 IP 라 IP 로 막지 않고 `ignoreip` 에 둡니다. 스캐너 경로는 nginx 가 444 로 이미 끊습니다.
- `set_real_ip_from` 으로 `CF-Connecting-IP` 를 믿지 **않습니다.** Worker 를 만들면 누구나 이 헤더를 원하는 값으로 보낼 수 있어서, 믿으면 남의 IP 를 차단시키거나 차단을 피할 수 있습니다.
- 대역 목록은 <https://www.cloudflare.com/ips/> 에서 가져왔고(2026-10-12) `jail.local` 의 `cloudflare_ips` 에 있습니다.

## 모드 (`F2B_MODE`)

| 값 | 동작 |
| --- | --- |
| `log` (기본) | 차단하지 않고 `fail2ban.log` 에 Found · Ban · Unban 만 남깁니다(`dummy` action) |
| `enforce` | 호스트 `DOCKER-USER` 체인에 차단 규칙을 겁니다 |

엔트리포인트가 값에 맞는 `banaction` 을 `jail.d/zz-mode.local` 에 써서 `jail.local` 을 덮습니다. 새 규칙은 `log` 로 하루 이상 Grafana `Infra 보안 (fail2ban)` 에서 오탐을 본 뒤 `enforce` 로 바꿉니다.

```bash
cd ~/infra/fail2ban
echo 'F2B_MODE=enforce' > .env          # 되돌리려면 log
docker compose -f docker-compose-fail2ban.yml up -d
docker exec fail2ban iptables -S DOCKER-USER   # -j f2b-nginx-scanner 등이 보이면 적용된 것
```

## 운영

```bash
# 반영 (빌드 포함). 컨테이너를 다시 만들면 차단 규칙이 풀렸다가 DB 에서 복원됩니다(Restore Ban).
cd ~/infra/fail2ban && docker compose -f docker-compose-fail2ban.yml up -d --build

docker exec fail2ban fail2ban-client status                      # jail 목록
docker exec fail2ban fail2ban-client status nginx-scanner        # jail 별 차단 IP
docker exec fail2ban fail2ban-client set nginx-scanner unbanip <IP>
docker exec fail2ban fail2ban-client unban --all

# 필터를 바꿨으면 기존 로그로 먼저 돌려 봅니다
docker exec fail2ban fail2ban-regex /var/log/nginx/access.log /etc/fail2ban/filter.d/nginx-errburst.conf
```

- 로그: `./logs/fail2ban.log` (호스트). logrotate 컨테이너가 주 단위로 4주 보관하고 `fail2ban-client flushlogs` 로 다시 엽니다.
- 시각은 KST 입니다(이미지에 `tzdata`).
- 호스트에서 `curl localhost` 로 시험하면 클라이언트가 docker 게이트웨이(`172.18.0.1`)로 찍히고 `ignoreip` 라 `Ignore` 로만 남습니다. 차단을 보려면 외부망에서 시험합니다.

## 파일

| 파일 | 역할 |
| --- | --- |
| `jail.local` | jail · 차단 시간 · 예외 |
| `fail2ban.local` | 로그 위치 · DB 보존 기간 |
| `filter.d/nginx-*.conf` | access.log `main` 포맷 정규식 |
| `docker-entrypoint-fail2ban.sh` | `F2B_MODE` 적용 후 포그라운드 실행 |
| `fail2ban-healthcheck.sh` | jail 별 차단 수 요약 (healthcheck) |
