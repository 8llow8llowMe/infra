# Vault 운영 가이드

이 디렉터리는 미니PC `ai-host`에서 HashiCorp Vault를 Docker 컨테이너로 운영하기 위한 IaC 구성입니다.

Vault는 BossPickSeoul 배포 시크릿의 원본 저장소입니다. Jenkins controller는 Vault에서 서비스별 `.env` 계약을 읽고, `backend-1` deploy agent는 배포 실행 책임만 갖도록 구성합니다. 실제 secret 값은 Git에 커밋하지 않습니다.

## 컨테이너로 운영해도 되나?

현재 규모에서는 Docker Compose로 운영하는 것을 권장합니다.

- 미니PC에 Vault, Jenkins, 관제를 함께 올리는 구조와 잘 맞습니다.
- 파일 스토리지 단일 노드 운영이 단순하고 백업 경로가 명확합니다.
- Jenkins와 같은 Docker 네트워크를 공유할 수 있어 내부 연동이 쉽습니다.
- 나중에 고가용성이 필요해지면 Raft storage 또는 별도 Vault 노드로 분리할 수 있습니다.

주의할 점은 있습니다. 운영 Vault는 dev 모드로 띄우면 안 되고, `vault.hcl` 기반 server 모드로 실행해야 합니다. 외부 공개망에 직접 노출하지 말고 사설망 또는 TLS reverse proxy 뒤에 두는 편이 안전합니다.

## 파일 구조

```text
vault/
├── docker-compose-vault.yml
├── vault.hcl
├── docker-entrypoint-vault.sh
├── install-vault.sh
├── .env.example
├── policies/
│   ├── jenkins-bosspickseoul.hcl
│   └── backend-bosspickseoul.hcl
├── scripts/
│   ├── bootstrap-bosspickseoul.sh
│   ├── reset-kv-bosspickseoul.sh
│   └── rotate-approle-secret.sh
└── README.md
```

실행 후 생성되는 로컬 데이터:

- `data/`: Vault file storage 데이터
- `logs/`: Vault 로그 디렉터리

## 환경변수

```bash
cd vault
cp .env.example .env
```

미니PC 사설 IP 또는 내부 DNS 이름으로 주소를 바꿉니다.

```env
VAULT_ADDR=http://<ai-host-private-ip>:8200
VAULT_API_ADDR=http://<ai-host-private-ip>:8200
```

필수 값:

| 변수             | 설명                         | 예시                    |
| ---------------- | ---------------------------- | ----------------------- |
| `VAULT_IMAGE`    | Vault 컨테이너 이미지        | `hashicorp/vault:1.18`  |
| `VAULT_PORT`     | Vault API/UI 노출 포트       | `8200`                  |
| `TZ`             | 컨테이너 타임존              | `Asia/Seoul`            |
| `VAULT_ADDR`     | CLI와 client가 접근할 주소   | `http://10.0.0.10:8200` |
| `VAULT_API_ADDR` | Vault가 외부에 알릴 API 주소 | `http://10.0.0.10:8200` |

`.env`, `data/`, `logs/`는 `.gitignore`에 포함되어 있어야 합니다.

## 실행

스크립트 실행:

```bash
cd vault
sh install-vault.sh
```

직접 실행:

```bash
cd vault
docker compose --env-file .env -f docker-compose-vault.yml up -d
```

상태 확인:

```bash
docker compose --env-file .env -f docker-compose-vault.yml ps
docker logs -f vault
docker exec vault vault status
```

중지:

```bash
docker compose --env-file .env -f docker-compose-vault.yml down
```

Compose 문법 확인:

```bash
docker compose --env-file .env -f docker-compose-vault.yml config
```

## 초기화와 Unseal

Vault는 최초 1회 초기화가 필요합니다. 초기화를 하면 unseal key 5개와 initial root token 1개가 발급됩니다.

```bash
docker exec -it vault vault operator init
```

출력되는 unseal key와 initial root token은 오프라인 비밀 저장소에 보관합니다. Git, 메신저, 일반 노트에 남기지 않습니다.

초기화 후에는 Vault가 sealed 상태입니다. 5개 unseal key 중 3개를 입력해 잠금을 해제합니다.

```bash
docker exec -it vault vault operator unseal
docker exec -it vault vault operator unseal
docker exec -it vault vault operator unseal
```

상태 확인:

```bash
docker exec vault vault status
```

다음처럼 `Sealed`가 `false`이면 사용할 수 있습니다.

```text
Initialized     true
Sealed          false
```

root token으로 로그인합니다.

```bash
docker exec -it vault vault login
```

컨테이너 재시작, 재생성, 서버 재부팅 후에는 다시 unseal이 필요합니다. 자동 unseal은 이번 구성 범위에 포함하지 않았습니다.

주의:

- `vault operator init`은 최초 1회만 실행합니다.
- 이미 초기화된 Vault에서 다시 init을 실행하면 실패합니다.
- `data/`를 삭제하면 기존 Vault 데이터와 키가 사라지므로 운영 중에는 삭제하지 않습니다.

## BossPickSeoul Secret Path

KV v2 mount는 `kv`를 사용합니다.

권장 path:

```text
kv/bosspickseoul/backend/{env}/{group}/{service}
```

여기서 앞의 `kv`는 secret engine mount 이름입니다. 실제 secret path에는 `kv/`를 한 번 더 넣지 않습니다.

예시:

```text
kv/bosspickseoul/backend/prod/core/api
kv/bosspickseoul/backend/prod/batch/scheduler
kv/bosspickseoul/backend/dev/core/api
```

secret 저장 예시:

```bash
docker exec -it vault vault kv put kv/bosspickseoul/backend/prod/core/api \
  SPRING_PROFILES_ACTIVE=prod \
  DB_HOST=raspberrypi \
  DB_PORT=3306 \
  DB_USERNAME=bosspick \
  DB_PASSWORD=change-me
```

조회:

```bash
docker exec -it vault vault kv get kv/bosspickseoul/backend/prod/core/api
```

Jenkins 경로는 다음처럼 단순하게 유지합니다.

```text
kv/bosspickseoul/backend/dev/env
kv/bosspickseoul/backend/prod/env
kv/bosspickseoul/frontend/dev/env
kv/bosspickseoul/frontend/prod/env
```

파이프라인은 `{root}/{env}/env` 규칙으로 경로를 조립합니다. root 기본값은 backend 잡이 `kv/bosspickseoul/backend`, frontend 잡이 `kv/bosspickseoul/frontend` 입니다. 잡 파라미터 `VAULT_SECRET_ROOT` / `VAULT_SECRET_PATH` 로 덮어쓸 수 있지만 평소에는 건드리지 않습니다.

frontend 경로는 `policies/jenkins-bosspickseoul.hcl` 에 backend 와 함께 들어 있습니다. **Jenkins credential 을 따로 만들 필요는 없습니다** — 두 파이프라인이 같은 AppRole 을 씁니다. 자세한 내용과 정책 반영 절차는 `Bootstrap` 절을 참고합니다.

### 프론트 secret 에 넣을 key

주입 시점이 둘로 나뉩니다. `NEXT_PUBLIC_*` 는 **빌드 시점에 코드로 인라인**되므로 컨테이너 환경변수로 넣어도 무시됩니다. 그래서 dev 와 prod 를 각각 빌드합니다.

key 목록의 기준은 애플리케이션 레포의 `frontend/.env.example` 이고, 배포 절차는 `frontend/docs/runbook/deployment.md` 를 따릅니다.

#### 필수 — 없으면 파이프라인이 실패합니다

| key | 시점 | dev 값 | prod 값 |
| --- | --- | --- | --- |
| `NEXT_PUBLIC_SITE_URL` | 빌드 | `https://dev.bosspickseoul.com` | `https://www.bosspickseoul.com` |
| `NEXT_PUBLIC_WS_URL` | 빌드 | `wss://api-dev.bosspickseoul.com/ws` | `wss://api.bosspickseoul.com/ws` |
| `NEXT_PUBLIC_KAKAO_JAVASCRIPT_KEY` | 빌드 | 카카오 콘솔의 JavaScript 키 (dev/prod 동일) | 〃 |
| `AUTH_SESSION_SECRET` | 런타임 | `openssl rand -base64 48` | dev 와 **다른** 값 |
| `BACKEND_API_URL` | 런타임 | `https://api-dev.bosspickseoul.com` | `https://api.bosspickseoul.com` |
| `TIME_ZONE` | 런타임 | `Asia/Seoul` | `Asia/Seoul` |
| `FRONTEND_WEB_PORT` | 런타임 | `6300` | `9300` |
| `FRONTEND_WEB_MEM_LIMIT` | 런타임 | `512m` | `768m` |

