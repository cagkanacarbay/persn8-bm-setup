#!/usr/bin/env bash
# Bring the latest origin/main into the current bm/ branch without losing local data.
#
# Phases (each is skipped when already done, so rerunning after a conflict is safe):
#   1. clean tree required, fetch origin/main, stop if already up to date
#   2. back up the databases
#   3. renumber local migration files that collide with incoming ones from main,
#      updating schema_migrations in every local database so nothing re-runs
#   4. git merge origin/main (merge, never rebase). Conflicts -> exit 2, nothing else touched
#   5. restart the app (rebuild if dependencies changed), wait until it answers.
#      If it does not: restore the backup, undo the merge with git reset --keep, restart, exit 3
#
# Exit codes: 0 ok, 1 precondition, 2 merge conflict (resolve, commit, rerun), 3 rolled back
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)/common.sh"

repo="$(repo_dir)"
cd "$repo" || exit 1
MIG="src/server/db/migrations"
PRE="$STATE_DIR/sync-premerge"
BK="$STATE_DIR/sync-backup"

say() { printf '%s\n' "$*"; log "sync-main: $*"; }

branch="$(current_branch)"
case "$branch" in bm/*) ;; *) say "Not on a bm/ branch (on '$branch'). Run new-work.sh <slug> first."; exit 1 ;; esac

if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
  conflicts="$(git diff --name-only --diff-filter=U)"
  say "A merge is in progress with conflicts in:"; printf '  %s\n' $conflicts
  say "Resolve them, then: git add <files> && git commit --no-edit, then rerun sync-main.sh. To give up: git merge --abort"
  exit 2
fi

if [ -n "$(git status --porcelain)" ]; then
  say "There are unsaved changes. Commit and push them first, then rerun sync-main.sh."
  exit 1
fi

git fetch origin main --quiet || { say "Could not reach GitHub (git fetch failed). Check the internet connection."; exit 1; }

# DB kinds -> which sqlite files hold their schema_migrations table.
db_files_for_kind() {
  case "$1" in
    meta) [ -f data/meta.sqlite ] && printf '%s\n' data/meta.sqlite ;;
    app) find data/users -mindepth 2 -maxdepth 2 -name '*.sqlite' ! -name '*.activity.sqlite' 2>/dev/null ;;
    activity) find data/users -mindepth 2 -maxdepth 2 -name '*.activity.sqlite' 2>/dev/null ;;
  esac
}

stop_app() { docker compose stop app >/dev/null 2>&1 || true; }
app_up() { curl -fsS -o /dev/null --max-time 3 "$APP_URL" 2>/dev/null; }
start_app() {
  if [ "${PERSN8_NO_APP:-}" = "1" ]; then return 0; fi
  if [ "${1:-}" = "rebuild" ]; then
    docker compose up -d --build app >>"$STATE_DIR/app.log" 2>&1
  else
    docker compose up -d app >>"$STATE_DIR/app.log" 2>&1 && docker compose restart app >>"$STATE_DIR/app.log" 2>&1
  fi
  for _ in $(seq 1 90); do app_up && return 0; sleep 2; done
  return 1
}

if ! git merge-base --is-ancestor origin/main HEAD; then
  # ---- phase 2: backup
  bk="$("$SETUP_DIR/scripts/backup-db.sh" sync-main | tail -1)"
  printf '%s' "$bk" > "$BK"
  say "Databases backed up to $bk"

  # ---- phase 3: migration number collisions
  incoming="$(git diff --name-only --diff-filter=A HEAD origin/main -- "$MIG" | grep '\.sql$' || true)"
  local_new="$(git diff --name-only --diff-filter=A origin/main HEAD -- "$MIG" | grep '\.sql$' || true)"
  renamed=0
  if [ -n "$incoming" ] && [ -n "$local_new" ]; then
    for lf in $local_new; do
      kind="$(basename "$(dirname "$lf")")"
      base="$(basename "$lf")"
      num="${base%%_*}"
      clash="$(printf '%s\n' $incoming | grep -E "^$MIG/$kind/${num}_" || true)"
      [ -n "$clash" ] || continue
      # next free number across existing, incoming, and local files of this kind
      max="$( { ls "$MIG/$kind" 2>/dev/null; printf '%s\n' $incoming $local_new | grep "/$kind/" | xargs -n1 basename 2>/dev/null; } | grep -E '^[0-9]+_' | sed -E 's/^0*([0-9]+)_.*/\1/' | sort -n | tail -1)"
      next="$(printf '%03d' $((max + 1)))"
      newbase="${next}_${base#*_}"
      say "Migration $kind/$base collides with $(basename "$clash") from main. Renumbering to $kind/$newbase."
      if [ "$renamed" = 0 ]; then stop_app; fi
      while IFS= read -r db; do
        [ -n "$db" ] || continue
        sqlite3 "$db" "UPDATE schema_migrations SET id='$newbase' WHERE id='$base';" 2>/dev/null || say "  warning: could not update $db"
      done < <(db_files_for_kind "$kind")
      git mv "$lf" "$MIG/$kind/$newbase"
      tbase="${base%.sql}.test.ts"
      if [ -f "$MIG/$kind/$tbase" ]; then
        git mv "$MIG/$kind/$tbase" "$MIG/$kind/${newbase%.sql}.test.ts"
        grep -rl "$base\|${base%.sql}" "$MIG/$kind/${newbase%.sql}.test.ts" >/dev/null 2>&1 && say "  note: ${newbase%.sql}.test.ts still mentions the old name; fix the string."
      fi
      renamed=$((renamed + 1))
    done
    if [ "$renamed" -gt 0 ]; then
      git commit --quiet -m "Renumber migration(s) to make room for main's" && say "Committed the renumbering."
    fi
  fi

  # ---- phase 4: merge
  git rev-parse HEAD > "$PRE"
  if ! git merge --no-edit origin/main >/dev/null 2>&1; then
    conflicts="$(git diff --name-only --diff-filter=U)"
    say "Merge has conflicts in:"; printf '  %s\n' $conflicts
    say "Resolve them (keep both the team's change and ours where possible), then: git add <files> && git commit --no-edit, then rerun sync-main.sh."
    say "If unsure, run git merge --abort and tell the user to message Cha. Nothing else was changed; the app and data are untouched."
    exit 2
  fi
  say "Merged origin/main into $branch."
