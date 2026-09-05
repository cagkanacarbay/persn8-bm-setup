#!/usr/bin/env bash
# One-time setup for a teammate's Mac. Idempotent: re-running only fills gaps.
set -u
SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="https://github.com/ohbob/Persn8.git"
REPO_DIR="${PERSN8_REPO_DIR:-$HOME/Persn8}"
STATE_DIR="$HOME/.persn8-bm"
APP_URL="http://127.0.0.1:8080"
export PATH="$HOME/.bun/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok() { printf '   ok: %s\n' "$*"; }
need() { printf '\n   ACTION NEEDED: %s\n' "$*"; }
die() { printf '\n   STOPPED: %s\n' "$*"; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "This installer is for macOS."
mkdir -p "$STATE_DIR"

step "Command line tools"
if ! xcode-select -p >/dev/null 2>&1; then
  xcode-select --install 2>/dev/null || true
  need "A window asked to install command line tools. Click Install, wait for it to finish, then run this installer again."
  exit 1
fi
ok "command line tools"

step "Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || die "Homebrew install failed."
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
  grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null || echo 'eval "$('"$(command -v brew)"' shellenv)"' >> "$HOME/.zprofile"
fi
ok "brew $(brew --version | head -1)"

step "git, GitHub CLI, jq, bun"
brew list git >/dev/null 2>&1 || brew install git
brew list gh >/dev/null 2>&1 || brew install gh
brew list jq >/dev/null 2>&1 || brew install jq
if ! command -v bun >/dev/null 2>&1; then
  curl -fsSL https://bun.sh/install | bash || die "bun install failed."
fi
ok "git $(git --version | awk '{print $3}'), gh $(gh --version | head -1 | awk '{print $3}'), bun $(bun --version)"

step "Docker Desktop"
if ! [ -d "/Applications/Docker.app" ]; then
  brew install --cask docker || die "Docker Desktop install failed. Install it from https://www.docker.com/products/docker-desktop/ and rerun."
fi
if ! docker info >/dev/null 2>&1; then
  open -a Docker
  printf '   waiting for Docker Desktop to start'
  for _ in $(seq 1 90); do docker info >/dev/null 2>&1 && break; printf '.'; sleep 2; done
  echo
  docker info >/dev/null 2>&1 || { need "Docker Desktop opened. Accept its terms and finish its first-run screens, then run this installer again."; exit 1; }
fi
ok "Docker is running"

step "Google Chrome"
[ -d "/Applications/Google Chrome.app" ] || brew install --cask google-chrome
ok "Chrome"

step "Claude Code"
if ! command -v claude >/dev/null 2>&1; then
  curl -fsSL https://claude.ai/install.sh | bash || die "Claude Code install failed."
fi
ok "claude $(claude --version 2>/dev/null | head -1)"

step "GitHub login"
if ! gh auth status >/dev/null 2>&1; then
  echo "   A browser window will open. Log in to GitHub and approve."
  gh auth login --hostname github.com --git-protocol https --web || die "GitHub login failed."
fi
gh auth setup-git >/dev/null 2>&1 || true
gh_user="$(gh api user --jq .login 2>/dev/null || echo "")"
ok "logged in as ${gh_user:-unknown}"

step "Persn8 code"
if [ ! -d "$REPO_DIR/.git" ]; then
  git clone "$REPO_URL" "$REPO_DIR" || die "Could not clone Persn8. Ask Cha to add ${gh_user:-your GitHub user} to the repository."
fi
printf '%s' "$REPO_DIR" > "$STATE_DIR/repo_dir"
ok "$REPO_DIR"

step "Your name for commits"
cur_name="$(git -C "$REPO_DIR" config user.name || true)"
cur_email="$(git -C "$REPO_DIR" config user.email || true)"
if [ -z "$cur_name" ]; then
  read -r -p "   Your name (shown on your commits): " name
  git -C "$REPO_DIR" config user.name "$name"
fi
if [ -z "$cur_email" ]; then
  gh_email="$(gh api user --jq '.email // empty' 2>/dev/null || true)"
  read -r -p "   Your email for commits [${gh_email:-}]: " email
  email="${email:-$gh_email}"
  [ -n "$email" ] && git -C "$REPO_DIR" config user.email "$email"
fi
ok "$(git -C "$REPO_DIR" config user.name) <$(git -C "$REPO_DIR" config user.email)>"

step "API keys (.env)"
if [ ! -f "$REPO_DIR/.env" ]; then
  cp "$REPO_DIR/.env.example" "$REPO_DIR/.env"
fi
set_env() { # set_env KEY prompt
  local key="$1" prompt="$2" cur val
  cur="$(grep -E "^$key=" "$REPO_DIR/.env" | head -1 | cut -d= -f2-)"
  if [ -z "$cur" ]; then
    read -r -s -p "   $prompt: " val; echo
    if [ -n "$val" ]; then
      if grep -qE "^$key=" "$REPO_DIR/.env"; then
        sed -i '' -E "s|^$key=.*|$key=$val|" "$REPO_DIR/.env"
      else
        printf '%s=%s\n' "$key" "$val" >> "$REPO_DIR/.env"
      fi
    fi
  fi
}
set_env GOOGLE_API_KEY "Google (Gemini) API key, from Cha (paste, it stays hidden)"
set_env OPENAI_API_KEY "OpenAI API key, from Cha (paste, it stays hidden)"
ok ".env written (keys stay on this computer)"

step "Browser mode"
mode_file="$STATE_DIR/browser_mode"
if [ ! -f "$mode_file" ]; then
  echo "   How should Claude show you the app?"
  echo "     1) Plain Chrome tab. Claude opens it, you look."
  echo "     2) Chrome with the Claude in Chrome extension. Claude can also see and click the page to check its own work. (Install the extension from the Chrome Web Store: search 'Claude in Chrome'.)"
  read -r -p "   Choose 1 or 2 [2]: " choice
  case "${choice:-2}" in 1) echo plain > "$mode_file" ;; *) echo extension > "$mode_file" ;; esac
fi
mode="$(cat "$mode_file")"
if [ "$mode" = "plain" ]; then
  browser_text="Plain Chrome tab. Open $APP_URL with 'open -a \"Google Chrome\" http://127.0.0.1:8080' after changes and ask me to look."
else
  browser_text="Chrome with the Claude in Chrome extension. After a UI change, use the browser tools to open http://127.0.0.1:8080, look at the page, and check your own work before telling me. If the browser tools are unavailable, fall back to 'open -a \"Google Chrome\" http://127.0.0.1:8080' and ask me to look."
fi
ok "$mode"

step "Claude Code local config in $REPO_DIR"
bash "$SETUP_DIR/render.sh" "$REPO_DIR" "$browser_text" || die "could not write config"
ok "CLAUDE.local.md and .claude/settings.local.json written and excluded from git"

step "Dependencies (bun install)"
(cd "$REPO_DIR" && bun install --silent) && ok "node_modules ready" || echo "   bun install failed, lint and tests will be skipped until it works"

step "Backup folder"
mkdir -p "$HOME/persn8-backups"
ok "$HOME/persn8-backups"

step "Update check script"
chmod +x "$SETUP_DIR"/*.sh "$SETUP_DIR"/scripts/*.sh "$SETUP_DIR"/hooks/*.sh 2>/dev/null || true
ok "done"

cat <<EOF

All set. To start working:

    cd ~/Persn8 && claude

Claude will start Docker and the app, open it in Chrome, and put you on your own
branch. Just say what you want to change.
EOF
