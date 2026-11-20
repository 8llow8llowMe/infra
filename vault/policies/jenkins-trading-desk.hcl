# Jenkins 가 trading-desk 배포 env 를 읽기 위한 정책입니다.
# KV v2는 값 조회에 /data, 목록 조회에 /metadata 경로를 사용합니다.
#
# 백엔드 · 웹 잡이 같은 AppRole(jenkins-trading-desk)로 로그인합니다. 1인용 도구라 두 잡이 같은 저장소 · 같은 develop 에서 돌고,
# 같은 호스트(backend-server)의 agent 에서 docker 소켓을 쓰므로 AppRole 을 나눠도 막히는 것이 없습니다(commerce-foundry 와 다른 점).
# 읽는 것은 kv/trading-desk/{backend,frontend}/{env}/env 뿐입니다 — + 는 경로 한 칸입니다.
# 목록(metadata) 권한도 주지 않습니다 — 파이프라인은 정해진 경로 하나만 읽습니다.
# trading-desk/* 로 넓히지 않습니다. 배포와 무관한 시크릿이 같은 mount 아래 생겨도 Jenkins 가 읽지 못하게.

path "kv/data/trading-desk/+/+/env" {
  capabilities = ["read"]
}
