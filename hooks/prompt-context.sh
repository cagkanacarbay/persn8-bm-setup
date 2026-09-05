#!/usr/bin/env bash
# UserPromptSubmit hook. Prints one line of repo state that Claude sees with every prompt.
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

cat >/dev/null
in_repo || exit 0
repo="$(repo_dir)"
cd "$repo" || exit 0

branch="$(current_branch)"
dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
  ahead="$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
else
  ahead="all (branch not on GitHub yet)"
fi
behind="$(git rev-list --count "HEAD..origin/main" 2>/dev/null || echo "?")"
if curl -fsS -o /dev/null --max-time 1 "$APP_URL" 2>/dev/null; then app="up"; else app="down"; fi

line="[persn8] branch=$branch | unsaved files=$dirty | unpushed commits=$ahead | behind main=$behind | app=$app"
if is_protected_branch "$branch"; then
  line="$line | RULE: you are on '$branch'. Do not edit anything. Run $SETUP_DIR/scripts/new-work.sh <slug> first."
fi
case "$branch" in bm/*|main|dev|HEAD|"") ;; *) line="$line | RULE: not a bm/ branch, do not edit here, run new-work.sh <slug>." ;; esac
printf '%s\n' "$line"
exit 0
