# Nginx 운영 가이드

이 디렉터리는 인프라 프로젝트에서 사용하는 Nginx 리버스 프록시 구성을 관리합니다.

주요 역할은 다음과 같습니다.

- 도메인별 가상 호스트 라우팅
- HTTP -> HTTPS 리다이렉트
- Certbot HTTP-01 인증 경로 제공
- 백엔드 애플리케이션, Jenkins, MinIO 등으로 프록시 전달
- 로그 파일 생성 및 외부 보안/로그 수집 도구와의 연계

---

## 디렉터리 구조

```text
nginx/
├── .env.example                # 환경변수 예시
├── .gitignore                  # 런타임 파일 제외
├── conf.d/                    # 도메인별 서버 블록 설정
├── docker-compose-nginx.yml   # Nginx 컨테이너 실행 정의
├── entrypoint.sh              # 컨테이너 시작 시 실행되는 엔트리포인트
├── install-nginx.sh           # Nginx 실행 스크립트
├── nginx.conf                 # Nginx 전역 설정
├── nginx.Dockerfile           # Nginx 커스텀 이미지 빌드 파일
└── README.md                  # 이 문서
```

---

## 구성 개요

현재 Nginx는 다음 흐름으로 동작합니다.

1. 클라이언트 요청이 `80`, `443` 포트로 Nginx에 도착합니다.
2. `conf.d/*.conf` 의 도메인 설정에 따라 요청을 분기합니다.
3. 정적 리다이렉트는 Nginx가 직접 처리합니다.
4. 동적 요청은 내부 컨테이너 또는 사설망 백엔드 서버로 프록시합니다.
5. 로그는 `/var/log/nginx` 에 파일로 남기고, 일부는 컨테이너 stdout 으로도 노출합니다.

---

## 주요 파일 설명

### nginx.conf

Nginx 전역 설정 파일입니다.

주요 내용:

- worker 프로세스 수 자동 설정
- 공통 access log 포맷 정의
- `/var/log/nginx/access.log` 파일 기록
- gzip 압축 설정
- `conf.d/*.conf` 포함

### docker-compose-nginx.yml

Nginx 컨테이너 실행 정의 파일입니다.

주요 내용:

- `80`, `443` 포트 바인딩
- `nginx.conf`, `conf.d`, `logs` 디렉터리 마운트
- Certbot 인증서 디렉터리 공유
- Docker 로그 롤링 정책 설정

### nginx.Dockerfile

커스텀 Nginx 이미지를 빌드합니다.

주요 내용:

- `nginx:alpine` 기반
- 로그 파일 사전 생성
- 설정 파일 복사
- 커스텀 `entrypoint.sh` 실행

### entrypoint.sh

컨테이너 시작 시 실행되는 스크립트입니다.

주요 역할:

- Nginx 실행
- `access.log` 를 `tail -F` 로 stdout 에 연결
- 종료 시 Nginx/tail 프로세스 정리

이 구조는 다음 도구와 함께 운영하기 좋습니다.

- Docker 로그 드라이버
- Filebeat
- Fail2Ban
- logrotate

---

## 가상 호스트 정책

`conf.d` 아래 각 파일은 하나 이상의 도메인 서버 블록을 포함합니다.

현재 공통 패턴은 다음과 같습니다.

### 1. HTTP -> HTTPS 강제 전환

대부분의 도메인은 `listen 80` 서버 블록에서 HTTPS 주소로 리다이렉트합니다.

예시:

```nginx
location / {
    return 301 https://example.com$request_uri;
}
```

### 2. ACME 챌린지 경로 유지

Let's Encrypt 인증서 갱신을 위해 아래 경로를 예외 처리합니다.

```nginx
location /.well-known/acme-challenge/ {
    root /var/www/certbot;
}
```

### 3. 정규 도메인으로 통일

`www` 또는 non-`www` 중 하나를 기준 도메인으로 정하고, 나머지는 301 리다이렉트로 정리합니다.

### 4. 백엔드 프록시

동적 요청은 아래 대상 중 하나로 전달됩니다.

