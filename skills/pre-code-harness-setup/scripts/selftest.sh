#!/usr/bin/env bash
# 이 컴퓨터에서 하네스 Hook이 Claude Code · Gemini CLI · Codex · Antigravity 입력 형식 모두에 맞게 동작하는지 검사한다.
# 임시 폴더에 가짜 저장소를 만들어 시험하므로 실제 프로젝트는 건드리지 않는다.
#   사용법: bash selftest.sh        (실패가 하나라도 있으면 종료 코드 1)
set -u
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for bin in jq git bash; do command -v "$bin" >/dev/null || { echo "필요한 도구가 없습니다: $bin"; exit 1; }; done
T="$(mktemp -d)"; trap 'cd /; git -C "$T" worktree prune >/dev/null 2>&1' EXIT
cd "$T" && git init -q -b main && git config user.email t@t && git config user.name t
mkdir -p tests/acceptance src && echo t > tests/acceptance/a.spec.ts && touch src/.keep
bash "$SKILL_DIR/scripts/install.sh" --target "$T" --tools claude,gemini,codex,antigravity >/dev/null
sed -i '$i step broken test ! -f src/broken' .harness/checks.sh   # 전체 검사 구역 끝에 시험용 기준 추가
git add -A && git commit -qm setup && bash "$SKILL_DIR/scripts/install.sh" --target "$T" --finalize >/dev/null && git add -A && git commit -qm fin
H="$T/.harness/hooks"; pass=0; fail=0
t() { local name="$1" exp="$2" hook="$3"; shift 3
  local rc; printf '%s' "$INPUT" | bash "$H/$hook" "$@" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$exp" ]; then pass=$((pass+1)); printf '  ✓ %s\n' "$name"; else fail=$((fail+1)); printf '  ✗ %s (종료 코드 %s, 기대 %s)\n' "$name" "$rc" "$exp"; fi; }

echo "[위험 명령 차단]"
INPUT=$(jq -n '{tool_name:"Bash",tool_input:{command:"git reset --hard"}}');                       t "Claude Code Bash" 2 guard-bash.sh
INPUT=$(jq -n '{tool_name:"run_shell_command",tool_input:{command:"psql -c \"DROP TABLE users\""}}'); t "Gemini run_shell_command" 2 guard-bash.sh
INPUT=$(jq -n '{tool_name:"Bash",tool_input:{command:["git","push","--force"]}}');                  t "Codex Bash(배열 명령)" 2 guard-bash.sh
INPUT=$(jq -n '{tool_name:"Bash",tool_input:{command:"npm test"}}');                                t "일반 명령은 통과" 0 guard-bash.sh
echo "[보호 파일 차단]"
INPUT=$(jq -n --arg f "$T/tests/acceptance/a.spec.ts" '{tool_name:"Edit",tool_input:{file_path:$f}}'); t "Claude Code Edit" 2 guard-paths.sh
INPUT=$(jq -n --arg c "$T" '{tool_name:"write_file",cwd:$c,tool_input:{file_path:"tests/acceptance/b.spec.ts"}}'); t "Gemini write_file(상대 경로)" 2 guard-paths.sh
INPUT=$(jq -n --arg c "$T" '{tool_name:"apply_patch",cwd:$c,tool_input:{command:"*** Begin Patch\n*** Update File: src/a.ts\n*** Update File: .harness/checks.sh\n*** End Patch"}}'); t "Codex apply_patch(패치 안의 경로)" 2 guard-paths.sh
INPUT=$(jq -n --arg c "$T" '{tool_name:"apply_patch",cwd:$c,tool_input:{command:"*** Begin Patch\n*** Add File: src/x.ts\n*** End Patch"}}'); t "일반 파일은 통과" 0 guard-paths.sh
echo "[코드 크기 리밋]"
seq 1 350 | sed 's|^|// l |' > src/big.js
INPUT=$(jq -n --arg f "$T/src/big.js" '{tool_name:"Write",tool_input:{file_path:$f}}');             t "소프트 리밋 알림(Claude Code)" 2 code-limits.sh --hook
INPUT=$(jq -n --arg c "$T" '{tool_name:"apply_patch",cwd:$c,tool_input:{command:"*** Begin Patch\n*** Add File: src/big.js\n*** End Patch"}}'); t "소프트 리밋 알림(Codex)" 2 code-limits.sh --hook
seq 1 520 | sed 's|^|// l |' > src/big.js
(cd "$T" && bash "$H/code-limits.sh" --check >/dev/null 2>&1); rc=$?; INPUT='{}'
[ "$rc" = 1 ] && { pass=$((pass+1)); echo "  ✓ 하드 리밋 초과 시 --check 실패"; } || { fail=$((fail+1)); echo "  ✗ 하드 리밋 --check (종료 코드 $rc, 기대 1)"; }
git -C "$T" checkout -q -- . 2>/dev/null; git -C "$T" clean -qfd src 2>/dev/null
echo "[완료 게이트]"
INPUT=$(jq -n --arg c "$T" '{session_id:"s",cwd:$c}');                                               t "변경 없음 → 통과" 0 stop-gate.sh
touch "$T/src/broken"
INPUT=$(jq -n --arg c "$T" '{hook_event_name:"Stop",session_id:"c",stop_hook_active:false,cwd:$c}');  t "Claude Code·Codex Stop: 검사 실패 → 계속" 2 stop-gate.sh
INPUT=$(jq -n --arg c "$T" '{hook_event_name:"AfterAgent",session_id:"g",stop_hook_active:false,cwd:$c}'); t "Gemini AfterAgent: 검사 실패 → 재시도" 2 stop-gate.sh
echo "확인 필요" > "$T/.harness/state/ask-user";                                                     t "ask-user 한 번 통과" 0 stop-gate.sh
                                                                                                    t "그 뒤엔 다시 막힘" 2 stop-gate.sh
echo "[worktree]"
rm -f "$T/src/broken"
echo ".worktrees/" >> .gitignore; git add -A >/dev/null; git commit -qm wt; git worktree add -q .worktrees/f -b f
W="$T/.worktrees/f"; touch "$W/src/broken"
INPUT=$(jq -n --arg c "$W" '{session_id:"w",stop_hook_active:false,cwd:$c}');                         t "worktree 안의 실패를 잡음" 2 stop-gate.sh
INPUT=$(jq -n --arg f "$W/tests/acceptance/a.spec.ts" '{tool_name:"Edit",tool_input:{file_path:$f}}'); t "worktree 안의 보호 파일을 막음" 2 guard-paths.sh
echo "[출근 브리핑]"
out=$(echo '{}' | bash "$H/session-brief.sh" --format gemini | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | head -1)
case "$out" in *출근*) pass=$((pass+1)); echo "  ✓ Gemini용 JSON 출력";; *) fail=$((fail+1)); echo "  ✗ Gemini용 JSON 출력";; esac

