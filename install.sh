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

# Claude and Codex run the hook from ~/.claude/hooks, per the shipped JSON
# shapes. The copy sits after the config validation pass so a refused run
# writes nothing.

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


def registered(entries):
    """True when any entry already runs the comment-length hook."""
    if not isinstance(entries, list):
        return False
    return any(
        "no-long-comments.py" in hook.get("command", "")
        for entry in entries if isinstance(entry, dict)
        for hook in entry.get("hooks", []) if isinstance(hook, dict))


def die(path, shape):
    print(f"install.sh: {path}: {shape}; refusing to edit", file=sys.stderr)
    sys.exit(2)


# Claude settings.json and Codex hooks.json both nest hooks under "hooks".
TARGETS = [
    os.path.join(HOME, ".claude", "settings.json"),
    os.path.join(HOME, ".codex", "hooks.json"),
]

# Pass 1: load and validate every target, so a bad shape cannot leave a
# partial install behind.
plans = []
for path in TARGETS:
    data = {}
    if os.path.exists(path):
        with open(path) as f:
            data = json.load(f)  # malformed JSON aborts before any write
    if not isinstance(data, dict):
        die(path, "top level is not an object")
    if "hooks" in data and not isinstance(data["hooks"], dict):
        die(path, "hooks is not an object")
    ptu = data.get("hooks", {}).get("PostToolUse", [])
    if not isinstance(ptu, list):
        die(path, "PostToolUse is not a list")
    if not all(isinstance(entry, dict) for entry in ptu):
        die(path, "PostToolUse entry is not an object")
    for entry in ptu:
        inner = entry.get("hooks", [])
        if not isinstance(inner, list):
            die(path, "entry hooks is not a list")
        if not all(isinstance(hook, dict) for hook in inner):
            die(path, "entry hooks item is not an object")
    # Older builds wrote a stray top-level PostToolUse; count it, never add it.
    if registered(ptu) or registered(data.get("PostToolUse")):
        plans.append((path, data, "skip"))
    else:
        plans.append((path, data, "write"))

# Pass 2: merge and write.
for path, data, action in plans:
    if action == "skip":
        print(f"SKIP  {path} (hook already registered)")
        continue
    ptu = data.setdefault("hooks", {}).setdefault("PostToolUse", [])
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
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    subprocess.run([sys.executable, "-m", "json.tool", path],
                   check=True, stdout=subprocess.DEVNULL)
    print(f"WROTE {path}{backup}")
PY

# Validation passed; copy the hook script into place.
mkdir -p "$HOME/.claude/hooks"
if [ -f "$HOOK_DST" ] && cmp -s "$HOOK_SRC" "$HOOK_DST"; then
    echo "SKIP  $HOOK_DST (identical)"
else
    [ -e "$HOOK_DST" ] && cp "$HOOK_DST" "$HOOK_DST.bak.$(date -u +%Y%m%d%H%M%S)"
    cp "$HOOK_SRC" "$HOOK_DST"
    chmod +x "$HOOK_DST"
    echo "WROTE $HOOK_DST"
fi
