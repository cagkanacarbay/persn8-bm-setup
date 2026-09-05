# persn8-bm-setup

Sets up one Mac so a non-technical teammate can develop Persn8 with Claude Code
without touching `main`, `dev`, or anyone else's work.

Everything here lives on the teammate's machine. Nothing is committed to the
Persn8 repo: Claude Code reads `CLAUDE.local.md` and `.claude/settings.local.json`
from the project folder and keeps both out of git.

## For the teammate

Plain-language guide to the whole workflow: https://claude.ai/code/artifact/3abc4155-7d3b-4c7b-a63a-1b3c54675797

1. Open Terminal (press Cmd+Space, type `Terminal`, press Enter).
2. Paste this line and press Enter:

   ```sh
   git clone https://github.com/cagkanacarbay/persn8-bm-setup.git ~/persn8-bm-setup && ~/persn8-bm-setup/install.sh
   ```

3. Follow the prompts. When it finishes, start working with:

   ```sh
   cd ~/Persn8 && claude
   ```

From then on you talk to Claude in plain language. It starts Docker and the
app, opens the browser, keeps your work on your own branch, saves your work,
and offers to open a pull request when you say you are done.

## What the installer does

- Installs Homebrew, git, GitHub CLI, bun, Docker Desktop, Google Chrome, and
  Claude Code if they are missing.
- Logs you in to GitHub and clones `ohbob/Persn8` to `~/Persn8`.
- Writes `~/Persn8/.env` from `.env.example` with the API keys you type in.
- Writes `~/Persn8/CLAUDE.local.md` and `~/Persn8/.claude/settings.local.json`
  from `templates/` and excludes both from git.
- Installs the skills in `skills/` to `~/.claude/skills/` (user level, not in the repo).
- Runs `bun install` so lint and tests can run on your machine.

## What runs while you work

| When | What happens |
|---|---|
| Claude session starts | Backs up the SQLite databases to `~/persn8-backups/`. If you are on `main` or `dev`, creates a `bm/<date>-<time>` branch from the latest `main`. Starts Docker Desktop and the app, opens it in Chrome. |
| Every prompt | Claude is told the current branch, unsaved change count, and how far behind `main` you are. |
| Before a migration file is created or edited | Backs up the SQLite databases again. |
| Every edit | Records the file for the end-of-turn checks. |
| Claude finishes a turn | Lints and tests the files it touched. Refuses to stop until the work is committed and pushed to your branch. |
| He asks for the team's latest changes, or the branch is behind `main` | The `sync-main` skill (installed to `~/.claude/skills/`) runs `scripts/sync-main.sh`: backup, renumber clashing local migration files (fixing the `schema_migrations` rows so nothing re-runs), merge `origin/main`, restart the app. If the app does not come back, it restores the backup and undoes the merge. |
| Any shell command | Blocks pushes to `main` or `dev`, force pushes, history rewrites, branch deletion, `gh pr merge`, `gh pr review`, and destructive Docker or `rm` commands. |

Backups contain only the `.sqlite` files (metadata, per-user databases,
activity logs). Generated media under `data/` is not copied. The last 30
backups are kept.

## Updating

```sh
~/persn8-bm-setup/update.sh
```

Pulls this repo and rewrites the two local files in `~/Persn8`.

## Escape hatch (for maintainers)

Set `PERSN8_UNSAFE=1` in the environment before starting `claude` to turn the
deny hook off for that session. Set `PERSN8_NO_APP=1` to skip starting Docker
and the app on session start.
