# ollama-01 호스트 안정화

대상: `192.168.0.10`, Ryzen 7 8845HS / Radeon 780M / RAM 32GB. API 모델은 **`gpt-oss:20b`**다. Ollama, Open WebUI, Jenkins controller·builder, Kafka 3 브로커, Vault, SearXNG가 함께 실행된다. 이 문서의 수치는 **OS `MemTotal`이 29Gi 이상일 때의 시작값**이며, 실제 장애 원인과 피크 사용량을 확인한 뒤 조정한다. CPU 100% 순간치는 종료 원인의 증거가 아니다.

## 1. 장애 원인부터 확인

재부팅 후 호스트에서 다음을 실행한다. `journalctl -b -1`은 이전 부팅의 로그이므로 persistent journal이 없으면 비어 있을 수 있다.

```bash
last -x reboot shutdown | head -30
sudo journalctl -b -1 -k --no-pager | grep -Ei 'out of memory|oom|killed process|thermal|thrott|critical temperature|watchdog|lockup|amdgpu|reset|nvme|mce|hardware error'
sudo journalctl -b -1 -u docker -u ssh --no-pager | tail -100
free -h
grep MemTotal /proc/meminfo
swapon --show
docker stats --no-stream
docker inspect -f '{{.Name}} OOM={{.State.OOMKilled}} Exit={{.State.ExitCode}} Restarts={{.RestartCount}}' ollama jenkins-controller jenkins-builder-agent
docker exec ollama ollama ps
cat /sys/class/drm/card*/device/mem_info_vram_total
sensors
```

- `Out of memory`, `Killed process`, `OOMKilled=true`: 메모리 압박. 당시 빌드·모델·Kafka 사용량, swap, `MemAvailable`을 대조한다. 컨테이너만 재시작했는지, 호스트 전체가 재부팅했는지 구분한다.
- `thermal`, `critical temperature`, `throttling`: 냉각·흡기/배기·팬·써멀 상태와 전원 어댑터를 점검한다. 임계 온도는 해당 기기/센서 기준으로 판단한다.
- 로그가 갑자기 끝나고 shutdown 기록이 없음: 전원·어댑터·과열 보호·펌웨어·커널 멈춤 가능성을 점검한다. 로그가 없다는 것만으로 전원 원인을 확정할 수 없다.
- 호스트 uptime은 유지되는데 SSH만 끊김: 네트워크, `sshd`, 메모리 압박으로 인한 응답 지연을 분리한다. 다른 LAN 기기에서 ping/SSH와 공유기 기록을 확인한다.

장애 재발 시 원인을 남기도록 `/var/log/journal`에 여유 공간을 확보하고 persistent journal을 활성화한다. `sudo mkdir -p /var/log/journal && sudo systemctl restart systemd-journald` 후 **다음 재부팅 뒤** `journalctl --list-boots`로 이전 부팅이 보이는지 확인한다. 시스템 설정에 `Storage=volatile`이 강제되어 있으면 journald 설정을 먼저 수정한다.

## 2. 메모리 예산과 적용 순서

`gpt-oss:20b`의 Ollama 모델 파일은 약 14GB이고, 실행 시 KV 캐시와 런타임 메모리가 추가된다. 이전의 **Ollama 7GB 상한은 이 모델에 맞지 않아 폐기**했다. 저장소의 2026-08-14 `free -h` 실측 총 메모리는 `30Gi`다. RAM 32GB(decimal)는 약 29.8GiB(binary)이므로 `30Gi`만 보고 UMA 2GB를 예약했다고 계산할 수 없다. BIOS 변경 이후의 현재 `MemTotal`과 실제 VRAM 크기를 다시 확인한다.

