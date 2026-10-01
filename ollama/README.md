# Ollama 운영 가이드

이 디렉터리는 미니PC `ai-host`에서 Ollama와 Open WebUI를 Docker Compose로 운영하기 위한 구성입니다.

Jenkins·Kafka와 공유하는 호스트의 자원 상한, 장애 진단, UMA 조정 절차는 [HOST-STABILITY.md](HOST-STABILITY.md)를 참고합니다.

장비는 Ryzen 7 8845HS + Radeon 780M + RAM 32GB 입니다. **Radeon 780M(gfx1103)은 ROCm 공식 지원 대상이 아니므로 Vulkan 백엔드(Mesa RADV 경유)로 iGPU 가속**을 사용합니다. 이미지는 베이스 `ollama/ollama:latest` 그대로 쓰며, `OLLAMA_VULKAN=1` 환경변수로 컴파일되어 있는 Vulkan 런타임을 opt-in 합니다.

## 구성 요약

- 이미지: `ollama/ollama:latest` (Vulkan 런타임 내장, `OLLAMA_VULKAN=1` 로 활성화)
- 디바이스: `/dev/dri` 만 컨테이너에 전달 (`/dev/kfd` 불필요)
- 그룹: 호스트 `render` 그룹(GID) 을 `group_add` 로 주입 → 컨테이너가 `/dev/dri/renderD128` 접근 가능
- Open WebUI: 같은 compose 안에서 `http://ollama:11434` 로 Ollama 에 연결

## 파일 구조

```text
ollama/
├── docker-compose-ollama.yml
├── install-ollama.sh
├── pull-model.sh
├── benchmark-api.py
├── .env.example
├── .gitignore
└── README.md
```

실행 후 생성되는 로컬 데이터:

- `ollama-data/`: Ollama 모델과 설정
- `open-webui-data/`: Open WebUI 사용자/설정 데이터

## 환경변수

```bash
cd ollama
cp .env.example .env
```

Compose 파일에는 기본값을 넣지 않습니다. 실행 전에 `.env`를 준비해야 합니다.

| 변수 | 설명 | 예시 |
| --- | --- | --- |
| `OLLAMA_IMAGE` | Ollama 이미지 | `ollama/ollama:latest` |
| `OLLAMA_CONTAINER_NAME` | Ollama 컨테이너 이름 | `ollama` |
| `OLLAMA_PORT` | Ollama 외부 포트 | `11434` |
| `OLLAMA_CONTAINER_PORT` | Ollama 컨테이너 포트 | `11434` |
| `OLLAMA_HOST` | Ollama listen 주소 | `0.0.0.0:11434` |
| `OLLAMA_KEEP_ALIVE` | API 모델 메모리 유지 시간 | `5h` |
| `OLLAMA_NUM_PARALLEL` | 동시 추론 수 | `1` |
| `OLLAMA_MAX_LOADED_MODELS` | 동시 로드 모델 수 | `1` |
| `OLLAMA_CONTEXT_LENGTH` | 기본 컨텍스트 길이 | `4096` |
| `OLLAMA_MAX_QUEUE` | 대기 요청 상한 | `16` |
| `OLLAMA_MEM_LIMIT` / `OLLAMA_CPUS` | Ollama 컨테이너 상한 (`MemTotal >= 29Gi` 전제) | `17g` / `8.0` |
| `OPEN_WEBUI_MEM_LIMIT` | Open WebUI 메모리 상한 | `1g` |
| `OLLAMA_VULKAN` | Vulkan 백엔드 활성화 | `1` |
| `OLLAMA_IGPU_ENABLE` | 내장 GPU 사용 허용 (0.32+ 필수, 없으면 CPU 폴백) | `1` |
| `OLLAMA_FLASH_ATTENTION` | flash attention 활성화 (KV 캐시 양자화 전제 조건) | `1` |
| `OLLAMA_KV_CACHE_TYPE` | KV 캐시 양자화 타입 (`q8_0`이면 메모리 절반) | `q8_0` |
| `OLLAMA_DATA_DIR` | 호스트 모델 데이터 경로 | `./ollama-data` |
| `OLLAMA_CONTAINER_DATA_DIR` | 컨테이너 모델 데이터 경로 | `/root/.ollama` |
| `OPEN_WEBUI_IMAGE` | Open WebUI 이미지 | `ghcr.io/open-webui/open-webui:main` |
| `OPEN_WEBUI_CONTAINER_NAME` | Open WebUI 컨테이너 이름 | `open-webui` |
| `OPEN_WEBUI_PORT` | Open WebUI 외부 포트 | `3000` |
| `OPEN_WEBUI_CONTAINER_PORT` | Open WebUI 컨테이너 포트 | `8080` |
| `OPEN_WEBUI_OLLAMA_BASE_URL` | WebUI 가 사용할 Ollama 내부 주소 | `http://ollama:11434` |
| `OPEN_WEBUI_DATA_DIR` | 호스트 WebUI 데이터 경로 | `./open-webui-data` |
| `OPEN_WEBUI_CONTAINER_DATA_DIR` | 컨테이너 WebUI 데이터 경로 | `/app/backend/data` |
| `WEBUI_SECRET_KEY` | WebUI 세션 암호화 키 | 긴 랜덤 문자열 |
| `AMD_GPU_DRI_DEVICE` | 컨테이너에 전달할 DRI 장치 | `/dev/dri` |
| `AMD_GPU_RENDER_GROUP` | render 그룹 GID (비우면 자동 해석) | `110` |
| `TZ` | 컨테이너 타임존 | `Asia/Seoul` |

