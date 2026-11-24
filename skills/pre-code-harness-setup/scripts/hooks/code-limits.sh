#!/usr/bin/env bash
# 코드 크기 소프트/하드 리밋 (git worktree 안에서도 그 작업 트리 기준)
#   --hook     PostToolUse / AfterTool (파일 수정): 방금 고친 파일만. '이번 변경으로' 넘은 것만 알림 (원래 크던 것은 탓하지 않음)
#   --check    .harness/checks.sh에서: 작업 트리 전체. 하드 리밋 초과 시 실패 → Stop Hook이 '완료'를 막음
#   --baseline 도입 시 1회: 이미 하드 리밋을 넘은 파일을 현재 줄 수와 함께 기록 (이후 '더 늘리지만 않으면' 통과)
MODE="${1:---check}"; [ "$MODE" = "--hook" ] || export HARNESS_NO_STDIN=1
HARNESS_EVENT=post; source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SOFT="${LIMIT_FILE_SOFT:-300}"
HARD="${LIMIT_FILE_HARD:-500}"
FN_SOFT="${LIMIT_FN_SOFT:-40}"; ARGS_SOFT="${LIMIT_ARGS_SOFT:-4}"
DEPTH_SOFT="${LIMIT_DEPTH_SOFT:-3}"; CX_SOFT="${LIMIT_CX_SOFT:-10}"
EXT_RE='\.(js|jsx|ts|tsx|mjs|cjs|py|go|rb|java|kt|swift|rs|php|cs|vue|svelte)$'
SKIP_RE='(^|/)(node_modules|dist|build|vendor|migrations|__generated__|\.next|coverage)/|\.min\.|\.d\.ts$|_pb2\.py$'

is_src() { [[ "$1" =~ $EXT_RE ]] && ! [[ "$1" =~ $SKIP_RE ]]; }
count() { grep -cv '^[[:space:]]*$' "$1" 2>/dev/null || true; }   # 빈 줄은 세지 않는다
base_of() { [ -f "$root/.harness/limits-baseline.txt" ] && awk -F'\t' -v p="$1" '$1==p{print $2}' "$root/.harness/limits-baseline.txt"; }
list_src() { git -C "$root" ls-files -co --exclude-standard | while IFS= read -r r; do is_src "$r" && [ -f "$root/$r" ] && echo "$r"; done; }

# 함수 단위 소프트 리밋 경고를 "줄번호<TAB>규칙<TAB>메시지"로 출력 (stdin = 소스). 해당 린터가 있을 때만.
soft_lint() {
  case "$1" in
    *.py) command -v ruff >/dev/null || return 0
          (cd "$root" && ruff check --select C901,PLR0912,PLR0913,PLR0915 --no-fix --output-format concise \
            --config "lint.pylint.max-args = $ARGS_SOFT" --config "lint.mccabe.max-complexity = $CX_SOFT" \
            --config "lint.pylint.max-statements = 30" --stdin-filename "$1" 2>/dev/null) \
          | sed -nE 's/^[^:]+:([0-9]+):[0-9]+: ([A-Z0-9]+) (.*)/\1\t\2\t\3/p' ;;
    *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs) [ -x "$root/node_modules/.bin/eslint" ] || return 0
          (cd "$root" && node_modules/.bin/eslint --no-warn-ignored --format stylish \
            --rule "max-lines-per-function: [warn, {max: $FN_SOFT, skipBlankLines: true, skipComments: true}]" \
            --rule "max-params: [warn, $ARGS_SOFT]" --rule "max-depth: [warn, $DEPTH_SOFT]" \
            --rule "complexity: [warn, $CX_SOFT]" --stdin --stdin-filename "$1" 2>/dev/null) \
          | grep -E '(max-lines-per-function|max-params|max-depth|complexity)$' \
          | sed -E 's/^ *([0-9]+):[0-9]+ +warning +(.*[^ ]) +([a-z-]+)$/\1\t\3\t\2/' ;;
  esac
}
# 경고마다 "규칙|그 줄의 소스" 키를 붙인다 → 줄 번호가 밀려도 같은 경고로 인식
keyed() { awk -F'\t' 'NR==FNR{src[FNR]=$0; next} {t=src[$1]; gsub(/^[ \t]+|[ \t]+$/,"",t); print $2 "|" t "\tL" $1 " " $3}' "$1" -; }