포트와 메모리 상한에 **환경 접미사가 없습니다.** 환경별로 `.env.runtime` 이 따로 만들어지므로 각 secret 에 값 하나만 넣으면 됩니다. compose 파일 하나에 dev/prod 서비스가 같이 정의되어 있지만 두 서비스가 같은 변수명을 참조하므로, 배포하지 않는 쪽 값을 따로 넣을 필요가 없습니다.

프론트 compose 에는 **환경변수 기본값(`:-`)을 두지 않습니다.** 값이 비면 조용히 다른 포트로 뜨는 대신 파이프라인의 `Runtime env key check` 에서 배포가 중단됩니다.

#### 선택 — 비워두거나 아예 넣지 않아도 됩니다

| key | 시점 | 비었을 때 |
| --- | --- | --- |
| `NEXT_PUBLIC_FIREBASE_API_KEY` | 빌드 | FCM 웹 푸시(채팅 알림)가 자동 비활성화됩니다. 앱 나머지는 정상 동작합니다. |
| `NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID` | 빌드 | 〃 |
| `NEXT_PUBLIC_FIREBASE_APP_ID` | 빌드 | 〃 |
| `NEXT_PUBLIC_FIREBASE_VAPID_KEY` | 빌드 | 〃 |
| `NEXT_PUBLIC_FIREBASE_MEASUREMENT_ID` | 빌드 | Analytics 용. 없어도 푸시는 동작합니다. |

Firebase 4종은 **넷이 모두 있어야** 푸시가 켜집니다. 하나라도 비면 코드가 스스로 비활성화하므로, 푸시를 쓰기로 정하기 전에는 Vault 에 넣지 않아도 됩니다.

#### 넣지 않는 key

| key | 이유 |
| --- | --- |
| `NEXT_PUBLIC_API_URL` | 브라우저 REST 호출은 same-origin `/api/bff` 로 나가고 백엔드 주소는 서버 쪽 `BACKEND_API_URL` 만 압니다. 번들에 넣을 이유가 없습니다. |
| `NEXT_PUBLIC_KAKAOMAP_API_KEY` | 카카오는 지도 SDK 와 공유 SDK 가 **같은 JavaScript 키** 하나를 씁니다. `NEXT_PUBLIC_KAKAO_JAVASCRIPT_KEY` 로 통합했습니다. |
| `BOSSPICK_API_DOCS_URL` | 로컬에서 OpenAPI 문서를 내려받는 스크립트 전용입니다. |

#### 주의

- **`AUTH_SESSION_SECRET` 은 환경당 한 번만 만들고 고정합니다.** 배포마다 새로 만들면 안 됩니다. 이 값은 세션 쿠키의 A256GCM 암호화 키(SHA-256 해시)라, 바뀌는 순간 기존 쿠키를 복호화할 수 없어 **로그인한 사용자가 전원 로그아웃**됩니다. 유출됐을 때만 의도적으로 교체하고, 그때도 전원 로그아웃을 감수하는 작업으로 다룹니다. dev 와 prod 는 서로 다른 값을 씁니다.
- **`NEXT_PUBLIC_*` 에는 비밀값을 넣지 않습니다.** 브라우저 번들에 문자열로 그대로 박힙니다. 위 목록의 카카오·Firebase 키는 원래 클라이언트 공개용이라 괜찮습니다.
- **`BACKEND_API_URL` 은 사설 IP 가 아니라 공개 도메인**을 씁니다. dev 프론트와 dev 게이트웨이가 같은 호스트에 있어 `http://192.168.0.11:6000` 으로 질러도 될 것 같지만, auth API(`/api/v1/auth`, `/api/v1/members`)는 게이트웨이를 거치지 않고 auth-service 로 직결되며 그 분기를 nginx 가 합니다.

### kv 경로 초기화

경로가 `kv/kv/...`처럼 꼬였고 Vault를 다시 구성하는 시점이라면 kv mount를 삭제 후 다시 만드는 편이 가장 깔끔합니다.

주의: 아래 작업은 `kv` secret engine 아래의 모든 secret을 삭제합니다.

```bash
docker exec -it \
  -e CONFIRM_RESET_KV=bosspickseoul \
  vault sh /vault/scripts/reset-kv-bosspickseoul.sh
```

그 다음 bootstrap으로 policy와 AppRole을 다시 반영합니다.

```bash
docker exec -it vault sh /vault/scripts/bootstrap-bosspickseoul.sh
```

Web UI 사용자를 같이 만들거나 갱신하려면 다음처럼 실행합니다.

```bash
docker exec -it \
  -e VAULT_UI_USERNAME='username' \
  -e VAULT_UI_PASSWORD='password' \
  vault sh /vault/scripts/bootstrap-bosspickseoul.sh
```

정리 후 secret은 반드시 mount `kv` 아래의 `bosspickseoul/...` 경로에 저장합니다.

```bash
docker exec -i vault vault kv put -mount="kv" bosspickseoul/backend/dev/env env_file=@/dev/stdin < .env
```

조회:

```bash
docker exec -it vault vault kv get -mount="kv" bosspickseoul/backend/dev/env
```

## Bootstrap

정책 파일:

- `policies/jenkins-bosspickseoul.hcl`: Jenkins가 배포용 secret을 읽는 권한 (**backend + frontend 공용**)
- `policies/backend-bosspickseoul.hcl`: backend-1 deploy/runtime 용 읽기 권한
- `policies/ui-bosspickseoul.hcl`: Web UI 사용자가 `kv/bosspickseoul/*` 시크릿을 관리하는 권한

### AppRole 은 파이프라인별로 나누지 않습니다

backend 파이프라인과 frontend 파이프라인이 **같은 AppRole(`jenkins-bosspickseoul`) 하나**를 씁니다. 그래서 `jenkins-frontend-...` 같은 role 이나 Jenkins credential 을 따로 만들 필요가 없습니다.

| AppRole | 쓰는 곳 | Jenkins credential | 읽는 경로 |
| --- | --- | --- | --- |
| `jenkins-bosspickseoul` | backend 잡, **frontend 잡** | `bosspickseoul-vault-role-id`, `bosspickseoul-vault-secret-id` | `kv/bosspickseoul/backend/*`, `kv/bosspickseoul/frontend/*` |
| `backend-bosspickseoul` | backend-1 deploy/runtime | (deploy agent secret) | `kv/bosspickseoul/backend/*` |

두 파이프라인의 `VAULT_ROLE_ID_CREDENTIAL_ID` / `VAULT_SECRET_ID_CREDENTIAL_ID` 기본값이 같기 때문에, 새 애플리케이션 그룹이 생기면 **credential 을 추가하는 게 아니라 `jenkins-bosspickseoul.hcl` 에 경로 블록을 추가**하고 bootstrap 을 다시 돌립니다. 실제로 frontend 도 그렇게 붙였습니다.

role 을 파이프라인별로 쪼개면 권한은 더 좁아지지만 credential 쌍과 회전 절차가 그만큼 늘어납니다. 지금 규모에서는 통합 쪽이 맞습니다.

실행 시점:

1. Vault 컨테이너 실행
2. `vault operator init`
3. `vault operator unseal`
4. `vault login`
5. 아래 bootstrap 스크립트 실행
6. AppRole `role_id`, `secret_id`를 Jenkins credential 또는 backend-1 deploy agent secret으로 등록

초기 bootstrap은 Vault 서버를 처음 구성할 때 1회 실행합니다. policy나 AppRole 설정을 바꾼 경우에는 다시 실행해 갱신할 수 있습니다.

```bash
docker exec -it vault sh /vault/scripts/bootstrap-bosspickseoul.sh
```

이 스크립트는 다음 작업을 수행합니다.

- `kv` KV v2 secret engine 활성화
- `approle` auth method 활성화
- `userpass` auth method 활성화
- Jenkins/backend policy 등록
- Web UI policy 등록
- `jenkins-bosspickseoul`, `backend-bosspickseoul` AppRole 생성
- `VAULT_UI_USERNAME`, `VAULT_UI_PASSWORD`가 전달된 경우 Web UI 사용자 생성 또는 갱신

성공하면 다음 메시지가 출력됩니다.

```text
Success! Enabled the kv-v2 secrets engine at: kv/
Success! Enabled approle auth method at: approle/
Success! Enabled userpass auth method at: userpass/
Success! Uploaded policy: jenkins-bosspickseoul
Success! Uploaded policy: backend-bosspickseoul
Success! Uploaded policy: ui-bosspickseoul
```

