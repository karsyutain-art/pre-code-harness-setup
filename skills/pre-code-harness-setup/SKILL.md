---
name: pre-code-harness-setup
description: 코드를 쓰기 전에 하네스(AGENTS.md 출근·퇴근 절차, PROGRESS/DECISIONS.md, 위험 명령·보호 파일 차단 Hook, 코드 크기 소프트/하드 리밋, 검수 에이전트), 루프(완료 기준 checks.sh와 완료 게이트 Hook), 그래프(단계·조건부 되돌림·사람 승인)를 프로젝트에 먼저 깔아둔다. Claude Code·Gemini CLI·Codex·Antigravity·ChatGPT에서 쓴다. 새 프로젝트나 기능 개발을 시작할 때, "바이브 코딩 시작 전 세팅", "하네스/Hook 설정", "루프 엔지니어링", "그래프 엔지니어링", "AI가 DB 지우지 못하게", "다 됐다는데 안 돼 있어", "테스트 통과할 때까지 알아서 돌게", "세션 넘어가면 맥락을 잃어", "파일이 너무 커져" 같은 요청이 오면 이름을 부르지 않아도 사용한다.
license: MIT
compatibility: bash, git, jq가 필요하다. Hook 자동 설치는 Claude Code·Gemini CLI·Codex·Antigravity를 지원하고, 저장소에 직접 접근할 수 없는 채팅(ChatGPT 웹 등)에서는 적용용 파일 묶음을 만든다.
metadata:
  version: "1.2.0"
  author: karsyutain-art
---

# 코딩 전 하네스·루프·그래프 세팅

프롬프트와 컨텍스트만으로는 두 가지가 해결되지 않는다. **규칙을 알려줘도 어기는 것**(→ 하네스)과 **"다 됐다"는 판정을 사람이 계속 해야 하는 것**(→ 루프). 일이 여러 단계로 얽히면 **어디서 틀렸는지 모르고 전부 다시 하는 것**(→ 그래프)이 더해진다. 이 스킬은 코드를 한 줄 쓰기 전에 세 장치를 프로젝트에 깔아두고, 이후 작업이 그 안에서 돌게 한다.

```
그래프  ─ 전체 업무 지도 (순서·조건·되돌릴 곳·사람 승인)
 └ 루프  ─ 한 작업을 완료 기준 통과까지 반복
    └ 하네스 ─ 작업이 도는 환경 (매뉴얼·도구·Hook)
```

판단이 애매할 때 돌아올 원칙:
1. **부탁보다 차단.** 매뉴얼(AGENTS.md)은 "부탁"이라 놓칠 수 있다. 정말 막아야 하는 건 Hook·권한·읽기 전용 계정처럼 AI 바깥에서 막는다.
2. **판정은 말이 아니라 실행 결과로.** "완료"는 테스트·린트·빌드 같은 명령의 종료 코드로 정한다. 만든 AI 본인의 "다 됐어요"는 판정이 아니다.
3. **경로는 설계가 정한다.** 순서가 중요한 일은 문서·코드로 고정된 경로를 따른다. 되돌릴 수 없는 일(돈·외부 발송·운영 배포·삭제) 앞에는 사람 승인을 둔다.

## 이 스킬의 파일

| 파일 | 용도 |
|---|---|
| `scripts/install.sh` | 대상 프로젝트에 하네스를 깐다. 기존 설정은 병합하고, 여러 번 실행해도 같다 |
| `scripts/selftest.sh` | 이 컴퓨터에서 Hook이 네 도구 입력 형식 모두에 맞게 도는지 임시 폴더에서 시험한다 |
| `scripts/hooks/` | 공통 Hook (`lib.sh`가 Claude Code·Gemini CLI·Codex·Antigravity의 입력·출력 차이를 맞춘다) |
| `assets/` | AGENTS.md·PROGRESS.md·DECISIONS.md·checks.sh·reviewer.md·workflow.md·보호 목록 템플릿, 도구별 Hook 설정 |
| `references/tools.md` | 도구별 차이 (파일 이름, Hook 이벤트, 신뢰 절차) |
| `references/limits.md` | 코드 크기 리밋 상세, 린터 설정, 기존 코드 기준선 |
| `references/graph.md` | workflow.md, n8n·LangGraph 선택과 골격 |
| `references/related-skills.md` | 기획·계획·TDD·코드 리뷰 스킬과 함께 쓸 때 역할 나누기 |

