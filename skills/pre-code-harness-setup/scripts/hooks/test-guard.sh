#!/usr/bin/env bash
# 테스트 약화 탐지 — .harness/checks.sh의 빠른 검사에서 돈다. 기준점 이후의 변경(커밋 + 아직 커밋 안 한 것)을 본다.
#   막음(높음): 테스트 파일 삭제, skip·only·xfail·ignore 표시 추가
#   경고(중간): 테스트 파일의 assertion 순감소, 느슨한 비교로 바꿈, 빈 catch·except pass 추가, 테스트를 끄는 설정
#   HARNESS_TEST_GUARD=strict 이면 중간도 막는다. =off 이면 검사하지 않는다.
# 의도한 변경이면:
#   - 그 줄에 `harness-allow-test-change: <이유>` 주석 → 통과(목록에 '허용됨'으로 표시, reviewer가 확인)
#   - 삭제·이동처럼 주석을 달 수 없으면 사람이 .harness/test-guard-allow.txt 에 경로(glob)를 적는다 (보호 파일)
# 기준점: $HARNESS_TEST_BASE → 기본 브랜치와의 merge-base(다른 브랜치일 때) → 세션 시작 시점(.harness/state/session-base) → HEAD
export HARNESS_NO_STDIN=1
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
[ "${HARNESS_TEST_GUARD:-on}" = off ] && exit 0
root="$(h_tree "$PWD")"; cd "$root" || exit 0
git rev-parse --verify -q HEAD >/dev/null || exit 0

valid() { [ -n "$1" ] && git rev-parse --verify -q "$1^{commit}" >/dev/null && git merge-base --is-ancestor "$1" HEAD 2>/dev/null; }
base=""
valid "${HARNESS_TEST_BASE:-}" && base="$HARNESS_TEST_BASE"
if [ -z "$base" ]; then
  cur="$(git symbolic-ref --short -q HEAD)"
  for def in main master; do
    if [ -n "$cur" ] && [ "$cur" != "$def" ] && git rev-parse --verify -q "$def" >/dev/null; then
      mb="$(git merge-base HEAD "$def" 2>/dev/null)"; valid "$mb" && { base="$mb"; break; }
    fi
  done
fi
[ -z "$base" ] && { sb="$(cat "$PROJ/.harness/state/session-base" 2>/dev/null)"; valid "$sb" && base="$sb"; }
[ -z "$base" ] && base=HEAD

TEST_RE='(^|/)(tests?|__tests__|spec|specs)/|[._-](test|spec)s?\.[A-Za-z0-9]+$|(^|/)test_[^/]*\.py$|_test\.(go|py)$|Tests?\.(java|kt|cs)$'
SKIP_RE='\.(skip|only)\(|\b(xit|xdescribe|xtest|fit|fdescribe)\(|@pytest\.mark\.(skip|skipif|xfail)|pytest\.skip\(|@unittest\.skip|\bt\.Skip(Now|f)?\(|#\[ignore\]|@(Disabled|Ignore)\b|\[(Ignore|Skip)\b|test\.todo\('
ASSERT_RE='\bexpect\(|\bassert|\bshould\b|\bt\.(Error|Fatal|Fail)|\brequire\.|\bAssert\.|assert_eq!|assert!\('
LOOSE_RE='\.toBeTruthy\(\)|\.toBeDefined\(\)|\.not\.toBeNull\(\)|\.toBeGreaterThanOrEqual\(0\)|assertIsNotNone|assert [A-Za-z_.]+ is not None$|assertTrue\(True\)'
STRICT_RE='\.toEqual\(|\.toStrictEqual\(|\.toBe\(|assertEqual|assert_eq!|==|\.toMatchObject\('
EMPTY_RE='catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{[[:space:]]*\}|except[^:]*:[[:space:]]*pass[[:space:]]*$'
CONF_RE='passWithNoTests|testPathIgnorePatterns|collect_ignore|--ignore=|"skip"[[:space:]]*:[[:space:]]*true|\bexclude.*test'
ALLOW_TAG='harness-allow-test-change'

allowed_path() {   # 사람이 관리하는 허용 목록
  local f="$1" list="$PROJ/.harness/test-guard-allow.txt" pat
  [ -f "$list" ] || return 1
  while IFS= read -r pat || [ -n "$pat" ]; do
    case "$pat" in ''|'#'*) continue ;; esac
    # shellcheck disable=SC2254
    case "$f" in $pat) return 0 ;; esac
  done < "$list"; return 1
}

