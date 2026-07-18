// Refresh-safe invariants. Unlike smoke.mjs (which pins snapshot-specific values
// like "A'ja = 33.2% usage" and "Toronto = 3 venues" that legitimately change as a
// season plays out), this asserts only the things that must hold for ANY valid
// snapshot — the silent-corruption traps from CLAUDE.md. Used as the gate in the
// daily refresh workflow, where the pinned values would produce false failures.
import { readFileSync, readdirSync } from 'fs';
const f = readdirSync('dist/assets').find(x => x.endsWith('.js'));
const js = readFileSync('dist/assets/' + f, 'utf8');
const D = JSON.parse(readFileSync('src/data/app-data.json', 'utf8'));
const usages = D.P.map(p => p[16]).filter(u => u != null);
const checks = [
  ['teams present',                       D.T.length >= 12],
  ['standings sorted by win pct',         D.S[0][3] >= D.S[D.S.length - 1][3]],
  ['games exclude teamless rows',         D.G.every(g => g[2] && g[3])],
  ['completed count matches box scores',  D.G.filter(g => g[9]).length === D.meta.completedGames],
  ['season in progress (some done, some upcoming)',
                                          D.meta.completedGames > 0 && D.meta.totalGames > D.meta.completedGames],
  ['players present',                     D.P.length > 50],
  ['usage is a percent not a fraction',   usages.every(u => u < 100) && Math.max(...usages) > 1],
  ['ppg values are sane',                 D.P.every(p => p[6] >= 0 && p[6] < 60)],
  ['shot fingerprints present',           D.SHOTS && Object.keys(D.SHOTS.P).length > 100],
  ['zone freqs sum to ~100 per player',   Object.values(D.SHOTS.P).every(p => Math.abs(p.f.reduce((a, b) => a + b, 0) - 100) < 0.6)],
  // Zone-geometry sanity: the restricted area must be the most efficient zone
  // (~60%), and corner threes must beat above-the-break threes. Catches a
  // miscalibrated shot-zone derivation before it can be committed.
  ['restricted area is the top-FG% zone', D.SHOTS.LG.fg[0] === Math.max(...D.SHOTS.LG.fg) && D.SHOTS.LG.fg[0] >= 55 && D.SHOTS.LG.fg[0] <= 72],
  ['corner 3 FG% >= above-break 3 FG%',   D.SHOTS.LG.fg[3] >= D.SHOTS.LG.fg[4] - 1],
  ['bundle embeds the data',              js.length > 50000],
  ['bundle has no raw pbp leak',          js.length < 400000],
];
let bad = 0;
for (const [n, ok] of checks) { console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${n}`); if (!ok) bad++; }
console.log(bad ? `\n${bad} FAILED` : '\nAll checks passed.');
process.exit(bad ? 1 : 0);