아래에서 `<스킬>`은 이 스킬 폴더의 경로다.

---

## 0단계 — 환경 확인과 진단

**먼저 어디서 실행 중인지 본다.**
- **셸로 대상 저장소에 접근할 수 있다** (Claude Code, Gemini CLI, Codex CLI·IDE, ChatGPT 데스크톱의 Codex, Antigravity 앱·IDE·CLI) → 일반 모드. 아래 단계를 그대로 한다.
- **저장소에 접근할 수 없다** (ChatGPT 웹·모바일 채팅 등) → **번들 모드**(6단계). 진단은 질문으로 하고, 결과는 적용용 파일 묶음으로 준다.

**설치할 도구**를 정한다. 지금 실행 중인 도구는 항상 포함하고, 저장소에 `.claude/`·`.gemini/`·`.codex/`·`.agents/hooks.json`·`CLAUDE.md`·`GEMINI.md`가 있으면 그 도구도 넣는다. 팀이 여러 도구를 쓰면 함께 넣는다(`--tools claude,gemini,codex,antigravity`).

**저장소를 먼저 살펴** 물을 것을 줄인다.
- 언어·패키지 매니저·프레임워크, 테스트·린트·빌드 명령 (package.json 스크립트, Makefile의 `check`/`test`, CI 설정)
- 린터 설정 (ESLint·Ruff 등) — 함수 단위 리밋을 걸 곳
- 이미 리밋을 넘은 큰 파일 (`git ls-files | xargs wc -l | sort -n | tail`)
- 이미 있는 것: AGENTS.md, CLAUDE.md, GEMINI.md, `.claude/`·`.gemini/`·`.codex/`·`.agents/hooks.json` 설정, `.harness/`
- git 여부와 작업 트리 상태, `jq` 설치 여부
- 되돌릴 수 없는 접점: DB, 외부 API, 결제, 배포 (`.env.example`, 마이그레이션 폴더, 배포 스크립트)
- 기획 문서(spec)가 있는지 — 있으면 목표·완료 기준은 거기서 가져온다

그다음 **알 수 없는 것만 한 번에** 묻는다(질문 도구가 있으면 사용, 최대 3~4개).
- 이번에 만들 기능/목표 (아직 말하지 않았다면)
- **가장 무서운 실수 한 가지** (예: 운영 DB 삭제, `.env` 노출, main 강제 푸시)
- **완료 기준**을 측정 가능한 문장으로 (예: "`npm test` 통과 + 375px에서 가로 스크롤 없음")
- 단계가 여러 개이고 **사람이 승인해야 하는 지점**이 있는지

사용자가 자리에 없거나 "알아서 해"라고 하면 저장소에서 읽은 값으로 정하고, 보고에 "이렇게 가정했다"를 적는다.

### 규모에 맞게 고르기

| 상황 | 하네스 | 루프 | 그래프 |
|---|---|---|---|
| 작은 수정·단일 기능 | 매뉴얼 + 위험 명령 차단 | 완료 기준 + 완료 게이트 | 생략 |
| 일반 기능 개발 (테스트 있음) | 전체 | 전체 + reviewer | 가벼운 workflow.md |
| 여러 단계·여러 담당·사람 승인 | 전체 | 전체 | workflow.md + (필요하면) n8n/LangGraph |
| 테스트가 아직 없음 | 전체 | **합격 기준 테스트부터 작성** 후 루프 | 상황에 따라 |

다른 스킬(기획·계획·TDD·코드 리뷰·코딩 규칙)이 함께 설치돼 있으면 `references/related-skills.md`를 읽고 역할을 나눈다.

---

## 1단계 — 하네스 설치

**시작 전 안전장치.** git 저장소가 아니면 `git init`을 제안하고, 있으면 현재 상태를 커밋하거나 사용자에게 알린다. 세팅 자체도 되돌릴 수 있어야 한다.

설치 전에 이 컴퓨터에서 Hook이 제대로 도는지 한 번 확인한다(임시 폴더에서 시험하므로 프로젝트는 건드리지 않는다).

```bash
bash <스킬>/scripts/selftest.sh
bash <스킬>/scripts/install.sh --target <프로젝트> --tools <도구 목록>
```