- Docker 네트워크 내부 컨테이너
- 같은 서버의 다른 서비스
- 사설 IP 기반 백엔드 서버

---

## 현재 설정 파일 설명

### conf.d/tripmarble.conf

- `tripmarble.com` 을 `www.tripmarble.com` 으로 정규화
- 메인 웹 요청을 `web-ssr:3000` 으로 프록시

### conf.d/api.tripmarble.conf

- `api.tripmarble.com` 처리
- `/auth-service/` 와 `/api-gateway/` 를 서로 다른 백엔드로 전달

### conf.d/jamjamnow.conf

- 정적 파일은 MinIO에서 제공
- `/api` 는 `jamjamnow-backend:8080` 으로 프록시
- `index.html` 캐시 비활성화

### conf.d/jenkins.conf

- Jenkins API/Webhook 도메인과 콘솔 도메인 분리
- WebSocket 연결 지원
- 장시간 응답을 고려한 timeout 설정 포함

### conf.d/minio.conf

- MinIO API와 MinIO Console 도메인 분리
- 브라우저 기반 접근을 위한 CORS 헤더 포함
- Console 접속 시 WebSocket 업그레이드 지원

### conf.d/kafka-ui.conf

- `kafka-ui.8llow8llowme.com` 을 ollama-01의 Kafka UI(`192.168.0.10:18080`)로 프록시
- 토픽 메시지 실시간 조회(SSE/WebSocket) 지원
- nginx basic auth를 두지 않습니다. 인증은 **Kafka UI 자체 로그인 폼**(`AUTH_TYPE=LOGIN_FORM`)이
  담당하며, 계정은 `kafka/.env` 의 `KAFKA_UI_AUTH_USERNAME` / `KAFKA_UI_AUTH_PASSWORD` 로 설정합니다.
  값이 비면 `install-kafka.sh` 가 기동을 막습니다.

Kafka UI는 호스트 포트(`18080`)로도 열려 있어 nginx basic auth로는 그 경로를 막을 수 없습니다.
애플리케이션 계층 인증이 두 경로를 모두 덮으므로 그쪽을 방어선으로 씁니다. 접근 범위까지 좁히려면
conf 안의 `allow 192.168.0.0/24; deny all;` 주석을 함께 풀면 됩니다.

---

## 실행 방법

실행 전 `.env`를 준비합니다.

```bash
cd nginx
cp .env.example .env
```

필수 값:

| 변수 | 설명 | 예시 |
| --- | --- | --- |
| `TZ` | 컨테이너 타임존 | `Asia/Seoul` |

### 스크립트 실행

```bash
cd nginx
sh install-nginx.sh
```

### 직접 실행

```bash
cd nginx
docker compose --env-file .env -f docker-compose-nginx.yml up -d --build
```

### 상태 확인

```bash
docker compose --env-file .env -f docker-compose-nginx.yml ps
docker logs -f nginx
```

### 설정 반영

설정 파일만 변경한 경우에는 컨테이너를 재시작하거나 reload 할 수 있습니다.

```bash
docker exec nginx nginx -t
docker exec nginx nginx -s reload
```

이미지 변경이 포함되면 재빌드가 필요합니다.

```bash
docker compose --env-file .env -f docker-compose-nginx.yml up -d --build
```

---

## 신규 SSL 도메인 추가 절차

인증서가 아직 없는 도메인은 HTTPS 설정을 바로 추가하면 Nginx가 인증서 파일을 찾지 못해 reload에 실패할 수 있습니다.

먼저 HTTP-only bootstrap 설정을 생성해 Let's Encrypt HTTP-01 challenge가 통과할 수 있게 합니다.

non-www 단일 도메인:

```bash
cd ~/infra/nginx
sh create-ssl-bootstrap-conf.sh grafana.8llow8llowme.com non-www grafana
docker exec nginx nginx -t
docker exec nginx nginx -s reload

cd ~/infra/certbot
./init-cert-non-www.sh grafana.8llow8llowme.com
```

www 포함 도메인:

