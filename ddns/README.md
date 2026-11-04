# Cloudflare DDNS

집 회선(SK브로드밴드)은 동적 공인 IP 입니다. 2026-11 초 `1.235.23.72` → `1.241.243.70` 으로 바뀌었고, 그때는 가비아에서 A 레코드를 손으로 고쳤습니다(#56).
이 컴포넌트는 DNS 를 Cloudflare(Free)로 옮긴 zone 의 A 레코드를 **공인 IP 가 바뀌면 1분 안에 자동으로 고칩니다**(#59).

- 실행 위치: `deploy`(`192.168.0.14`, 모니터링 서버) — 상시 기동, 메모리 상한 64MiB
- 이미지: [`favonia/cloudflare-ddns`](https://github.com/favonia/cloudflare-ddns) `1.17.1` (Apache-2.0)

## 왜 이 구성인가 — "얼마나 써도 무료"

| 구성 | 비용 | 판단 |
| --- | --- | --- |
| **DNS only(회색 구름) + DDNS** | 무료 | **채택.** 사용자 트래픽이 Cloudflare 를 거치지 않으므로 트래픽 양에 따른 제한 · 과금 경로가 없습니다. Cloudflare 는 이름 → IP 응답만 합니다 |
| 프록시(주황 구름) | 무료 | 쓰지 않습니다. CDN 약관상 무료 플랜으로 영상 · 대용량 · 비중이 큰 이미지를 서비스하면 제한될 수 있습니다(쇼핑몰 이미지). 또 프록시를 켜면 fail2ban 이 Cloudflare IP 만 보게 됩니다 |
| Tunnel | 무료 | 쓰지 않습니다. 프록시와 같은 약관 위험이 있고, nginx · certbot · fail2ban 구조를 바꿔야 합니다 |

- Cloudflare 계정에 **결제수단을 등록하지 않습니다.** 유료 기능이 켜질 경로를 처음부터 없앱니다.
- API 한도는 토큰당 5분에 1200건입니다. 이 컨테이너는 공인 IP 를 `1.1.1.1/cdn-cgi/trace` 로 확인하고(API 아님), 레코드 수정 API 는 IP 가 바뀔 때만 부릅니다.
- `PROXIED=false` 는 **새로 만드는 레코드의 기본값**입니다. 이미 있는 레코드의 구름 상태는 바꾸지 않으므로, zone 을 가져올 때 레코드가 전부 회색인지 직접 확인합니다.
- 네임서버를 Cloudflare 에서 다시 빼면 Free zone 은 7일 뒤 자동 삭제됩니다. 등록하고 28일 안에 활성화하지 않아도 삭제됩니다.

조사 근거(2026-11-04): [API 한도](https://developers.cloudflare.com/api/limits) · [서비스별 약관(CDN)](https://www.cloudflare.com/service-specific-terms-application-services/) · [zone 상태 · 자동 삭제](https://developers.cloudflare.com/dns/zone-setups/reference/domain-status/)

## 대상 zone 과 레코드 (2026-11-04 `nslookup` 실측)

도메인 등록은 가비아에 그대로 두고 **네임서버만** Cloudflare 로 바꿉니다. 4개 zone 모두 MX · TXT · 와일드카드 레코드가 없습니다(메일 영향 없음).

| 순서 | zone | 집 공인 IP 를 가리키는 A 레코드 |
| --- | --- | --- |
| 1 | `8llow8llowme.com` | `@` `www` `jenkins` `console.jenkins` `grafana` `kafka-ui` `minio` `console.minio` `vault` `ai` |
| 2 | `mokoyuri.shop` | `@` `www` `admin` `admin-dev` `api` `api-dev` `dev` |
| 3 | `hondigagae.com` | `@` `www` `api` `api-dev` `dev` |
| 4 | `bosspickseoul.com` | `@` `www` `api` `api-dev` `dev` |

제외: `mokoyuri.com`(카페24 운영 중, 203.245.12.103), `sneezecast.com`(Route53), `jamjamnow.com`(NS 없음).

## 이전 절차 (zone 하나씩)

사용자가 할 일은 **(사용자)** 로 표시했습니다. 한 zone 이 Active 가 되고 접속을 확인한 뒤 다음 zone 으로 갑니다.

1. **(사용자)** Cloudflare 가입 → Add a domain → **Free** 플랜. 결제수단은 넣지 않습니다.
2. **(사용자)** 자동으로 가져온 레코드를 위 표와 대조합니다. 빠진 건 추가하고, **전부 회색 구름(DNS only)**, TTL 은 1분(60)으로 둡니다.
3. **(사용자)** 가비아 My가비아 → 도메인 관리 → 네임서버를 Cloudflare 가 준 2개로 바꿉니다. 가비아에서 DNSSEC 를 켜 둔 상태면 먼저 끕니다.
4. Active 확인 뒤 `nslookup <각 이름> 1.1.1.1` 이 현재 공인 IP 인지, 사이트가 열리는지 확인합니다.
5. **(사용자)** 첫 zone 이 Active 가 되면 API 토큰을 만듭니다: My Profile → API Tokens → Create Token → *Edit zone DNS* 템플릿, Zone Resources 는 **옮긴 zone 만**. 다음 zone 을 옮길 때 토큰의 Zone Resources 에 더합니다.
6. 토큰을 deploy 에 둡니다(값은 채팅 · 이슈 · 커밋에 쓰지 않습니다).

   ```bash
   cd ~/infra/ddns
   mkdir -p secrets && chmod 700 secrets
   (umask 077; printf '%s' '<token>' > secrets/cloudflare-api-token)
   ```

   같은 값을 Vault 에도 백업합니다(경로 제안: `kv/infra/ddns` 의 `CLOUDFLARE_API_TOKEN`). deploy 디스크가 날아가도 다시 만들 수 있게 하기 위함입니다.
7. `.env` 의 `DDNS_DOMAINS` 를 **Cloudflare 로 옮긴 zone 의 이름만** 남기고 `sh install-ddns.sh`. 다음 zone 을 옮기면 이름을 더하고 `docker compose --env-file .env -f docker-compose-ddns.yml up -d` 로 다시 띄웁니다.

## 확인

```bash
docker logs --tail 50 cloudflare-ddns
# 시작 직후 각 이름에 대해 "already up to date" 류 메시지가 나오면 정상입니다.
# 공인 IP 가 바뀌면 "Updated ..." 로그가 남습니다.
```

- 강제 시험: Cloudflare 대시보드에서 이름 하나의 A 레코드를 일부러 다른 IP 로 바꾸고 1분 안에 되돌아오는지 봅니다.
- 컨테이너 로그는 deploy 의 promtail 이 Loki 로 보냅니다. IP 변경 알림(Grafana)은 로그 문구를 실측한 뒤 붙입니다.

## IP 가 바뀐 뒤에도 손으로 할 일

DDNS 는 DNS 만 고칩니다. fail2ban `ignoreip` · 외부 API IP 허용 목록 · 작업 PC SSH 설정은 루트 README "공인 IP 가 바뀌면" 체크리스트(#56)를 따릅니다.

## 환경변수

| 변수 | 설명 | 기본값 |
| --- | --- | --- |
| `DDNS_IMAGE` | 이미지(버전 고정) | `favonia/cloudflare-ddns:1.17.1` |
| `DDNS_UID` / `DDNS_GID` | 실행 uid:gid — 토큰 파일을 읽을 수 있어야 함 | `1000` / `1003` (deploy) |
| `DDNS_DOMAINS` | 갱신할 이름(쉼표 구분, Cloudflare 로 옮긴 zone 만) | 없음(필수) |
| `DDNS_UPDATE_CRON` | 확인 주기 | `@every 1m` |
| `DDNS_TTL` | 새로 만드는 레코드 TTL(초) | `60` |
| `DDNS_MEM_LIMIT` / `DDNS_CPUS` | 자원 상한 | `64m` / `0.25` |

고정값(compose): `PROXIED=false`, `IP6_PROVIDER=none`(IPv6 미사용), `UPDATE_ON_START=true`, `DELETE_ON_STOP=false`(컨테이너를 내려도 레코드를 지우지 않음).
