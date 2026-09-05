#!/usr/bin/env bash
# Start a new piece of work: fresh branch bm/<date>-<slug> from the latest origin/main,
# plus a database backup. Refuses if there are unsaved changes.
# Usage: new-work.sh <slug>
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)/common.sh"

slug="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
[ -n "$slug" ] || { echo "usage: new-work.sh <short-slug>   e.g. new-work.sh brand-page-colors"; exit 1; }

repo="$(repo_dir)"
cd "$repo" || exit 1

if [ -n "$(git status --porcelain)" ]; then
  echo "There are unsaved changes on branch $(current_branch). Commit and push them first, then run new-work.sh again."
  exit 1
fi

git fetch origin main --quiet || { echo "could not reach GitHub (git fetch failed). Check the internet connection and try again."; exit 1; }

branch="bm/$(date +%Y%m%d)-$slug"
if git show-ref --verify --quiet "refs/heads/$branch"; then
  echo "branch $branch already exists, switching to it"
  git checkout --quiet "$branch"
else
  git checkout --quiet -b "$branch" origin/main
  echo "created branch $branch from the latest main"
fi

"$SETUP_DIR/scripts/backup-db.sh" new-work >/dev/null && echo "databases backed up to $BACKUP_ROOT/latest"
log "new-work $branch"