`MemTotal >= 29Gi`인 경우 초기 상한은 Ollama 17Gi, WebUI 1Gi, Jenkins builder 3Gi, controller 2.5Gi, Kafka 브로커 3개 3Gi + UI 512Mi + exporter 128Mi다. 합계는 **약 27.1Gi**다. OS·Vault·SearXNG·Docker·GPU GTT가 남은 메모리를 공유하므로 **모든 서비스가 상한까지 동시에 쓰는 상황은 안전하지 않다.** 이 값은 동시 최대 사용 보장이 아닌 장애 범위 제한이다. `MemTotal`이 29Gi보다 낮으면 이 상한을 그대로 배포하지 않는다. `gpt-oss:20b` API와 무거운 빌드를 동시에 안정적으로 운영하려면 builder를 별도 호스트로 옮기는 것이 가장 효과적이다.

1. 장애 로그와 평시/동시 빌드 피크를 먼저 기록한다. `free -h`, `docker stats --no-stream`, `docker exec ollama ollama ps`, `sensors`를 빌드 전·중·후에 비교한다.
2. Jenkins UI에서 controller executor를 `0`, `ai-host-builder` executor를 **`1`**로 설정한다. 동시에 빌드 2개가 돌아가는 상태를 막는다. Docker socket으로 시작한 별도 build/container는 builder의 `mem_limit` 밖에 있을 수 있으므로 `docker ps`와 `docker stats`에서 함께 확인한다. builder CPU 4개 상한은 빌드가 iGPU와 같은 APU의 전력·발열 여유를 모두 쓰는 상황을 줄인다. Gradle은 `GRADLE_OPTS`로 workers 최대 2개와 유휴 daemon 비활성화를 적용한다. 프로젝트의 명시적 Gradle 옵션은 별도로 확인한다.
3. `.env.example`의 자원값을 **기존 비밀값이 들어 있는 각 `.env`에 수동 병합**한다. Ollama는 `OLLAMA_KEEP_ALIVE=5h`, `OLLAMA_MAX_LOADED_MODELS=1`, `OLLAMA_NUM_PARALLEL=1`, `OLLAMA_CONTEXT_LENGTH=4096`을 적용한다. 실행 중인 빌드가 없을 때 아래처럼 재생성한다. `config -q`는 비밀값을 출력하지 않고 설정만 검사한다. `install-jenkins-*.sh`는 `--build`를 수행하므로 보수적 적용에는 직접 `up -d`를 쓴다.
4. 빌더가 3Gi 상한에서 OOM을 내면 빌드 한 건의 실제 피크를 기록한다. 메모리 상한만 올리면 호스트 보호 여유가 사라질 수 있다. Gradle workers/heap, Node heap, Docker build 자식 컨테이너를 줄이거나 빌더를 별도 호스트로 옮긴다. controller가 2.5Gi 상한에 닿으면 JVM heap(현재 1.5Gi)과 플러그인 사용량을 점검한다. Ollama가 17Gi 상한에 닿으면 모델 로드 크기와 context를 확인하고, builder 이전 전에는 상한을 올리지 않는다.
5. `swapon --show`가 비어 있으면 루트 파일시스템과 여유 공간을 확인한 뒤 4~8GB swap을 준비한다. swap은 OOM 직전의 완충이며 메모리 증설이 아니다. 빌드 중 swap-in/out이 계속 늘면 그 빌드는 실패로 보고 부하를 낮춘다. swapfile 생성 방법은 파일시스템별로 달라서 호스트 종류를 확인한 뒤 적용한다.

저장소 루트에서 적용 예시:

```bash
cd ollama
docker compose --env-file .env -f docker-compose-ollama.yml config -q
docker compose --env-file .env -f docker-compose-ollama.yml up -d
cd ../jenkins
docker compose --env-file .env -f docker-compose-jenkins-controller.yml config -q
docker compose --env-file .env -f docker-compose-jenkins-builder-agent.yml config -q
docker compose --env-file .env -f docker-compose-jenkins-controller.yml up -d
docker compose --env-file .env -f docker-compose-jenkins-builder-agent.yml up -d
```

