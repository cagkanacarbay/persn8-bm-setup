#!/usr/bin/env bash
# PreToolUse(Write|Edit|MultiEdit|Bash) hook. If the tool is about to touch a file under
# src/server/db/migrations/, back up the databases first. The dev server applies new
# migration files on the next DB open, so the backup must happen before the write.
# At most one backup per session for this reason.
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

input="$(cat)"
in_repo || exit 0

fp="$(json_field "$input" '.tool_input.file_path')"
cmd="$(json_field "$input" '.tool_input.command')"
sid="$(json_field "$input" '.session_id' | tr -c 'A-Za-z0-9_.-' '_')"

touches=false
case "$fp" in *src/server/db/migrations/*) touches=true ;; esac
if [ -n "$cmd" ] && printf '%s' "$cmd" | grep -Eq 'src/server/db/migrations/[^[:space:]]*\.sql' && printf '%s' "$cmd" | grep -Eq '(>|>>|tee|cp|mv|cat[[:space:]]*>|sed[[:space:]]+-i|touch|Begin Patch)'; then
  touches=true
fi
[ "$touches" = true ] || exit 0

marker="$STATE_DIR/${sid:-unknown}.migration-backup"
if [ -f "$marker" ]; then
  exit 0
fi

bk="$("$SETUP_DIR/scripts/backup-db.sh" before-migration 2>/dev/null | tail -1)"
[ -n "$bk" ] && printf '%s\n' "$bk" > "$marker"
jq -cn --arg c "A migration file is about to change. Databases were backed up to $bk. Tell the user this path. Restore with $SETUP_DIR/scripts/restore-db.sh if the migration goes wrong." \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",additionalContext:$c}}'
exit 0
