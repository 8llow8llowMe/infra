# Jenkins가 sneezecast 배포 시크릿을 읽기 위한 정책입니다.
# KV v2는 값 조회에 /data, 목록 조회에 /metadata 경로를 사용합니다.
#
# backend 와 frontend 를 한 policy 에 두는 이유:
# 두 파이프라인 모두 같은 AppRole(jenkins-sneezecast) 로 로그인합니다.
# (frontend 는 아직 없습니다. 생기면 정책을 다시 고치지 않고 kv 경로만 만들면 됩니다)
# 애플리케이션 그룹이 더 늘어나면 여기에 블록을 추가합니다.
# (와일드카드를 sneezecast/* 로 넓히지 않는 것은, 나중에 배포와 무관한 시크릿이
#  같은 mount 에 생겼을 때 Jenkins 가 그것까지 읽게 되는 것을 막기 위해서입니다)
#
# backend/* 는 서비스별 경로(.../{env}/surveillance-service 의 REPORTER_KEY_PEPPER 포함)를 모두 덮습니다.
# 잡별로 읽는 경로를 좁히는 것은 정책이 아니라 파이프라인의 몫입니다 (vault/README.md sneezecast 절).

# ── backend ──────────────────────────────────────────────
path "kv/data/sneezecast/backend/*" {
  capabilities = ["read"]
}

# backend 하위 secret 목록 조회용 권한입니다.
path "kv/metadata/sneezecast/backend" {
  capabilities = ["list", "read"]
}

# env 하위 경로 목록 조회용 권한입니다.
path "kv/metadata/sneezecast/backend/*" {
  capabilities = ["list", "read"]
}

# ── frontend ─────────────────────────────────────────────
path "kv/data/sneezecast/frontend/*" {
  capabilities = ["read"]
}

# frontend 하위 secret 목록 조회용 권한입니다.
path "kv/metadata/sneezecast/frontend" {
  capabilities = ["list", "read"]
}

# env 하위 경로 목록 조회용 권한입니다.
path "kv/metadata/sneezecast/frontend/*" {
  capabilities = ["list", "read"]
}
