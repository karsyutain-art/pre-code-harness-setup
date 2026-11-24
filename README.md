# pre-code-harness-setup

[![skills.sh](https://skills.sh/b/karsyutain-art/pre-code-harness-setup)](https://skills.sh/karsyutain-art/pre-code-harness-setup)

AI 코딩 에이전트가 **코드를 쓰기 전에** 프로젝트에 세 가지 장치를 깔아 주는 Agent Skill입니다. Claude Code, Gemini CLI, Codex, ChatGPT에서 씁니다.

- **하네스** — 규칙을 알려주기만 하는 게 아니라 Hook으로 지키게 만듭니다
  - 공통 매뉴얼(AGENTS.md)에 출근·퇴근 절차를 넣고, PROGRESS.md·DECISIONS.md로 세션 사이에 맥락을 넘깁니다
  - DB 삭제·강제 push 같은 위험 명령과, 합격 기준 테스트 같은 보호 파일 수정을 실행 전에 막습니다
  - 코드 크기 소프트/하드 리밋으로 파일·함수가 비대해지는 것을 막습니다
- **루프** — "다 됐다"를 AI의 말이 아니라 `.harness/checks.sh`의 결과로 판정합니다. 통과할 때까지 끝내지 못하고, 횟수 제한과 사용자 질문 통로가 있습니다
- **그래프** — 작업을 단계로 나누고, 실패하면 문제 난 단계로만 되돌리며, 되돌릴 수 없는 일 앞에는 사람 승인을 둡니다

## 설치

### 모든 에이전트 공통 (skills CLI)
```bash
npx skills add karsyutain-art/pre-code-harness-setup
# 특정 에이전트만: -a claude-code / -a codex / -a gemini-cli
```

### Claude Code
```
/plugin marketplace add karsyutain-art/pre-code-harness-setup
/plugin install pre-code-harness-setup@pre-code-harness
```

### Codex (CLI·IDE·ChatGPT 데스크톱의 Codex)
```bash
codex plugin marketplace add karsyutain-art/pre-code-harness-setup
```
추가한 뒤 Codex의 플러그인 목록에서 `pre-code-harness-setup`을 설치합니다.

### Gemini CLI
```bash
gemini extensions install https://github.com/karsyutain-art/pre-code-harness-setup
```
버전에 따라 Agent Skills와 Hook이 실험 기능이면 설정에서 켜야 합니다.

### ChatGPT (웹·데스크톱)
[`dist/pre-code-harness-setup.zip`](https://github.com/karsyutain-art/pre-code-harness-setup/raw/main/dist/pre-code-harness-setup.zip)을 받아 ChatGPT의 스킬 화면에서 업로드합니다. 채팅의 ChatGPT는 사용자 저장소에 직접 쓸 수 없으므로, 진단 결과로 채운 **적용용 파일 묶음(zip)**을 만들어 줍니다. 저장소에서 안내된 `install.sh` 명령을 실행하면 적용됩니다.

## 사용

에이전트에게 이렇게 말하면 스킬이 동작합니다.
> 이 프로젝트에 새 기능 만들기 전에 하네스부터 세팅해줘

에이전트는 저장소를 진단하고(테스트·린트 명령, 큰 파일, 위험한 접점), 꼭 필요한 것만 묻고(가장 무서운 실수, 완료 기준), 다음을 설치합니다.

```
AGENTS.md (+ CLAUDE.md / GEMINI.md → @AGENTS.md)   PROGRESS.md   DECISIONS.md
.harness/hooks/     위험 명령·보호 파일 차단, 코드 크기 리밋, 완료 게이트, 출근 브리핑
.harness/checks.sh  완료 기준의 단일 출처
.claude/settings.json · .gemini/settings.json · .codex/hooks.json   (기존 설정에 병합)
```

설치 스크립트를 직접 쓸 수도 있습니다.
```bash
bash skills/pre-code-harness-setup/scripts/selftest.sh                       # 이 컴퓨터에서 동작 확인
bash skills/pre-code-harness-setup/scripts/install.sh --target . --tools claude,gemini,codex
# checks.sh·AGENTS.md를 채운 뒤
bash skills/pre-code-harness-setup/scripts/install.sh --target . --finalize   # 보호 목록·기준선
```

**Codex 사용자:** 프로젝트 Hook은 프로젝트를 신뢰(trust)하고 `/hooks`에서 검토·신뢰해야 실행됩니다.

## 요구 사항
- bash, git, jq
- 함수 단위 소프트 리밋(선택): 프로젝트의 ESLint 또는 Ruff

## 도구별 Hook 대응

| | Claude Code | Gemini CLI | Codex |
|---|---|---|---|
| 실행 전 차단 | PreToolUse | BeforeTool | PreToolUse |
| 수정 후 알림 | PostToolUse | AfterTool | PostToolUse |
| 완료 게이트 | Stop | AfterAgent | Stop |
| 파일 경로 | `tool_input.file_path` | `tool_input.file_path` | `apply_patch` 패치 텍스트 안 |

`.harness/hooks/lib.sh`가 이 차이를 맞추므로 세 도구가 같은 스크립트를 씁니다. 자세한 내용은 [references/tools.md](skills/pre-code-harness-setup/references/tools.md)를 보세요.

## English summary

An Agent Skill that sets up guardrails **before** an AI coding agent writes code: a shared `AGENTS.md` manual with session start/end routines, hooks that block irreversible commands and edits to protected files (acceptance tests, check scripts), soft/hard code-size limits, a completion gate that won't let the agent stop until `.harness/checks.sh` passes, and an optional staged workflow with human approval points. The same hook scripts work with Claude Code, Gemini CLI and Codex; ChatGPT chat gets an apply-yourself bundle. Install with `npx skills add karsyutain-art/pre-code-harness-setup`.

## 라이선스
MIT