`install.sh`가 하는 일 (자세한 결과물은 `references/tools.md`):
- `.harness/hooks/`에 공통 Hook 복사, `.harness/checks.sh`·`reviewer.md`·`workflow.md` 템플릿 생성
- `AGENTS.md`에 하네스 구역 추가(없으면 생성), `CLAUDE.md`·`GEMINI.md`는 `@AGENTS.md`로 같은 매뉴얼을 불러오게 함
- `PROGRESS.md`·`DECISIONS.md` 생성
- 도구별 Hook 설정 **병합**: `.claude/settings.json`, `.gemini/settings.json`, `.codex/hooks.json`, `.agents/hooks.json`(Antigravity, `pre-code-harness` 그룹) — 기존 항목은 보존하고 같은 명령은 중복 추가하지 않는다
- Claude Code면 `.claude/agents/reviewer.md`, 그리고 `.gitignore`에 `.harness/state/`
- 이미 있는 문서·검사 파일은 **절대 덮어쓰지 않는다**

### 1-1. 매뉴얼 채우기 — AGENTS.md

설치된 하네스 구역의 `<...>`를 진단 결과로 채운다: 구조, 가장 무서운 실수, 자주 쓰는 명령. 이 구역에는 이미 다음이 들어 있다.
- **출근 절차**: PROGRESS.md·DECISIONS.md 읽기 → `bash .harness/checks.sh`로 일관성 확인(실패하면 기록하고 알림) → "다음 단계"에서 이어가기
- **퇴근 절차**: PROGRESS.md 갱신, 중요 결정은 DECISIONS.md에 → 완료 게이트가 checks.sh 통과를 확인 → 통과한 작업만 작은 단위로 커밋, push는 사용자 확인 후
- **사용자에게 묻는 멈춤**: 검사 실패 중에도 사람의 결정이 필요하면 `.harness/state/ask-user`에 질문을 적고 끝낸다
- **코드 크기와 재사용 규칙**, 검수 방법, "반복된 실수" 칸

짧고 구체적으로 둔다. 특정 상황에만 필요한 긴 절차는 매뉴얼에 넣지 말고 별도 스킬로 뺀다.

**검사 명령은 하나로.** 매뉴얼·완료 게이트·CI가 모두 `.harness/checks.sh` 하나를 가리킨다. `make check`를 새로 만들지 않는다 — make가 없는 환경이 있고, 검사 목록이 두 곳에 생기면 어긋난다. 이미 `make check`가 있으면 checks.sh가 그것을 부르게 한다.

### 1-2. 차단 장치 — Hook이 하는 일

| Hook | 언제 | 하는 일 |
|---|---|---|
| guard-bash | 셸 명령 실행 직전 | DB 삭제·`rm -rf`·강제 push·`reset --hard` 같은 되돌릴 수 없는 명령을 막는다 |
| guard-paths | 파일 수정 직전 | 보호 목록(합격 기준 테스트, 검사 장치, 기준선)의 수정을 막는다. 테스트를 고쳐서 통과시키는 꼼수 방지 |
| code-limits | 파일 수정 직후 | 이번 변경으로 생긴 소프트 리밋 초과를 알린다 (Antigravity는 다음 모델 호출 직전에 notes.sh가 전달) |
| session-brief | 세션 시작 | PROGRESS.md·DECISIONS.md·진행 기록 요약을 넣는다 (출근 절차를 "부탁"이 아니라 자동으로) |
| stop-gate | "끝났다"고 할 때 | checks.sh가 통과해야 끝낼 수 있다 (2단계) |

guard-bash의 패턴은 프로젝트에 맞게 조정한다. 예를 들어 테스트에서 `DELETE FROM`을 정당하게 쓰면 그 패턴은 빼고 DB 계정 권한으로 막는다. 권한보다 더 확실한 건 **AI 바깥에서 능력 자체를 빼는 것**이다. 개발용 읽기 전용 DB 계정, 테스트용 결제 키만 `.env`에 두라고 사용자에게 권한다(실제 키나 비밀번호를 대신 입력하지 않는다).

guard-paths는 파일 수정 도구만 막는다. 셸(`sed -i` 등)로 우회할 수 있으므로 reviewer가 두 번째 방어선이다.

### 1-3. 코드 크기 소프트/하드 리밋

AI는 기존 코드를 찾아 쓰기보다 새로 쓰는 쪽으로 기울어 파일과 함수가 커진다. **소프트 = 알림, 하드 = 완료 차단**.

| 항목 | 소프트 | 하드 |
|---|---|---|
| 파일 길이 | 300줄 | 500줄 |
| 함수 길이 | 40줄 | 80줄 |
| 매개변수 | 4 | 6 |
| 중첩 깊이 | 3 | 4 |
| 순환 복잡도 | 10 | 15 |

