#!/usr/bin/env python3
"""PostToolUse(Write|Edit): reject comments that carry no information.

Scans only the text being written, not the whole file, so pre-existing
comments are never flagged. Comment markers follow the language: a C
preprocessor directive is code, a shell '#' is a comment.

A comment must carry something the code cannot: a formula, an ASCII
dataflow diagram, an invariant, a contract, an attribution. Length is not
the test, so a diagram or a derivation may run as long as it needs.
Rejected instead: changelog entries, workaround narration, benchmark
receipts, records of failed attempts.
"""
import json
import os
import re
import sys

MAX_LEN = 100  # chars in one comment line
# bare "I" is omitted: it collides with the identity matrix
PERSON = re.compile(r"\b(we|we'\w+|our|ours|us|you|you'\w+|your|yours|i'\w+|let's)\b", re.I)

# Categories the comment rule rejects. Each pattern names its category so the
# message tells the writer which rule fired.
REJECT = (
    ("benchmark receipt", re.compile(
        r"\bMEASURED\b"
        r"|\bbenchmark(ed|s)?\b"
        r"|\bspeed-?up\b"
        r"|[\d.]+\s*(x|%)\s*(faster|slower|win|gain|loss|speed)"
        r"|[\d.]+\s*(ms|us|µs|ns|GB/s|Gflops?)\b", re.I)),
    ("failed attempt", re.compile(
        r"\b(tried|attempt(ed|s)?|did ?n[o']t (work|help)|does ?n[o']t help"
        r"|no (gain|win|speedup)|reverted|gave up)\b", re.I)),
    ("workaround narration", re.compile(
        r"\b(work-?around|for some reason|not sure why|no idea why|somehow"
        r"|apparently|seems to|something weird|weird here)\b", re.I)),
    ("changelog entry", re.compile(
        r"\b(previous(ly)? (arg|name|version)|used to be|formerly"
        r"|renamed (from|to)|no longer (needed|used))\b", re.I)),
)

# '*' matches block-comment continuation; '#' is excluded as a directive
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

# build files that carry no extension, or a prose one, yet take '#'
BY_NAME = dict.fromkeys(
    ("CMakeLists.txt Makefile makefile GNUmakefile Dockerfile Justfile justfile"
     " Vagrantfile Rakefile SConstruct SConscript").split(), HASH)

PROSE = (".md", ".rst", ".txt", ".org", ".adoc", ".markdown")

data = json.load(sys.stdin)
if data.get("tool_name") not in ("Write", "Edit"):
    sys.exit(0)
ti = data.get("tool_input", {})
text = ti.get("content") or ti.get("new_string") or ""
path = ti.get("file_path", "")

name = os.path.basename(path)
ext = os.path.splitext(name)[1].lower()
mark = BY_NAME.get(name) or BY_EXT.get(ext)
if mark is None:
    if ext in PROSE:  # prose carries no code comments
        sys.exit(0)
    mark = HASH  # unknown suffix: '#' is the safest default

bad = []
for n, line in enumerate(text.splitlines(), 1):
    if not mark.match(line):
        continue
    if len(line.rstrip()) > MAX_LEN:
        bad.append(f"  line {n}: comment is {len(line.rstrip())} chars (max {MAX_LEN})")
    p = PERSON.search(line)
    if p:
        bad.append(f"  line {n}: first/second person \"{p.group(0)}\" — the code is the subject")
    for label, pat in REJECT:
        hit = pat.search(line)
        if hit:
            bad.append(f"  line {n}: {label} \"{hit.group(0)}\" — the memory store holds that")

if bad:
    print(
        f"Comment style violations in {path}:\n"
        + "\n".join(bad)
        + "\nA comment must carry what the code cannot: a formula, a diagram, an"
          " invariant, a contract, an attribution. Cut the rest and re-edit.",
        file=sys.stderr,
    )
    sys.exit(2)
