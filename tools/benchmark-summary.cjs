#!/usr/bin/env node
const fs = require('node:fs');
for (const file of process.argv.slice(2)) {
  const rows = fs.readFileSync(file, 'utf8').trim().split('\n').slice(1).map(line => line.split(',').map(Number));
  for (const [phase, keep] of [
    ['sweep', t => t >= 4000 && t % 4000 < 1467],
    ['idle', t => t > 0 && t % 4000 >= 1467],
  ]) {
    const sample = rows.filter(row => keep(row[0]));
    const times = sample.map(row => row[1] / 1000).sort((a, b) => a - b);
    const mean = times.reduce((sum, time) => sum + time, 0) / times.length;
    const bytes = sample.reduce((sum, row) => sum + row[2], 0) / sample.length;
    console.log(`${file} ${phase}: mean ${mean.toFixed(2)} ms, p95 ${times[Math.floor(times.length * .95)].toFixed(2)} ms, ${Math.round(bytes)} bytes/frame`);
  }
}