파일 길이는 code-limits가 처리한다. 함수 단위 하드 리밋은 **프로젝트 린터 설정에 error로** 걸고 checks.sh에 린트 명령을 넣는다. 린터 설정은 사용자 코딩 규칙과 공유해서 한 벌만 둔다. 설정 예시, 린터가 없을 때의 처리, 기존 코드 기준선은 `references/limits.md`를 읽고 따른다. 수치는 출발점이니 사용자와 조정하고 DECISIONS.md에 기록한다.

---

## 2단계 — 루프 세팅

사람 지시 → AI 작업 → 사람 검수 → 재지시의 핑퐁을, AI 작업 → 기계 검사 → AI 수정 → 재검사 → 통과 시 보고로 바꾼다. 세 요소를 모두 정한다.

| 요소 | 나쁜 예 | 좋은 예 |
|---|---|---|
| 성공 기준 | "완벽해질 때까지" | "`npm test` 통과 + 메인 버튼 클릭 시 콘솔 에러 0 + 375px 가로 스크롤 없음" |
| 검증자 | 만든 AI의 "다 됐어요" | 명령의 종료 코드, 별도 reviewer, 실제 사용자 |
| 종료 조건 | "될 때까지" | "통과하면 종료, 5회 실패하면 멈추고 원인 보고" |

### 2-1. checks.sh — 완료 기준의 단일 출처

성공 기준을 **실행 가능한 명령**으로 바꿔 `.harness/checks.sh`에 모은다. 템플릿에는 파일 길이 리밋이 이미 들어 있다. 진단에서 찾은 린트·타입 검사·테스트 명령을 넣는다. 말로만 된 기준("모바일에서 깨지지 않게")은 가능한 한 명령으로 바꾸고(Playwright 뷰포트 테스트, 스크린샷 비교, 숫자 검산), 명령으로 못 바꾸는 기준은 `.harness/reviewer.md`에 항목으로 넣는다.

**테스트가 없다면**: 기능 코드보다 먼저 합격 기준 테스트를 작성하고(실패하는 상태 확인), 보호 목록에 넣는다. 보호하는 것은 이 합격 기준 테스트뿐이다 — 구현 중 쓰는 단위 테스트는 설계와 함께 바뀌어야 하므로 보호하지 않는다.

테스트가 오래 걸리면 checks.sh에는 빠른 검사만 두고 느린 E2E는 reviewer 단계나 CI로 보낸다. 끝낼 때마다 몇 분씩 기다리면 루프가 오히려 느려진다.

### 2-2. 완료 게이트 — stop-gate

에이전트가 끝내려는 순간(Claude Code·Codex·Antigravity의 Stop, Gemini CLI의 AfterAgent) checks.sh를 돌리고, 실패하면 로그와 함께 돌려보낸다.
- **무한 루프 방지**: 세션별 실패 카운터, 상한(`STOP_GATE_MAX`, 기본 5) 초과 시 끝내고 `.harness/state/loop-report.md`에 기록
- **코드 변경이 없는 턴은 생략**: 질문·설명, 문서(`.md`·`docs/`)만 바뀐 턴. 기획 단계에서 사용자에게 묻지 못하는 일을 막는다
- **사용자에게 묻는 멈춤**: `.harness/state/ask-user`에 질문을 적으면 한 번 통과하고 기록을 남긴다. guard-bash가 "사용자에게 직접 실행을 요청하라"고 할 때처럼 검사 실패 중에도 사람의 결정이 필요한 순간이 있다. 남용은 reviewer가 기록으로 확인한다
- **worktree 인식**: 지금 작업 중인 작업 트리(`.worktrees/` 포함)를 검사한다

### 2-3. reviewer — 만든 사람과 검사하는 사람 분리

`.harness/reviewer.md`가 검수 지시다. 수정 권한을 주지 않는다 — 고칠 수 있으면 검수가 아니라 또 하나의 작성자가 된다.
- Claude Code: `.claude/agents/reviewer.md` 서브에이전트(설치됨)
- Gemini CLI·Codex: 서브에이전트가 있으면 그것으로, 없으면 새 비대화형 세션(`gemini -p "$(cat .harness/reviewer.md)"`, `codex exec "$(cat .harness/reviewer.md)"`)
- 다른 회사 모델로 교차 검수하면 놓치는 지점이 달라 효과가 크다. 사용자 컴퓨터에 그 도구가 있을 때만 제안하고, 설치하지는 않는다

