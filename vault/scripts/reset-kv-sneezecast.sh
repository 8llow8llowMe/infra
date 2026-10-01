#!/usr/bin/env sh
# sneezecast kv 경로만 삭제합니다.
#
# ⚠️ BossPickSeoul·혼디가개와 같은 kv mount 를 공유하므로 `vault secrets disable kv` 를 쓰면 안 됩니다.
#    그건 다른 프로젝트 시크릿까지 함께 날립니다.
#    (reset-kv-bosspickseoul.sh 는 mount 를 통째로 지우는 스크립트입니다 - 혼동하지 마세요)
#    여기서는 kv/sneezecast 아래 metadata 를 재귀 삭제하는 방식만 씁니다.
#
# ⚠️ surveillance-service 경로의 REPORTER_KEY_PEPPER 도 함께 지워집니다.
#    pepper 를 잃으면 기존 보고의 reporter_key 를 다시 만들 수 없습니다. 지우기 전에 값을 따로 보관하세요.

set -eu

if [ "${CONFIRM_RESET_KV:-}" != "sneezecast" ]; then
  cat <<'INNER'
ERROR: 이 스크립트는 kv/sneezecast 아래 모든 secret 을 영구 삭제합니다.
       (surveillance-service 경로의 REPORTER_KEY_PEPPER 포함 - 잃으면 기존 보고와 다시 연결할 수 없습니다)

정말 실행하려면 아래처럼 확인값을 전달하세요.
  docker exec -it -e CONFIRM_RESET_KV=sneezecast vault sh /vault/scripts/reset-kv-sneezecast.sh
INNER
  exit 1
fi

delete_tree() {
  prefix="$1"

  # 경로는 `kv/sneezecast/...` 처럼 **논리 경로**로 넘깁니다.
  # `vault kv list` 는 KV v2 에서 /metadata 를 스스로 끼워 넣으므로
  # `kv/metadata/...` 를 넘기면 kv/metadata/metadata/... 를 보게 되어
  # 조용히 빈 결과가 돌아오고 아무것도 지워지지 않습니다.
  #
  # 출력은 표 형식이라 "Keys" 와 "----" 두 줄을 건너뜁니다.
  # 디렉터리에는 / 접미사가 붙습니다.
  for entry in $(vault kv list -format=table "kv/${prefix}" 2>/dev/null | tail -n +3); do
    case "$entry" in
      */) delete_tree "${prefix}$(printf '%s' "$entry" | tr -d '/')/" ;;
      *)
        echo "destroy: kv/${prefix}${entry}"
        # metadata delete 는 모든 버전을 영구 삭제합니다 (kv delete 는 최신 버전만 soft delete).
        vault kv metadata delete "kv/${prefix}${entry}"
        ;;
    esac
  done
}

if ! vault kv list "kv/sneezecast/" >/dev/null 2>&1; then
  echo "kv/sneezecast 아래에 secret 이 없거나 읽을 권한이 없습니다. 삭제할 것이 없습니다."
  exit 0
fi

delete_tree "sneezecast/"

cat <<'EOM'
kv/sneezecast 아래 secret 을 삭제했습니다. mount(kv) 자체는 그대로입니다.

다시 넣는 방법은 vault/README.md 의 sneezecast 절(키별 적재)을 따릅니다.
`env_file=@.env` 한 키 저장은 파이프라인이 거부하므로 쓰지 않습니다.
EOM
