#!/usr/bin/env bash
# pre-code-harness-setup 설치 스크립트 — 하네스(Hook·검사·문서 템플릿)를 대상 프로젝트에 깐다.
# Claude Code · Gemini CLI · Codex(ChatGPT) 공통. 여러 번 실행해도 결과가 같다(이미 있는 것은 건드리지 않음).
#
# 사용법:
#   bash install.sh --target <프로젝트> [--tools claude,gemini,codex|auto] [--overlay <폴더>] [--force]
#   bash install.sh --target <프로젝트> --finalize      # 세팅 마지막: 보호 목록 설치 + 기준선 기록
#
#   --tools    설정을 만들 도구. auto(기본)는 .claude/.gemini/.codex·CLAUDE.md·GEMINI.md·AGENTS.md로 감지, 없으면 셋 다
#   --overlay  미리 채워 둔 파일(AGENTS.md, .harness/checks.sh 등)이 있는 폴더. 템플릿 대신 이것을 쓴다
#   --force    Hook 스크립트가 이미 있어도 새 버전으로 덮어쓴다 (문서·검사 파일은 절대 덮어쓰지 않음)
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$SKILL_DIR/assets"
TARGET="" TOOLS="auto" OVERLAY="" FORCE=0 FINALIZE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --target)   TARGET="$2"; shift 2 ;;
    --tools)    TOOLS="$2"; shift 2 ;;
    --overlay)  OVERLAY="$2"; shift 2 ;;
    --force)    FORCE=1; shift ;;
    --finalize) FINALIZE=1; shift ;;
    -h|--help)  sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 64 ;;
  esac
done
[ -n "$TARGET" ] || { echo "--target 이 필요합니다" >&2; exit 64; }
for bin in jq git; do command -v "$bin" >/dev/null || { echo "필요한 도구가 없습니다: $bin" >&2; exit 69; }; done
mkdir -p "$TARGET"; TARGET="$(cd "$TARGET" && pwd)"
say() { printf '  %s\n' "$*"; }

# ---------- 마무리 단계: 보호 목록 + 기준선 ----------
if [ "$FINALIZE" = 1 ]; then
  echo "[하네스 마무리] $TARGET"
  if [ -f "$TARGET/.harness/protected-paths.txt" ]; then say "보호 목록 유지: .harness/protected-paths.txt (이미 있음)"
  else
    src="$ASSETS/protected-paths.txt"; [ -n "$OVERLAY" ] && [ -f "$OVERLAY/.harness/protected-paths.txt" ] && src="$OVERLAY/.harness/protected-paths.txt"
    cp "$src" "$TARGET/.harness/protected-paths.txt"; say "보호 목록 설치: .harness/protected-paths.txt — 이후 사람이 고친다"
  fi
  (cd "$TARGET" && bash .harness/hooks/code-limits.sh --baseline | sed 's/^/  /')
  exit 0
fi

# ---------- 도구 감지 ----------
if [ "$TOOLS" = "auto" ]; then
  TOOLS=""
  { [ -d "$TARGET/.claude" ] || [ -f "$TARGET/CLAUDE.md" ]; } && TOOLS+="claude,"
  { [ -d "$TARGET/.gemini" ] || [ -f "$TARGET/GEMINI.md" ]; } && TOOLS+="gemini,"
  [ -d "$TARGET/.codex" ] && TOOLS+="codex,"
  [ -n "$TOOLS" ] || TOOLS="claude,gemini,codex,"
