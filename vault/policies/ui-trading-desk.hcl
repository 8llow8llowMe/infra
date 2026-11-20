# trading-desk Vault Web UI 사용자가 시크릿을 관리하기 위한 정책입니다.
# 운영 범위는 kv/trading-desk 하위로 제한합니다.

path "kv/data/trading-desk/*" {
  capabilities = ["create", "read", "update", "delete", "patch"]
}

# Web UI가 secret 구조를 확인할 때 사용하는 KV v2 subkeys 조회 권한입니다.
path "kv/subkeys/trading-desk/*" {
  capabilities = ["read"]
}

# KV v2에서 UI 목록 조회와 secret metadata 관리를 위해 필요합니다.
# Web UI의 kv mount 첫 화면에서 `trading-desk/` 폴더를 보려면 root metadata list 권한이 필요합니다.
path "kv/metadata" {
  capabilities = ["list", "read"]
}

path "kv/metadata/trading-desk" {
  capabilities = ["list", "read", "update", "delete", "patch"]
}

path "kv/metadata/trading-desk/*" {
  capabilities = ["list", "read", "update", "delete", "patch"]
}

# 삭제된 버전 복구와 영구 삭제가 필요할 때 사용합니다.
path "kv/delete/trading-desk/*" {
  capabilities = ["update"]
}

path "kv/undelete/trading-desk/*" {
  capabilities = ["update"]
}

path "kv/destroy/trading-desk/*" {
  capabilities = ["update"]
}
