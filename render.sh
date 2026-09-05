#!/usr/bin/env bash
# Write CLAUDE.local.md and .claude/settings.local.json into the Persn8 clone from templates/.
# Usage: render.sh <repo-dir> [browser-text]
set -u
SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${1:?repo dir}"
BROWSER_TEXT="${2:-Plain Chrome tab. Open http://127.0.0.1:8080 with 'open -a \"Google Chrome\" http://127.0.0.1:8080' after changes and ask me to look.}"

[ -d "$REPO_DIR/.git" ] || { echo "not a git repo: $REPO_DIR"; exit 1; }
mkdir -p "$REPO_DIR/.claude"

python3 - "$SETUP_DIR" "$REPO_DIR" "$BROWSER_TEXT" <<'PY'
import sys, pathlib
setup, repo, browser = sys.argv[1:4]
for src, dst in (("templates/CLAUDE.local.md", "CLAUDE.local.md"),
                 ("templates/settings.local.json", ".claude/settings.local.json")):
    text = pathlib.Path(setup, src).read_text()
    text = text.replace("__SETUP_DIR__", setup).replace("__REPO_DIR__", repo).replace("__BROWSER_MODE__", browser)
    pathlib.Path(repo, dst).write_text(text)
PY

# Keep both files out of git without touching the repo's .gitignore.
excl="$REPO_DIR/.git/info/exclude"
touch "$excl"
for p in CLAUDE.local.md .claude/settings.local.json; do
  grep -qxF "$p" "$excl" || printf '%s\n' "$p" >> "$excl"
done
echo "wrote $REPO_DIR/CLAUDE.local.md and $REPO_DIR/.claude/settings.local.json"
