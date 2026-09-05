#!/usr/bin/env bash
# Make sure Docker Desktop is running, start the Persn8 dev container, wait until the app
# answers, then open it in Chrome. Safe to run repeatedly. Logs to ~/.persn8-bm/app.log.
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)/common.sh"

repo="$(repo_dir)"
cd "$repo" || exit 1
LOGF="$STATE_DIR/app.log"
open_browser="${1:-open}"   # pass "noopen" to skip the browser

say() { printf '%s\n' "$*"; printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOGF"; }

if ! docker info >/dev/null 2>&1; then
  say "starting Docker Desktop"
  open -a Docker 2>/dev/null || { say "Docker Desktop is not installed"; exit 1; }
  for _ in $(seq 1 90); do docker info >/dev/null 2>&1 && break; sleep 2; done
  docker info >/dev/null 2>&1 || { say "Docker did not start within 3 minutes"; exit 1; }
fi

if curl -fsS -o /dev/null --max-time 3 "$APP_URL" 2>/dev/null; then
  say "app already up at $APP_URL"
else
  say "starting the app (first start builds the image, this can take a few minutes)"
  docker compose up -d --build app >> "$LOGF" 2>&1 || { say "docker compose failed, see $LOGF"; exit 1; }
  for _ in $(seq 1 150); do
    curl -fsS -o /dev/null --max-time 3 "$APP_URL" 2>/dev/null && break
    sleep 2
  done
  curl -fsS -o /dev/null --max-time 3 "$APP_URL" 2>/dev/null || { say "app did not answer within 5 minutes, check: docker compose logs app"; exit 1; }
  say "app is up at $APP_URL"
fi

if [ "$open_browser" = "open" ]; then
  if [ -f "$STATE_DIR/browser_opened_$(date +%Y%m%d)" ] && [ "${2:-}" != "force" ]; then
    say "browser already opened today, not opening again"
  else
    open -a "Google Chrome" "$APP_URL" 2>/dev/null || open "$APP_URL"
    touch "$STATE_DIR/browser_opened_$(date +%Y%m%d)"
    say "opened $APP_URL in Chrome"
  fi
fi
