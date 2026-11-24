#!/usr/bin/env bash
# PreToolUse / BeforeTool (파일 수정): 보호 파일 수정 차단. 파일이 속한 작업 트리(worktree 포함) 기준으로 판정.
HARNESS_EVENT=pre; source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  d="$(dirname "$f")"; while [ ! -d "$d" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done
  top="$(h_tree "$d")"
  list="$top/.harness/protected-paths.txt"; [ -f "$list" ] || list="$PROJ/.harness/protected-paths.txt"
  [ -f "$list" ] || continue
  rel="${f#"$top"/}"
  while IFS= read -r pat || [ -n "$pat" ]; do
    case "$pat" in ''|'#'*) continue ;; esac
    # shellcheck disable=SC2254
    case "$rel" in
      $pat) h_block "차단됨(guard-paths): '$rel'은 보호 대상($pat)입니다." \
                    "합격 기준 테스트·검사 장치·마이그레이션 이력은 고쳐서 통과시키지 말고 구현을 고치세요. 기준 자체가 틀렸다면 사용자에게 알리세요." ;;
    esac
  done < "$list"
done < <(h_files)
h_pass
