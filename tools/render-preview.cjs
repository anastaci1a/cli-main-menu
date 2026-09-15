#!/usr/bin/env node
// Convert frames from preview-frames.bash into a terminal-style PNG and GIF.
// Rendering uses the ANSI stream; no copy of the menu artwork lives here.
const fs = require('node:fs');
const path = require('node:path');
const { createCanvas, GlobalFonts } = require('@napi-rs/canvas');
const { GIFEncoder, quantize, applyPalette } = require('gifenc');

const input = process.argv[2];
const outputDir = process.argv[3];
if (!input || !outputDir) {
  process.stderr.write('Usage: node tools/render-preview.cjs FRAMES_FILE OUTPUT_DIR\n');
  process.exit(2);
}
const streams = fs.readFileSync(input).toString('utf8').split('\0').filter(Boolean);
if (!streams.length) throw new Error('No preview frames');
fs.mkdirSync(outputDir, { recursive: true });

GlobalFonts.registerFromPath('/usr/share/fonts/TTF/DejaVuSansMono.ttf', 'Preview Mono');
GlobalFonts.registerFromPath('/usr/share/fonts/TTF/DejaVuSansMono-Bold.ttf', 'Preview Mono Bold');
const columns = 80;
const rows = 24;
const cellWidth = 11;
const cellHeight = 20;
const padding = 20;
const width = columns * cellWidth + 2 * padding;
const height = rows * cellHeight + 2 * padding;
const canvas = createCanvas(width, height);
const ctx = canvas.getContext('2d');
const encoder = GIFEncoder();
const background = [9, 11, 17];
const levels = [0, 95, 135, 175, 215, 255];

function indexedColor(code) {
  if (code < 16) return [200, 200, 200];
  if (code >= 232) return Array(3).fill(8 + (code - 232) * 10);
  code -= 16;
  return [levels[Math.floor(code / 36)], levels[Math.floor(code / 6) % 6], levels[code % 6]];
}
function blankScreen() {
  return Array.from({ length: rows * columns }, () => ({ char: ' ', fg: [224, 224, 224], bg: background, bold: false, strike: false }));
}
function decode(stream) {
  const cells = blankScreen();
  let row = 0;
  let col = 0;
  let fg = [224, 224, 224];
  let bg = background;
  let bold = false;
  let strike = false;
  for (let pos = 0; pos < stream.length;) {
    if (stream[pos] === '\x1b' && stream[pos + 1] === '[') {
      const match = /^\x1b\[([0-9;]*)([A-Za-z])/.exec(stream.slice(pos));
      if (!match) { pos++; continue; }
      const args = match[1] ? match[1].split(';').map(Number) : [];
      if (match[2] === 'H') {
        row = (args[0] || 1) - 1;
        col = (args[1] || 1) - 1;
      } else if (match[2] === 'm') {
        for (let index = 0; index < args.length; index++) {
          const code = args[index];
          if (code === 0) { fg = [224, 224, 224]; bg = background; bold = false; strike = false; }
          else if (code === 1) bold = true;
          else if (code === 9) strike = true;
          else if (code === 38 && args[index + 1] === 2) { fg = args.slice(index + 2, index + 5); index += 4; }
          else if (code === 48 && args[index + 1] === 2) { bg = args.slice(index + 2, index + 5); index += 4; }
          else if (code === 38 && args[index + 1] === 5) { fg = indexedColor(args[index + 2]); index += 2; }
          else if (code === 48 && args[index + 1] === 5) { bg = indexedColor(args[index + 2]); index += 2; }
        }
      }
      pos += match[0].length;
      continue;
    }
    const char = stream[pos++];
    if (char === '\r') { col = 0; continue; }
    if (char === '\n') { row++; continue; }
    if (char < ' ') continue;
    if (row >= 0 && row < rows && col >= 0 && col < columns) {
      cells[row * columns + col] = { char, fg, bg, bold, strike };
    }
    col++;
  }
  return cells;
}
function paint(cells) {
  ctx.fillStyle = `rgb(${background.join(',')})`;
  ctx.fillRect(0, 0, width, height);
  for (let index = 0; index < cells.length; index++) {
    const cell = cells[index];
    const x = padding + index % columns * cellWidth;
    const y = padding + Math.floor(index / columns) * cellHeight;
    if (cell.bg !== background) {
      ctx.fillStyle = `rgb(${cell.bg.join(',')})`;
      ctx.fillRect(x, y, cellWidth, cellHeight);
    }
    if (cell.char !== ' ') {
      ctx.fillStyle = `rgb(${cell.fg.join(',')})`;
      ctx.font = cell.bold ? '17px "Preview Mono Bold"' : '17px "Preview Mono"';
      ctx.fillText(cell.char, x, y + 16);
      if (cell.strike) ctx.fillRect(x, y + 9, cellWidth, 1);
    }
  }
}
for (let index = 0; index < streams.length; index++) {
  const cells = decode(streams[index]);
  paint(cells);
  if (index === 12) fs.writeFileSync(path.join(outputDir, 'menu-preview.png'), canvas.toBuffer('image/png'));
  const rgba = ctx.getImageData(0, 0, width, height).data;
  const palette = quantize(rgba, 128);
  const indexed = applyPalette(rgba, palette);
  encoder.writeFrame(indexed, width, height, { palette, delay: 200, repeat: 0 });
}
encoder.finish();
fs.writeFileSync(path.join(outputDir, 'menu-demo.gif'), Buffer.from(encoder.bytes()));
process.stdout.write(`${streams.length} frames, ${width}x${height}\n`);
