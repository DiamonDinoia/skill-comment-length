# skill-comment-length

Reject comment lines over `MAX_LEN = 100` chars when an agent writes or edits code.

## What it does

The hook runs on PostToolUse(Write|Edit). It scans only the text being
written, not the whole file, so pre-existing comments are never flagged. A
comment marker follows the language: a C preprocessor directive is code, a
shell '#' is a comment. Prose files carry no code comments and are skipped.

The Python hook (Claude Code, Codex) also checks first/second person and
four reject categories: benchmark receipts, failed attempts, workaround
narration, changelog entries. The opencode and hermes ports implement the
length rule only.

## Install

Run the install script from a clone of the repo. It handles Claude Code and
Codex, needs only python3 and the shell, and is idempotent: an existing
registration prints SKIP and the file is not touched. Any file it edits is
first backed up next to itself with a UTC timestamp suffix.

```
./skill-comment-length/install.sh
```

Claude Code. The script copies `hook/no-long-comments.py` to
`~/.claude/hooks/` and merges a `PostToolUse` entry with matcher
`Write|Edit` into `~/.claude/settings.json`.

Codex. The script merges the same hook into `~/.codex/hooks.json` under
`hooks.PostToolUse`. Codex asks to trust the changed file on the next
start.

OpenCode. UNVERIFIED: no local API reference documents the tool hook name,
so `plugins/opencode/comment-length.js` follows the upstream opencode
plugin docs and the export shape of the locally installed ponytail plugin.
Add it to `~/.config/opencode/opencode.json`:

```
"plugins": ["file:///path/to/skill-comment-length/plugins/opencode/comment-length.js"]
```

Hermes. The plugin uses the `post_tool_call` hook, which fires after the
edit lands, so it warns in the log instead of rejecting the edit. Install
the directory as a Hermes plugin:

```
hermes plugins install /path/to/skill-comment-length/plugins/hermes
```

## Uninstall

```
rm ~/.claude/hooks/no-long-comments.py
hermes plugins remove comment-length
```

Remove the `Write|Edit` entry from `~/.claude/settings.json` and
`~/.codex/hooks.json` by hand, or restore the `.bak.<timestamp>` file the
installer left next to each. Remove the plugin path from
`~/.config/opencode/opencode.json`.

## Layout

- `hook/no-long-comments.py` — the hook, byte-identical to
  `~/.claude/hooks/no-long-comments.py`.
- `install.sh` — idempotent installer for the two JSON-config harnesses.
- `plugins/opencode/comment-length.js` — opencode plugin, length rule.
- `plugins/hermes/` — Hermes plugin (`plugin.yaml`, `__init__.py`),
  length rule.

## License

MIT. See `LICENSE`.