```bash
cd ~/infra/nginx
sh create-ssl-bootstrap-conf.sh example.com with-www example
docker exec nginx nginx -t
docker exec nginx nginx -s reload

cd ~/infra/certbot
./init-cert-with-www.sh example.com
```

인증서 발급 후에는 `conf.d/*.bootstrap.conf`를 제거하거나 실제 HTTPS conf로 교체하고 Nginx를 reload합니다.

```bash
docker exec nginx nginx -t
docker exec nginx nginx -s reload
```

Grafana처럼 서비스별 HTTPS 템플릿이 있는 경우:

```bash
cp templates/services/grafana.ssl.conf.template conf.d/grafana.conf
docker exec nginx nginx -t
docker exec nginx nginx -s reload
```

---

## 로그 운영

로그는 두 방향으로 사용됩니다.

### 파일 로그

경로:

- `/var/log/nginx/access.log`
- `/var/log/nginx/error.log`

용도:

- 운영 점검
- Fail2Ban 분석
- logrotate 관리
- Filebeat 수집

### 컨테이너 로그

`entrypoint.sh` 에서 `access.log` 를 stdout 으로 전달하므로 `docker logs nginx` 로도 일부 접근 로그를 확인할 수 있습니다.

---

## 인증서 연동

Certbot 관련 마운트 경로는 다음과 같습니다.

- `../certbot/webroot:/var/www/certbot`
- `../certbot/letsencrypt:/etc/letsencrypt`

즉, Nginx는 Certbot이 발급한 인증서를 직접 참조하며, HTTP-01 챌린지 파일도 같은 경로를 공유합니다.

---

## 운영 시 주의사항

- `conf.d` 안의 도메인 설정은 인증서 경로와 `server_name` 이 정확히 일치해야 합니다.
- 사설 IP로 프록시하는 설정은 대상 서버 IP 변경 시 함께 수정해야 합니다.
- WebSocket 또는 SSE를 쓰는 서비스는 `proxy_http_version`, `Upgrade`, `Connection`, timeout 설정을 확인해야 합니다.
- `bosspickseoul` 관련 설정처럼 작업 중인 파일이 있을 수 있으므로, 운영 전 `git status` 로 로컬 변경사항을 먼저 확인하는 것이 좋습니다.

---

## 점검 명령어

### 설정 문법 테스트

```bash
docker exec nginx nginx -t
```

### 액세스 로그 확인

```bash
docker exec nginx tail -f /var/log/nginx/access.log
```

### 에러 로그 확인

```bash
docker exec nginx tail -f /var/log/nginx/error.log
```

### 컨테이너 로그 확인

```bash
docker logs -f nginx
```

---

## 개선 포인트 메모

현재 구성은 실무적으로 충분히 동작할 수 있지만, 장기적으로는 아래 개선을 고려할 수 있습니다.

- 공통 프록시 헤더를 `include` 스니펫으로 분리
- 공통 SSL 설정을 스니펫으로 정리
- 도메인별 네이밍 규칙 일관화
- 운영/개발 환경 분리
- 설정 검증 자동화(`nginx -t`)를 CI에 추가

---

## BossPickSeoul 도메인 맵

| 도메인 | 대상 | 호스트 | 설정 파일 |
| --- | --- | --- | --- |
| `https://www.bosspickseoul.com` | 운영 웹 (Next.js SSR) | backend-1 `192.168.0.13:9300` | `conf.d/bosspickseoul.conf` |
| `https://dev.bosspickseoul.com` | 개발 웹 (Next.js SSR) | main-server `192.168.0.11:6300` | `conf.d/dev.bosspickseoul.conf` |
| `https://api.bosspickseoul.com` | 운영 API 게이트웨이 | backend-1 `192.168.0.13:9000` | `conf.d/api.bosspickseoul.conf` |
| `https://api-dev.bosspickseoul.com` | 개발 API 게이트웨이 | main-server `192.168.0.11:6000` | `conf.d/api-dev.bosspickseoul.conf` |