이미 한 번 실행한 뒤 다시 실행하면 `kv`, `approle`, `userpass` 활성화 메시지는 생략될 수 있습니다. policy와 AppRole은 다시 등록되어 갱신됩니다.

### 정책(`.hcl`)만 고쳤을 때 — bootstrap 재실행이 전부입니다

`policies/` 는 컨테이너에 bind mount(`./policies:/vault/policies:ro`) 되어 있어, 호스트에서 `.hcl` 을 고치면 컨테이너 안에서 **이미 보입니다.** 이미지 재빌드도 컨테이너 재시작도 필요 없습니다.

다만 **Vault 는 그 파일을 읽어서 정책을 적용하지 않습니다.** 정책은 Vault 내부 스토리지에 저장되므로 `vault policy write` 로 밀어넣어야 반영됩니다. 그게 bootstrap 이 하는 일입니다.

```bash
cd ~/infra && git pull                         # .hcl 파일이 서버에 있어야 합니다
docker exec -it vault vault status             # Sealed: false 확인
docker exec -it -e VAULT_TOKEN='<root-token>' vault sh /vault/scripts/bootstrap-bosspickseoul.sh
docker exec -it vault vault policy read jenkins-bosspickseoul   # 반영 확인
```

> ⚠️ **`install-vault.sh` 를 쓰지 마십시오.** 그건 컨테이너를 띄우는 스크립트입니다. `vault.hcl` 이 `storage "file"` 에 auto-unseal 설정이 없어서, 컨테이너가 재생성되면 **Vault 가 sealed 상태로 떠서 수동 unseal 이 필요**합니다. 정책 변경에는 컨테이너를 건드릴 이유가 없습니다.

재실행해도 안전한 이유:

| bootstrap 동작 | 재실행 시 |
| --- | --- |
| `secrets enable kv` / `auth enable approle,userpass` | 이미 활성화되어 있으면 실패를 무시하고 넘어감 |
| `vault policy write` × 3 | 덮어쓰기. 내용이 그대로면 실질 변화 없음 |
| `vault write auth/approle/role/...` | **`role_id` 와 기존 `secret_id` 는 그대로 유지됩니다.** role 설정(TTL 등)만 갱신되고 자격증명은 별도 엔드포인트로 관리됩니다 |
| Web UI 사용자 생성 | `VAULT_UI_USERNAME` / `VAULT_UI_PASSWORD` 를 넘기지 않으면 건너뜀 |

따라서 **Jenkins credential 을 재발급할 필요가 없고**, 진행 중인 배포에도 영향이 없습니다.

`require_admin_token` 검사가 있어 **Web UI userpass 계정 토큰으로는 실행되지 않습니다.** root token 또는 policy 갱신 권한이 있는 token 이 필요합니다.

## Web UI username/password 로그인

Vault Web UI에서 username/password로 로그인하려면 `userpass` auth method와 UI 사용자가 필요합니다. Vault를 다시 초기화할 필요는 없고, unseal과 root token 로그인 이후 bootstrap을 다시 실행하면 됩니다.

비밀번호는 Git에 커밋하지 않고 실행 시점에만 환경변수로 전달합니다.

bootstrap은 policy와 AppRole도 함께 갱신하므로 root token 또는 관리자 권한 token으로 실행해야 합니다. Web UI userpass 계정으로 로그인한 token은 보통 권한이 부족합니다.

컨테이너 안에 root token으로 먼저 로그인:

```bash
docker exec -it vault vault login
```

또는 실행 시점에 token 전달:

```bash
docker exec -it \
  -e VAULT_TOKEN='<root-token>' \
  -e VAULT_UI_USERNAME='username' \
  -e VAULT_UI_PASSWORD='password' \
  vault sh /vault/scripts/bootstrap-bosspickseoul.sh
```

root token 로그인 후 실행:

```bash
docker exec -it \
  -e VAULT_UI_USERNAME='username' \
  -e VAULT_UI_PASSWORD='password' \
  vault sh /vault/scripts/bootstrap-bosspickseoul.sh
```

Web UI 로그인 화면에서는 Method를 `Username` 또는 `userpass`로 선택하고 위 username/password를 입력합니다.

비밀번호 변경:

```bash
docker exec -it vault vault write auth/userpass/users/admin/password password='<새-비밀번호>'
```

사용자 삭제:

```bash
docker exec -it vault vault delete auth/userpass/users/admin
```

## AppRole 발급과 회전

Bootstrap 이후 Jenkins와 backend-1 deploy agent가 사용할 AppRole 값을 발급합니다. `role_id`는 role을 식별하는 값이고, `secret_id`는 비밀번호처럼 동작하는 값입니다. `secret_id` 원문은 Git, README, 이슈, 메신저에 남기지 않습니다.

이 repo에서 IaC로 관리하는 범위:

| 대상 | 관리 방식 |
| --- | --- |
| Vault policy | `policies/*.hcl` |
| AppRole role 설정 | `scripts/bootstrap-bosspickseoul.sh` |
| `role_id`, `secret_id` 발급 절차 | `scripts/rotate-approle-secret.sh` |
| `secret_id` 원문 | Jenkins Credential 또는 별도 비밀 저장소 |

### 1. bootstrap으로 role 설정 반영

policy나 AppRole TTL, policy 매핑을 바꾼 경우 먼저 bootstrap을 다시 실행합니다. 이 작업은 root token 또는 관리자 권한 token이 필요합니다.

```bash
docker exec -it vault vault login
docker exec -it vault sh /vault/scripts/bootstrap-bosspickseoul.sh
```

현재 bootstrap은 아래 AppRole을 생성하거나 갱신합니다.

| role | policy | token TTL | max TTL | secret_id TTL | secret_id 사용 횟수 |
| --- | --- | --- | --- | --- | --- |
| `jenkins-bosspickseoul` | `jenkins-bosspickseoul` | `1h` | `4h` | `만료 없음 (0)` | 무제한 |
| `backend-bosspickseoul` | `backend-bosspickseoul` | `30m` | `2h` | `720h` | 무제한 |

### 2. Jenkins용 role_id/secret_id 발급

Jenkins controller가 Vault에 로그인할 때 사용할 값을 발급합니다.

```bash
docker exec -it vault sh /vault/scripts/rotate-approle-secret.sh jenkins-bosspickseoul
```

옵션 없이 실행해도 기본값은 Jenkins용 role입니다.

```bash
docker exec -it vault sh /vault/scripts/rotate-approle-secret.sh
```

출력 예시:

```text
role_name:
jenkins-bosspickseoul

role_id:
...

new_secret_id:
...
```

Jenkins에는 아래처럼 등록합니다.

| Jenkins Credential ID | 종류 | 값 |
| --- | --- | --- |
| `bosspickseoul-vault-role-id` | Secret text | 출력된 `role_id` |
| `bosspickseoul-vault-secret-id` | Secret text | 출력된 `new_secret_id` |

### 3. backend deploy/runtime용 값 발급

backend deploy agent 또는 runtime 쪽에서 직접 Vault 로그인이 필요한 경우에만 발급합니다. Jenkins가 Vault를 읽고 deploy agent에 `.env.runtime`만 전달하는 구조라면 backend AppRole은 사용하지 않아도 됩니다.

```bash
docker exec -it vault sh /vault/scripts/rotate-approle-secret.sh backend-bosspickseoul
```

발급한 값은 backend-1 deploy agent의 비밀 저장소에 넣고, Git에는 저장하지 않습니다.

### 4. secret_id 회전 절차

Jenkins용 `secret_id`는 기본 IaC 기준으로 만료 없이 운영합니다. 따라서 30일 같은 주기 만료로 빌드가 깨지지는 않아야 합니다. 다만 값이 노출됐거나 보안 점검 차원에서 직접 회전하려는 경우에는 새 값을 발급하고 Jenkins Credential만 갱신합니다.

1. 새 secret 발급:

```bash
docker exec -it vault sh /vault/scripts/rotate-approle-secret.sh jenkins-bosspickseoul
```

2. Jenkins에서 `bosspickseoul-vault-secret-id` 값을 새 `new_secret_id`로 교체합니다.
3. `bosspickseoul-vault-role-id`는 role을 재생성하지 않았다면 보통 그대로 둡니다. 그래도 스크립트 출력값과 맞춰 갱신해도 문제 없습니다.
4. Jenkins pipeline 또는 아래 AppRole 로그인 테스트를 실행합니다.
5. 테스트가 성공하면 이전 `secret_id`는 운영상 폐기된 값으로 간주합니다.

기존 `secret_id`를 즉시 무효화하려면 Vault의 `secret_id_accessor`가 필요합니다. 평소에는 새 값 발급 후 Jenkins credential을 갱신하는 방식으로 회전하고, 즉시 폐기가 필요한 사고 대응 상황에서는 관리자 token으로 accessor를 확인해 폐기합니다.

