#!/usr/bin/env bash
# PreToolUse(Bash) hook. Denies commands that could reach main/dev, rewrite history,
# merge or approve a PR, or destroy local data. False positives are acceptable.
# PERSN8_UNSAFE=1 turns it off.
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

[ "${PERSN8_UNSAFE:-}" = "1" ] && exit 0
input="$(cat)"
full_cmd="$(json_field "$input" '.tool_input.command')"
[ -n "$full_cmd" ] || exit 0

deny() {
  log "DENY: $1 :: $full_cmd"
  jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Split on shell separators so `a && git push ...` is still caught. Newlines too.
segments="$(printf '%s' "$full_cmd" | sed -E 's/(&&|\|\||;|\|)/\n/g')"

while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  s="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//')"

  # ---- git ----
  if printf '%s' "$s" | grep -Eqi '(^|[[:space:]])git[[:space:]]'; then
    sub="$(printf '%s' "$s" | sed -E 's/^.*[[:space:]]?git[[:space:]]+//')"

    if printf '%s' "$sub" | grep -Eqi '^push([[:space:]]|$)'; then
      printf '%s' "$sub" | grep -Eqi '[[:space:]](--all|--mirror|--branches|--tags)([[:space:]=]|$)' && deny "Bulk git push is not allowed."
      printf '%s' "$sub" | grep -Eqi '[[:space:]](-f|--force|--force-with-lease|--force-if-includes)([[:space:]=]|$)' && deny "Force push is not allowed."
      printf '%s' "$sub" | grep -Eqi '[[:space:]](-d|--delete)([[:space:]]|$)' && deny "Deleting remote branches is not allowed."
      after="$(printf '%s' "$sub" | sed -E 's/^push[[:space:]]*//')"
      positional=(); head_tok=false
      for tok in $after; do
        case "$tok" in -*) continue ;; esac
        positional+=("$tok")
        t="${tok#+}"
        [ "${tok#+}" != "$tok" ] && deny "Force push (+refspec) is not allowed."
        printf '%s' "$t" | grep -Eqi '(^|:)(refs/heads/)?(main|dev)$' && deny "Pushing to main or dev is not allowed. Push to your bm/ branch and open a pull request."
        [ "$t" = "HEAD" ] && head_tok=true
      done
      if [ "${#positional[@]}" -le 1 ] || [ "$head_tok" = true ]; then
        cur="$(current_branch)"
        is_protected_branch "$cur" && deny "You are on '$cur'. Pushing here is not allowed. Run new-work.sh <slug> first."
      fi
    fi

    printf '%s' "$sub" | grep -Eqi '^(checkout|switch)[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(main|dev)([[:space:]]|$)' && deny "Switching to main or dev is not allowed. Stay on your bm/ branch, or run new-work.sh <slug> for a new one."
    printf '%s' "$sub" | grep -Eqi '^reset[[:space:]].*--hard' && deny "git reset --hard is not allowed. Use git stash or git checkout -- <file> instead."
    printf '%s' "$sub" | grep -Eqi '^clean([[:space:]]|$)' && deny "git clean is not allowed."
    printf '%s' "$sub" | grep -Eqi '^rebase([[:space:]]|$)' && deny "git rebase is not allowed. Merge origin/main instead."
    printf '%s' "$sub" | grep -Eqi '^branch[[:space:]]+(.*[[:space:]])?(-D|-d|--delete)([[:space:]]|$)' && deny "Deleting branches is not allowed."
    printf '%s' "$sub" | grep -Eqi '^branch[[:space:]]+(.*[[:space:]])?(-M|-m)[[:space:]].*(^|[[:space:]])(main|dev)([[:space:]]|$)' && deny "Renaming to or from main/dev is not allowed."
    printf '%s' "$sub" | grep -Eqi '^stash[[:space:]]+(drop|clear)' && deny "Dropping stashes is not allowed."
    printf '%s' "$sub" | grep -Eqi '^(filter-branch|filter-repo|replace|reflog[[:space:]]+(expire|delete))' && deny "History rewriting is not allowed."
    printf '%s' "$sub" | grep -Eqi '^update-ref' && deny "git update-ref is not allowed."
  fi

  # ---- GitHub CLI ----
  if printf '%s' "$s" | grep -Eqi '(^|[[:space:]])gh[[:space:]]'; then
    printf '%s' "$s" | grep -Eqi 'gh[[:space:]]+pr[[:space:]]+(merge|review|ready|edit[[:space:]].*--base)' && deny "Merging, reviewing, or retargeting pull requests is not allowed. The team does that."
    printf '%s' "$s" | grep -Eqi 'gh[[:space:]]+api[[:space:]].*(merge|/reviews|/protection|/rulesets|-X[[:space:]]+(DELETE|PUT|PATCH))' && deny "That GitHub API call is not allowed."
    printf '%s' "$s" | grep -Eqi 'gh[[:space:]]+repo[[:space:]]+(delete|edit|archive|rename)' && deny "Changing the repository settings is not allowed."
  fi

  # ---- destructive filesystem / docker ----
  if printf '%s' "$s" | grep -Eqi '(^|[[:space:]])rm[[:space:]]+-[a-z]*[rR]'; then
    printf '%s' "$s" | grep -Eqi '(^|[[:space:]/])(data|\.git|node_modules|~|\$HOME|/Users)(/|[[:space:]]|$)|[[:space:]]/([[:space:]]|$)|[[:space:]]\*' && deny "Recursive delete of data, .git, node_modules, or home is not allowed. Use restore-db.sh for database problems."
  fi
  printf '%s' "$s" | grep -Eqi 'docker[[:space:]]+(compose[[:space:]]+down[[:space:]].*(-v|--volumes)|system[[:space:]]+prune|volume[[:space:]]+(rm|prune))' && deny "Removing Docker volumes is not allowed."
  printf '%s' "$s" | grep -Eqi 'sqlite3[[:space:]].*(DROP[[:space:]]+TABLE|DELETE[[:space:]]+FROM)' && deny "Direct destructive SQL on the databases is not allowed. Use a migration file."
done <<<"$segments"

exit 0