FE/BE 모두 **컨테이너명이 아니라 사설 IP로 프록시**합니다. `8llow8llowme-net` 은 호스트별 브리지라 storage(`192.168.0.12`)에서 도는 nginx 는 다른 호스트의 컨테이너명을 해석하지 못합니다. 과거 `web-ssr:3000` 으로 프록시하던 시절에는 같은 호스트의 tripmarble 컨테이너가 BossPickSeoul 요청에 응답하는 사고가 있었으므로, 공유 컨테이너명으로는 되돌리지 않습니다.

`api` / `api-dev` 도메인은 tripmarble과 동일한 구조로, auth-service 단독 호출과 api-gateway 경유 호출을 분리하고, Swagger는 api-gateway가 auth 포함 서비스 문서를 집계해 제공합니다. 자세한 라우팅은 `conf.d/api.bosspickseoul.conf`, `conf.d/api-dev.bosspickseoul.conf`를 참고합니다.

### DNS 체크리스트

- `bosspickseoul.com` A/AAAA -> 공개 Nginx 호스트
- `www.bosspickseoul.com` A/AAAA 또는 CNAME -> 공개 Nginx 호스트
- `dev.bosspickseoul.com` A/AAAA 또는 CNAME -> 공개 Nginx 호스트
- `api.bosspickseoul.com` A/AAAA 또는 CNAME -> 공개 Nginx 호스트
- `api-dev.bosspickseoul.com` A/AAAA 또는 CNAME -> 공개 Nginx 호스트

### Certbot 체크리스트

- `bosspickseoul.com` 인증서는 `bosspickseoul.com`과 `www.bosspickseoul.com`을 포함합니다
- `dev.bosspickseoul.com`은 별도 인증서가 필요합니다
- `api.bosspickseoul.com`은 별도 인증서가 필요합니다
- `api-dev.bosspickseoul.com`은 별도 인증서가 필요합니다

`conf.d/dev.bosspickseoul.conf` 는 **HTTPS 블록이 주석 처리된 상태로 커밋**되어 있습니다. `ssl_certificate` 파일이 없으면 nginx 가 기동조차 못 하고, 이 nginx 는 전 도메인의 단일 인그레스라 다른 서비스까지 함께 내려갑니다. 인증서를 발급한 뒤 주석을 풀고 `nginx -t && nginx -s reload` 하십시오.

예시 명령어:

```bash
cd ~/infra/nginx
sh create-ssl-bootstrap-conf.sh api-dev.bosspickseoul.com non-www api-dev-bosspickseoul
docker exec nginx nginx -t
docker exec nginx nginx -s reload

cd ~/infra/certbot
./init-cert-non-www.sh api-dev.bosspickseoul.com
```

### 개발 access 로그

- 전용 로그 파일: `/var/log/nginx/bosspickseoul_dev_access.log`
- `docker exec nginx tail -f /var/log/nginx/bosspickseoul_dev_access.log`로 확인합니다
- 개발 API 서버도 전역 `/var/log/nginx/access.log`에 계속 기록합니다

---

## 혼디가개 도메인 맵

| 도메인 | 대상 | 호스트 | 설정 파일 |
| --- | --- | --- | --- |
| `https://www.hondigagae.com` | 운영 웹 (Next.js SSR) | backend-1 `192.168.0.13:5300` | `conf.d/hondigagae.conf` |
| `https://dev.hondigagae.com` | 개발 웹 (Next.js SSR) | main-server `192.168.0.11:7300` | `conf.d/dev.hondigagae.conf` |
| `https://api.hondigagae.com` | 운영 API 게이트웨이 | backend-1 `192.168.0.13:5000` | `conf.d/api.hondigagae.conf` |
| `https://api-dev.hondigagae.com` | 개발 API 게이트웨이 | main-server `192.168.0.11:7000` | `conf.d/api-dev.hondigagae.conf` |

auth-service 는 게이트웨이를 거치지 않고 직결한다 (prod `5081`, dev `7081`).
BossPickSeoul·tripmarble 과 동일한 구조로, Swagger 는 api-gateway 가 auth 포함 4개 서비스 문서를
집계해 제공한다. 자세한 라우팅은 각 conf 파일을 참고한다.