다른 검수(코드 리뷰 스킬, 코딩 규칙 스킬의 검토)가 있으면 겹치지 않게 범위를 줄인다(`references/related-skills.md`).

### 2-4. 시작 문구 준비

목표 조건을 걸어두면 스스로 계속 작업하는 모드(Claude Code의 `/goal` 등)가 있는 도구라면, 사용자가 복사해 쓸 문구를 만들어 준다.

```
다음을 모두 만족할 때까지 계속할 것:
1) bash .harness/checks.sh 가 종료 코드 0
2) reviewer 검수에서 '심각' 항목 0
3) <명령으로 못 바꾼 기준>
5번 시도해도 안 되면 멈추고 원인과 시도한 방법을 PROGRESS.md에 보고할 것.
```

사람 없이 돌리려면 도구의 권한·승인 모드가 따로 필요하다는 것도 알린다. 긴 작업이 맥락 흐림으로 무너질 것 같으면, 같은 지시서를 매번 새 세션에 주고 진행은 PROGRESS.md·git으로 이어받는 방식(Ralph 루프)을 안내하되 반드시 **횟수 제한과 완료 탈출 조건**을 넣는다.

---

## 3단계 — 그래프 세팅

여러 단계가 얽힌 일에서 실패 시 **문제 난 단계로만** 되돌아가게 하고, 되돌릴 수 없는 일 앞에 사람을 세운다. 단일 기능이면 건너뛴다.

`.harness/workflow.md` 템플릿의 노드·엣지·상태를 이번 기능에 맞게 채운다. 노드는 "단계"이지 task가 아니다 — 구현 계획이 있으면 구현 노드에는 계획 파일 경로만 적는다. 규칙으로 판정 가능한 일은 AI가 아니라 코드 노드에 맡긴다. 순서가 반드시 지켜져야 하면 n8n이나 LangGraph로 옮기라고 명시한다. 수준 선택과 LangGraph 골격은 `references/graph.md`.

---

## 4단계 — 마무리와 검증

1. checks.sh, AGENTS.md, workflow.md를 다 채운 **뒤에** 보호 목록과 기준선을 설치한다. 먼저 설치하면 세팅 도중 checks.sh를 고칠 때 스스로 막힌다.
   ```bash
   bash <스킬>/scripts/install.sh --target <프로젝트> --finalize
   ```
   보호 목록(`.harness/protected-paths.txt`)에 이번 프로젝트의 합격 기준 테스트 경로, 이미 적용된 마이그레이션을 추가한다. 이후 이 목록은 사람이 고친다.
2. 말로 "설정했다"가 아니라 실행해서 확인한다:
   ```bash
   jq empty .claude/settings.json .gemini/settings.json .codex/hooks.json .agents/hooks.json 2>&1   # 설치한 도구 것만
   bash .harness/checks.sh; echo "checks => $?"      # 테스트 작성 전이면 실패가 정상
   echo '{}' | bash .harness/hooks/session-brief.sh | head -3
   ```
   selftest를 이미 통과했다면 Hook 동작은 확인된 것이다. 프로젝트에 맞게 guard-bash 패턴을 바꿨다면 그 패턴으로 한 번 더 시험한다.
3. 세팅을 **커밋**한다(`.harness/`, AGENTS.md, CLAUDE.md, GEMINI.md, PROGRESS.md, DECISIONS.md, 도구 설정, `.agents/hooks.json`). worktree는 커밋된 파일만 가져간다.
4. 도구별로 사용자가 해야 할 일을 알린다:
   - Claude Code: 재시작하거나 `/hooks`로 등록 확인
   - Gemini CLI: 재시작 후 `/hooks` 확인. 버전에 따라 Hook·Skills를 설정에서 켜야 한다
   - Codex: 프로젝트를 신뢰(trust)하고 `/hooks`에서 새 Hook을 검토·신뢰해야 **실행된다**
   - Antigravity: CLI는 `/hooks`, 앱·IDE는 Customizations > Hooks에서 `pre-code-harness` 그룹이 보이는지 확인. Antigravity는 AGENTS.md를 직접 읽는다

Hook은 사용자 컴퓨터 권한 그대로 실행된다. 설치한 스크립트 목록과 하는 일을 보여준다.

---

## 5단계 — 보고와 넘기기

