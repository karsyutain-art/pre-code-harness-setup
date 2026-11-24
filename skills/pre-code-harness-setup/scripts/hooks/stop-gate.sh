#!/usr/bin/env bash
# Stop (Claude Code·Codex) / AfterAgent (Gemini CLI): 완료 기준(.harness/checks.sh)을 통과해야 멈출 수 있다.
# 세 도구 모두 exit 2 + stderr를 "아직 끝나지 않았다, 이 내용을 보고 계속하라"로 처리한다.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ok() { echo '{}'; exit 0; }   # Codex는 exit 0일 때 stdout이 JSON이어야 한다
sid="$(h_get .session_id)"; sid="${sid:-default}"
active="$(h_get .stop_hook_active)"
root="$(h_tree)"                                   # 지금 작업 중인 트리 (worktree면 그 worktree)
MAX="${STOP_GATE_MAX:-5}"
state="$PROJ/.harness/state"; mkdir -p "$state"
cnt="$state/stop-gate-$sid.count"; log="$state/stop-gate.log"

# 1) 사용자 결정이 필요해서 멈추는 경우: 질문을 ask-user에 적었으면 한 번 통과 (기록은 남김)
if [ -s "$state/ask-user" ]; then
  { echo "## $(date '+%F %T') 사용자 확인 요청으로 멈춤 ($root)"; cat "$state/ask-user"; echo; } >> "$state/loop-report.md"
  rm -f "$state/ask-user" "$cnt"; ok
fi

# 2) 코드 변경이 없는 턴(질문·설명·문서·계획 작성)은 검사하지 않는다
if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
   && [ -z "$(git -C "$root" status --porcelain -- . ':(exclude).harness' ':(exclude).claude' ':(exclude).gemini' ':(exclude).codex' ':(exclude)*.md' ':(exclude)docs')" ]; then
  rm -f "$cnt"; ok
fi

[ "$active" = "true" ] || echo 0 > "$cnt"
n="$(cat "$cnt" 2>/dev/null || echo 0)"

checks="$root/.harness/checks.sh"; [ -f "$checks" ] || checks="$PROJ/.harness/checks.sh"
if (cd "$root" && bash "$checks") >"$log" 2>&1; then rm -f "$cnt"; ok; fi

n=$((n + 1)); echo "$n" > "$cnt"
if [ "$n" -gt "$MAX" ]; then
  { echo "## $(date '+%F %T') 루프 중단: 완료 기준을 ${MAX}회 넘게 통과하지 못함 ($root)"; tail -n 40 "$log"; echo; } >> "$state/loop-report.md"
  rm -f "$cnt"; ok
fi
{
  echo "아직 완료가 아닙니다: 완료 기준(.harness/checks.sh) 미통과 ($n/$MAX, $root)."
  echo "아래 로그를 보고 구현을 고친 뒤 다시 끝내세요. 테스트를 지우거나 약화하지 마세요."
  echo "사용자의 결정·직접 실행이 필요해서 멈추는 것이라면, 질문을 .harness/state/ask-user 에 적고 끝내세요."
  [ "$n" -eq "$MAX" ] && echo "마지막 시도입니다. 이번에도 실패하면 원인·시도한 방법을 PROGRESS.md에 정리하세요."
  tail -n 30 "$log"
} >&2
exit 2