`docker inspect -f '{{.HostConfig.Memory}} {{.HostConfig.MemorySwap}} {{.HostConfig.NanoCpus}} {{.HostConfig.PidsLimit}}' <container>`와 `docker stats`로 상한 반영을 확인한다. `memswap_limit=mem_limit`로 이 컨테이너의 swap 사용을 막아 추론/빌드가 디스크 swap으로 느려지는 상황을 피한다. 상한에 도달한 작업은 OOM으로 종료될 수 있다. `MemAvailable`이 동시 부하 중 3Gi 아래로 지속되면 builder 분리 또는 서비스 이전을 우선한다.

## 3. BIOS UMA

8GB 고정 UMA가 GPU의 연산 능력이나 RAM 대역폭 자체를 올려주지는 않는다. 그러나 GPU가 모델을 어디에 적재하는지와 Ollama가 보고받는 VRAM 크기는 바꿀 수 있다. `gpt-oss:20b`는 약 14GB이므로 **8GB UMA만으로도 전체 모델이 고정 GPU 영역에 들어가지 않는다.** GTT 또는 CPU 메모리를 함께 쓸 수 있으며, 실제 배치는 `ollama ps`의 `PROCESSOR`로 확인한다. `radeontop` 등의 GPU 사용률 100%는 모델이 100% GPU에 적재되었다는 뜻이 아니다.

과거 인벤토리의 `30Gi`는 32GB RAM의 정상적인 GiB 표기와 비슷하다. 당시 이미 8GB UMA가 적용되었다는 증거는 없다. 유지보수 시간에 현재 BIOS 값과 `MemTotal`, `mem_info_vram_total`, `mem_info_gtt_total`을 먼저 기록한다. 그다음 아래의 **동일한 API 요청**으로 현재값과 Auto/2GB(또는 4GB)를 비교한다. GPU 배치, load/prompt/decode 시간, 토큰/초, `MemAvailable`, `sensors`, 빌드 동시 실행 시 상태를 모두 본다. 더 작은 UMA에서 속도나 안정성이 나빠지면 되돌린다. 작은 UMA가 모델의 GTT 사용을 늘리면 OS에 보이는 RAM이 늘어도 실제 가용 RAM은 늘지 않을 수 있다.

## 4. API 응답 지연 측정과 개선

같은 모델·프롬프트·컨텍스트로 `python3 benchmark-api.py --model gpt-oss:20b`를 실행한다. 첫 요청과 이어지는 요청의 `load_s`, `prompt_s`, `decode_s`, `tok_per_s`를 비교한다. `load_s`가 크면 모델 재로딩이 첫 요청을 늦추므로 공유 API 모델의 `OLLAMA_KEEP_ALIVE=5h`가 도움이 된다. 5시간 동안 요청이 없으면 다음 요청에서 다시 로드할 수 있다. 요청이 자주 들어오면 유휴 시간이 다시 계산되어 계속 적재될 수 있다. 5시간은 상주 메모리의 **시간**을 늘릴 뿐 피크 사용량이나 따뜻한 상태의 토큰/초를 바꾸지 않는다. 빌드와 겹칠 때 `MemAvailable`이 3GiB 아래로 내려가거나 OOM이 발생하면 builder 분리를 우선한다. `prompt_s`가 크면 긴 프롬프트/히스토리를 줄인다. `decode_s`가 크고 토큰/초가 낮으면 GPU/CPU 배치, APU 전력·온도, 모델 크기 자체가 병목이다. 측정 중 `docker exec ollama ollama ps`, `free -h`, `sensors`를 함께 본다.

Ollama `/api/show`에서 `gpt-oss:20b`의 지원 thinking 값을 확인하고, 짧은 API 답변에는 요청의 `"think": "low"`를 시험한다. 기본값은 모델 버전에 따라 확인한다. 품질이 중요한 작업에는 `medium`을 유지한다. 응답을 받는 클라이언트가 지원하면 `"stream": true`로 첫 출력의 대기 시간을 줄인다. 스트리밍은 총 생성 시간을 줄이는 기능은 아니다. 요청별 `num_ctx`를 필요 이상 크게 지정하거나 `keep_alive: 0`을 보내면 서버 기본값의 이점이 사라진다.