echo "[Antigravity (JSON decision 방식)]"
rm -f "$W/src/broken"
ag() { local name="$1" want="$2" hook="$3"; shift 3   # want: 출력 JSON에 대한 jq 조건
  local out; out=$(printf '%s' "$INPUT" | HARNESS_FORMAT=antigravity bash "$H/$hook" "$@" 2>/dev/null)
  if [ $? = 0 ] && jq -e "$want" <<<"$out" >/dev/null 2>&1; then pass=$((pass+1)); printf '  ✓ %s\n' "$name"
  else fail=$((fail+1)); printf '  ✗ %s (출력: %s)\n' "$name" "$out"; fi; }
INPUT=$(jq -n --arg c "$T" '{conversationId:"a",workspacePaths:[$c],toolCall:{name:"run_command",args:{CommandLine:"git reset --hard",Cwd:$c}}}')
ag "run_command 위험 명령 → deny" '.decision=="deny"' guard-bash.sh
INPUT=$(jq -n --arg c "$T" '{conversationId:"a",workspacePaths:[$c],toolCall:{name:"run_command",args:{CommandLine:"npm test",Cwd:$c}}}')
ag "일반 명령 → allow" '.decision=="allow"' guard-bash.sh
INPUT=$(jq -n --arg c "$T" --arg f "$T/tests/acceptance/a.spec.ts" '{conversationId:"a",workspacePaths:[$c],toolCall:{name:"replace_file_content",args:{TargetFile:$f}}}')
ag "replace_file_content 보호 파일 → deny" '.decision=="deny"' guard-paths.sh
seq 1 350 | sed 's|^|// l |' > "$T/src/ag.js"
INPUT=$(jq -n --arg c "$T" --arg f "$T/src/ag.js" '{conversationId:"a",workspacePaths:[$c],toolCall:{name:"write_to_file",args:{TargetFile:$f}}}')
ag "write_to_file 소프트 리밋 → {} 반환" '. == {}' code-limits.sh --hook
INPUT='{"conversationId":"a"}'
ag "다음 호출 직전에 알림 삽입(PreInvocation)" '.injectSteps[0].ephemeralMessage | test("소프트 리밋")' notes.sh
ag "알림은 한 번만" '. == {}' notes.sh
rm -f "$T/src/ag.js"; touch "$T/src/broken"
INPUT=$(jq -n --arg c "$T" '{conversationId:"s1",workspacePaths:[$c],executionNum:1,terminationReason:"model_stop"}')
ag "Stop: 검사 실패 → continue" '.decision=="continue" and (.reason|test("완료 기준"))' stop-gate.sh
rm -f "$T/src/broken"
ag "Stop: 통과 → 멈춤 허용" '.decision!="continue"' stop-gate.sh
INPUT='{"conversationId":"a"}'
ag "SessionStart 브리핑 삽입" '.injectSteps[0].systemMessage.systemMessage | test("출근")' session-brief.sh --format antigravity
jq -e 'has("pre-code-harness")' "$T/.agents/hooks.json" >/dev/null && { pass=$((pass+1)); echo "  ✓ .agents/hooks.json 그룹 설치"; } || { fail=$((fail+1)); echo "  ✗ .agents/hooks.json 그룹 설치"; }