high=() mid=() ok=()
# 1) 삭제·이름 변경으로 사라진 테스트 파일
while IFS=$'\t' read -r st a b; do
  case "$st" in
    D)  [[ "$a" =~ $TEST_RE ]] || continue
        if allowed_path "$a"; then ok+=("삭제 $a (허용 목록)"); else high+=("테스트 파일 삭제: $a"); fi ;;
    R*) [[ "$a" =~ $TEST_RE ]] && ! [[ "$b" =~ $TEST_RE ]] && { allowed_path "$a" && ok+=("이동 $a → $b (허용 목록)") || high+=("테스트 파일을 테스트가 아닌 경로로 옮김: $a → $b"); } ;;
  esac
done < <(git diff --name-status -M "$base" -- . ':(exclude).harness' 2>/dev/null)

# 2) 파일별로 추가·삭제된 줄 분석
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -e "$f" ] || continue   # 삭제된 파일은 1)에서 다뤘다
  is_test=0; [[ "$f" =~ $TEST_RE ]] && is_test=1
  if git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then diff="$(git diff -U0 "$base" -- "$f" 2>/dev/null)"
  else diff="$(sed 's/^/+ /' "$f" 2>/dev/null)"; fi   # 아직 git에 없는 새 파일: 모든 줄이 추가된 줄
  [ -n "$diff" ] || continue
  added="$(grep -E '^\+[^+]' <<<"$diff" | cut -c2-)"; removed="$(grep -E '^-[^-]' <<<"$diff" | cut -c2-)"
  if [ "$is_test" = 1 ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      if grep -q "$ALLOW_TAG" <<<"$line"; then ok+=("$f: $(sed -E 's/^[[:space:]]+//' <<<"$line" | cut -c1-80) (주석으로 허용)"); continue; fi
      grep -qE "$SKIP_RE" <<<"$line" && high+=("$f: skip/only 표시 추가 → $(sed -E 's/^[[:space:]]+//' <<<"$line" | cut -c1-80)")
      grep -qE "$EMPTY_RE" <<<"$line" && mid+=("$f: 빈 catch/except 추가 → $(sed -E 's/^[[:space:]]+//' <<<"$line" | cut -c1-80)")
    done <<<"$added"
    na=$(grep -cE "$ASSERT_RE" <<<"$added"); nr=$(grep -cE "$ASSERT_RE" <<<"$removed")
    if [ "$nr" -gt "$na" ] && ! grep -q "$ALLOW_TAG" <<<"$added"; then mid+=("$f: assertion 순감소 ($nr개 삭제, $na개 추가)"); fi
    if grep -qE "$LOOSE_RE" <<<"$added" && grep -qE "$STRICT_RE" <<<"$removed" && ! grep -q "$ALLOW_TAG" <<<"$added"; then
      mid+=("$f: 엄격한 비교를 느슨한 비교로 바꿈 (예: toEqual → toBeTruthy)")
    fi
  else
    case "$f" in
      package.json|jest.config.*|vitest.config.*|pytest.ini|pyproject.toml|setup.cfg|tox.ini|conftest.py|*/conftest.py|.mocharc*|karma.conf.*)
        while IFS= read -r line; do
          [ -n "$line" ] || continue
          grep -q "$ALLOW_TAG" <<<"$line" && continue
          grep -qE "$CONF_RE" <<<"$line" && mid+=("$f: 테스트를 끄거나 건너뛰는 설정 추가 → $(sed -E 's/^[[:space:]]+//' <<<"$line" | cut -c1-80)")
        done <<<"$added" ;;
    esac
  fi
done < <({ git diff --name-only "$base" -- . ':(exclude).harness' 2>/dev/null; git ls-files -o --exclude-standard 2>/dev/null; } | sort -u)

strict=0; [ "${HARNESS_TEST_GUARD:-on}" = strict ] && strict=1
[ ${#ok[@]} -gt 0 ] && { echo "[test-guard] 허용된 테스트 변경 (reviewer가 이유를 확인):"; printf '  - %s\n' "${ok[@]}"; }
[ ${#mid[@]} -gt 0 ] && { echo "[test-guard] 테스트 약화 의심 ($([ $strict = 1 ] && echo '막음: strict' || echo '경고')):"; printf '  - %s\n' "${mid[@]}"; }
if [ ${#high[@]} -gt 0 ]; then
  echo "[test-guard] 테스트 약화 (막음):"; printf '  - %s\n' "${high[@]}"
  echo "  → 테스트가 아니라 구현을 고치세요. 의도한 변경이면 그 줄에 '$ALLOW_TAG: <이유>' 주석을 달거나,"
  echo "    삭제·이동이면 사용자에게 .harness/test-guard-allow.txt 등록을 요청하세요(.harness/state/ask-user)."
  exit 1
fi
[ $strict = 1 ] && [ ${#mid[@]} -gt 0 ] && exit 1
exit 0
