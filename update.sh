#!/usr/bin/env bash
# Pull the latest setup and rewrite the two local Claude files in the Persn8 clone.
set -u
SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/.persn8-bm"
REPO_DIR="$(cat "$STATE_DIR/repo_dir" 2>/dev/null || echo "$HOME/Persn8")"

git -C "$SETUP_DIR" pull --ff-only || { echo "could not update; check the internet connection"; exit 1; }
chmod +x "$SETUP_DIR"/*.sh "$SETUP_DIR"/scripts/*.sh "$SETUP_DIR"/hooks/*.sh 2>/dev/null || true

mode="$(cat "$STATE_DIR/browser_mode" 2>/dev/null || echo extension)"
if [ "$mode" = "plain" ]; then
  browser_text="Plain Chrome tab. Open http://127.0.0.1:8080 with 'open -a \"Google Chrome\" http://127.0.0.1:8080' after changes and ask me to look."
else
  browser_text="Chrome with the Claude in Chrome extension. After a UI change, use the browser tools to open http://127.0.0.1:8080, look at the page, and check your own work before telling me. If the browser tools are unavailable, fall back to 'open -a \"Google Chrome\" http://127.0.0.1:8080' and ask me to look."
fi
bash "$SETUP_DIR/render.sh" "$REPO_DIR" "$browser_text"
echo "updated. Restart Claude Code to pick up the new hooks."