check_one() {   # $1 = 절대 경로. 알릴 내용이 있으면 msg에 덧붙인다
  local f="$1" rel n b prev now old new tmp
  [ -f "$f" ] || return 0
  root="$(h_tree "$(dirname "$f")")"; rel="${f#"$root"/}"
  is_src "$rel" || return 0
  n=$(count "$f"); b=$(base_of "$rel")
  prev=$(git -C "$root" show "HEAD:$rel" 2>/dev/null | grep -cv '^[[:space:]]*$' || true); prev="${prev:-0}"   # 마지막 커밋의 줄 수 (새 파일이면 0)
  if [ -n "$b" ]; then
    [ "$n" -gt "$b" ] && msg+="하드 리밋: $rel 은(는) 기존 초과 파일인데 ${b}줄 → ${n}줄로 늘었습니다. 늘어난 코드는 별도 모듈로 빼세요."$'\n'
  elif [ "$n" -gt "$HARD" ]; then
    msg+="하드 리밋: $rel = ${n}줄 (> $HARD, 빈 줄 제외). 이대로면 완료 판정에서 실패합니다. 책임별로 모듈을 나누세요."$'\n'
  elif [ "$n" -gt "$SOFT" ] && { [ "$prev" -le "$SOFT" ] || [ "$n" -gt "$prev" ]; }; then
    msg+="소프트 리밋: $rel = ${n}줄 (> $SOFT, 마지막 커밋 ${prev}줄). 이번에 늘어난 부분을 나눌 수 있으면 나누고, 미룬다면 이유를 PROGRESS.md에 적으세요. 기존 코드를 이 김에 리팩터링하지는 마세요."$'\n'
  fi
  now=$(soft_lint "$rel" < "$f" | keyed "$f")
  if [ -n "$now" ]; then
    tmp=$(mktemp); git -C "$root" show "HEAD:$rel" > "$tmp" 2>/dev/null
    old=$(soft_lint "$rel" < "$tmp" | keyed "$tmp" | cut -f1); rm -f "$tmp"
    new=$(awk -F'\t' 'NR==FNR{if($0!="")seen[$0]=1; next} !($1 in seen){print "  " $2}' <(printf '%s\n' "$old") <(printf '%s\n' "$now"))
    [ -n "$new" ] && msg+="소프트 리밋(함수, 이번 변경으로 생김) — $rel:"$'\n'"$new"$'\n'
  fi
}

case "$MODE" in
--hook)
  msg=""
  while IFS= read -r f; do check_one "$f"; done < <(h_files)
  [ -z "$msg" ] && h_pass
  h_block "$msg" "→ 재사용 가능한 단위(함수·모듈)로 나누는 것을 먼저 검토하세요. 비슷한 코드가 이미 있으면 새로 만들지 말고 그것을 쓰세요." ;;
--baseline)
  root="$(h_tree "$PWD")"; bl="$root/.harness/limits-baseline.txt"; : > "$bl"
  list_src | while IFS= read -r r; do n=$(count "$root/$r"); [ "$n" -gt "$HARD" ] && printf '%s\t%s\n' "$r" "$n" >> "$bl"; done
  echo "기존 하드 리밋 초과 파일 $(wc -l < "$bl" | tr -d ' ')개를 ${bl#"$root"/} 에 기록했습니다." ;;
--check)
  root="$(h_tree "$PWD")"; fail=0
  while IFS= read -r r; do
    n=$(count "$root/$r"); b=$(base_of "$r")
    if [ -n "$b" ]; then
      [ "$n" -gt "$b" ] && { echo "하드 리밋 위반: $r ${b}→${n}줄 (기존 초과 파일은 늘릴 수 없음)"; fail=1; }
    elif [ "$n" -gt "$HARD" ]; then
      echo "하드 리밋 위반: $r = ${n}줄 (> $HARD, 빈 줄 제외)"; fail=1
    fi
  done < <(list_src)
  exit $fail ;;
*) echo "사용법: code-limits.sh --hook|--check|--baseline" >&2; exit 64 ;;
esac
