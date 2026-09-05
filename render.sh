#!/usr/bin/env bash
# Write CLAUDE.local.md and .claude/settings.local.json into the Persn8 clone from templates/.
# Usage: render.sh <repo-dir> [browser-text]
set -u
SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${1:?repo dir}"
BROWSER_TEXT="${2:-Plain Chrome tab. Open http://127.0.0.1:8080 with 'open -a \"Google Chrome\" http://127.0.0.1:8080' after changes and ask me to look.}"

[ -d "$REPO_DIR/.git" ] || { echo "not a git repo: $REPO_DIR"; exit 1; }
mkdir -p "$REPO_DIR/.claude"

SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
mkdir -p "$SKILLS_DIR"
python3 - "$SETUP_DIR" "$REPO_DIR" "$BROWSER_TEXT" "$SKILLS_DIR" <<'PY'
import sys, pathlib
setup, repo, browser, skills = sys.argv[1:5]
def render(text):
    return text.replace("__SETUP_DIR__", setup).replace("__REPO_DIR__", repo).replace("__BROWSER_MODE__", browser)
for src, dst in (("templates/CLAUDE.local.md", "CLAUDE.local.md"),
                 ("templates/settings.local.json", ".claude/settings.local.json")):
    pathlib.Path(repo, dst).write_text(render(pathlib.Path(setup, src).read_text()))
# User-level skills (~/.claude/skills/<name>/SKILL.md): per machine, never in the Persn8 repo.
for skill in pathlib.Path(setup, "skills").iterdir():
    if not skill.is_dir(): continue
    out = pathlib.Path(skills, skill.name); out.mkdir(parents=True, exist_ok=True)
    for f in skill.iterdir():
        if f.is_file(): (out / f.name).write_text(render(f.read_text()))
    print(f"installed skill {skill.name} -> {out}")
PY

# Keep both files out of git without touching the repo's .gitignore.
excl="$REPO_DIR/.git/info/exclude"
touch "$excl"
for p in CLAUDE.local.md .claude/settings.local.json; do
  grep -qxF "$p" "$excl" || printf '%s\n' "$p" >> "$excl"
done
echo "wrote $REPO_DIR/CLAUDE.local.md and $REPO_DIR/.claude/settings.local.json"