### 5. 수동 발급 명령

스크립트를 쓰지 않고 직접 발급할 수도 있습니다.

Jenkins credential에 등록할 값:

```bash
docker exec -it vault vault read auth/approle/role/jenkins-bosspickseoul/role-id
docker exec -it vault vault write -f auth/approle/role/jenkins-bosspickseoul/secret-id
```

backend-1 deploy agent용 값:

```bash
docker exec -it vault vault read auth/approle/role/backend-bosspickseoul/role-id
docker exec -it vault vault write -f auth/approle/role/backend-bosspickseoul/secret-id
```

발급한 값은 다음처럼 관리합니다.

| 값 | 저장 위치 | 용도 |
| --- | --- | --- |
| Jenkins `role_id` | Jenkins Credential `bosspickseoul-vault-role-id` | Vault 로그인용 |
| Jenkins `secret_id` | Jenkins Credential `bosspickseoul-vault-secret-id` | Vault 로그인용 |
| backend `role_id` | backend-1 deploy agent secret | 필요 시 Vault 로그인용 |
| backend `secret_id` | backend-1 deploy agent secret | 필요 시 Vault 로그인용 |

`secret_id`는 비밀번호처럼 취급합니다. Git에 커밋하지 않습니다.

## AppRole 로그인 테스트

Jenkins용 AppRole이 실제로 Vault에 로그인할 수 있는지 테스트할 수 있습니다.

먼저 `role_id`, `secret_id`를 변수로 준비합니다.

```bash
JENKINS_ROLE_ID='<발급받은-role-id>'
JENKINS_SECRET_ID='<발급받은-secret-id>'
```

로그인 테스트:

```bash
docker exec -e JENKINS_ROLE_ID="$JENKINS_ROLE_ID" -e JENKINS_SECRET_ID="$JENKINS_SECRET_ID" vault \
  vault write auth/approle/login role_id="$JENKINS_ROLE_ID" secret_id="$JENKINS_SECRET_ID"
```

응답에 `token`이 나오면 AppRole 로그인은 정상입니다.

## Secret 저장 테스트

Bootstrap 후에는 `kv` 경로에 secret을 저장할 수 있습니다.

예시:

```bash
docker exec -it vault vault kv put kv/bosspickseoul/backend/dev/core/api \
  SPRING_PROFILES_ACTIVE=dev \
  DB_HOST=raspberrypi \
  DB_PORT=3306 \
  DB_USERNAME=bosspick \
  DB_PASSWORD=change-me
```

조회:

```bash
docker exec -it vault vault kv get kv/bosspickseoul/backend/dev/core/api
```

Jenkins pipeline에서는 이 경로를 환경별로 바꿔 읽습니다.

```text
kv/bosspickseoul/backend/{env}/{group}/{service}
```

## AppRole 읽기 권한 테스트

발급된 AppRole token으로 secret 읽기 권한까지 확인할 수 있습니다.

```bash
JENKINS_VAULT_TOKEN='<approle-login-token>'

docker exec -e VAULT_TOKEN="$JENKINS_VAULT_TOKEN" vault \
  vault kv get kv/bosspickseoul/backend/dev/core/api
```

secret이 조회되면 Jenkins용 policy와 AppRole 권한이 정상입니다.

## Jenkins 배포 흐름

권장 흐름:

1. Jenkins controller가 AppRole로 Vault 로그인
2. Jenkins가 `kv/bosspickseoul/backend/{env}/{group}/{service}`를 읽음
3. Jenkins가 `.env.runtime`을 생성하거나 deploy agent 작업 공간에 전달
4. `backend-1` deploy agent가 `$HOME/deploy/bosspickseoul/backend/...`에 파일 배치
5. `docker compose --env-file .env.runtime up -d --build` 실행
6. 배포 후 `.env.runtime`은 필요 최소 기간만 유지하고 권한을 제한

원칙:

- Vault 원본은 미니PC에 둡니다.
- backend-1에는 secret 원본을 오래 저장하지 않습니다.
- Jenkins는 서비스별 전체 `.env` 계약을 Vault에서 읽습니다.
- deploy agent는 배포만 하고 secret 관리 책임을 최소화합니다.

## 백업과 복구

백업 대상:

- `data/`
- `.env`
- 별도로 보관 중인 unseal key와 root token

백업 예시:

```bash
cd vault
tar czf vault-backup-$(date +%Y%m%d).tar.gz data .env
```

복구 예시:

```bash
cd vault
tar xzf vault-backup-YYYYMMDD.tar.gz
docker compose -f docker-compose-vault.yml up -d
docker exec -it vault vault operator unseal
```

## 운영 주의사항

- root token은 초기 설정과 긴급 복구에만 사용합니다.
- **root token을 채팅·이슈·PR·로그에 붙여넣지 않습니다.** 노출됐다면 즉시 폐기하고 새로 발급합니다. 폐기하지 않으면 그 토큰으로 Vault 전체를 읽고 쓸 수 있습니다.
  ```bash
  docker exec -it -e VAULT_TOKEN='<노출된-root-token>' vault vault token revoke -self
  docker exec -it vault vault operator generate-root -init   # unseal key 로 새 root token 발급
  ```
- Jenkins와 backend-1은 root token 대신 AppRole을 사용합니다.
- 정책(`.hcl`)을 바꿨을 때는 컨테이너를 건드리지 말고 bootstrap만 다시 실행합니다. (`Bootstrap` 절 참고)
- 운영 중 `vault.hcl`을 바꾸면 컨테이너 재시작이 필요하고, 재시작하면 **sealed 상태가 되어 수동 unseal이 필요**합니다.
- 서비스 또는 환경이 분리되면 policy도 분리합니다. 단, Jenkins 파이프라인이 늘어나는 경우는 AppRole을 새로 만들지 말고 `jenkins-bosspickseoul.hcl`에 경로 블록을 추가합니다.
- 공개망 노출이 필요하면 Nginx TLS proxy, IP allowlist, 방화벽 정책을 먼저 적용합니다.

## 문제 해결

상태 확인:

```bash
docker exec vault vault status
```

로그 확인:

```bash
docker logs -f vault
```

권한과 마운트 확인:

```bash
docker exec vault ls -la /vault/file /vault/logs /vault/policies /vault/scripts
```

`Initialized`가 `false`면 `vault operator init`을 먼저 실행합니다. `Sealed`가 `true`면 unseal key로 해제합니다.

---

## 혼디가개(hondigagae) Secret Path

혼디가개는 **같은 Vault 인스턴스와 같은 `kv` mount 를 공유**하고, policy / AppRole / 경로만 분리합니다.
Vault 를 새로 띄우거나 다시 초기화할 필요가 없습니다.

```text
kv/hondigagae/backend/dev/env
kv/hondigagae/backend/prod/env
kv/hondigagae/frontend/dev/env
kv/hondigagae/frontend/prod/env
```

파이프라인은 BossPickSeoul 과 같은 `{root}/{env}/env` 규칙으로 경로를 조립합니다.
root 기본값은 backend 잡이 `kv/hondigagae/backend`, frontend 잡이 `kv/hondigagae/frontend` 입니다.

**환경당 secret 하나에 전 서비스의 env 키를 모아 둡니다.** 서비스별로 쪼개지 않습니다.
`JWT_ACCESS_KEY` 처럼 여러 서비스가 같은 값을 써야 하는 키가 있어, 쪼개면 그 불일치가 곧 장애가 됩니다.

key 목록의 단일 기준은 애플리케이션 레포의 `backend/.env.example` 과 `frontend/.env.example` 입니다.

### 저장 방법 — 키별로 넣는다

파이프라인은 secret 의 `data.data` 를 **키별 평면 맵**으로 읽어 `.env.runtime` 을 만듭니다.
줄바꿈이 든 값은 거부합니다. 그래서 `.env` 파일 전체를 `env_file` 한 키에 넣는 방식
(`vault kv put ... env_file=@.env`)은 **저장은 되지만 배포 단계에서 실패**합니다.
BossPickSeoul 과 같은 방식으로 키 하나에 값 하나씩 넣습니다.

가장 쉬운 방법은 Web UI 입니다. `kv/hondigagae/backend/dev/env` 를 만들 때 **JSON 토글**을 켜고
`{"KEY": "value", ...}` 를 통째로 붙여 넣습니다. BossPickSeoul secret 을 열어 JSON 으로 복사한 뒤
키 이름은 그대로 두고 값만 바꾸는 것이 제일 빠릅니다 (아래 키 표 참고).

