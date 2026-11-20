#!/usr/bin/env sh
# trading-desk(개인 도구)용 Vault 정책과 AppRole을 구성합니다. 여러 번 실행해도 됩니다(멱등).
# 실행 시점: Vault init, unseal 완료 후. root token 또는 관리자 token 이 필요합니다.
#
# 다른 프로젝트와 같은 Vault 인스턴스를 공유하되 policy / AppRole / kv 경로만 분리합니다.
# 백엔드 · 웹 잡이 AppRole 하나(jenkins-trading-desk)를 씁니다 — 이유는 policies/jenkins-trading-desk.hcl 머리말.
# 앱은 Vault 를 직접 읽지 않습니다(env 로만 받음). 그래서 backend-trading-desk AppRole 은 만들지 않습니다.
# kv 값은 만들지 않습니다 — kv put 은 secret 전체를 덮어씁니다. 값 넣기는 앱 레포 docs/deploy.md 3절.
#
# 사용:
#   docker exec -e VAULT_TOKEN='<root-token>' vault sh /vault/scripts/bootstrap-trading-desk.sh
#   기존 Web UI 계정에 ui-trading-desk 를 더하려면 VAULT_UI_USERNAME 을 함께 넘깁니다(기존 정책은 유지).

set -eu

if ! vault token lookup >/dev/null 2>&1; then
  echo "ERROR: Vault token 이 없거나 유효하지 않습니다. VAULT_TOKEN 을 넘기세요." >&2
  exit 1
fi

if ! vault token capabilities sys/policies/acl/jenkins-trading-desk 2>/dev/null | grep -Eq '(^| )sudo( |$)|(^| )update( |$)|root'; then
  echo "ERROR: 현재 token 에는 policy 를 갱신할 권한이 없습니다. root 또는 관리자 token 으로 실행하세요." >&2
  exit 1
fi

vault secrets enable -path=kv kv-v2 2>/dev/null || true
vault auth enable approle 2>/dev/null || true

vault policy write jenkins-trading-desk /vault/policies/jenkins-trading-desk.hcl
vault policy write ui-trading-desk /vault/policies/ui-trading-desk.hcl

vault write auth/approle/role/jenkins-trading-desk \
  token_policies="jenkins-trading-desk" \
  token_ttl="1h" \
  token_max_ttl="4h" \
  secret_id_ttl="0" \
  secret_id_num_uses="0"

# 기존 UI 계정의 정책 목록에 ui-trading-desk 를 더합니다. 비밀번호는 건드리지 않습니다.
if [ -n "${VAULT_UI_USERNAME:-}" ]; then
  current="$(vault read -field=token_policies "auth/userpass/users/${VAULT_UI_USERNAME}" | tr -d '[]' | tr ' ' ',')"
  case ",${current}," in
    *,ui-trading-desk,*) echo "UI 계정 ${VAULT_UI_USERNAME} 에 이미 ui-trading-desk 가 있습니다." ;;
    *)
      vault write "auth/userpass/users/${VAULT_UI_USERNAME}/policies" policies="${current:+${current},}ui-trading-desk"
      echo "UI 계정 ${VAULT_UI_USERNAME} 에 ui-trading-desk 를 더했습니다."
      ;;
  esac
fi

cat <<'EOM'
trading-desk Vault 구성이 완료되었습니다.

Jenkins credential(Secret text, 폴더 trading-desk 범위)로 등록할 값:
  trading-desk-vault-role-id    ← vault read -field=role_id auth/approle/role/jenkins-trading-desk/role-id
  trading-desk-vault-secret-id  ← vault write -f -field=secret_id auth/approle/role/jenkins-trading-desk/secret-id
EOM
