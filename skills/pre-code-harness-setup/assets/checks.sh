#!/usr/bin/env bash
# 완료 기준. 하나라도 실패하면 '완료 아님'. 실행한 위치의 작업 트리(worktree 포함)를 검사한다.
#   bash .harness/checks.sh           전체 검사 (빠른 검사 + 테스트·빌드) — 완료를 주장할 때, CI, 출근 체크
#   bash .harness/checks.sh --fast    빠른 검사만 (리밋·테스트 약화·린트·타입) — 작업 중간에 끝낼 때마다
# 완료 게이트 · /goal · CI · 출근 체크가 모두 이 파일 하나를 본다. 처음 내용은 detect-checks.sh가 자동으로 채웠다 — 확인하고 고친다.
MODE="${1:---full}"
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1
step() {   # step <이름> <명령...> — 실패하면 어느 단계인지 표시하고 멈춘다 (완료 게이트가 이 이름으로 안내를 고른다)
  local name="$1"; shift
  echo "[harness-step] $name: $*"
  "$@" || { echo "[harness-failed] $name"; exit 1; }
}

# ---------- 빠른 검사 (매번) ----------
step limits     bash .harness/hooks/code-limits.sh --check
step test-guard bash .harness/hooks/test-guard.sh
#@FAST@
[ "$MODE" = "--fast" ] && exit 0

# ---------- 전체 검사 (완료를 주장할 때) ----------
#@FULL@
exit 0
