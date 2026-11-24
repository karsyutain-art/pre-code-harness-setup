#!/usr/bin/env bash
# PreToolUse / BeforeTool (셸): 되돌릴 수 없는 명령 차단. 패턴은 프로젝트에 맞게 조정한다.
HARNESS_EVENT=pre; source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cmd="$(h_command)"; [ -n "$cmd" ] || h_pass
if grep -qiE '(drop[[:space:]]+(table|database|schema)|truncate[[:space:]]+table|delete[[:space:]]+from|rm[[:space:]]+-[a-z]*r[a-z]*f|rm[[:space:]]+-[a-z]*f[a-z]*r|git[[:space:]]+push[[:space:]].*(--force|-f)|git[[:space:]]+reset[[:space:]]+--hard)' <<<"$cmd"; then
  h_block "차단됨(guard-bash): 되돌릴 수 없는 명령입니다 → $cmd" \
          "데이터·이력을 지우지 않는 다른 방법을 찾으세요. 꼭 필요하면 사용자에게 직접 실행을 요청하세요(요청 내용을 .harness/state/ask-user 에 적고 멈추기)."
fi
h_pass
