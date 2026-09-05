#!/usr/bin/env bash
# Restore the .sqlite files from a backup folder into <repo>/data. Stops the app first,
# takes a safety backup of the current state, copies, restarts the app.
# Usage: restore-db.sh <backup-folder>   (or "latest")
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)/common.sh"

src="${1:-}"
[ -n "$src" ] || { echo "usage: restore-db.sh <backup-folder|latest>"; echo "available:"; ls -1 "$BACKUP_ROOT" 2>/dev/null; exit 1; }
[ "$src" = "latest" ] && src="$BACKUP_ROOT/latest"
case "$src" in /*) ;; *) src="$BACKUP_ROOT/$src" ;; esac
src="$(cd "$src" 2>/dev/null && pwd -P)" || { echo "backup folder not found: $1"; exit 1; }
[ -f "$src/BRANCH" ] || { echo "not a backup folder (no BRANCH file): $src"; exit 1; }

repo="$(repo_dir)"
data="$repo/data"
mkdir -p "$data"

echo "stopping the app"
(cd "$repo" && docker compose stop app >/dev/null 2>&1) || true

echo "saving the current databases first"
"$SETUP_DIR/scripts/backup-db.sh" before-restore >/dev/null

count=0
while IFS= read -r -d '' f; do
  rel="${f#$src/}"
  mkdir -p "$data/$(dirname "$rel")"
  rm -f "$data/$rel" "$data/$rel-wal" "$data/$rel-shm"
  cp "$f" "$data/$rel"
  count=$((count + 1))
done < <(find "$src" -type f -name '*.sqlite' -print0)

echo "restored $count databases from $src"
log "restore from $src ($count databases)"

echo "starting the app"
(cd "$repo" && docker compose up -d app >/dev/null 2>&1) || echo "could not start the app, run start-app.sh"
