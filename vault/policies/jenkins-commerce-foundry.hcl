# Jenkins 가 commerce-foundry 백엔드 배포 시크릿을 읽기 위한 정책입니다.
# KV v2는 값 조회에 /data, 목록 조회에 /metadata 경로를 사용합니다.
#
# 혼디가개와 달리 frontend 블록을 두지 않습니다.
# commerce-foundry 는 프론트 잡이 백엔드 시크릿(JWT 개인키 · DB 비밀번호)을 읽지 못하게
# 백엔드 · 프론트 AppRole 을 나눴습니다(jenkins-commerce-foundry-frontend.hcl).

path "kv/data/commerce-foundry/backend/*" {
  capabilities = ["read"]
}

# backend 하위 secret 목록 조회용 권한입니다.
path "kv/metadata/commerce-foundry/backend" {
  capabilities = ["list", "read"]
}

# env 하위 경로 목록 조회용 권한입니다.
path "kv/metadata/commerce-foundry/backend/*" {
  capabilities = ["list", "read"]
}
