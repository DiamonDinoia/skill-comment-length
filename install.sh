#!/bin/bash
# Install the comment-length hook and register it in the Claude Code and Codex
# hook configs. Idempotent: a config that already has the hook prints SKIP and
# is not touched. Needs only python3 and the shell.
set -eu

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
HOOK_SRC="$REPO_DIR/hook/no-long-comments.py"
HOOK_DST="$HOME/.claude/hooks/no-long-comments.py"

if [ -z "${HOME:-}" ]; then
    echo "install.sh: HOME is not set; export HOME and retry" >&2
    exit 1
fi
command -v python3 >/dev/null 2>&1 || { echo "install.sh: python3 not found" >&2; exit 1; }

# Claude and Codex run the hook from ~/.claude/hooks, per the shipped JSON shapes.
mkdir -p "$HOME/.claude/hooks"
if [ -f "$HOOK_DST" ] && cmp -s "$HOOK_SRC" "$HOOK_DST"; then
    echo "SKIP  $HOOK_DST (identical)"
else
    [ -e "$HOOK_DST" ] && cp "$HOOK_DST" "$HOOK_DST.bak.$(date -u +%Y%m%d%H%M%S)"
    cp "$HOOK_SRC" "$HOOK_DST"
    chmod +x "$HOOK_DST"
    echo "WROTE $HOOK_DST"
fi

python3 - <<'PY'
"""Merge the comment-length PostToolUse(Write|Edit) hook into both configs."""
import datetime
import json
import os
import shutil
import subprocess
import sys

COMMAND = ('test -x "$HOME/.claude/hooks/no-long-comments.py" '
           '&& "$HOME/.claude/hooks/no-long-comments.py"')
HOOK = {"type": "command", "command": COMMAND}
HOME = os.environ["HOME"]
TS = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")

# (path, nested): Codex keeps its hooks under a top-level "hooks" key.
TARGETS = [
    (os.path.join(HOME, ".claude", "settings.json"), False),
    (os.path.join(HOME, ".codex", "hooks.json"), True),
]

for path, nested in TARGETS:
    data = {}
    if os.path.exists(path):
        with open(path) as f:
            data = json.load(f)  # malformed JSON aborts before any write
    container = data.setdefault("hooks", {}) if nested else data
    ptu = container.setdefault("PostToolUse", [])
    if not isinstance(ptu, list):
        print(f"install.sh: {path}: PostToolUse is not a list; leaving it alone",
              file=sys.stderr)
        continue
    already = any(
        COMMAND in hook.get("command", "")
        for entry in ptu if isinstance(entry, dict)
        for hook in entry.get("hooks", []) if isinstance(hook, dict))
    if already:
        print(f"SKIP  {path} (hook already registered)")
        continue
    for entry in ptu:
        if entry.get("matcher") == "Write|Edit":
            entry.setdefault("hooks", []).append(dict(HOOK))
            break
    else:
        ptu.append({"matcher": "Write|Edit", "hooks": [dict(HOOK)]})
    backup = ""
    if os.path.exists(path):
        backup = f" (backup: {path}.bak.{TS})"
        shutil.copy2(path, f"{path}.bak.{TS}")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    subprocess.run([sys.executable, "-m", "json.tool", path],
                   check=True, stdout=subprocess.DEVNULL)
    print(f"WROTE {path}{backup}")
PY
