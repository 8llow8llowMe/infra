#!/usr/bin/env sh
# Spring Docker 대시보드 템플릿으로 프로젝트 대시보드 폴더를 만듭니다.
#
# 사용법 (monitoring/grafana 에서):
#   sh render-dashboards.sh <project 라벨> <폴더/표시 이름>
#   sh render-dashboards.sh hondigagae Hondigagae
#
# dashboard-templates/spring-docker/*.template.json 의 __PROJECT__ 를 project 라벨로,
# __PROJECT_TITLE__ 를 폴더/표시 이름으로 바꿔 dashboards/<폴더 이름>/ 에 씁니다.
# uid 는 "<project>-..." 로 정해지므로 project 라벨이 다르면 다른 프로젝트와 겹치지 않습니다.
# 생성된 JSON 은 커밋합니다. 템플릿을 고치면 모든 프로젝트를 다시 렌더링합니다.

set -eu

if [ "$#" -ne 2 ]; then
  echo "사용법: sh render-dashboards.sh <project 라벨> <폴더/표시 이름>" >&2
  echo "예:     sh render-dashboards.sh hondigagae Hondigagae" >&2
  exit 1
fi

PROJECT="$1"
TITLE="$2"

case "$PROJECT" in
  *[!a-z0-9-]* | '')
    echo "project 라벨은 소문자·숫자·하이픈만 씁니다: $PROJECT" >&2
    exit 1
    ;;
esac
case "$TITLE" in
  *[!A-Za-z0-9-]* | '')
    echo "폴더 이름은 영문·숫자·하이픈만 씁니다 (Grafana 폴더명이 됩니다): $TITLE" >&2
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/dashboard-templates/spring-docker"
OUT_DIR="$SCRIPT_DIR/dashboards/$TITLE"

mkdir -p "$OUT_DIR"

count=0
for template in "$TEMPLATE_DIR"/*.template.json; do
  name="$(basename "$template" .template.json)"
  sed -e "s/__PROJECT_TITLE__/$TITLE/g" -e "s/__PROJECT__/$PROJECT/g" "$template" > "$OUT_DIR/$name.json"
  count=$((count + 1))
done

if grep -l "__PROJECT" "$OUT_DIR"/*.json >/dev/null 2>&1; then
  echo "치환되지 않은 자리표시자가 남았습니다:" >&2
  grep -l "__PROJECT" "$OUT_DIR"/*.json >&2
  exit 1
fi

echo "$count 개 대시보드를 $OUT_DIR 에 만들었습니다."