`WEBUI_SECRET_KEY` 는 운영 전에 반드시 바꿉니다.

`AMD_GPU_RENDER_GROUP` 은 비워두면 `install-ollama.sh` 가 호스트의 `getent group render` 로 GID 를 자동 해석합니다. 직접 지정하려면 호스트에서 `getent group render | cut -d: -f3` 로 확인한 숫자 GID 를 넣습니다.

Docker json 로그는 compose 에서 `max-size: "10m"`, `max-file: "3"` 으로 고정합니다.
Docker 네트워크 이름은 compose 에서 `8llow8llowme-net` 으로 고정합니다.

SearXNG 를 붙여 웹 검색을 사용하려면 [README-SEARXNG.md](README-SEARXNG.md) 를 참고합니다.

## 사전 준비 (호스트)

1. BIOS UMA 설정값과 실제 적용값을 구분합니다. `free -h`의 `MemTotal`, `/sys/class/drm/card*/device/mem_info_vram_total`, 모델 로드 시 `ollama ps`를 기록합니다. API 모델 `gpt-oss:20b`는 약 14GB이므로 UMA Auto/2GB 변경은 같은 요청의 성능 비교 후 결정합니다.
2. 호스트에 amdgpu 드라이버와 Mesa Vulkan 드라이버 설치 확인:
   ```bash
   ls /dev/dri          # card0, renderD128 이 보여야 함
   getent group render  # render 그룹과 GID 가 출력되어야 함
   ```
3. (선택) 호스트에서 Vulkan 디바이스 인식 확인:
   ```bash
   sudo apt install -y vulkan-tools mesa-vulkan-drivers
   vulkaninfo --summary | grep -iE "deviceName|driverName"
   # AMD Radeon Graphics (RADV GFX1103_R1) 같은 줄이 나와야 정상
   ```

## 실행

스크립트 사용:

```bash
cd ollama
sh install-ollama.sh
```

직접 실행:

```bash
cd ollama
# 호스트의 render 그룹 GID 를 환경변수로 주입
export AMD_GPU_RENDER_GROUP="$(getent group render | cut -d: -f3)"
docker compose --env-file .env -f docker-compose-ollama.yml up -d
```

