#!/usr/bin/env bash
# PreInvocation (Antigravity 전용): 파일 수정 직후 쌓인 소프트 리밋 알림을 다음 모델 호출 직전에 넣는다.
# Antigravity의 PostToolUse는 에이전트에게 피드백을 돌려줄 수 없어서 이렇게 한 단계 늦게 전달한다.
HARNESS_EVENT=invoke; source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
f="$PROJ/.harness/state/pending-notes"
if [ -s "$f" ]; then
  jq -Rs '{injectSteps: [{ephemeralMessage: ("[하네스 알림]\n" + .)}]}' < "$f"; : > "$f"
else
  echo '{}'
fi
exit 0
