#!/usr/bin/env bash
# Back up every .sqlite file under <repo>/data to ~/persn8-backups/<stamp>-<branch>-<reason>/.
# Uses sqlite3 .backup so a live WAL database is copied consistently. Media is not copied.
# Usage: backup-db.sh [reason]   (repo comes from CLAUDE_PROJECT_DIR or ~/.persn8-bm/repo_dir)
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)/common.sh"

reason="${1:-manual}"
repo="$(repo_dir)"
data="$repo/data"
[ -d "$data" ] || { echo "no data dir at $data, nothing to back up"; exit 0; }

branch="$(current_branch | tr '/' '_')"
stamp="$(date '+%Y%m%d-%H%M%S')"
dest="$BACKUP_ROOT/$stamp-${branch:-nobranch}-$reason"
[ -e "$dest" ] && dest="$dest-$$"
mkdir -p "$dest"

count=0
while IFS= read -r -d '' f; do
  rel="${f#$data/}"
  mkdir -p "$dest/$(dirname "$rel")"
  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "$f" ".backup '$dest/$rel'" 2>/dev/null || cp "$f" "$dest/$rel"
  else
    cp "$f" "$dest/$rel"
  fi
  count=$((count + 1))
done < <(find "$data" -type f -name '*.sqlite' -not -path '*/cache/*' -print0 2>/dev/null)

printf '%s\n' "$branch" > "$dest/BRANCH"
ln -sfn "$dest" "$BACKUP_ROOT/latest"

# Keep the newest 30 backups.
ls -1dt "$BACKUP_ROOT"/*/ 2>/dev/null | tail -n +31 | while IFS= read -r old; do rm -rf "$old"; done

log "backup $reason -> $dest ($count databases)"
echo "$dest"
