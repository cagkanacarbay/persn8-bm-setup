# How to work with me on Persn8

@AGENTS.md

## Who I am

I am not a developer and I do not know git. I describe what I want in plain
language and you make it happen. Handle every git, Docker, and terminal step
yourself. Never ask me a git question. When you do a git step, tell me what it
did in one short plain sentence so I learn the basics over time. Basics only:
branch, commit, push, pull request. Skip anything deeper.

## My setup

- The app runs locally from `~/Persn8` with `docker compose`. It is at
  http://127.0.0.1:8080 once it is up. A session-start script starts Docker
  Desktop and the app for you. If the app is not up, run
  `__SETUP_DIR__/scripts/start-app.sh` and wait for it.
- Browser: __BROWSER_MODE__
- The app's data (SQLite databases and generated media) lives in
  `~/Persn8/data/`. It is mine and local. It is not the production data.
- Backups of the databases are in `~/persn8-backups/`. One is made every time
  a session starts and before any migration file is created or edited.

## Branches

- I only ever work on branches named `bm/<date>-<slug>`. Never edit anything
  while on `main` or `dev`. If I am on `main` or `dev`, run
  `__SETUP_DIR__/scripts/new-work.sh <short-slug>` first. It makes a fresh
  branch from the latest `main`.
- The session-start script may have created a branch named `bm/<date>-<time>`.
  Once you know what I am working on, rename it before the first push:
  `git branch -m bm/<date>-<slug>`.
- When I start something unrelated to the current branch, run `new-work.sh`
  again with a new slug. One piece of work per branch.
- If the branch is behind `main`, or I ask for the team's latest changes, use
  the `sync-main` skill. It runs `__SETUP_DIR__/scripts/sync-main.sh`, which
  backs up my data, merges `origin/main`, and restarts the app. Never rebase.
  If it reports a conflict you cannot resolve safely, `git merge --abort` and
  tell me to message Cha.

## Saving work

- After every change that works, commit with a plain-language message and push
  to my branch (`git push -u origin <branch>`). The team watches my branch to
  see progress. A hook will not let you stop with unsaved or unpushed work.
- Lint and tests run automatically on the files you touched when you finish.
  Fix what they report before stopping.

## Finishing

- When I say I am done, happy, or ask what is next, ask me: "Is this at a good
  place? If yes, I can open a pull request. That asks the team to review and
  merge your changes into the main app." Only open it when I say yes.
- Open it with `gh pr create --base main`. Title in plain words. Body: what
  changed, why, how to try it, and a screenshot if the UI changed. Post the
  link to me.
- Never merge, approve, or review a pull request. Never push to `main` or
  `dev`. A hook blocks these, do not try to work around it.

## Database changes (migrations)

- I can add migration files under `src/server/db/migrations/` for my local
  work. A backup of the databases is taken automatically before you create or
  edit one. Tell me the backup folder when that happens.
- If a migration goes wrong, restore with
  `__SETUP_DIR__/scripts/restore-db.sh <backup-folder>` (it stops the app,
  copies the databases back, and restarts). `ls ~/persn8-backups` lists them,
  newest last.
- Cha reviews every migration in the pull request before it reaches real data.
  Say so in the pull request body when one is included.

## Seeing my changes

- After a UI change, reload http://127.0.0.1:8080 and look at it. Use the
  browser mode above. If something looks wrong, fix it before committing.
- Logs: `docker compose logs -f app` in `~/Persn8`.
