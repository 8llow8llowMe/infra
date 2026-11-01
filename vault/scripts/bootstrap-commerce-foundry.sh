#!/usr/bin/env sh
# commerce-foundry(MOKOYURI)용 Vault 정책과 AppRole을 구성합니다. 여러 번 실행해도 됩니다(멱등).
# 실행 시점: Vault init, unseal 완료 후. root token 또는 관리자 token 이 필요합니다.
#
# 다른 프로젝트와 같은 Vault 인스턴스를 공유하되 policy / AppRole / kv 경로만 분리합니다.
# 혼디가개와 달리 백엔드 · 프론트 AppRole 을 나눕니다 — 프론트 잡이 백엔드 시크릿을 읽지 못하게.
#
# 사용:
#   docker exec -e VAULT_TOKEN='<root-token>' vault sh /vault/scripts/bootstrap-commerce-foundry.sh
#   기존 Web UI 계정에 ui-commerce-foundry 를 더하려면 VAULT_UI_USERNAME 을 함께 넘깁니다(기존 정책은 유지).

set -eu

if ! vault token lookup >/dev/null 2>&1; then
  echo "ERROR: Vault token 이 없거나 유효하지 않습니다. VAULT_TOKEN 을 넘기세요." >&2
  exit 1
fi

if ! vault token capabilities sys/policies/acl/jenkins-commerce-foundry 2>/dev/null | grep -Eq '(^| )sudo( |$)|(^| )update( |$)|root'; then
  echo "ERROR: 현재 token 에는 policy 를 갱신할 권한이 없습니다. root 또는 관리자 token 으로 실행하세요." >&2
  exit 1
fi

vault secrets enable -path=kv kv-v2 2>/dev/null || true
vault auth enable approle 2>/dev/null || true

vault policy write jenkins-commerce-foundry /vault/policies/jenkins-commerce-foundry.hcl
vault policy write jenkins-commerce-foundry-frontend /vault/policies/jenkins-commerce-foundry-frontend.hcl
vault policy write ui-commerce-foundry /vault/policies/ui-commerce-foundry.hcl

vault write auth/approle/role/jenkins-commerce-foundry \
  token_policies="jenkins-commerce-foundry" \
  token_ttl="1h" \
  token_max_ttl="4h" \
  secret_id_ttl="0" \
  secret_id_num_uses="0"

vault write auth/approle/role/jenkins-commerce-foundry-frontend \
  token_policies="jenkins-commerce-foundry-frontend" \
  token_ttl="1h" \
  token_max_ttl="4h" \
  secret_id_ttl="0" \
  secret_id_num_uses="0"

# 기존 UI 계정의 정책 목록에 ui-commerce-foundry 를 더합니다. 비밀번호는 건드리지 않습니다.
if [ -n "${VAULT_UI_USERNAME:-}" ]; then
  current="$(vault read -field=token_policies "auth/userpass/users/${VAULT_UI_USERNAME}" | tr -d '[]' | tr ' ' ',')"
  case ",${current}," in
    *,ui-commerce-foundry,*) echo "UI 계정 ${VAULT_UI_USERNAME} 에 이미 ui-commerce-foundry 가 있습니다." ;;
    *)
      vault write "auth/userpass/users/${VAULT_UI_USERNAME}/policies" policies="${current:+${current},}ui-commerce-foundry"
      echo "UI 계정 ${VAULT_UI_USERNAME} 에 ui-commerce-foundry 를 더했습니다."
      ;;
  esac
fi

cat <<'EOM'
commerce-foundry Vault 구성이 완료되었습니다.

Jenkins credential(Secret text)로 등록할 값:
  commerce-foundry-vault-role-id            ← vault read -field=role_id auth/approle/role/jenkins-commerce-foundry/role-id
  commerce-foundry-vault-secret-id          ← vault write -f -field=secret_id auth/approle/role/jenkins-commerce-foundry/secret-id
  commerce-foundry-frontend-vault-role-id   ← vault read -field=role_id auth/approle/role/jenkins-commerce-foundry-frontend/role-id
  commerce-foundry-frontend-vault-secret-id ← vault write -f -field=secret_id auth/approle/role/jenkins-commerce-foundry-frontend/secret-id
EOM
