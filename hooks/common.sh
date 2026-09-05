#!/usr/bin/env bash
# Shared helpers for the hooks. Source, do not execute.

SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$HOME/.persn8-bm"
BACKUP_ROOT="$HOME/persn8-backups"
APP_URL="http://127.0.0.1:8080"
export PATH="$HOME/.bun/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

mkdir -p "$STATE_DIR" 2>/dev/null || true

# The Persn8 clone: Claude's project dir, else the configured repo, else cwd.
repo_dir() {
  local d="${CLAUDE_PROJECT_DIR:-}"
  if [ -z "$d" ] && [ -f "$STATE_DIR/repo_dir" ]; then d="$(cat "$STATE_DIR/repo_dir")"; fi
  if [ -z "$d" ]; then d="$PWD"; fi
  printf '%s' "$d"
}

# Only act inside the Persn8 clone.
in_repo() {
  local d; d="$(repo_dir)"
  [ -d "$d/.git" ] && [ -f "$d/package.json" ] && grep -q '"tanstack_start_ts"\|persn8' "$d/package.json" 2>/dev/null
}

json_field() {
  # json_field <json> <jq path>
  printf '%s' "$1" | jq -r "$2 // \"\"" 2>/dev/null
}

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$STATE_DIR/hooks.log" 2>/dev/null || true
}

current_branch() {
  git -C "$(repo_dir)" rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""
}

is_protected_branch() {
  case "$1" in main|dev|HEAD|"") return 0 ;; *) return 1 ;; esac
}