Ollama 만 실행:

```bash
docker compose --env-file .env -f docker-compose-ollama.yml up -d ollama
```

상태 확인:

```bash
docker compose --env-file .env -f docker-compose-ollama.yml ps
docker logs -f ollama
docker logs -f open-webui
```

중지:

```bash
docker compose --env-file .env -f docker-compose-ollama.yml down
```

## GPU 인식 검증

Vulkan 초기화에 실패하면 Ollama 는 별다른 경고 없이 CPU 로 폴백합니다. 기동 직후 반드시 확인합니다.

```bash
# Vulkan 디바이스 인식 확인
docker logs ollama 2>&1 | grep -iE "vulkan|radv"
# 다음 같은 줄이 보여야 정상:
#   OLLAMA_VULKAN:true
#   Vulkan0: AMD Radeon Graphics (RADV GFX1103_R1)

# 모델 로드 후 GPU 점유율 확인
docker exec ollama ollama ps
# PROCESSOR 컬럼이 100% GPU 또는 XX%/YY% GPU/CPU 분할이면 정상
# 100% CPU 면 Vulkan 초기화 실패 → 아래 문제 해결 참고
```

호스트에서 실시간 모니터링:

```bash
sudo apt install -y radeontop
radeontop                                              # GPU 사용률 실시간
cat /sys/class/drm/card0/device/mem_info_vram_used     # UMA 사용량 (bytes)
```

## 접속

Ollama API:

```text
http://<ai-host-ip>:11434
```

Open WebUI:

```text
http://<ai-host-ip>:3000
```

Docker 네트워크 내부에서는 다음 주소를 사용합니다.

```text
http://ollama:11434
```

## 모델 설치

API에서 사용하는 모델:

```bash
sh pull-model.sh gpt-oss:20b
```

직접 실행:

```bash
docker exec -it ollama ollama pull gpt-oss:20b
docker exec -it ollama ollama run gpt-oss:20b
```

## iGPU 메모리 (UMA + GTT)

Radeon 780M 은 dGPU 처럼 별도 VRAM 이 없고 시스템 RAM 을 나눠 씁니다.

- **UMA Frame Buffer** — BIOS 에서 미리 떼어 GPU 전용으로 고정하는 영역. 현재 실제 적용 크기는 호스트의 `mem_info_vram_total`로 확인해야 합니다.
- **GTT (Graphics Translation Table)** — GPU 가 접근할 수 있는 시스템 RAM 영역입니다. 사용 가능 크기와 Ollama의 모델 배치는 드라이버·BIOS·모델에 따라 달라집니다.

RAM 32GB는 보통 `free -h`에서 약 `30Gi`로 보입니다(GB와 GiB 단위 차이). 과거 인벤토리의 `30Gi`만으로 BIOS UMA 예약량이 2GB라고 계산할 수 없습니다. `gpt-oss:20b`의 파일 크기는 약 14GB이며 실행 메모리는 더 필요합니다. UMA 8GB만으로 모델 전체가 고정 GPU 영역에 들어가지는 않습니다. 고정 UMA를 줄여도 활성 모델이 GTT를 사용하면 시스템 메모리 소비가 다시 늘어납니다.

여러 프로젝트의 API가 공유하는 `gpt-oss:20b`의 재로딩을 줄이기 위해 `OLLAMA_KEEP_ALIVE=5h`로 모델을 유지하고, `MAX_LOADED_MODELS=1`, `NUM_PARALLEL=1`, `CONTEXT_LENGTH=4096`으로 동시 메모리 급증을 억제합니다. 5시간 설정은 유휴 모델의 유지 시간만 늘리며, 모델이 이미 메모리에 있을 때의 생성 속도를 높이지는 않습니다. 클라이언트의 `keep_alive`와 `num_ctx`는 서버 기본값을 덮어쓸 수 있습니다. UMA 변경 판단과 요청 단계별 속도 측정은 [HOST-STABILITY.md](HOST-STABILITY.md)를 따릅니다.