CLI 로 넣을 때는 `.env` 를 KEY=VALUE 인자로 풀어서 넘깁니다.

```bash
# 애플리케이션 레포에서 .env.example 을 .env 로 복사해 <...> 를 채운 뒤 (주석·빈 줄 제외)
docker exec -i vault vault kv put -mount="kv" hondigagae/backend/dev/env \
  $(grep -Ev '^\s*(#|$)' backend/.env | xargs)
docker exec -it vault vault kv get -mount="kv" hondigagae/backend/dev/env
```

`kv put` 은 secret 전체를 **덮어씁니다.** 키 하나만 바꾸려면 `vault kv patch` 를 씁니다.

### 프론트 secret 에 넣을 key — `kv/hondigagae/frontend/{env}/env`

**키 이름은 BossPickSeoul 프론트 secret 과 같습니다.** 두 프로젝트를 나란히 관리하므로 갈라 두지
않습니다. 차이는 `NEXT_PUBLIC_WS_URL` 이 없다는 것 하나입니다 (WebSocket 미사용 — 들어 있어도 무해).

| key | 시점 | dev 값 | prod 값 |
| --- | --- | --- | --- |
| `NEXT_PUBLIC_SITE_URL` | 빌드 | `https://dev.hondigagae.com` | `https://www.hondigagae.com` |
| `NEXT_PUBLIC_KAKAO_JAVASCRIPT_KEY` | 빌드 | 혼디가개 카카오 앱의 JavaScript 키 | 〃 (같은 앱, 도메인만 추가 등록) |
| `AUTH_SESSION_SECRET` | 빌드 + 런타임 | `openssl rand -base64 48` | dev 와 **다른** 값 |
| `BACKEND_API_URL` | 빌드 + 런타임 | `https://api-dev.hondigagae.com` | `https://api.hondigagae.com` |
| `TIME_ZONE` | 런타임 | `Asia/Seoul` | `Asia/Seoul` |
| `FRONTEND_WEB_PORT` | 런타임 | `7300` | `5300` |
| `FRONTEND_WEB_MEM_LIMIT` | 런타임 | `512m` | `768m` |

- `AUTH_SESSION_SECRET` 과 `BACKEND_API_URL` 은 `NEXT_PUBLIC_` 이 아닌데도 **빌드에도 필요**합니다.
  `src/lib/env.server.ts` 가 모듈 로드 시점에 zod 로 fail-fast 하기 때문입니다.
- 카카오 앱은 **BossPickSeoul 앱을 공유하지 않습니다.** 도메인(`dev.hondigagae.com`, `www.hondigagae.com`)이
  다르므로 혼디가개용 앱을 만들고 그 JavaScript 키 / REST API 키를 씁니다.
- `AUTH_SESSION_SECRET` 은 환경당 한 번만 만들고 고정합니다. 바뀌면 전원 로그아웃됩니다.

### 백엔드 secret 에 넣을 key — `kv/hondigagae/backend/{env}/env`

전체 목록(137개)의 단일 기준은 애플리케이션 레포 `backend/.env.example` 이고, 상수 성격의 키
(포트표, `*_APP_NAME`, 임계값, TTL, 공공데이터 base URL)는 그 파일의 값을 그대로 넣습니다.
사람이 **채우거나 환경마다 다르게 넣어야 하는 키**만 아래에 모았습니다.

#### 발급·생성해야 하는 비밀값

| key | 어디서 | 비고 |
| --- | --- | --- |
| `JASYPT_ENCRYPTOR_KEY` | `openssl rand -base64 32` | 비면 빌드 단계에서 중단 |
| `DB_PASSWORD` | MySQL `hondigagae` 계정 생성 시 정한 값 | `DB_USERNAME=hondigagae` |
| `REDIS_PASSWORD` | main-server `redis-node1` requirepass | **BossPickSeoul dev 와 같은 값** (같은 Redis) |
| `JWT_ACCESS_KEY` / `JWT_REFRESH_KEY` | `openssl rand -base64 64 \| tr -d '\n'` | BossPickSeoul 과 **다른 값**. 같은 Redis 를 쓰므로 키가 같으면 토큰이 서로 통과한다 |
| `OAUTH_KAKAO_CLIENT_ID` / `_SECRET` | 혼디가개 카카오 앱 (REST API 키 / Client Secret) | 프론트 secret 의 JavaScript 키와 같은 앱 |
| `OAUTH_NAVER_CLIENT_ID` / `_SECRET` | 네이버 개발자센터 | 아직 안 쓰면 빈 값 |
| `MAIL_USERNAME` / `MAIL_PASSWORD` | Gmail 계정 / 앱 비밀번호 | BossPickSeoul 과 공용 가능 |
| `MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY` | storage MinIO | BossPickSeoul 과 같은 MinIO. 버킷 `hondigagae` 는 따로 만든다 |
| `TOUR_API_SERVICE_KEY` / `KMA_API_SERVICE_KEY` | data.go.kr 디코딩(원문) 키 | 한 키로 둘 다 가능. 기상특보는 별도 활용신청 |
| `VWORLD_API_KEY` | vworld.kr | 비면 음식점이 좌표 없이 적재 |
| `AI_LLM_API_KEY` | — | Ollama 는 키가 없다. 빈 값 |

#### 환경(dev / prod)마다 값이 다른 키

| key | dev | prod |
| --- | --- | --- |
| `SPRING_PROFILES_ACTIVE` | `dev` | `prod` (dev 로 두면 운영 스키마가 배포마다 자동 변경된다) |
| `SERVICE_DISCOVERY_HOSTNAME` | `hondigagae-service-discovery-dev` | `hondigagae-service-discovery-prod` |
| `*_APP_NAME` 7개 | `{service}-dev` | `{service}-prod` |
| `AUTH_DB_URL` / `TOUR_DB_URL` / `PLAN_DB_URL` / `BATCH_DB_URL` | main-server MySQL, `hondigagae_{auth,tour,plan}_dev` (batch 는 tour) | 운영 MySQL, `hondigagae_{...}_prod` |
| `REDIS_KEY_PREFIX` | `hondigagae:dev` | `hondigagae:prod` |
| `REDIS_MODE` / `REDIS_HOST` | `standalone` / main-server Redis (BossPickSeoul dev 와 동일) | 운영 Redis 구성에 맞춤 |
| `OAUTH_KAKAO_REDIRECT_URI` | `https://dev.hondigagae.com/oauth/kakao/callback` | `https://www.hondigagae.com/oauth/kakao/callback` |
| `OAUTH_NAVER_REDIRECT_URI` | `https://dev.hondigagae.com/oauth/naver/callback` | `https://www.hondigagae.com/oauth/naver/callback` |
| `BATCH_DATA_DIR` | `/home/<main-server 계정>/deploy/hondigagae/backend/data` | backend-1 의 호스트 경로 |
| `JWT_*_KEY`, `JASYPT_ENCRYPTOR_KEY`, `DB_PASSWORD` | dev 값 | dev 와 **다른** 값 |

`REDIS_MASTER_NAME` / `REDIS_SENTINEL_NODES` 는 standalone 이면 빈 값으로 둡니다. sentinel 로 바꿀 때만 채웁니다.

#### 공통 인프라 값 (BossPickSeoul dev secret 과 같다)

`REDIS_HOST`, `REDIS_PORT`, `MINIO_ENDPOINT`, `MINIO_PUBLIC_URL`, `MAIL_HOST`, `MAIL_PORT`,
`AI_LLM_BASE_URL`, `AI_LLM_PROVIDER`, `AI_LLM_MODEL` 은 같은 인프라를 가리키므로 BossPickSeoul dev secret 의
값을 그대로 복사합니다. `MINIO_BUCKET` 만 `hondigagae` 입니다.

### 포트 키에 주의

compose 파일 하나에 dev/prod 서비스가 같이 정의되어 있고 `docker compose config` 가 양쪽을
모두 해석합니다. 그래서 **dev secret 에도 `_PORT_PROD` 값을, prod secret 에도 `_PORT_DEV` 값을**
넣습니다. 두 secret 에 같은 포트표를 넣어 두면 됩니다.

프론트는 반대로 `FRONTEND_WEB_PORT` 하나만 씁니다(환경 접미사 없음). 환경별 `.env.runtime` 이
따로 만들어지므로 각 secret 에 값 하나만 넣으면 됩니다.

## 혼디가개 Bootstrap

정책 파일:

- `policies/jenkins-hondigagae.hcl`: Jenkins 배포용 읽기 권한 (**backend + frontend 공용**)
- `policies/backend-hondigagae.hcl`: 배포 호스트 deploy/runtime 용 읽기 권한
- `policies/ui-hondigagae.hcl`: Web UI 사용자가 `kv/hondigagae/*` 를 관리하는 권한

