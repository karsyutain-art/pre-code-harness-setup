#!/usr/bin/env bash
# 하네스 Hook 공통 라이브러리 — Claude Code · Gemini CLI · Codex(ChatGPT) 입력을 같은 모양으로 읽는다.
#   Claude Code : Bash / Edit·Write·MultiEdit(tool_input.file_path)            / Stop
#   Gemini CLI  : run_shell_command / write_file·replace(tool_input.file_path)  / AfterAgent
#   Codex       : Bash / apply_patch(tool_input.command 안의 패치 텍스트)        / Stop
# 모든 도구가 stdin JSON에 cwd·session_id를 주고, exit 2 + stderr를 "막고 이유 전달"로 해석한다.

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # <프로젝트>/.harness
PROJ="$(dirname "$HARNESS_DIR")"                                   # 하네스가 설치된 프로젝트 루트
HARNESS_INPUT=""
# Hook으로 불릴 때만 stdin(JSON)을 읽는다. 터미널·checks.sh에서 직접 부르면 읽지 않는다.
if [ -z "${HARNESS_NO_STDIN:-}" ] && [ ! -t 0 ]; then HARNESS_INPUT="$(cat 2>/dev/null || true)"; fi

h_get() { jq -r "$1 // empty" <<<"$HARNESS_INPUT" 2>/dev/null; }
h_tool()  { h_get .tool_name; }
h_event() { h_get .hook_event_name; }
h_cwd()   { local c; c="$(h_get .cwd)"; [ -n "$c" ] && [ -d "$c" ] && echo "$c" || echo "$PWD"; }
h_tree()  { git -C "${1:-$(h_cwd)}" rev-parse --show-toplevel 2>/dev/null || echo "$PROJ"; }

# 셸 명령 문자열 (apply_patch의 패치 텍스트는 명령이 아니므로 제외)
h_command() {
  case "$(h_tool)" in apply_patch|Edit|Write|MultiEdit|write_file|replace) return 0 ;; esac
  jq -r '.tool_input.command // empty | if type=="array" then join(" ") else . end' <<<"$HARNESS_INPUT" 2>/dev/null
}

# 이번 도구 호출이 건드리는 파일들(절대 경로, 한 줄에 하나)
h_files() {
  local cwd p; cwd="$(h_cwd)"
  {
    jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' <<<"$HARNESS_INPUT" 2>/dev/null
    if [ "$(h_tool)" = "apply_patch" ]; then
      jq -r '.tool_input.command // .tool_input.patch // .tool_input.input // empty | if type=="array" then join("\n") else . end' <<<"$HARNESS_INPUT" 2>/dev/null \
        | sed -nE 's/^\*\*\* (Add|Update|Delete) File: (.+)$/\2/p; s/^\*\*\* Move to: (.+)$/\1/p'
    fi
  } | while IFS= read -r p; do
    [ -z "$p" ] && continue
    case "$p" in /*) echo "$p" ;; *) echo "$cwd/$p" ;; esac
  done
}

h_block() { printf '%s\n' "$@" >&2; exit 2; }   # 막고 이유를 에이전트에게 전달