`OLLAMA_MAX_QUEUE=16`은 대기열이 지나치게 길어지는 것을 막습니다. 동시 요청이 많으면 초과 요청은 503으로 거절될 수 있으므로 API 호출 측에서 재시도 정책과 동시 요청 수를 맞춥니다.

## 운영 주의사항

- `ollama-data/`, `open-webui-data/`, `.env`는 Git 에 커밋하지 않습니다.
- 모델 파일은 용량이 크므로 SSD 여유 공간을 주기적으로 확인합니다.
- `gpt-oss:20b`를 쓰는 동안 `OLLAMA_NUM_PARALLEL=1`을 유지합니다. 병렬 요청은 KV 캐시 메모리를 늘립니다.
- API 포트 `11434` 는 공개망에 직접 노출하지 않습니다.
- Open WebUI 를 외부에 열어야 한다면 Nginx TLS, 인증, IP allowlist 를 먼저 구성합니다.
- Jenkins·Kafka·Vault·Open WebUI가 함께 떠 있으므로 실제 `MemTotal`과 모델 실행 중 `MemAvailable`을 측정한 뒤 컨테이너 상한을 적용합니다.
- **Vulkan 초기화 실패 시 Ollama 는 조용히 CPU 로 폴백합니다.** 기동 직후 위 "GPU 인식 검증" 절차로 반드시 확인합니다.
- `OLLAMA_VULKAN` 은 Ollama 업스트림에서 experimental 플래그로 표기되어 있습니다. 변경 가능성이 있으므로 운영 안정성이 필요해지면 이미지 핀(`ollama/ollama:0.X.Y`) 을 고려합니다.

## 백업과 복구

백업 대상:

- `.env`
- `open-webui-data/`
- 필요한 경우 `ollama-data/`

모델은 다시 pull 받을 수 있으므로 백업 시간이 부담되면 `ollama-data/` 는 제외할 수 있습니다.

백업 예시:

```bash
cd ollama
tar czf ollama-backup-$(date +%Y%m%d).tar.gz .env open-webui-data
```

복구 예시:

```bash
cd ollama
tar xzf ollama-backup-YYYYMMDD.tar.gz
sh install-ollama.sh
```

## 문제 해결

Ollama API 확인:

```bash
curl http://localhost:11434/api/tags
```

컨테이너 로그:

```bash
docker logs -f ollama
docker logs -f open-webui
```

모델 목록:

```bash
docker exec -it ollama ollama list
```

디스크 사용량:

```bash
du -sh ollama-data open-webui-data
```

### GPU 가속이 안 될 때

증상별 점검 순서:

1. `docker logs ollama 2>&1 | grep -i vulkan` 에 `OLLAMA_VULKAN:false` 가 보인다
   → `.env` 의 `OLLAMA_VULKAN=1` 확인 후 `docker compose down && sh install-ollama.sh` 로 재기동
2. `docker logs ollama` 에 `failed to open /dev/dri/renderD128: permission denied` 가 보인다
   → 컨테이너 render GID 가 호스트와 불일치. `docker exec ollama id` 로 그룹 확인, `.env` 의 `AMD_GPU_RENDER_GROUP` 을 호스트 `getent group render | cut -d: -f3` 결과로 명시
3. `vulkaninfo --summary` 출력이 호스트에서 비어 있다
   → 호스트 Vulkan 드라이버 미설치. `sudo apt install -y mesa-vulkan-drivers vulkan-tools` 후 재부팅
4. `ollama ps` 의 PROCESSOR 가 `100% CPU` 다
   → 위 1~3 을 모두 확인한 뒤에도 동일하면 모델이 UMA 보다 커서 fallback 된 경우일 수 있음. 더 작은 quant 모델로 재시도
