#!/usr/bin/env bash
# SessionStart: 출근 브리핑. Claude Code·Codex는 stdout을 그대로, Gemini CLI는 JSON(--format gemini)으로 받는다.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
brief() {
  echo "[출근 브리핑] AGENTS.md의 '세션 시작(출근)' 절차를 따르세요."
  if [ -f "$PROJ/PROGRESS.md" ]; then echo "--- PROGRESS.md (앞 60줄)"; head -n 60 "$PROJ/PROGRESS.md"
  else echo "PROGRESS.md 없음: 첫 세션이면 템플릿으로 만드세요."; fi
  [ -f "$PROJ/DECISIONS.md" ] && { echo "--- DECISIONS.md 결정 목록 (최근 20개)"; grep -E '^## ' "$PROJ/DECISIONS.md" | tail -n 20; }
  ledger=$(ls -t "$PROJ"/.superpowers/sdd/*/progress.md "$PROJ"/.worktrees/*/.superpowers/sdd/*/progress.md 2>/dev/null | head -n 1)
  [ -n "$ledger" ] && { echo "--- 진행 중인 계획 ledger: ${ledger#"$PROJ"/} (마지막 10줄)"; tail -n 10 "$ledger"; }
  [ -s "$PROJ/.harness/state/loop-report.md" ] && { echo "--- 지난 루프 중단·질문 기록 (마지막 10줄)"; tail -n 10 "$PROJ/.harness/state/loop-report.md"; }
  git -C "$PROJ" log --oneline -5 2>/dev/null | sed 's/^/최근 커밋: /'
}
if [ "${1:-}" = "--format" ] && [ "${2:-}" = "gemini" ]; then
  brief | jq -Rs '{hookSpecificOutput: {additionalContext: .}}'
else
  brief
fi
exit 0
