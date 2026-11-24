# 그래프 엔지니어링 — 단계·조건부 되돌림·사람 승인

여러 단계가 얽힌 일에서 실패 시 **문제 난 단계로만** 되돌아가게 하고, 되돌릴 수 없는 일 앞에 사람을 세운다. 단일 기능이면 건너뛴다.

## workflow.md

`.harness/workflow.md`(설치 시 템플릿 생성)에 노드·엣지·상태를 적는다.
- 노드는 "단계"이지 task가 아니다. 구현 계획(task 목록)이 있으면 구현 노드에는 계획 파일 경로만 적는다.
- 각 노드의 담당을 AI / 코드 / 사람 중에서 고른다. **규칙으로 판정 가능한 일(금칙어, 스키마 검사, 숫자 검산)은 코드에** 맡기는 게 싸고 정확하다.
- 상태는 PROGRESS.md("현재 상태"의 현재 노드, "다음 단계")에 기록한다. 세션이 끊겨도 출근 절차가 이어받는다.

## 구현 수준 고르기

| 수준 | 언제 | 무엇을 만드나 |
|---|---|---|
| 가벼운 버전 (기본) | 개발 작업, 순서가 대체로 지켜지면 됨 | workflow.md + PROGRESS.md + AGENTS.md의 "단계 순서를 따를 것" |
| n8n / Make | 비개발자 운영, 외부 서비스 연결, 정기 실행 | 노드·엣지 표를 옮길 설계 메모 (IF/Switch=조건부 엣지, AI Agent 노드, Wait=사람 승인) |
| LangGraph | 순서가 **반드시** 지켜져야 하고 코드로 운영 | 아래 골격 |

가벼운 버전은 흐름을 AI가 판단하므로 가끔 단계를 건너뛸 수 있다. 순서가 깨지면 안 되는 업무라면 n8n이나 LangGraph로 옮기라고 명시한다 — 그래프 엔지니어링의 본질은 경로를 설계(코드)가 결정하는 것이다.

## LangGraph 골격

사용자가 코드 오케스트레이션을 원할 때만. 설치 전에 사용하는 버전의 API를 공식 문서로 확인한다.

```python
from typing import TypedDict
from langgraph.graph import StateGraph, END
from langgraph.types import interrupt, Command
from langgraph.checkpoint.memory import MemorySaver  # 운영은 Postgres 등 영속 저장소

class State(TypedDict, total=False):
    spec: str; code: str; review_ok: bool; review_note: str; retries: int; approved: bool

def implement(s): ...                     # AI 노드: review_note를 반영해 구현
def check(s):                             # 코드 노드: 규칙 판정
    ok = run_checks()                     # .harness/checks.sh 실행 결과
    return {"review_ok": ok, "retries": s.get("retries", 0) + 1}
def approve(s):                           # 사람 노드: 여기서 멈추고 상태 저장
    return {"approved": interrupt({"질문": "운영 배포할까요?"})}
def deploy(s): ...

g = StateGraph(State)
for n, f in [("implement", implement), ("check", check), ("approve", approve), ("deploy", deploy)]:
    g.add_node(n, f)
g.set_entry_point("implement")
g.add_edge("implement", "check")
g.add_conditional_edges("check",
    lambda s: "pass" if s["review_ok"] else ("give_up" if s["retries"] >= 3 else "fix"),
    {"pass": "approve", "fix": "implement", "give_up": END})   # 실패 시 구현 단계로만
g.add_conditional_edges("approve", lambda s: "go" if s["approved"] else "stop",
    {"go": "deploy", "stop": END})
g.add_edge("deploy", END)
app = g.compile(checkpointer=MemorySaver())
# cfg = {"configurable": {"thread_id": "feature-001"}}
# app.invoke({"retries": 0}, cfg)        → 승인 지점에서 멈춤
# app.invoke(Command(resume=True), cfg)  → 승인 후 그 자리에서 재개
```

## 체크리스트
- 각 노드 담당(AI/코드/사람)과 입출력이 정해졌는가
- 실패 시 **어디로** 돌아가는가, 재시도 한도와 포기 경로는
- 되돌릴 수 없는 일 앞에 사람 승인이 있는가
- 중간에 멈춰도 이어갈 수 있게 상태가 파일·DB에 남는가
