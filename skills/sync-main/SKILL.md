---
name: sync-main
description: Bring the latest team changes from main into the user's current bm/ branch while keeping their local data. Use when the user says "get the latest", "sync with main", "update my branch", "am I up to date", asks for the team's changes, or when the [persn8] prompt line shows "behind main" greater than 0 and they are about to start or continue work.
---

# Sync with main

The user is not technical. Explain each step in one plain sentence. Never rebase, never reset --hard, never touch `data/` by hand.

## Steps

1. If there are unsaved changes, commit them with a plain message and push first.
2. Run the script and read its output:

   ```
   __SETUP_DIR__/scripts/sync-main.sh
   ```

   It backs up the databases, renumbers any of the user's migration files that clash with ones arriving from main (and fixes the tracking rows in every local database so nothing re-runs), merges `origin/main`, restarts the app, and waits for it to answer.

3. Act on the exit code.

   Exit 0 means it worked. Tell the user "Your branch now has the team's latest changes, and your data is intact." Mention the backup folder it printed, then run `git push`.

   Exit 2 means a merge conflict. The script lists the conflicting files and stopped before touching the app. Open each file and keep both the team's change and ours where both make sense. If the conflict is in server code, database code, or a migration and the right answer is not obvious, run `git merge --abort` and tell the user to message Cha. Otherwise resolve, `git add` the files, `git commit --no-edit`, and rerun the script to finish the app restart.

   Exit 3 means the app did not start with the merged code. The script already restored the databases and put the branch back. Tell the user their work and data are safe, and to message Cha because the latest main does not run with this branch yet.

4. If the script renamed a migration file, say so: "The team also added a database change with the same number as yours, so I renumbered yours. Nothing else changed." If it noted that a `.test.ts` file still mentions the old name, fix that string and commit.

5. After a successful sync, reload the app in the browser once to confirm it looks right.

## Why the data survives

Git only changes code. The databases live in `data/`, which git ignores. New migration files from main apply when the app restarts, and the script backs up first so a bad one can be undone with `__SETUP_DIR__/scripts/restore-db.sh latest`.
