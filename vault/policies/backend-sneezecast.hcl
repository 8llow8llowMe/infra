# sneezecast 배포 대상 호스트(dev: backend-1 192.168.0.13 / prod: 신규 미니PC)의 deploy/runtime 이
# backend 시크릿을 읽기 위한 정책입니다.
#
# 서비스별 경로(kv/sneezecast/backend/{env}/{service})를 따로 막지 않습니다. 혼디가개와 같은 범위입니다.
# 그래서 이 정책을 가진 토큰은 surveillance-service 경로의 REPORTER_KEY_PEPPER 도 읽을 수 있습니다.
# pepper 를 auth 쪽에서 떼어 놓는 일은 파이프라인(잡마다 공통 + 자기 서비스 경로만 읽음)이 맡습니다.
# 서비스 그룹이 더 나뉘면 이 정책도 더 좁게 분리합니다.

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
