# Jenkins 가 commerce-foundry 프론트(storefront · admin) 배포 시크릿을 읽기 위한 정책입니다.
# 백엔드 경로는 읽지 못합니다 — 프론트 잡이 백엔드 시크릿에 닿지 않게 AppRole 을 나눴습니다.

path "kv/data/commerce-foundry/frontend/*" {
  capabilities = ["read"]
}

# frontend 하위 secret 목록 조회용 권한입니다.
path "kv/metadata/commerce-foundry/frontend" {
  capabilities = ["list", "read"]
}

# env 하위 경로 목록 조회용 권한입니다.
path "kv/metadata/commerce-foundry/frontend/*" {
  capabilities = ["list", "read"]
}