실행:

```bash
cd ~/infra && git pull                         # .hcl 파일이 서버에 있어야 합니다
docker exec -it vault vault status             # Sealed: false 확인
docker exec -it -e VAULT_TOKEN='<root-token>' vault sh /vault/scripts/bootstrap-hondigagae.sh
docker exec -it vault vault policy read jenkins-hondigagae   # 반영 확인
```

BossPickSeoul bootstrap 과 마찬가지로 `kv` mount 와 `approle`/`userpass` auth 는 이미
활성화되어 있으면 그냥 넘어갑니다. 재실행해도 안전하고, 기존 `role_id`/`secret_id` 는 유지됩니다.

> ⚠️ `install-vault.sh` 를 쓰지 마십시오. 컨테이너를 재생성하면 auto-unseal 이 없어
> **Vault 가 sealed 상태로 떠서 수동 unseal 이 필요**해집니다. 정책 변경에 컨테이너를 건드릴 이유가 없습니다.

### AppRole

| AppRole | 쓰는 곳 | Jenkins credential | 읽는 경로 |
| --- | --- | --- | --- |
| `jenkins-hondigagae` | backend 잡 7개, frontend 잡 | `hondigagae-vault-role-id`, `hondigagae-vault-secret-id` | `kv/hondigagae/backend/*`, `kv/hondigagae/frontend/*` |
| `backend-hondigagae` | 배포 호스트 deploy/runtime | (deploy agent secret) | `kv/hondigagae/backend/*` |

TTL 은 BossPickSeoul 과 같습니다 (jenkins: token 1h/4h, secret_id 만료 없음 /
backend: token 30m/2h, secret_id 720h).

발급:

```bash
docker exec -it vault sh /vault/scripts/rotate-approle-secret.sh jenkins-hondigagae
```

출력된 `role_id` / `new_secret_id` 를 Jenkins Secret text credential
`hondigagae-vault-role-id` / `hondigagae-vault-secret-id` 에 넣습니다.
`rotate-approle-secret.sh` 는 BossPickSeoul 과 공용 스크립트라 role 이름만 인자로 넘기면 됩니다.

### Web UI 계정

이미 BossPickSeoul UI 계정이 있다면 **새 계정을 만들지 말고 정책만 덧붙이는 편**이 낫습니다.

```bash
docker exec -it vault vault write auth/userpass/users/<username>/policies \
  policies="ui-bosspickseoul,ui-hondigagae"
```

새로 만들려면 bootstrap 실행 시 환경변수를 넘깁니다.

```bash
docker exec -it \
  -e VAULT_UI_USERNAME='username' \
  -e VAULT_UI_PASSWORD='password' \
  vault sh /vault/scripts/bootstrap-hondigagae.sh
```

### kv 경로 초기화

⚠️ **`reset-kv-bosspickseoul.sh` 를 혼디가개 정리에 쓰지 마십시오.**
그 스크립트는 `kv` mount 를 통째로 지우므로 BossPickSeoul 시크릿까지 함께 날아갑니다.

혼디가개 경로만 지우려면 전용 스크립트를 씁니다.

```bash
docker exec -it -e CONFIRM_RESET_KV=hondigagae vault sh /vault/scripts/reset-kv-hondigagae.sh
```

## sneezecast Secret Path

sneezecast 도 **같은 Vault 인스턴스와 같은 `kv` mount 를 공유**하고, policy / AppRole / 경로만 분리합니다.
Vault 를 새로 띄우거나 다시 초기화할 필요가 없습니다.

```text
kv/sneezecast/backend/{env}/env                    # 공통 — 둘 이상의 서비스가 같은 값을 써야 하는 키
kv/sneezecast/backend/{env}/api-gateway
kv/sneezecast/backend/{env}/auth-service
kv/sneezecast/backend/{env}/surveillance-service   # REPORTER_KEY_PEPPER 는 여기에만
kv/sneezecast/backend/{env}/batch-service
kv/sneezecast/frontend/{env}/env                   # 프론트가 생기면
```

`{env}` 는 `dev` / `prod` 입니다. service-discovery 는 공통 secret 만 읽으므로 서비스 경로가 없습니다.
서비스 경로 이름은 파이프라인 설정의 `serviceName`(모듈 디렉터리 이름)과 같게 둡니다.

### 혼디가개와 다른 점 — 공통 + 서비스별 두 층

혼디가개는 환경당 secret 하나(`{env}/env`)에 전 서비스의 키를 모읍니다. sneezecast 는 그 `{env}/env` 를
**공통 secret** 으로 그대로 쓰고, 한 서비스만 쓰는 키는 서비스 경로로 뺍니다.

- **공통 키는 한 곳에만 둡니다.** `JWT_ACCESS_KEY` 는 게이트웨이 · auth · surveillance 가 같은 항목을 읽습니다.
  서비스 경로에 복사본을 두지 않습니다 — 길이는 맞고 값만 다른 키가 들어가면 기동 검사는 통과하고 모든
  토큰이 401 이 됩니다. `REDIS_*`, `SERVICE_DISCOVERY_*`, 게이트웨이가 라우팅에 쓰는 `*_SERVICE_APP_NAME` 도
  같은 이유로 공통입니다. 혼디가개가 secret 을 하나로 모은 이유와 같습니다.
- **서비스 전용 비밀은 그 서비스 경로에 둡니다.** 개인정보 경계 때문입니다. `REPORTER_KEY_PEPPER` 와 auth DB
  계정이 한 `.env.runtime` 에 같이 있으면, 그 파일 하나로 회원(`memberId`)과 가명 보고(`reporter_key`)를
  이을 수 있습니다. 앱 레포 `backend/docs/architecture-guide.md` §6 은 pepper 를 "surveillance 경로에만, auth 는
  모른다" 로 정해 두었습니다. DB 계정 세 개(auth · surveillance · batch)를 나눈 것도 같은 경계입니다.
- **같은 키를 두 경로에 넣지 않습니다.** 어느 값이 이기는지에 기대지 않습니다.

#### 파이프라인 — 앱 레포에 구현됨 (sneezecast#10)

앱 레포 `Jenkinsfile.backend-common.groovy` 가 잡마다 `{root}/{env}/env` 와 `{root}/{env}/{serviceName}` 을 읽어
합친 뒤 `.env.runtime` 을 만듭니다. 상세는 앱 레포 `backend/docs/deploy-guide.md` 입니다.

- 서비스 경로는 잡의 `serviceName` 으로만 조립합니다(경로를 바꾸는 빌드 파라미터 없음). service-discovery 는 공통만 읽습니다.
- 같은 키가 양쪽에 있으면 **실패**시킵니다 (덮어쓰지 않음).
- 서비스 전용 키(`REPORTER_KEY_PEPPER` · `SURVEILLANCE_DB_*` · `AUTH_DB_*` · `BATCH_DB_*`)가 공통이나 남의 서비스
  경로에 있으면 **실패**시킵니다 — pepper 를 공통에 잘못 넣는 실수까지 막습니다.
- 서비스별 필수 키(아래 표의 "필수")가 비면 배포 전에 실패합니다. `JASYPT_ENCRYPTOR_KEY` 는 요구하지 않습니다.
- `SPRING_PROFILES_ACTIVE` 가 배포 환경(dev / prod)과 다르면 실패합니다.

#### 정책은 pepper 를 auth 쪽에서 막지 않는다

`jenkins-sneezecast` · `backend-sneezecast` 정책은 혼디가개와 같이 `kv/data/sneezecast/backend/*` 전체를 읽습니다.
서비스별로 나뉘지 않으므로 **Vault 만으로는 auth 잡이 pepper 를 읽는 것을 막지 못합니다.** 실제로 떼어 놓는
것은 두 단계입니다.

1. 파이프라인: 잡마다 공통 + 자기 서비스 경로만 읽는다 → auth 배포 디렉터리의 `.env.runtime` 에 pepper 가 없다.
2. compose: auth compose 는 `REPORTER_KEY_PEPPER` 를 컨테이너에 넘기지 않는다.

Vault 단에서도 막으려면 surveillance 잡 전용 AppRole(정책: `.../+/surveillance-service` 만 read)을 따로 두고
`jenkins-sneezecast` 에 그 경로 `deny` 블록을 더해야 합니다. Jenkins credential 도 잡 단위로 범위를 좁혀야
의미가 있습니다. 지금은 하지 않았습니다 — 운영자 수가 늘거나 감사 요구가 생기면 검토합니다.

### 저장 방법 — 키별로 넣는다