짧은 응답을 원하는 Ollama `/api/chat` 요청 예시:

```json
{"model":"gpt-oss:20b","messages":[{"role":"user","content":"질문"}],"think":"low","stream":true,"options":{"num_ctx":4096}}
```

```bash
curl http://localhost:11434/api/show -d '{"model":"gpt-oss:20b"}'
python3 benchmark-api.py --model gpt-oss:20b --think default
python3 benchmark-api.py --model gpt-oss:20b --think low
```

모델 파일 14GB의 로딩·추론과 Jenkins·Kafka를 32GB RAM의 단일 APU에서 함께 처리하는 하드웨어 한계는 BIOS UMA 설정만으로 해결할 수 없다. API 지연과 호스트 가용성이 모두 중요하면 builder를 다른 호스트로 옮기는 것이 우선이다.

현재 예시 이미지의 `latest`는 업데이트 시 Vulkan 동작이 바뀔 수 있다. 호스트에서 사용 중인 `docker image inspect ollama/ollama:latest --format '{{.Id}}'`, `docker exec ollama ollama --version`과 API 지표를 기록하고, 안정성이 확인된 **실제 실행 버전 태그**로 `.env`를 고정한다. Radeon 780M에서 큰 모델의 Vulkan 회귀가 보고된 적이 있어, 버전 변경은 동일한 벤치마크로 검증한다. 특정 예전 버전을 검증 없이 고정하지 않는다.

## 5. 접속 불능 방지와 관측

- `monitoring/node-exporter`를 이 호스트에서 실행하고 Prometheus의 `ollama-01` target이 `UP`인지 확인한다. `node_memory_MemAvailable_bytes`, swap, CPU, `node_hwmon_temp_celsius`(센서가 노출될 때), filesystem, uptime을 Grafana에서 본다. **Prometheus target만 추가해도 알림은 오지 않는다.** Grafana 연락처와 알림 규칙을 별도로 설정해 `up == 0`, available < 3GB, 온도 상승, swap 지속 사용을 통보한다.
- 호스트의 Docker·SSH 서비스 자동 시작, 충분한 디스크 여유, 전원 복구 시 자동 부팅 BIOS 옵션을 점검한다. 호스트가 완전히 멈추면 Docker `restart: unless-stopped`는 복구 수단이 아니다. 하드웨어 watchdog/원격 전원 제어는 장비 지원 여부를 확인하고 실제 복구 시험 후 사용한다.
- 강제 재부팅을 OOM의 기본 대응으로 설정하지 않는다. `panic_on_oom`은 전체 시스템을 재부팅시킬 수 있다. 원인 확인 전에는 컨테이너 제한과 로그 보존으로 범위를 좁힌다.
- 전원 차단·어댑터 불량·팬 고장·커널/펌웨어 결함까지 설정만으로 100% 막을 수는 없다. 전원/열 문제는 UPS, 냉각, 하드웨어 진단이 필요하다.

근거: [Ollama gpt-oss:20b](https://ollama.com/library/gpt-oss:20b), [Ollama FAQ](https://docs.ollama.com/faq), [Ollama API 지표](https://docs.ollama.com/api/chat), [Ollama thinking](https://docs.ollama.com/capabilities/thinking), [Docker Compose 서비스 옵션](https://docs.docker.com/reference/compose-file/services/), [Gradle 빌드 환경](https://docs.gradle.org/current/userguide/build_environment.html), [Linux AMDGPU 메모리 도메인](https://docs.kernel.org/gpu/amdgpu/driver-misc.html), [Linux OOM 동작](https://docs.kernel.org/admin-guide/sysctl/vm.html), [Radeon 780M Vulkan 회귀 사례](https://github.com/ollama/ollama/issues/17748).
