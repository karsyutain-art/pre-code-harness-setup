#!/usr/bin/env bash
# 프로젝트의 검사 명령을 자동으로 찾아 .harness/checks.sh 에 넣을 줄을 출력한다.
#   사용법: bash detect-checks.sh <프로젝트> [--fast|--full|--summary]
#   --fast    매번 도는 빠른 검사 (린트·타입 검사)       → "step <이름> <명령...>" 줄
#   --full    "완료"를 주장할 때 도는 전체 검사 (테스트·빌드)
#   --summary 사람이 읽는 요약 (기본)
# 찾는 곳: package.json 스크립트(npm·pnpm·yarn·bun), pyproject.toml·setup.cfg·pytest.ini, go.mod, Cargo.toml,
#          Gradle·Maven, .NET, Makefile(check·lint·test 타깃). 찾은 것은 출발점일 뿐이니 에이전트가 확인하고 고친다.
set -u
T="${1:?프로젝트 경로가 필요합니다}"; MODE="${2:---summary}"
FAST=() FULL=()
add_fast() { FAST+=("step $1 ${*:2}"); }
add_full() { FULL+=("step $1 ${*:2}"); }
has_file() { [ -e "$T/$1" ]; }
grep_q() { [ -f "$T/$2" ] && grep -qE "$1" "$T/$2"; }

# ---------- JavaScript / TypeScript ----------
if has_file package.json && command -v jq >/dev/null; then
  if has_file pnpm-lock.yaml; then run="pnpm"; elif has_file yarn.lock; then run="yarn"; elif has_file bun.lockb || has_file bun.lock; then run="bun run"; else run="npm run"; fi
  script() { jq -r --arg k "$1" '.scripts[$k] // empty' "$T/package.json"; }
  first_script() { local k; for k in "$@"; do [ -n "$(script "$k")" ] && { echo "$k"; return; }; done; }
  k=$(first_script lint eslint);                          [ -n "$k" ] && add_fast lint $run "$k"
  k=$(first_script typecheck type-check check-types tsc); if [ -n "$k" ]; then add_fast typecheck $run "$k"
  elif has_file tsconfig.json; then add_fast typecheck npx tsc --noEmit; fi
  t=$(script test)
  if [ -n "$t" ] && ! grep -q 'no test specified' <<<"$t"; then add_full test $run test; fi
  [ -n "$(script build)" ] && add_full build $run build
fi

# ---------- Python ----------
if has_file pyproject.toml || has_file setup.cfg || has_file setup.py || has_file requirements.txt; then
  if grep_q '^\[tool\.ruff' pyproject.toml || has_file ruff.toml || has_file .ruff.toml; then add_fast lint ruff check .; fi
  if grep_q '^\[tool\.mypy' pyproject.toml || has_file mypy.ini || grep_q '^\[mypy' setup.cfg; then add_fast typecheck mypy .; fi
  if grep_q '^\[tool\.pytest' pyproject.toml || has_file pytest.ini || grep_q '^\[tool:pytest' setup.cfg || [ -d "$T/tests" ]; then
    add_full test python -m pytest -q
  fi
fi

# ---------- Go / Rust / JVM / .NET ----------
if has_file go.mod; then add_fast vet go vet ./...; add_full test go test ./...; fi
if has_file Cargo.toml; then add_fast check cargo check --quiet; add_full test cargo test --quiet; fi
if has_file gradlew; then add_full test ./gradlew test --quiet
elif has_file pom.xml; then add_full test mvn -q test; fi
if compgen -G "$T/*.sln" >/dev/null || compgen -G "$T/*.csproj" >/dev/null; then add_full test dotnet test --nologo; fi

# ---------- Makefile: check 타깃이 있으면 그것이 기준 ----------
if has_file Makefile; then
  if grep -qE '^check:' "$T/Makefile"; then FULL=("step make-check make check")
  else
    [ ${#FAST[@]} -eq 0 ] && grep -qE '^lint:' "$T/Makefile" && add_fast lint make lint
    [ ${#FULL[@]} -eq 0 ] && grep -qE '^test:' "$T/Makefile" && add_full test make test
  fi
fi

case "$MODE" in
  --fast) printf '%s\n' "${FAST[@]+"${FAST[@]}"}" ;;
  --full) printf '%s\n' "${FULL[@]+"${FULL[@]}"}" ;;
  *) echo "빠른 검사 (매번):";            printf '  %s\n' "${FAST[@]:-(찾지 못함)}"
     echo "전체 검사 (완료를 주장할 때):"; printf '  %s\n' "${FULL[@]:-(찾지 못함)}" ;;
esac