혼디가개와 같습니다. 파이프라인은 secret 의 `data.data` 를 **키별 평면 맵**으로 읽고 줄바꿈이 든 값을
거부합니다. `env_file=@.env` 한 키 저장은 배포 단계에서 실패합니다.

sneezecast 파이프라인은 **`$` 가 든 값과 따옴표(`"` · `'`)로 감싼 값도 거부**합니다. compose 의 env-file 은
따옴표 없는 값에 `$VAR` 치환을 해서, 예를 들어 pepper 가 조용히 다른 값으로 바뀌면 전 보고가 재키잉됩니다.
무작위 값은 아래 명령(base64)으로 만들면 `$` 가 나오지 않습니다. 팀 Redis · DB 비밀번호에 `$` 가 있으면 바꿔야 합니다.

- Web UI: secret 을 만들 때 **JSON 토글**을 켜고 `{"KEY": "value", ...}` 를 붙여 넣습니다. 비밀값은 셸 이력에
  남지 않도록 이 방법을 권합니다.
- CLI: `kv put` 은 secret 전체를 **덮어씁니다.** 키 하나만 바꾸려면 `kv patch` 를 씁니다.

```bash
docker exec -it vault vault kv put -mount="kv" sneezecast/backend/dev/env \
  SPRING_PROFILES_ACTIVE=dev REDIS_KEY_PREFIX=sneezecast:dev ...
docker exec -it vault vault kv patch -mount="kv" sneezecast/backend/dev/auth-service AUTH_DB_PASSWORD=...
docker exec -it vault vault kv get -mount="kv" sneezecast/backend/dev/env
```

생성해야 하는 무작위 값 (환경마다 따로 만들고, BossPickSeoul · 혼디가개 값과도 다르게 둡니다):

| key | 생성 | 조건 |
| --- | --- | --- |
| `JWT_ACCESS_KEY` | `openssl rand -base64 64 \| tr -d '\n'` (88자) | UTF-8 64바이트 이상, 공백 금지. 미달이면 기동 실패 |
| `JWT_REFRESH_KEY` | 같은 명령으로 **따로** 생성 | 위와 같음. access 키와 다른 값 |
| `REPORTER_KEY_PEPPER` | `openssl rand -base64 48 \| tr -d '\n'` (64자) | 32자 이상. 미달이면 기동 실패. **교체 금지** (아래) |

### 키 표

기준은 앱 레포 각 모듈 `src/main/resources/application*.yml` 의 `${...}` 자리표시자입니다
(develop `942482a`, 2026-10-01). **필수**는 기본값이 없는 키로, 없으면 기동하지 못합니다. **기본값**이 있는 키는
넣지 않아도 되고, 표의 dev 값을 비워 둔 것은 기본값을 그대로 쓴다는 뜻입니다.

#### 공통 — `kv/sneezecast/backend/{env}/env`

| key | 쓰는 서비스 | 필수 / 기본값 | dev 값 | 비고 |
| --- | --- | --- | --- | --- |
| `SPRING_PROFILES_ACTIVE` | 5종 | 기본값 `dev` | `dev` | prod 에는 **반드시** `prod`. 빠지면 dev 프로필(`ddl-auto: update`)로 뜬다 |
| `SERVICE_DISCOVERY_HOSTNAME` | gateway · auth · surveillance · batch | 필수 | `192.168.0.13` | 사설 IP (배치 원칙 4). prod 는 미니PC IP(미정). 파이프라인이 환경별 기대값과 대조 |
| `SERVICE_DISCOVERY_PORT` | 5종 | 필수 | `3761` (prod `4761`) | discovery 의 `server.port` = 호스트 포트 = 클라이언트 접속 포트. 모든 잡이 기대값과 대조 |
| `JWT_ACCESS_KEY` | gateway · auth · surveillance | 필수 | 생성 (위 표) | 세 서비스가 이 항목 하나를 읽는다 |
| `REDIS_MASTER_NAME` | gateway · auth | 필수 | `master-redis` | `redis/sentinel.conf` 의 `sentinel monitor` 이름 |
| `REDIS_SENTINEL_NODES` | gateway · auth | 필수 | `192.168.0.11:26379,192.168.0.13:26379,192.168.0.12:26379` | sentinel 1~3. 적재 전 `sentinel get-master-addr-by-name master-redis` 로 확인 |
| `REDIS_PASSWORD` | gateway · auth | 필수 | 팀 Redis requirepass | BossPickSeoul · 혼디가개 secret 과 같은 값 (같은 Redis) |
| `REDIS_KEY_PREFIX` | gateway · auth | 기본값 `sneezecast` | `sneezecast:dev` | prod 는 `sneezecast:prod`. 두 서비스가 같은 값이어야 한다(블랙리스트 키) |
| `REDIS_COMMAND_TIMEOUT` | gateway · auth | 기본값 `1s` | | |
| `AUTH_SERVICE_APP_NAME` | gateway (라우트 `lb://`) | 필수 | `auth-service` | auth 의 `SPRING_APPLICATION_NAME` 과 같아야 한다 |
| `SURVEILLANCE_SERVICE_APP_NAME` | gateway (라우트 `lb://`) | 필수 | `surveillance-service` | surveillance 의 `SPRING_APPLICATION_NAME` 과 같아야 한다 |

`SPRING_APPLICATION_NAME`(5종, 기본값은 각 서비스 이름)은 서비스마다 값이 달라 secret 에 한 키로 둘 수
없습니다. 넣지 않고 기본값을 쓰거나, compose 가 `*_SERVICE_APP_NAME` 을 컨테이너별로 넘깁니다(혼디가개 방식).

#### api-gateway — `kv/sneezecast/backend/{env}/api-gateway`

| key | 필수 / 기본값 | 비고 |
| --- | --- | --- |
| `API_GATEWAY_PORT` | 필수 | `3000`(prod `4000`). **컨테이너 내부 포트 = 호스트 포트** — 파이프라인이 잡의 `hostPorts` 와 대조 |
| `GATEWAY_CONNECT_TIMEOUT_MS` | 기본값 `2000` | |
| `GATEWAY_RESPONSE_TIMEOUT` | 기본값 `10s` | |
| `JWT_BLACKLIST_FAIL_OPEN` | 기본값 `false` | 넣지 않는다. `true` 면 Redis 장애 때 폐기 토큰이 통과한다 |

#### auth-service — `kv/sneezecast/backend/{env}/auth-service`

