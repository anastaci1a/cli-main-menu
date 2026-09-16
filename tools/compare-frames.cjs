#!/usr/bin/env node
// Compare actual terminal cells, including RGB and weight, rather than ANSI byte
// spelling. Captures come from BENCH_CAPTURE=... bash tools/benchmark.bash.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const [before, after] = process.argv.slice(2).map(file => fs.readFileSync(file, 'utf8').split('\0'));
assert.equal(before.length, after.length, 'frame count');
function terminal() {
  let row = 1, col = 1, fg = '', bold = false, strike = false;
  const cells = new Map();
  return stream => {
    for (let offset = 0; offset < stream.length;) {
      if (stream[offset] === '\x1b') {
        const match = /^\x1b\[([\d;]*)([A-Za-z])/.exec(stream.slice(offset));
        assert.ok(match, 'supported escape sequence');
        offset += match[0].length;
        const args = match[1].split(';').map(Number);
        switch (match[2]) {
          case 'H': row = args[0] || 1; col = args[1] || 1; break;
          case 'C': col += args[0] || 1; break;
          case 'G': col = args[0] || 1; break;
          case 'J':
            assert.equal(args[0], 0, 'erase to end of screen');
            for (const key of cells.keys()) {
              const [r, c] = key.split(':').map(Number);
              if (r > row || (r === row && c >= col)) cells.delete(key);
            }
            break;
          case 'm':
            for (let index = 0; index < args.length; index++) {
              const code = args[index];
              if (!code) { fg = ''; bold = strike = false; }
              else if (code === 1) bold = true;
              else if (code === 22) bold = false;
              else if (code === 9) strike = true;
              else if (code === 29) strike = false;
              else if (code === 38 && args[index + 1] === 2) { fg = args.slice(index + 2, index + 5).join(';'); index += 4; }
              else if (code === 38 && args[index + 1] === 5) { fg = `indexed:${args[index + 2]}`; index += 2; }
              else assert.fail(`unsupported SGR ${code}`);
            }
            break;
          default: assert.fail(`unsupported command ${match[2]}`);
        }
        continue;
      }
      const glyph = String.fromCodePoint(stream.codePointAt(offset));
      offset += glyph.length;
      if (glyph === '\r') { col = 1; continue; }
      if (glyph === '\n') { row++; continue; }
      const key = `${row}:${col++}`;
      if (glyph === ' ' && !strike) cells.delete(key);
      else cells.set(key, `${glyph}:${fg}:${+bold}:${+strike}`);
    }
    return new Map([...cells].sort(([a], [b]) => a.localeCompare(b)));
  };
}
const oldScreen = terminal(), newScreen = terminal();
for (let index = 0; index < before.length - 1; index += 4) {
  assert.equal(before[index], after[index], 'frame time');
  assert.deepEqual(newScreen(after[index + 1]), oldScreen(before[index + 1]), `animation at ${before[index]} ms`);
  assert.equal(after[index + 2], before[index + 2], `status color at ${before[index]} ms`);
  assert.deepEqual(terminal()(after[index + 3]), terminal()(before[index + 3]), `repair at ${before[index]} ms`);
}
console.log(`PASS ${(before.length - 1) / 4} identical animation frames, status colors, and foreground repairs`);