else
  say "Branch already contains origin/main."
fi

# ---- phase 5: app
pre="$(cat "$PRE" 2>/dev/null || true)"
if [ -n "$pre" ]; then
  deps_changed=""
  git diff --name-only "$pre" HEAD -- bun.lock package.json 2>/dev/null | grep -q . && deps_changed=1
  if [ -n "$deps_changed" ]; then
    say "Dependencies changed, running bun install and rebuilding the app."
    bun install --silent >/dev/null 2>&1 || say "  warning: bun install failed on the host; lint/tests may not run."
  fi
  new_migs="$(git diff --name-only --diff-filter=A "$pre" HEAD -- "$MIG" | grep '\.sql$' || true)"
  [ -n "$new_migs" ] && say "New migrations from main will apply when the app restarts:" && printf '  %s\n' $new_migs
fi

if [ "${PERSN8_NO_APP:-}" = "1" ]; then
  say "PERSN8_NO_APP=1, not restarting the app."
  rm -f "$PRE"
  exit 0
fi

say "Restarting the app..."
if start_app "${deps_changed:+rebuild}"; then
  say "App is up at $APP_URL with the latest main."
  rm -f "$PRE"
  exit 0
fi

say "The app did not come back after the merge."
if [ -n "$pre" ]; then
  say "Rolling back: restoring the databases and undoing the merge."
  bk="$(cat "$BK" 2>/dev/null || echo latest)"
  stop_app
  "$SETUP_DIR/scripts/restore-db.sh" "$bk" >/dev/null 2>&1
  git reset --keep "$pre" >/dev/null 2>&1 && say "Branch is back at the commit before the merge."
  start_app && say "App is up again on the previous version." || say "App still down. Check: docker compose logs app"
  rm -f "$PRE"
  say "Tell the user to message Cha: the latest main does not run with this branch."
  exit 3
fi
say "Check: docker compose logs app"
exit 3