### 포트 대역이 BossPickSeoul 과 다른 이유

혼디가개는 dev `7XXX` / prod `5XXX` 를 쓴다. BossPickSeoul 이 dev `6XXX` / prod `9XXX` 를
이미 점유하고 있어, 같은 호스트(dev `.11` / prod `.13`)에 올리면 둘 다 auth 가 6081 을 원해
포트 바인딩이 실패하기 때문이다. (README §4 배치 원칙 5번)

FE/BE 모두 **컨테이너명이 아니라 사설 IP로 프록시**한다. `8llow8llowme-net` 은 호스트별
브리지라 storage(`192.168.0.12`)에서 도는 nginx 는 다른 호스트의 컨테이너명을 해석하지 못한다.

### ⚠️ 네 파일 모두 HTTPS 블록이 주석 처리된 상태로 커밋되어 있다

`ssl_certificate` 파일이 없으면 nginx 가 기동조차 못 하고, 이 nginx 는 전 도메인의 단일
인그레스라 다른 서비스까지 함께 내려간다. 인증서를 발급한 뒤 주석을 풀고
`nginx -t && nginx -s reload` 한다.

적용 순서:

```bash
# 1) conf 4개를 배치하고 HTTP 블록만 살린 채 reload
cd ~/infra && git pull
docker exec nginx nginx -t && docker exec nginx nginx -s reload

# 2) 인증서 발급 (apex 는 www 를 함께 담는다)
cd ~/infra/certbot
./init-cert-with-www.sh hondigagae.com
./init-cert-non-www.sh dev.hondigagae.com
./init-cert-non-www.sh api.hondigagae.com
./init-cert-non-www.sh api-dev.hondigagae.com

# 3) 각 conf 의 HTTPS 블록 주석 해제 후 다시 reload
docker exec nginx nginx -t && docker exec nginx nginx -s reload
```

각 conf 의 `listen 80` 블록이 HTTP-01 챌린지 경로(`/.well-known/acme-challenge/`)를 이미
열어 주므로 `create-ssl-bootstrap-conf.sh` 로 별도 bootstrap conf 를 만들 필요가 없다.

### DNS 체크리스트

- `hondigagae.com` A/AAAA -> 공개 Nginx 호스트
- `www.hondigagae.com` A/AAAA 또는 CNAME -> 공개 Nginx 호스트
- `dev.hondigagae.com` A/AAAA 또는 CNAME -> 공개 Nginx 호스트
- `api.hondigagae.com` A/AAAA 또는 CNAME -> 공개 Nginx 호스트
- `api-dev.hondigagae.com` A/AAAA 또는 CNAME -> 공개 Nginx 호스트

### Certbot 체크리스트

- `hondigagae.com` 인증서는 `hondigagae.com` 과 `www.hondigagae.com` 을 포함한다
- `dev.hondigagae.com` / `api.hondigagae.com` / `api-dev.hondigagae.com` 은 각각 별도 인증서가 필요하다

### 개발 access 로그

- API: `/var/log/nginx/hondigagae_api_dev_access.log`
- 웹: `/var/log/nginx/hondigagae_web_dev_access.log`
- 운영도 각각 `hondigagae_api_access.log`, `hondigagae_web_access.log` 에 따로 남는다
- 전역 `/var/log/nginx/access.log` 에도 계속 기록된다

---

## sneezecast 도메인 맵

| 도메인 | 대상 | 호스트 | 설정 파일 |
| --- | --- | --- | --- |
| `https://api-dev.sneezecast.com` | 개발 API 게이트웨이 | backend-1(dev 서버 2) `192.168.0.13:3000` | `conf.d/api-dev.sneezecast.conf` |

이번에는 `api-dev` 하나만 만든다. 나머지는 대상이 정해지면 추가한다.

