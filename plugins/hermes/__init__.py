"""comment-length — Hermes plugin.

post_tool_call hook that ports the length rule of hook/no-long-comments.py
to Hermes write_file and patch calls. post_tool_call fires after the edit
lands, so the hook logs a warning instead of rejecting the edit. The Claude
Code and Codex hooks can reject; this one only reports.
"""

import logging
import os
import re

MAX_LEN = 100  # chars in one comment line

C_LIKE = re.compile(r"^\s*(//|/\*|\*)")
HASH = re.compile(r"^\s*#")
DASH = re.compile(r"^\s*--")
PERCENT = re.compile(r"^\s*%")
SEMI = re.compile(r"^\s*;")

BY_EXT = {}
for _exts, _mark in (
    (".c .h .cpp .hpp .cc .hh .cxx .hxx .ipp .inl .cu .cuh .java .js .mjs .cjs .ts .tsx"
     " .jsx .rs .go .swift .kt .kts .scala .cs .php .dart .proto .glsl", C_LIKE),
    (".py .sh .bash .zsh .fish .rb .pl .pm .yaml .yml .toml .cmake .mk .jl .nim .tcl"
     " .awk .r .gnuplot .cfg .ini .conf", HASH),
    (".lua .sql .hs .elm .adb .ads .vhd .vhdl", DASH),
    (".tex .sty .cls .erl", PERCENT),
    (".el .lisp .cl .clj .cljs .scm .rkt .asm .s", SEMI),
):
    BY_EXT.update(dict.fromkeys(_exts.split(), _mark))

BY_NAME = dict.fromkeys(
    ("CMakeLists.txt Makefile makefile GNUmakefile Dockerfile Justfile justfile"
     " Vagrantfile Rakefile SConstruct SConscript").split(), HASH)

PROSE = (".md", ".rst", ".txt", ".org", ".adoc", ".markdown")

logger = logging.getLogger(__name__)


def _marker_for(path):
    name = os.path.basename(path)
    ext = os.path.splitext(name)[1].lower()
    mark = BY_NAME.get(name) or BY_EXT.get(ext)
    if mark is not None:
        return mark
    if ext in PROSE:
        return None
    return HASH


def _violations(path, text):
    mark = _marker_for(path)
    if mark is None or not text:
        return []
    return [
        f"  line {n}: comment is {len(line.rstrip())} chars (max {MAX_LEN})"
        for n, line in enumerate(text.splitlines(), 1)
        if mark.match(line) and len(line.rstrip()) > MAX_LEN
    ]


def _on_post_tool_call(tool_name, args, result, task_id, **kwargs):
    """Warn when a written or patched comment line runs past MAX_LEN."""
    if tool_name not in ("write_file", "patch"):
        return
    args = args or {}
    path = args.get("path") or args.get("file_path") or ""
    text = args.get("content") or args.get("new_string") or ""
    bad = _violations(path, text)
    if bad:
        logger.warning(
            "Comment style violations in %s:\n%s\n"
            "A comment line must fit in 100 chars. Re-edit to fix.",
            path, "\n".join(bad),
        )


def register(ctx):
    ctx.register_hook("post_tool_call", _on_post_tool_call)