| key | 필수 / 기본값 | 비고 |
| --- | --- | --- |
| `AUTH_SERVICE_PORT` | 필수 | `3081`(prod `4081`). 내부 포트 = 호스트 포트. 호스트에는 `127.0.0.1` 로만 publish (LAN 비노출) |
| `AUTH_DB_URL` | 필수 | dev: `jdbc:mysql://192.168.0.11:3306/sneezecast_auth?...` (URL 옵션은 혼디가개 secret 과 같게) |
| `AUTH_DB_USERNAME` / `AUTH_DB_PASSWORD` | 필수 | `sneezecast_auth` 스키마 전용 계정 |
| `JWT_REFRESH_KEY` | 필수 | 생성 (위 표). auth 만 쓰므로 공통이 아니다 |
| `JWT_ACCESS_EXPIRATION` | 기본값 `PT15M` | 15분을 넘기면 기동 실패 |
| `JWT_REFRESH_EXPIRATION` | 기본값 `P14D` | |
| `MINIO_ENDPOINT` / `MINIO_PUBLIC_URL` | 필수 | storage MinIO(`.12`). 혼디가개 secret 과 같은 값 |
| `MINIO_BUCKET` | 필수 | `sneezecast` (버킷은 따로 만든다) |
| `MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY` | 필수 | |
| `MINIO_MAX_FILE_BYTES` | 기본값 `5242880` | |
| `MULTIPART_MAX_REQUEST_SIZE` | 기본값 `6MB` | nginx `client_max_body_size 6M` 과 짝. 바꾸면 conf 도 함께 |
| `MAIL_USERNAME` / `MAIL_PASSWORD` | 필수 | 인증 코드 메일을 보내는 SMTP 계정. Gmail 이면 앱 비밀번호. `$` · 따옴표가 든 비밀번호는 파이프라인이 거부한다 (sneezecast#56) |
| `MAIL_HOST` / `MAIL_PORT` | 기본값 `smtp.gmail.com` / `587` | STARTTLS |
| `MAIL_FROM_NAME` / `MAIL_FROM_ADDRESS` | 기본값 `우리동네체온계` / 빈 값 | 발신 주소가 비면 SMTP 계정에서 유도한다 |
| `LEGAL_TERMS_VERSION` · `LEGAL_PRIVACY_VERSION` · `LEGAL_SENSITIVE_HEALTH_INFO_VERSION` | 기본값 `2026-10-01` | 동의 문서 버전. 문서를 개정하면 올린다 — 이전 버전 동의자는 다음 로그인 때 재동의. 프론트 legal 상수와 같은 값 |
| `SNOWFLAKE_DATACENTER_ID` / `SNOWFLAKE_WORKER_ID` | 기본값 `0` / `0` | 인스턴스를 늘리면 인스턴스마다 다른 `SNOWFLAKE_WORKER_ID`(0~31) |
| `AUTH_EMAIL_SEND_*` (8개) | 모두 기본값 있음 | 인증 메일 발송 · 검증 한도(IP 상한 · 쿨다운 · 코드 수명 등). 목록과 기본값은 앱 레포 `backend/docs/deploy-guide.md` |
| `AUTH_LOGIN_MAX_FAILURE_COUNT` / `AUTH_LOGIN_LOCK_DURATION` | 기본값 `5` / `PT10M` | 이메일당 로그인 실패 허용 횟수와 잠금 시간. 잠금 시간을 바꾸면 프론트 잠금 문구("10분 뒤")도 함께 (sneezecast#57) |
| `AUTH_LOGIN_IP_MAX_FAILURE_COUNT` / `AUTH_LOGIN_IP_WINDOW` | 기본값 `30` / `PT1H` | IP당 로그인 실패 상한과 창 |
| `AUTH_SESSION_MAX_DEVICES` / `AUTH_SESSION_ROTATION_GRACE` | 기본값 `5` / `PT10S` | 회원당 로그인 기기 상한, 여러 탭 동시 재발급을 경합으로 봐 주는 시간 |

#### surveillance-service — `kv/sneezecast/backend/{env}/surveillance-service`

| key | 필수 / 기본값 | 비고 |
| --- | --- | --- |
| `SURVEILLANCE_SERVICE_PORT` | 필수 | `3082`(prod `4082`). 내부 포트 = 호스트 포트. 호스트에는 `127.0.0.1` 로만 publish |
| `SURVEILLANCE_DB_URL` | 필수 | dev: `jdbc:mysql://192.168.0.11:3306/sneezecast_surveillance?...` |
| `SURVEILLANCE_DB_USERNAME` / `SURVEILLANCE_DB_PASSWORD` | 필수 | auth 와 **다른** 계정 |
| `REPORTER_KEY_PEPPER` | 필수 | 생성 (위 표). **이 경로에만** 둔다 |

#### batch-service — `kv/sneezecast/backend/{env}/batch-service`

| key | 필수 / 기본값 | 비고 |
| --- | --- | --- |
| `BATCH_SERVICE_PORT` | 필수 | `3080`(prod `4080`). 내부 포트 = 호스트 포트. 호스트에는 `127.0.0.1` 로만 publish |
| `BATCH_DB_URL` | 필수 | `sneezecast_surveillance` 스키마 (적재 대상 + `BATCH_*` 메타 테이블) |
| `BATCH_DB_USERNAME` / `BATCH_DB_PASSWORD` | 필수 | 적재 전용 계정. surveillance-service 계정과 다르다 |
| `BATCH_SCHEDULE_ENABLED` | 기본값 dev `true` / prod `false` | prod 는 첫 적재를 dev 에서 관찰한 뒤 켠다 |

외부 API 키(SGIS · 공공데이터포털)는 아직 yml 에 자리표시자가 없습니다. 생기는 이슈에서 batch-service
경로와 이 표에 함께 추가합니다.

### REPORTER_KEY_PEPPER — 교체 금지

- `reporter_key = HMAC-SHA256(pepper, memberId)` 입니다. **교체 = 전 보고 재키잉**입니다. 바꾸면 기존 보고가
  모두 다른 사람의 것처럼 갈라지고, 집계의 "같은 사람 같은 주 한 번" 이 깨집니다.
- 잃으면 복구할 수 없습니다. 탈퇴 · 동의 철회 때의 보고 파기는 `memberId` 로 `reporter_key` 를 다시 계산해
  찾으므로, pepper 가 없으면 파기 의무를 지킬 수 없습니다. 처음 만들 때 Vault 밖에 오프라인 사본을 한 부 둡니다.
- **32자 이상 무작위**로 만들고(위 표의 `openssl` 명령), dev 와 prod 는 다른 값을 씁니다.
- 공통 경로 · auth-service 경로에 두지 않습니다.
- 기동 로그에는 SHA-256 앞 8자 지문만 남습니다. 값이 바뀌지 않았는지는 배포 전후 지문으로 확인합니다.

## sneezecast Bootstrap

정책 파일:

- `policies/jenkins-sneezecast.hcl`: Jenkins 배포용 읽기 권한 (**backend + frontend 공용**, frontend 는 경로만 예약)
- `policies/backend-sneezecast.hcl`: 배포 호스트 deploy/runtime 용 읽기 권한
- `policies/ui-sneezecast.hcl`: Web UI 사용자가 `kv/sneezecast/*` 를 관리하는 권한

실행:

```bash
cd ~/infra && git pull                         # .hcl 파일이 서버에 있어야 합니다
docker exec -it vault vault status             # Sealed: false 확인
docker exec -it -e VAULT_TOKEN='<root-token>' vault sh /vault/scripts/bootstrap-sneezecast.sh
docker exec -it vault vault policy read jenkins-sneezecast   # 반영 확인
```

혼디가개 bootstrap 과 동작이 같습니다. `kv` mount 와 `approle`/`userpass` auth 는 이미 켜져 있으면 넘어가고,
재실행해도 기존 `role_id`/`secret_id` 는 유지됩니다. **secret 값이나 키 자리는 만들지 않습니다** — `kv put` 은
전체 덮어쓰기라 bootstrap 재실행이 실제 값을 지우게 됩니다. 값은 위 `저장 방법` 대로 넣습니다.

> ⚠️ `install-vault.sh` 를 쓰지 마십시오. 컨테이너를 재생성하면 Vault 가 sealed 상태로 떠서 수동 unseal 이
> 필요해집니다. 정책 변경에 컨테이너를 건드릴 이유가 없습니다.

### AppRole

| AppRole | 쓰는 곳 | Jenkins credential | 읽는 경로 |
| --- | --- | --- | --- |
| `jenkins-sneezecast` | backend 잡 5개 (frontend 잡 예정) | `sneezecast-vault-role-id`, `sneezecast-vault-secret-id` | `kv/sneezecast/backend/*`, `kv/sneezecast/frontend/*` |
| `backend-sneezecast` | 배포 호스트 deploy/runtime | (deploy agent secret) | `kv/sneezecast/backend/*` |

- TTL 은 혼디가개와 같습니다 (jenkins: token 1h/4h, secret_id 만료 없음 / backend: token 30m/2h, secret_id 720h).
- 배포 lock 은 `sneezecast-backend-deploy`, dev deploy agent 는 `backend-dev2-agent`(라벨 `deploy-backend-dev2`,
  backend-1 `192.168.0.13`)입니다.
- 두 role 모두 서비스 경로를 가리지 않고 읽습니다 — pepper 격리는 위 `정책은 pepper 를 auth 쪽에서 막지 않는다` 참고.

발급:

```bash
docker exec -it vault sh /vault/scripts/rotate-approle-secret.sh jenkins-sneezecast
```

출력된 `role_id` / `new_secret_id` 를 Jenkins Secret text credential
`sneezecast-vault-role-id` / `sneezecast-vault-secret-id` 에 넣습니다.

### Web UI 계정

이미 쓰는 UI 계정이 있다면 새 계정을 만들지 말고 정책만 덧붙입니다. `policies` 는 **덮어쓰기**이므로 기존
정책을 함께 적습니다 (`vault read auth/userpass/users/<username>` 로 먼저 확인).

```bash
docker exec -it vault vault write auth/userpass/users/<username>/policies \
  policies="ui-bosspickseoul,ui-hondigagae,ui-sneezecast"
```

새로 만들려면 bootstrap 실행 시 `VAULT_UI_USERNAME` / `VAULT_UI_PASSWORD` 를 넘깁니다 (혼디가개 절과 같음).

### kv 경로 초기화

⚠️ **`reset-kv-bosspickseoul.sh` 를 sneezecast 정리에 쓰지 마십시오.** `kv` mount 를 통째로 지웁니다.

```bash
docker exec -it -e CONFIRM_RESET_KV=sneezecast vault sh /vault/scripts/reset-kv-sneezecast.sh
```

`REPORTER_KEY_PEPPER` 도 함께 지워집니다. 실행 전에 오프라인 사본이 있는지 확인합니다.