| 도메인 | 상태 | 필요한 것 |
| --- | --- | --- |
| `dev.sneezecast.com` | 미작성 | 프론트(PWA) 호스트 결정. dev 포트는 `3300` 예정 |
| `api.sneezecast.com` | 미작성 | 백엔드 prod 미니PC IP. 게이트웨이 `4000` 예정 |
| `www.sneezecast.com` (+ apex) | 미작성 | 프론트 prod 호스트 결정. `4300` 예정, apex 는 `init-cert-with-www.sh` 로 www 와 함께 발급 |

### auth-service 직결 라우트를 두지 않는다

BossPickSeoul·혼디가개 conf 는 `/api/v1/auth`, `/api/v1/members`, `/auth-service/` 를 게이트웨이를
거치지 않고 auth 포트(`x081`)로 보낸다. sneezecast 는 **모든 REST 를 게이트웨이(`3000`) 하나로만**
보내고, auth(`3081`) · surveillance(`3082`) · batch(`3080`) · discovery(`3761`) 포트는 nginx 가 보지 않는다.

- 서비스 actuator(`health`, `info`, `prometheus`)가 인증 없이 열려 있다. sneezecast 는
  "서비스 포트를 외부에 노출하지 않는다" 를 배포 전제로 두고 있어(앱 레포 `backend/docs/modules.md`),
  직결 location 하나가 그 전제를 깬다.
- access token 블랙리스트 확인, 클라이언트가 보낸 회원 헤더 제거, 업스트림 타임아웃은 게이트웨이가
  맡는다. 직결하면 이 검사를 건너뛴다.
- 같은 이유로 혼디가개의 `/api-gateway/` prefix 직결도 두지 않는다. 그 location 은 게이트웨이의
  `/actuator/**` 까지 그대로 연다. `/api/` 밖의 경로는 전부 404 다.

Swagger 집계 라우트도 없다. 게이트웨이에 아직 집계가 없어서다 — 생기면 혼디가개 conf 의 `[A]` 블록을 옮긴다.

### ⚠️ HTTPS 블록이 주석 처리된 상태로 커밋되어 있다

혼디가개와 같다. `ssl_certificate` 파일이 없으면 `nginx -t` 가 실패하고, 이 nginx 는 전 도메인의 단일
인그레스라 다른 프로젝트 도메인까지 함께 내려간다. `listen 80` 블록이 HTTP-01 챌린지 경로를 이미 열어
주므로 `create-ssl-bootstrap-conf.sh` 로 bootstrap conf 를 만들 필요는 없다.

적용 순서:

```bash
# 0) DNS: api-dev.sneezecast.com A 레코드 -> 공개 Nginx 호스트. 전파 확인 후 진행한다
#    (전파 전에 발급하면 HTTP-01 검증이 실패하고, 실패가 쌓이면 Let's Encrypt rate limit 에 걸린다)
dig +short api-dev.sneezecast.com

# 1) conf 를 배치하고 HTTP 블록만 살린 채 reload
cd ~/infra && git pull
docker exec nginx nginx -t && docker exec nginx nginx -s reload

# 2) 인증서 발급
cd ~/infra/certbot
./init-cert-non-www.sh api-dev.sneezecast.com

# 3) conf 의 HTTPS 블록 주석 해제 후 다시 reload
docker exec nginx nginx -t && docker exec nginx nginx -s reload
```

3) 을 하기 전에는 `https://api-dev.sneezecast.com` 이 열리지 않는다(HTTP 는 HTTPS 로 301). 게이트웨이가
`.13` 에 아직 배포되지 않았다면 3) 뒤에도 502 가 나는 것이 정상이다.

### DNS 체크리스트

- `api-dev.sneezecast.com` A/AAAA 또는 CNAME -> 공개 Nginx 호스트

### Certbot 체크리스트

- `api-dev.sneezecast.com` 은 별도 인증서(`/etc/letsencrypt/live/api-dev.sneezecast.com/`)를 쓴다

### 개발 access 로그

- API: `/var/log/nginx/sneezecast_api_dev_access.log`
- 전역 `/var/log/nginx/access.log` 에도 계속 기록된다
