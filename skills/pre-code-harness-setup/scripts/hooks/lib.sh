#!/usr/bin/env bash
# 하네스 Hook 공통 라이브러리 — 네 도구의 입력·출력을 같은 모양으로 맞춘다.
#   Claude Code : Bash / Edit·Write·MultiEdit(tool_input.file_path)               / Stop       — exit 2 + stderr로 막음
#   Gemini CLI  : run_shell_command / write_file·replace(tool_input.file_path)     / AfterAgent — exit 2 + stderr로 막음
#   Codex       : Bash / apply_patch(tool_input.command 안의 패치 텍스트)           / Stop       — exit 2 + stderr로 막음
#   Antigravity : run_command(args.CommandLine) / write_to_file·replace_file_content·
#                 multi_replace_file_content(args.TargetFile) / Stop — stdout JSON의 decision으로 막음
# 각 Hook 스크립트는 source 전에 HARNESS_EVENT(pre|post|stop|start|invoke)를 정한다.

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # <프로젝트>/.harness
PROJ="$(dirname "$HARNESS_DIR")"                                   # 하네스가 설치된 프로젝트 루트
HARNESS_EVENT="${HARNESS_EVENT:-pre}"
HARNESS_INPUT=""
# Hook으로 불릴 때만 stdin(JSON)을 읽는다. 터미널·checks.sh에서 직접 부르면 읽지 않는다.
if [ -z "${HARNESS_NO_STDIN:-}" ] && [ ! -t 0 ]; then HARNESS_INPUT="$(cat 2>/dev/null || true)"; fi

h_get() { jq -r "$1 // empty" <<<"$HARNESS_INPUT" 2>/dev/null; }

# 출력 방식: antigravity(JSON decision) | exit2(나머지 세 도구). 설정의 HARNESS_FORMAT 또는 입력 모양으로 판단
if [ -z "${HARNESS_FORMAT:-}" ]; then
  if [ -n "$(h_get '.toolCall.name // .conversationId')" ]; then HARNESS_FORMAT=antigravity; else HARNESS_FORMAT=exit2; fi
fi

h_tool()    { h_get '.toolCall.name // .tool_name'; }
h_session() { local s; s="$(h_get '.conversationId // .session_id')"; echo "${s:-default}"; }
h_cwd()     { local c; c="$(h_get '.cwd // .toolCall.args.Cwd // .workspacePaths[0]')"; [ -n "$c" ] && [ -d "$c" ] && echo "$c" || echo "$PWD"; }
h_tree()    { git -C "${1:-$(h_cwd)}" rev-parse --show-toplevel 2>/dev/null || echo "$PROJ"; }

# 셸 명령 문자열 (파일 수정 도구의 내용은 명령이 아니므로 제외)
h_command() {
  case "$(h_tool)" in
    apply_patch|Edit|Write|MultiEdit|write_file|replace|write_to_file|replace_file_content|multi_replace_file_content) return 0 ;;
  esac
  jq -r '(.toolCall.args.CommandLine // .tool_input.command // empty) | if type=="array" then join(" ") else . end' <<<"$HARNESS_INPUT" 2>/dev/null
}

# 이번 도구 호출이 건드리는 파일들(절대 경로, 한 줄에 하나)
h_files() {
  local cwd p; cwd="$(h_cwd)"
  {
    jq -r '.toolCall.args.TargetFile // .tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' <<<"$HARNESS_INPUT" 2>/dev/null
    if [ "$(h_tool)" = "apply_patch" ]; then
      jq -r '.tool_input.command // .tool_input.patch // .tool_input.input // empty | if type=="array" then join("\n") else . end' <<<"$HARNESS_INPUT" 2>/dev/null \
        | sed -nE 's/^\*\*\* (Add|Update|Delete) File: (.+)$/\2/p; s/^\*\*\* Move to: (.+)$/\1/p'
    fi
  } | while IFS= read -r p; do
    [ -z "$p" ] && continue
    case "$p" in /*) echo "$p" ;; *) echo "$cwd/$p" ;; esac
  done
}

# 통과: 도구가 기대하는 "괜찮다" 응답을 내고 끝낸다
h_pass() {
  if [ "$HARNESS_FORMAT" = antigravity ]; then
    case "$HARNESS_EVENT" in pre) echo '{"decision":"allow"}' ;; stop) echo '{"decision":"stop"}' ;; *) echo '{}' ;; esac
  elif [ "$HARNESS_EVENT" = stop ]; then echo '{}'   # Codex는 Stop이 exit 0일 때 stdout이 JSON이어야 한다
  fi
  exit 0
}

# 막고 이유를 에이전트에게 전달한다
h_block() {
  local msg; msg="$(printf '%s\n' "$@")"
  if [ "$HARNESS_FORMAT" = antigravity ]; then
    case "$HARNESS_EVENT" in
      pre)  jq -n --arg r "$msg" '{decision:"deny", reason:$r}' ;;
      stop) jq -n --arg r "$msg" '{decision:"continue", reason:$r}' ;;
      post) # Antigravity의 PostToolUse는 피드백을 못 돌려준다 → 다음 모델 호출 직전(PreInvocation, notes.sh)에 넣는다
            mkdir -p "$PROJ/.harness/state"; printf '%s\n' "$msg" >> "$PROJ/.harness/state/pending-notes"; echo '{}' ;;
      *)    echo '{}' ;;
    esac
    exit 0
  fi
  printf '%s\n' "$msg" >&2; exit 2
}
