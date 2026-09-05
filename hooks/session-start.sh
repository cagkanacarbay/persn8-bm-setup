#!/usr/bin/env bash
# SessionStart hook. Backs up the databases, moves off main/dev onto a bm/ branch,
# starts Docker and the app in the background, and tells Claude the state.
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

input="$(cat)"
in_repo || exit 0
repo="$(repo_dir)"
cd "$repo" || exit 0

notes=()

# 1. Database backup.
bk="$("$SETUP_DIR/scripts/backup-db.sh" session-start 2>/dev/null | tail -1)"
[ -n "$bk" ] && notes+=("Databases backed up to $bk.")

# 2. Latest main.
if git fetch origin main --quiet 2>/dev/null; then
  fetched=1
else
  fetched=0
  notes+=("Could not reach GitHub to fetch main. Work offline and retry later.")
fi

# 3. Branch.
branch="$(current_branch)"
if is_protected_branch "$branch"; then
  if [ -n "$(git status --porcelain)" ]; then
    notes+=("WARNING: on '$branch' with unsaved changes. Stash them (git stash), run new-work.sh <slug>, then git stash pop.")
  else
    new="bm/$(date +%Y%m%d)-$(date +%H%M)"
    base="origin/main"; [ "$fetched" = 1 ] || base="main"
    if git checkout --quiet -b "$new" "$base" 2>/dev/null; then
      old="$branch"
      branch="$new"
      notes+=("Was on '$old', created $new from $base. Rename it with 'git branch -m bm/$(date +%Y%m%d)-<slug>' once you know the task.")
    else
      notes+=("WARNING: on '$branch' and could not create a bm/ branch. Run new-work.sh <slug> before editing.")
    fi
  fi
fi

behind=""
if [ "$fetched" = 1 ] && ! is_protected_branch "$branch"; then
  behind="$(git rev-list --count "$branch..origin/main" 2>/dev/null || echo "")"
  [ -n "$behind" ] && [ "$behind" != "0" ] && notes+=("Branch is $behind commits behind main. Merge origin/main in before continuing.")
fi

# 4. App.
if [ "${PERSN8_NO_APP:-}" != "1" ]; then
  nohup bash "$SETUP_DIR/scripts/start-app.sh" open >/dev/null 2>&1 &
  notes+=("Docker and the app are starting in the background (log: $STATE_DIR/app.log). The app will open in Chrome at $APP_URL when ready. Check with: curl -fsS -o /dev/null $APP_URL && echo up.")
fi

case "$branch" in
  bm/*) ;;
  *) [ -z "$branch" ] || notes+=("Branch '$branch' is not a bm/ branch. Do not edit on it. Run new-work.sh <slug>.") ;;
esac

ctx="Persn8 session state: branch=$branch. $(printf '%s ' "${notes[@]}")"
log "session-start branch=$branch behind=${behind:-?}"
jq -cn --arg c "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
exit 0
