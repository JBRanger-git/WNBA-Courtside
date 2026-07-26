// Refresh-safe invariants. Unlike smoke.mjs (which pins snapshot-specific values
// like "A'ja = 33.2% usage" and "Toronto = 3 venues" that legitimately change as a
// season plays out), this asserts only the things that must hold for ANY valid
// snapshot — the silent-corruption traps from CLAUDE.md. Used as the gate in the
// daily refresh workflow, where the pinned values would produce false failures.
import { readFileSync, readdirSync } from 'fs';
// Vite splits into multiple JS chunks and the data can land in any of them, so
// scan them all. `js` = all chunks concatenated (content checks); `maxJs` = the
// largest single chunk (the pbp-leak size guard).
const blobs = readdirSync('dist/assets').filter(x => x.endsWith('.js'))
  .map(x => readFileSync('dist/assets/' + x, 'utf8'));
const js = blobs.join('\n');
const maxJs = Math.max(...blobs.map(b => b.length));
const D = JSON.parse(readFileSync('src/data/app-data.json', 'utf8'));
const usages = D.P.map(p => p[16]).filter(u => u != null);
const checks = [
  ['teams present',                       D.T.length >= 12],
  // WNBA franchise count grows slowly (expansion, not weekly). This is the
  // check that would have caught "Team Spoon"/"Team Coop" (All-Star draft
  // squads) leaking into the team list as if they were real clubs.
  ['team count is sane (no synthetic squads)', D.T.length <= 16],
  ['standings sorted by win pct',         D.S[0][3] >= D.S[D.S.length - 1][3]],
  ['games reference only real clubs (All-Star filtered)',
    (() => { const ids = new Set(D.T.map(t => t[0])); return D.G.every(g => ids.has(g[2]) && ids.has(g[3])); })()],
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
  // Cap is a raw-pbp-leak tripwire (pbp is ~54 MB), not a tight budget. Checks
  // the largest chunk, with headroom for the head-to-head game log (GHIST) — a
  // leak would still blow past this by orders of magnitude.
  ['bundle has no raw pbp leak',          maxJs < 480000],
];
let bad = 0;
for (const [n, ok] of checks) { console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${n}`); if (!ok) bad++; }
console.log(bad ? `\n${bad} FAILED` : '\nAll checks passed.');
process.exit(bad ? 1 : 0);
