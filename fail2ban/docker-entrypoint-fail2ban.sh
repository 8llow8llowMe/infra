#!/bin/sh
# Fail2Ban 컨테이너 엔트리포인트
# - F2B_MODE 에 따라 차단 방식(banaction)을 정한 뒤 fail2ban 을 포그라운드로 띄웁니다 (#37).
#     log     : 차단하지 않고 fail2ban.log 에 Ban/Unban 만 남깁니다(dummy). 새 규칙을 처음 켤 때 씁니다.
#     enforce : 호스트 iptables DOCKER-USER 체인에 차단 규칙을 겁니다(network_mode: host 필요).

set -e

MODE="${F2B_MODE:-log}"
MODE_FILE=/etc/fail2ban/jail.d/zz-mode.local

mkdir -p /etc/fail2ban/jail.d /var/log/fail2ban /var/lib/fail2ban /var/run/fail2ban
chmod 755 /var/run/fail2ban
touch /var/log/fail2ban/fail2ban.log

case "$MODE" in
  enforce)
    cat > "$MODE_FILE" <<'CONF'
[DEFAULT]
banaction          = iptables-multiport
banaction_allports = iptables-allports
CONF
    ;;
  log)
    cat > "$MODE_FILE" <<'CONF'
[DEFAULT]
banaction          = dummy
banaction_allports = dummy
CONF
    ;;
  *)
    echo "[ERROR] F2B_MODE must be log or enforce (got: $MODE)" >&2
    exit 1
    ;;
esac

echo "[INFO] Starting Fail2Ban (foreground, mode=$MODE)"
echo "[INFO] Logs -> /var/log/fail2ban/fail2ban.log"

# -f: 포그라운드, -x: 남은 pid/socket 정리 후 시작. exec 로 PID 1 이 되어 docker 가 직접 관리합니다.
exec fail2ban-server -f -x start
