# 도구별 차이 — Claude Code · Gemini CLI · Codex · Antigravity · ChatGPT

하네스의 내용(검사·규칙·문서)은 같고, **어디에 적고 어떻게 연결하는지**만 다르다. `scripts/install.sh`가 아래 차이를 처리하므로, 이 문서는 설치 결과를 이해하거나 손으로 고칠 때 본다.

## 한눈에 보기

| 항목 | Claude Code | Gemini CLI | Codex (CLI·IDE·ChatGPT 데스크톱) | Antigravity (앱·IDE·CLI) |
|---|---|---|---|---|
| 프로젝트 매뉴얼 | `CLAUDE.md` → `@AGENTS.md` 불러오기 | `GEMINI.md` → `@AGENTS.md` 불러오기 | `AGENTS.md`를 직접 읽음 | `AGENTS.md`를 직접 읽음 |
| Hook 설정 파일 | `.claude/settings.json` | `.gemini/settings.json` | `.codex/hooks.json` | `.agents/hooks.json` (최상위 키가 그룹 이름: `pre-code-harness`) |
| 셸 명령 도구 | `Bash` | `run_shell_command` | `Bash` | `run_command` (`args.CommandLine`) |
| 파일 수정 도구 | `Edit` `Write` `MultiEdit` (`tool_input.file_path`) | `write_file` `replace` (`tool_input.file_path`) | `apply_patch` (경로가 **패치 텍스트 안**에 있음: `*** Update File: <경로>`) | `write_to_file` `replace_file_content` `multi_replace_file_content` (`args.TargetFile`) |
| 실행 전 차단 | `PreToolUse` | `BeforeTool` | `PreToolUse` | `PreToolUse` → JSON `{"decision":"deny"}` |
| 실행 후 알림 | `PostToolUse` | `AfterTool` | `PostToolUse` | `PostToolUse`는 피드백 불가 → 알림을 쌓아 두고 `PreInvocation`(notes.sh)이 다음 모델 호출 직전에 넣음 |
| "끝"을 막는 게이트 | `Stop` (exit 2 → 계속) | `AfterAgent` (exit 2 → 자동 재시도) | `Stop` (exit 2 → 이어서 작업) | `Stop` → JSON `{"decision":"continue","reason":...}` |
| 세션 시작 브리핑 | `SessionStart` stdout | `SessionStart` JSON `hookSpecificOutput.additionalContext` | `SessionStart` stdout | `SessionStart` JSON `injectSteps[].systemMessage` |
| 완료 게이트가 읽는 마지막 메시지 | `last_assistant_message` | `prompt_response` | `last_assistant_message` | 없음 → 항상 전체 검사 |
| Hook 시간 제한 단위 | 초 | 밀리초 (기본 60000) | 초 (기본 600) | 초 (기본 30) |
| 프로젝트 경로 변수 | `$CLAUDE_PROJECT_DIR` | `$GEMINI_PROJECT_DIR` | 없음 → `git rev-parse --show-toplevel` | 없음 → `git rev-parse --show-toplevel`. 입력에 `cwd`가 없어 `args.Cwd`·`workspacePaths[0]` 사용 |
| 스킬 설치 | 플러그인 마켓플레이스 / `npx skills add` | `gemini extensions install` / `npx skills add` | `codex plugin marketplace add` / `npx skills add` | `agy plugin install <GitHub 주소>` / `npx skills add -a antigravity` |
| 처음 실행할 때 | `/hooks`로 확인 | `/hooks`로 확인. 버전에 따라 Hook·Skills를 설정에서 켜야 함 | 프로젝트 신뢰(trust) + `/hooks`에서 새 Hook 검토·신뢰. 안 하면 **실행되지 않는다** | CLI `/hooks`, 앱·IDE Customizations > Hooks |
| 권한 차단 목록 | `permissions.deny` | `tools.exclude` 등 (이 스킬은 Hook으로 처리) | 승인·샌드박스 정책 (이 스킬은 Hook으로 처리) | 권한 정책 (이 스킬은 Hook으로 처리) |
| 검수 에이전트 | `.claude/agents/reviewer.md` | 서브에이전트(미리보기 기능) 또는 `gemini -p "$(cat .harness/reviewer.md)"` | 서브에이전트 또는 `codex exec "$(cat .harness/reviewer.md)"` | 서브에이전트 또는 다른 도구의 비대화형 세션 |

