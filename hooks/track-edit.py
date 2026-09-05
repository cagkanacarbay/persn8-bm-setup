#!/usr/bin/env python3
"""PostToolUse hook. Records every .ts/.tsx file Claude edits inside the Persn8 clone
into a per-session ledger under ~/.persn8-bm/, for the Stop hook to lint and test."""
import json, os, re, sys

STATE = os.path.expanduser("~/.persn8-bm")


def repo_dir(d: dict) -> str:
    r = os.environ.get("CLAUDE_PROJECT_DIR") or ""
    if not r:
        p = os.path.join(STATE, "repo_dir")
        if os.path.exists(p):
            r = open(p).read().strip()
    return r or d.get("cwd") or ""


def main() -> None:
    try:
        d = json.load(sys.stdin)
    except Exception:
        return
    root = os.path.realpath(repo_dir(d))
    if not root or not os.path.isdir(os.path.join(root, ".git")):
        return
    cwd = d.get("cwd") or root
    sid = re.sub(r"[^A-Za-z0-9_.-]", "_", str(d.get("session_id") or "unknown"))
    ti = d.get("tool_input") or {}
    paths = []
    fp = ti.get("file_path")
    if isinstance(fp, str):
        paths.append(fp)
    for e in ti.get("edits") or []:
        if isinstance(e, dict) and isinstance(e.get("file_path"), str):
            paths.append(e["file_path"])
    keep = []
    for p in paths:
        p = p.strip()
        if not os.path.isabs(p):
            p = os.path.normpath(os.path.join(cwd, p))
        p = os.path.realpath(p)
        if not p.endswith((".ts", ".tsx")):
            continue
        if not p.startswith(root + "/") or "/node_modules/" in p:
            continue
        keep.append(p)
    if not keep:
        return
    os.makedirs(STATE, exist_ok=True)
    with open(os.path.join(STATE, sid + ".files"), "a") as f:
        for p in keep:
            f.write(p + "\n")


if __name__ == "__main__":
    main()
