// LuaJIT allows 200 local variables alive at once in one function, and a file's top level is one function. A file near the limit breaks on its next `local`
// ("too many local variables"). This counts the top-level locals of every Lua file under mod/ (a statement at column 0 starting with `local`) and fails above MAX.
//   node tools/locals_check.js [max]     (default 180: 20 left over for the next features)
// shortcut: text count of column-0 `local` statements, not a parse: a `do ... end` block at the top level is counted as if it never ended, loop slots are not counted. Fine for a margin of 20.
const fs = require('fs');
const path = require('path');

const MAX = Number(process.argv[2]) || 180;
const ROOT = path.join(__dirname, '..', 'mod');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    e.isDirectory() ? walk(p, out) : /\.lua$/i.test(e.name) && out.push(p);
  }
  return out;
}

function countLocals(text) {
  let n = 0;
  for (const line of text.split(/\r?\n/)) {
    const m = /^local\s+(function\s+)?([A-Za-z_][\w]*(?:\s*,\s*[A-Za-z_][\w]*)*)/.exec(line);
    if (!m) continue;
    n += m[1] ? 1 : m[2].split(',').length;
  }
  return n;
}

if (require.main === module) {
  const rows = walk(ROOT).map((f) => [countLocals(fs.readFileSync(f, 'utf8')), path.relative(ROOT, f).split(path.sep).join('/')]).sort((a, b) => b[0] - a[0]);
  for (const [n, f] of rows.slice(0, 5)) console.log(String(n).padStart(4) + '  ' + f);
  const bad = rows.filter(([n]) => n > MAX);
  if (bad.length) { console.error('too many top-level locals (max ' + MAX + '): ' + bad.map(([n, f]) => f + ' ' + n).join(', ')); process.exit(1); }
  console.log('locals check passed: no file above ' + MAX + ' top-level locals (' + rows.length + ' Lua files)');
} else {
  module.exports = { countLocals };
}