Claude Code·Gemini CLI·Codex는 Hook에 stdin JSON(`session_id`, `cwd`, `tool_name`, `tool_input` 등)을 주고, **exit 2 + stderr**를 "막고 이유를 에이전트에게 전달"로 해석한다. Antigravity는 camelCase JSON(`conversationId`, `workspacePaths`, `toolCall.name`, `toolCall.args`)을 주고, 종료 코드 대신 **stdout JSON의 `decision`**으로 판정한다. `.harness/hooks/lib.sh`가 입력 모양으로 도구를 알아내(또는 설정의 `HARNESS_FORMAT=antigravity`) 읽기·응답 방식을 맞추므로 같은 스크립트를 네 도구가 함께 쓴다. Antigravity Stop 입력에는 `stop_hook_active`가 없어서, 완료 게이트 카운터는 통과하거나 상한(`STOP_GATE_MAX`)에 닿을 때만 비운다.

## 공통 구조 (설치 결과)

```
<프로젝트>/
├── AGENTS.md                 하네스 구역(<!-- harness:start --> ~ end)이 들어간 공통 매뉴얼
├── CLAUDE.md / GEMINI.md     @AGENTS.md 한 줄 (기존 내용은 그대로)
├── PROGRESS.md  DECISIONS.md
├── .harness/
│   ├── hooks/                lib.sh, guard-bash.sh, guard-paths.sh, code-limits.sh, test-guard.sh, stop-gate.sh, session-brief.sh, notes.sh
│   ├── checks.sh             완료 기준의 단일 출처 (빠른 검사 / 전체 검사)
│   ├── protected-paths.txt   (finalize 단계에서 설치)
│   ├── limits-baseline.txt   (finalize 단계에서 기록)
│   ├── test-guard-allow.txt  (finalize 단계에서 생성, 사람이 관리)
│   ├── reviewer.md  workflow.md
│   └── state/                (gitignore) 카운터·로그·ask-user·loop-report·pending-notes
├── .claude/settings.json  .claude/agents/reviewer.md
├── .gemini/settings.json
├── .codex/hooks.json
└── .agents/hooks.json        (Antigravity)
```

Hook 명령은 모두 `bash "<경로>/.harness/hooks/x.sh"` 형태다. `bash`로 직접 부르므로 zip을 풀어 실행 권한이 사라져도 동작한다.

## 손으로 확인하는 법

```bash
bash <스킬 폴더>/scripts/selftest.sh          # 이 컴퓨터에서 네 도구 입력 형식 모두 시험 (임시 폴더 사용)
jq empty .claude/settings.json .gemini/settings.json .codex/hooks.json .agents/hooks.json
bash .harness/checks.sh; echo $?
```

## ChatGPT (웹·모바일 채팅, Work)

채팅의 ChatGPT는 사용자 컴퓨터의 저장소에 직접 파일을 쓰거나 Hook을 실행할 수 없다. 이때는 SKILL.md의 "번들 모드"로 동작한다. 0단계 진단 질문으로 내용을 채운 파일 묶음(zip)을 만들어 주고, 사용자가 저장소에서 `install.sh --overlay`로 적용한다. Hook이 실제로 도는 곳은 이후 사용자가 쓰는 Codex·Claude Code·Gemini CLI·Antigravity다.

## 참고 문서
- Claude Code Hooks: https://code.claude.com/docs/en/hooks
- Gemini CLI Hooks: https://geminicli.com/docs/hooks/reference/
- Codex Hooks: https://learn.chatgpt.com/docs/hooks
- Antigravity Hooks: https://antigravity.google/docs/hooks
- Agent Skills 규격: https://agentskills.io/specification
