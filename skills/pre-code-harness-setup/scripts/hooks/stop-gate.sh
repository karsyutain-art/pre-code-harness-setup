#!/usr/bin/env bash
# 완료 게이트 — Stop (Claude Code·Codex·Antigravity) / AfterAgent (Gemini CLI).
# 에이전트가 끝내려 할 때 .harness/checks.sh를 돌리고, 통과해야 끝낼 수 있다.
#   · 마지막 메시지가 완료를 주장하면 전체 검사, 아니면 빠른 검사(--fast)만. 메시지를 주지 않는 도구는 항상 전체 검사
#   · 전체 검사를 통과한 뒤 코드가 그대로면 다시 돌리지 않는다
#   · 실패한 단계(리밋·테스트 약화·그 밖)에 맞는 안내를 붙인다
HARNESS_EVENT=stop; source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ok() { h_pass; }
sid="$(h_session)"
active="$(h_get .stop_hook_active)"
[ "$HARNESS_FORMAT" = antigravity ] && active=true   # Antigravity엔 이 필드가 없다 → 통과·상한 도달 때만 카운터를 비운다
root="$(h_tree)"                                       # 지금 작업 중인 트리 (worktree면 그 worktree)
MAX="${STOP_GATE_MAX:-5}"
state="$PROJ/.harness/state"; mkdir -p "$state"
cnt="$state/stop-gate-$sid.count"; log="$state/stop-gate.log"; passed="$state/full-pass-tree"

# 1) 사용자 결정이 필요해서 멈추는 경우: 질문을 ask-user에 적었으면 한 번 통과 (기록은 남김)
if [ -s "$state/ask-user" ]; then
  { echo "## $(date '+%F %T') 사용자 확인 요청으로 멈춤 ($root)"; cat "$state/ask-user"; echo; } >> "$state/loop-report.md"
  rm -f "$state/ask-user" "$cnt"; ok
fi

# 2) 코드 변경이 없는 턴(질문·설명·문서·계획 작성)은 검사하지 않는다
if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
   && [ -z "$(git -C "$root" status --porcelain -- . ':(exclude).harness' ':(exclude).claude' ':(exclude).gemini' ':(exclude).codex' ':(exclude).agents' ':(exclude)*.md' ':(exclude)docs')" ]; then
  rm -f "$cnt"; ok
fi

# 3) 검사 범위: 완료를 주장하면 전체, 아니면 빠른 검사
msg="$(h_get '.last_assistant_message // .prompt_response')"
DONE_RE='완료|끝났|끝냈|마쳤|마무리|구현했|구현을 마|통과했|모두 통과|다 됐|해결했|수정했|done|complete|finished|implemented|all (tests|checks) pass|ready (for|to)|fixed|resolved'
if [ -z "$msg" ] || grep -qiE "$DONE_RE" <<<"$msg"; then mode=--full; else mode=--fast; fi

# 4) 전체 검사를 이미 통과한 상태 그대로면 다시 돌리지 않는다
tree_id() { { git -C "$root" rev-parse HEAD 2>/dev/null; git -C "$root" diff HEAD 2>/dev/null
              git -C "$root" ls-files -o --exclude-standard -z 2>/dev/null | (cd "$root" && xargs -0 -r sha1sum 2>/dev/null); } | sha1sum | cut -c1-40; }
now_id="$(tree_id)"
[ -f "$passed" ] && [ "$(cat "$passed")" = "$now_id" ] && { rm -f "$cnt"; ok; }

[ "$active" = "true" ] || echo 0 > "$cnt"
n="$(cat "$cnt" 2>/dev/null || echo 0)"

checks="$root/.harness/checks.sh"; [ -f "$checks" ] || checks="$PROJ/.harness/checks.sh"
if (cd "$root" && bash "$checks" "$mode") >"$log" 2>&1; then
  rm -f "$cnt"; [ "$mode" = --full ] && echo "$now_id" > "$passed"; ok
fi

n=$((n + 1)); echo "$n" > "$cnt"
if [ "$n" -gt "$MAX" ]; then
  { echo "## $(date '+%F %T') 루프 중단: 완료 기준을 ${MAX}회 넘게 통과하지 못함 ($root)"; tail -n 40 "$log"; echo; } >> "$state/loop-report.md"
  rm -f "$cnt"; ok
fi

failed="$(sed -n 's/^\[harness-failed\] //p' "$log" | tail -n 1)"
case "$failed" in
  limits) hint="코드 크기 하드 리밋을 넘었습니다. 책임별로 파일·함수를 나누세요. 줄을 억지로 합치지 마세요.
생성 코드·데이터 표처럼 나눌 수 없는 정당한 이유가 있으면, 사용자에게 예외(.harness/limits-baseline.txt 등록) 승인을 요청하세요(.harness/state/ask-user)." ;;
  test-guard) hint="테스트를 약화한 변경이 있습니다. 테스트가 아니라 구현을 고치세요.
의도한 변경이면 그 줄에 'harness-allow-test-change: <이유>' 주석을, 삭제·이동이면 사용자에게 .harness/test-guard-allow.txt 등록을 요청하세요." ;;
  *) hint="아래 로그를 보고 구현을 고친 뒤 다시 끝내세요. 테스트를 지우거나 약화하지 마세요." ;;
esac
h_block "$(
  echo "아직 완료가 아닙니다: 완료 기준(.harness/checks.sh $mode)의 '${failed:-검사}' 단계 실패 ($n/$MAX, $root)."
  echo "$hint"
  echo "사용자의 결정·직접 실행이 필요해서 멈추는 것이라면, 질문을 .harness/state/ask-user 에 적고 끝내세요."
  [ "$n" -eq "$MAX" ] && echo "마지막 시도입니다. 이번에도 실패하면 원인·시도한 방법을 PROGRESS.md에 정리하세요."
  tail -n 30 "$log"
)"
