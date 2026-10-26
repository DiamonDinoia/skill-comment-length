// comment-length — OpenCode plugin.
//
// PostToolUse(write|edit) for OpenCode: blocks edits whose comment lines run
// past MAX_LEN characters. Ports the length rule of hook/no-long-comments.py;
// the person and category checks stay in the Python hook, which this plugin
// does not replace.
//
// OpenCode loads server plugins from the "plugins" array in opencode.json:
//   { "plugins": ["file:///path/to/comment-length.js"] }
//
// The export shape (id + server() hook map) mirrors the locally installed
// ponytail plugin (.opencode/plugins/ponytail.mjs). No local reference
// documents the tool hook name or the argument field names, so
// 'tool.execute.before' follows the upstream OpenCode plugin docs:
// UNVERIFIED against this machine's opencode v2.0.25.

const MAX_LEN = 100;

// '*' matches block-comment continuation; '#' is excluded as a directive.
const C_LIKE = /^\s*(\/\/|\/\*|\*)/;
const HASH = /^\s*#/;
const DASH = /^\s*--/;
const PERCENT = /^\s*%/;
const SEMI = /^\s*;/;

const BY_EXT = {};
for (const [exts, mark] of [
  ['c h cpp hpp cc hh cxx hxx ipp inl cu cuh java js mjs cjs ts tsx jsx rs go swift kt kts scala cs php dart proto glsl', C_LIKE],
  ['py sh bash zsh fish rb pl pm yaml yml toml cmake mk jl nim tcl awk r gnuplot cfg ini conf', HASH],
  ['lua sql hs elm adb ads vhd vhdl', DASH],
  ['tex sty cls erl', PERCENT],
  ['el lisp cl clj cljs scm rkt asm s', SEMI],
]) {
  for (const ext of exts.split(' ')) BY_EXT[ext] = mark;
}

// Build files that carry no extension, or a prose one, yet take '#'.
const BY_NAME = {};
for (const name of ('CMakeLists.txt Makefile makefile GNUmakefile Dockerfile Justfile justfile ' +
    'Vagrantfile Rakefile SConstruct SConscript').split(' ')) BY_NAME[name] = HASH;

const PROSE = new Set(['md', 'rst', 'txt', 'org', 'adoc', 'markdown']);

function markerFor(filePath) {
  const name = filePath.split('/').pop();
  const ext = (name.includes('.') ? name.split('.').pop() : '').toLowerCase();
  if (BY_NAME[name]) return BY_NAME[name];
  if (BY_EXT[ext]) return BY_EXT[ext];
  if (PROSE.has(ext)) return null; // prose carries no code comments
  return HASH; // unknown suffix: '#' is the safest default
}

// Returns the violation lines, or null when clean.
function check(filePath, text) {
  const mark = markerFor(filePath);
  if (!mark || !text) return null;
  const bad = [];
  text.split('\n').forEach((line, i) => {
    const trimmed = line.replace(/\s+$/, '');
    if (mark.test(line) && trimmed.length > MAX_LEN) {
      bad.push(`  line ${i + 1}: comment is ${trimmed.length} chars (max ${MAX_LEN})`);
    }
  });
  return bad.length ? bad : null;
}

export default {
  id: 'comment-length',

  async server() {
    return {
      'tool.execute.before': async (input, output) => {
        if (!input || (input.tool !== 'write' && input.tool !== 'edit')) return;
        const args = (output && output.args) || {};
        // Field names differ between the write and edit tools; read both spellings.
        const filePath = args.file_path || args.filePath || '';
        const text = String(args.content || args.new_string || args.newString || '');
        const bad = check(filePath, text);
        if (bad) {
          throw new Error(
            `Comment style violations in ${filePath}:\n${bad.join('\n')}\n` +
            'A comment line must fit in 100 chars. Cut it down and re-edit.');
        }
      },
    };
  },
};