echo "[빠른 검사·전체 검사 구분]"
rm -f "$T/src/broken" "$W/src/broken"; cd "$T"
touch "$T/src/broken"; rm -f "$T/.harness/state/full-pass-tree"
INPUT=$(jq -n --arg c "$T" '{hook_event_name:"Stop",session_id:"m1",stop_hook_active:false,cwd:$c,last_assistant_message:"질문이 하나 있습니다. 어느 쪽으로 할까요?"}')
t "완료 주장 없음 → 빠른 검사만 → 통과" 0 stop-gate.sh
INPUT=$(jq -n --arg c "$T" '{hook_event_name:"Stop",session_id:"m2",stop_hook_active:false,cwd:$c,last_assistant_message:"구현을 완료했습니다."}')
t "완료 주장 → 전체 검사 → 실패" 2 stop-gate.sh
INPUT=$(jq -n --arg c "$T" '{hook_event_name:"AfterAgent",session_id:"m3",stop_hook_active:false,cwd:$c,prompt_response:"All tests pass, done."}')
t "Gemini prompt_response 완료 주장 → 전체 검사" 2 stop-gate.sh
rm -f "$T/src/broken"; echo "x" > "$T/src/new.txt"
INPUT=$(jq -n --arg c "$T" '{hook_event_name:"Stop",session_id:"m4",stop_hook_active:false,cwd:$c,last_assistant_message:"완료"}')
t "전체 검사 통과" 0 stop-gate.sh
before=$(stat -c %Y "$T/.harness/state/stop-gate.log" 2>/dev/null); sleep 1
t "코드 그대로면 다시 돌리지 않음(통과)" 0 stop-gate.sh
after=$(stat -c %Y "$T/.harness/state/stop-gate.log" 2>/dev/null)
[ "$before" = "$after" ] && { pass=$((pass+1)); echo "  ✓ 검사를 실제로 건너뜀"; } || { fail=$((fail+1)); echo "  ✗ 검사를 건너뛰지 않음"; }
rm -f "$T/src/new.txt"
echo "[실패 원인별 안내]"
seq 1 520 | sed 's|^|// l |' > "$T/src/huge.js"
out=$(jq -n --arg c "$T" '{session_id:"h1",stop_hook_active:false,cwd:$c,last_assistant_message:"완료"}' | bash "$H/stop-gate.sh" 2>&1 >/dev/null)
grep -q "하드 리밋" <<<"$out" && grep -q "ask-user" <<<"$out" && { pass=$((pass+1)); echo "  ✓ 리밋 실패 → 예외 승인 안내"; } || { fail=$((fail+1)); echo "  ✗ 리밋 실패 안내"; }
rm -f "$T/src/huge.js"
printf "test.skip('a', () => {});\n" > "$T/tests/acceptance/b.spec.ts"
out=$(jq -n --arg c "$T" '{session_id:"h2",stop_hook_active:false,cwd:$c,last_assistant_message:"잠깐 확인"}' | bash "$H/stop-gate.sh" 2>&1 >/dev/null)
grep -q "harness-allow-test-change" <<<"$out" && { pass=$((pass+1)); echo "  ✓ 테스트 약화 → 빠른 검사에서도 막고 안내"; } || { fail=$((fail+1)); echo "  ✗ 테스트 약화 안내"; }
rm -f "$T/tests/acceptance/b.spec.ts"
echo "[테스트 약화 탐지]"
g() { local name="$1" exp="$2"; (cd "$T" && bash "$H/test-guard.sh" >/dev/null 2>&1); local rc=$?
  [ "$rc" = "$exp" ] && { pass=$((pass+1)); printf '  ✓ %s\n' "$name"; } || { fail=$((fail+1)); printf '  ✗ %s (종료 코드 %s, 기대 %s)\n' "$name" "$rc" "$exp"; }; }
echo '{}' | bash "$H/session-brief.sh" >/dev/null   # 세션 시작 = 기준점
g "변경 없음" 0
git -C "$T" rm -q tests/acceptance/a.spec.ts; g "테스트 파일 삭제 → 막음" 1
git -C "$T" commit -qm "rm test"; g "세션 중 커밋한 삭제도 막음" 1
echo 'tests/acceptance/a.spec.ts' >> "$T/.harness/test-guard-allow.txt"; g "사람이 허용 목록에 넣으면 통과" 0
echo "[검사 명령 자동 감지]"
D="$(mktemp -d)"; echo '{"scripts":{"lint":"eslint .","test":"vitest run"}}' > "$D/package.json"; touch "$D/pnpm-lock.yaml"
out=$(bash "$SKILL_DIR/scripts/detect-checks.sh" "$D" --fast; bash "$SKILL_DIR/scripts/detect-checks.sh" "$D" --full)
grep -q "step lint pnpm lint" <<<"$out" && grep -q "step test pnpm test" <<<"$out" && { pass=$((pass+1)); echo "  ✓ package.json·pnpm 감지"; } || { fail=$((fail+1)); echo "  ✗ package.json 감지: $out"; }

echo; echo "결과: 통과 $pass, 실패 $fail"
[ "$fail" = 0 ]
