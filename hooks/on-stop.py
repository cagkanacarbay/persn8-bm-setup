#!/usr/bin/env python3
"""Stop hook. When Claude wants to finish a turn:
  1. eslint + matching bun tests on the .ts/.tsx files it edited this session
  2. the branch must be a bm/ branch, with no unsaved changes and nothing unpushed
On failure it returns {"decision":"block"} with instructions, at most MAX_BLOCKS
times per session so a stuck check cannot loop forever."""
import json, os, re, subprocess, sys, time

STATE = os.path.expanduser("~/.persn8-bm")
LOG = os.path.join(STATE, "hooks.log")
MAX_BLOCKS = 3
CMD_TIMEOUT = 240
os.environ["PATH"] = ":".join([os.path.expanduser("~/.bun/bin"), "/opt/homebrew/bin", "/usr/local/bin", os.environ.get("PATH", "")])


def log(msg: str) -> None:
    os.makedirs(STATE, exist_ok=True)
    with open(LOG, "a") as f:
        f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + msg + "\n")


def repo_dir(d: dict) -> str:
    r = os.environ.get("CLAUDE_PROJECT_DIR") or ""
    if not r:
        p = os.path.join(STATE, "repo_dir")
        if os.path.exists(p):
            r = open(p).read().strip()
    return os.path.realpath(r or d.get("cwd") or "")


def run(cmd: list[str], cwd: str) -> tuple[int, str]:
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=CMD_TIMEOUT)
        return p.returncode, (p.stdout + p.stderr).strip()
    except subprocess.TimeoutExpired:
        return 124, f"timed out after {CMD_TIMEOUT}s: {' '.join(cmd)}"
    except FileNotFoundError as e:
        return 127, str(e)


def git(root: str, *args: str) -> tuple[int, str]:
    return run(["git", *args], root)


def tail(s: str, n: int = 40, cap: int = 4000) -> str:
    return "\n".join(s.splitlines()[-n:])[-cap:]


def test_files_for(path: str) -> list[str]:
    if re.search(r"\.(test|spec)\.tsx?$", path):
        return [path]
    base = re.sub(r"\.tsx?$", "", path)
    return [c for c in (base + ".test.ts", base + ".test.tsx") if os.path.exists(c)]


def main() -> None:
    try:
        d = json.load(sys.stdin)
    except Exception:
        return
    root = repo_dir(d)
    if not root or not os.path.isdir(os.path.join(root, ".git")):
        return
    sid = re.sub(r"[^A-Za-z0-9_.-]", "_", str(d.get("session_id") or "unknown"))
    ledger = os.path.join(STATE, sid + ".files")
    attempts_file = os.path.join(STATE, sid + ".blocks")

    failures: list[str] = []
    summary: list[str] = []

    # 1. Lint and tests on edited files.
    files: list[str] = []
    if os.path.exists(ledger):
        with open(ledger) as f:
            files = sorted({l.strip() for l in f if l.strip() and os.path.exists(l.strip())})
    if files:
        rel = [os.path.relpath(p, root) for p in files]
        if os.path.isdir(os.path.join(root, "node_modules")):
            code, out = run(["bunx", "eslint", "--cache", "--cache-location", os.path.join(STATE, "eslintcache"), *rel], root)
            summary.append(f"eslint {len(rel)} file(s): exit {code}")
            if code != 0:
                failures.append("eslint failed:\n" + tail(out))
            tests = sorted({t for p in files for t in test_files_for(p)})
            if tests:
                trel = [os.path.relpath(t, root) for t in tests]
                code, out = run(["bun", "test", *trel], root)
                summary.append(f"bun test {len(trel)} file(s): exit {code}")
                if code != 0:
                    failures.append("bun test failed:\n" + tail(out))
        else:
            summary.append("node_modules missing, lint/tests skipped (run: bun install)")

    # 2. Branch, unsaved, unpushed.
    _, branch = git(root, "rev-parse", "--abbrev-ref", "HEAD")
    _, status = git(root, "status", "--porcelain")
    dirty = [l for l in status.splitlines() if l.strip()]
    changed_anything = bool(files) or bool(dirty)

    if branch in ("main", "dev", "HEAD", ""):
        if dirty:
            failures.append(f"You are on '{branch}' with unsaved changes. Run: git stash && <setup>/scripts/new-work.sh <slug> && git stash pop, then commit and push.")
    else:
        if not branch.startswith("bm/"):
            if dirty:
                failures.append(f"Branch '{branch}' is not a bm/ branch. Move the work: git stash && new-work.sh <slug> && git stash pop.")
        if dirty:
            failures.append(f"{len(dirty)} unsaved file(s). Commit them with a plain-language message and push to {branch}.")
        code, _ = git(root, "rev-parse", "--abbrev-ref", "@{u}")
        if code != 0:
            if changed_anything or git(root, "rev-list", "--count", "origin/main..HEAD")[1].strip() not in ("", "0"):
                failures.append(f"Branch {branch} is not on GitHub yet. Push it: git push -u origin {branch}")
        else:
            _, ahead = git(root, "rev-list", "--count", "@{u}..HEAD")
            if ahead.strip() not in ("", "0"):
                failures.append(f"{ahead.strip()} commit(s) not pushed. Run: git push")

    blocks = 0
    if os.path.exists(attempts_file):
        try:
            blocks = int(open(attempts_file).read().strip() or 0)
        except ValueError:
            blocks = 0

    if not failures:
        log(f"{sid} PASS branch={branch} " + "; ".join(summary))
        for p in (ledger, attempts_file):
            if os.path.exists(p):
                os.remove(p)
        if summary:
            print(json.dumps({"systemMessage": "persn8: checks passed, work is saved and pushed (" + "; ".join(summary) + ")"}))
        return

    blocks += 1
    with open(attempts_file, "w") as f:
        f.write(str(blocks))
    reason = "persn8: finish these before stopping.\n\n" + "\n\n".join(failures)
    if blocks <= MAX_BLOCKS:
        log(f"{sid} BLOCK #{blocks} branch={branch} " + "; ".join(summary))
        print(json.dumps({"decision": "block", "reason": reason}))
    else:
        log(f"{sid} FAIL-NOBLOCK after {blocks} branch={branch}")
        print(json.dumps({"systemMessage": f"persn8: still failing after {blocks} attempts, not blocking again. Tell the user what is wrong.\n{reason}"}))


if __name__ == "__main__":
    main()