fi
has() { case ",$TOOLS," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
echo "[하네스 설치] 대상: $TARGET / 도구: ${TOOLS%,}"

# ---------- 1) Hook 스크립트 ----------
mkdir -p "$TARGET/.harness/hooks" "$TARGET/.harness/state"
for f in "$SKILL_DIR"/scripts/hooks/*.sh; do
  dest="$TARGET/.harness/hooks/$(basename "$f")"
  if [ -f "$dest" ] && [ "$FORCE" = 0 ] && ! cmp -s "$f" "$dest"; then say "유지(이미 있음, 갱신하려면 --force): .harness/hooks/$(basename "$f")"; continue; fi
  cp "$f" "$dest"; chmod +x "$dest"
done
say "Hook 스크립트: .harness/hooks/"

# ---------- 2) 문서·검사 템플릿 (없을 때만) ----------
place() {   # place <assets 안 이름> <대상 상대경로>
  local src="$ASSETS/$1" dest="$TARGET/$2"
  [ -n "$OVERLAY" ] && [ -f "$OVERLAY/$2" ] && src="$OVERLAY/$2"
  if [ -e "$dest" ]; then say "유지(이미 있음): $2"; return 0; fi
  mkdir -p "$(dirname "$dest")"; cp "$src" "$dest"; say "생성: $2"
}
place checks.sh   .harness/checks.sh; chmod +x "$TARGET/.harness/checks.sh"
place reviewer.md .harness/reviewer.md
place workflow.md .harness/workflow.md
place PROGRESS.md PROGRESS.md
place DECISIONS.md DECISIONS.md

# AGENTS.md: 없으면 만들고, 있으면 하네스 구역만 덧붙인다
agents_src="$ASSETS/AGENTS.md"; [ -n "$OVERLAY" ] && [ -f "$OVERLAY/AGENTS.md" ] && agents_src="$OVERLAY/AGENTS.md"
if [ ! -f "$TARGET/AGENTS.md" ]; then cp "$agents_src" "$TARGET/AGENTS.md"; say "생성: AGENTS.md"
elif grep -q 'harness:start' "$TARGET/AGENTS.md"; then say "유지(하네스 구역 있음): AGENTS.md"
else { echo; cat "$agents_src"; } >> "$TARGET/AGENTS.md"; say "덧붙임: AGENTS.md 끝에 하네스 구역"; fi

link_md() {   # CLAUDE.md / GEMINI.md 가 AGENTS.md를 불러오게 한다
  local f="$TARGET/$1"
  if [ ! -f "$f" ]; then printf '@AGENTS.md\n' > "$f"; say "생성: $1 (@AGENTS.md)"
  elif grep -qE '^@\.?/?AGENTS\.md' "$f"; then say "유지: $1 (이미 @AGENTS.md 있음)"
  else printf '\n@AGENTS.md\n' >> "$f"; say "덧붙임: $1 끝에 @AGENTS.md"; fi
}
has claude && link_md CLAUDE.md
has gemini && link_md GEMINI.md

# ---------- 3) 도구별 Hook 설정 병합 (기존 항목 보존, 같은 명령은 중복 추가 안 함) ----------
merge() {   # merge <설정 파일> <추가할 JSON 파일>
  local file="$TARGET/$1" add="$2" tmp
  mkdir -p "$(dirname "$file")"; [ -s "$file" ] || echo '{}' > "$file"
  jq empty "$file" 2>/dev/null || { echo "  ! $1 이 올바른 JSON이 아니라 건너뜁니다 (주석이 있으면 직접 병합하세요)" >&2; return 0; }
  tmp="$(mktemp)"
  jq --slurpfile a "$add" '
    ($a[0]) as $add
    | .hooks = (.hooks // {})
    | reduce ($add.hooks | to_entries[]) as $e (.;
        .hooks[$e.key] = (
          (.hooks[$e.key] // []) as $cur
          | ($cur | [.[].hooks[]?.command]) as $have
          | $cur + [ $e.value[] | select(([.hooks[]?.command] - $have) | length > 0) ]))
    | if $add.permissions then
        .permissions = (.permissions // {})
        | .permissions.deny = (((.permissions.deny // []) + $add.permissions.deny) | unique)
      else . end
    | if ($add.description and (.description | not)) then .description = $add.description else . end
  ' "$file" > "$tmp" && mv "$tmp" "$file"
  say "Hook 설정 병합: $1"
}
has claude && merge .claude/settings.json "$ASSETS/config/claude-settings.json"
has gemini && merge .gemini/settings.json "$ASSETS/config/gemini-settings.json"
has codex  && merge .codex/hooks.json     "$ASSETS/config/codex-hooks.json"
if has claude && [ ! -f "$TARGET/.claude/agents/reviewer.md" ]; then
  mkdir -p "$TARGET/.claude/agents"; cp "$ASSETS/claude-agent-reviewer.md" "$TARGET/.claude/agents/reviewer.md"; say "생성: .claude/agents/reviewer.md"
fi

# ---------- 4) .gitignore ----------
gi="$TARGET/.gitignore"; touch "$gi"
for line in ".harness/state/" ".claude/settings.local.json"; do grep -qxF "$line" "$gi" || echo "$line" >> "$gi"; done
say ".gitignore: .harness/state/"

cat <<EOF

다음 단계
  1. .harness/checks.sh 를 프로젝트의 린트·테스트 명령으로 채우고, AGENTS.md의 <...> 자리를 채운다
  2. 기존 큰 파일 기준선과 보호 목록은 마지막에:  bash install.sh --target "$TARGET" --finalize
  3. 세팅 파일(.harness/ 등)을 커밋한다 — worktree는 커밋된 파일만 가져간다
EOF
has claude && echo "  · Claude Code: 재시작하거나 /hooks 로 등록 확인"
has gemini && echo "  · Gemini CLI: 재시작 후 /hooks 로 등록 확인 (Hook·Skills가 실험 기능인 버전은 설정에서 켜기)"
has codex  && echo "  · Codex: 프로젝트를 신뢰(trust)하고 /hooks 에서 새 Hook을 검토·신뢰해야 실행된다"
exit 0