코딩을 시작하기 전에 짧게 보고한다.
1. **무엇을 깔았나** — 표 하나: 파일 / 역할 / 강제력(부탁·차단·판정)
2. **검증 결과** — 실제 출력 요약 (selftest 통과 수, checks.sh 결과)
3. **가정한 것** — 묻지 않고 정한 것 (완료 기준, 리밋 수치, 재시도 한도)
4. **시작 문구** — 바로 쓸 목표 문구 또는 첫 지시
5. **남은 위험** — 막지 못한 것 (셸로 보호 파일 우회 가능 → reviewer가 확인, 운영 DB 계정 권한은 사용자가 직접 낮춰야 함, Codex Hook 신뢰 전에는 미작동, Antigravity의 수정 직후 알림은 한 단계 늦게 전달)

그다음 사용자가 원하면 workflow.md의 첫 노드부터 시작한다. 작업 중 AI가 같은 실수를 반복하면 AGENTS.md "반복된 실수"에 한 줄, 정말 막아야 하면 Hook 패턴에 추가한다 — 하네스는 한 번에 완성하는 게 아니라 실수가 나올 때마다 자란다.

---

## 6단계 — 번들 모드 (저장소에 접근할 수 없을 때)

ChatGPT 웹·모바일 채팅처럼 사용자의 저장소에 셸로 접근할 수 없으면:
1. 0단계 진단을 질문으로 한다. 사용자가 package.json·디렉터리 구조 등을 붙여넣거나 올려주면 그것을 읽는다.
2. 작업 공간에 `harness-bundle/` 폴더를 만들고, 진단 결과로 채운 파일을 **프로젝트에 놓일 경로 그대로** 둔다: `AGENTS.md`, `.harness/checks.sh`, `.harness/workflow.md`, `.harness/protected-paths.txt`, `PROGRESS.md`, `DECISIONS.md`.
3. 이 스킬의 `scripts/`와 `assets/`를 `harness-bundle/harness-setup/`에 복사하고, zip으로 묶어 사용자에게 준다.
4. 적용 방법을 알려준다 (사용자가 저장소 루트에서 실행):
   ```bash
   unzip harness-bundle.zip -d /tmp/hb
   bash /tmp/hb/harness-bundle/harness-setup/scripts/selftest.sh
   bash /tmp/hb/harness-bundle/harness-setup/scripts/install.sh --target . --tools <쓰는 도구> --overlay /tmp/hb/harness-bundle
   bash /tmp/hb/harness-bundle/harness-setup/scripts/install.sh --target . --finalize --overlay /tmp/hb/harness-bundle
   ```
   `--overlay`의 파일은 템플릿 대신 쓰이고, 저장소에 이미 있는 문서는 덮어쓰지 않는다. Hook은 이후 사용자가 쓰는 Codex·Claude Code·Gemini CLI·Antigravity에서 돈다.

---

## 증상 → 보강할 곳 (세팅 이후)

| 증상 | 보강 |
|---|---|
| 하지 말라는 걸 함 | guard-bash 패턴, AI 바깥 권한 축소 |
| "다 됐다"는데 안 돼 있음 | checks.sh에 측정 가능한 기준 추가, reviewer |
| 끝없이 고치다 엉망 | `STOP_GATE_MAX` 낮추기, 성공 기준 구체화 |
| 테스트를 고쳐서 통과시킴 | 보호 목록 등록, reviewer의 diff 점검 |
| 어디서 틀렸는지 모름 | workflow.md 단계 분리, 단계별 판정, PROGRESS.md 기록 |
| 새 세션이 이전 작업·결정을 모름 | PROGRESS.md "다음 단계" 구체화, DECISIONS.md 기록, session-brief Hook 확인 |
| 파일·함수가 계속 커지고 비슷한 코드가 반복됨 | 소프트 리밋 낮추기, 중복 탐지 추가 (`references/limits.md`) |
| 리밋 때문에 루프가 레거시를 고치느라 헛돎 | 기준선 다시 기록 — 사람이 |
| AI가 중요한 결정을 혼자 내림 | workflow.md에 사람 승인 노드 추가 |
| 질문해야 하는데 완료 게이트 때문에 멈추지 못함 | ask-user 사용법이 AGENTS.md에 있는지 확인 |
| worktree·특정 도구에서 Hook이 안 걸림 | 세팅이 커밋됐는지, Codex Hook 신뢰, `references/tools.md` |
| 검수가 여러 겹이라 느림·비쌈 | reviewer 범위 축소 (`references/related-skills.md`) |
