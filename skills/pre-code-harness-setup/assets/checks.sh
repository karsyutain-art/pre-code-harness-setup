#!/usr/bin/env bash
# 완료 기준. 하나라도 실패하면 '완료 아님'. 실행한 위치의 작업 트리(worktree 포함)를 검사한다.
# Stop Hook · /goal · CI · 출근 체크가 모두 이 파일 하나를 본다. (make check가 이미 있으면 아래 대신 그것을 호출)
set -e
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
bash .harness/hooks/code-limits.sh --check   # 파일 길이 하드 리밋
# --- 프로젝트에 맞게 채운다 (0단계 진단 결과) ---
# npm run lint                                # 함수 단위 하드 리밋 포함
# npx tsc --noEmit
# npm test
# npx playwright test tests/acceptance        # E2E 합격 기준이 있으면
# make check
