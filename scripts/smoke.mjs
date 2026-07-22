// Prove the built bundle actually contains real data, not an empty shell.
import { readFileSync, readdirSync } from 'fs';
// Vite splits into multiple JS chunks (App code vs the data chunk) and the data
// can land in any of them, so scan them all rather than the first one the
// filesystem happens to list. `js` = all chunks concatenated (content checks);
// `maxJs` = the largest single chunk (the pbp-leak size guard).
const blobs = readdirSync('dist/assets').filter(x => x.endsWith('.js'))
  .map(x => readFileSync('dist/assets/' + x, 'utf8'));
const js = blobs.join('\n');
const maxJs = Math.max(...blobs.map(b => b.length));
const D = JSON.parse(readFileSync('src/data/app-data.json','utf8'));
const checks = [
  ['teams', D.T.length === 15],
  ['standings sorted by win pct', D.S[0][3] >= D.S[14][3]],
  ['games exclude teamless All-Star row', D.G.every(g => g[2] && g[3])],
  ['completed count matches box scores', D.G.filter(g=>g[9]).length === D.meta.completedGames],
  ['usage is a percent not a fraction', D.P[0][16] > 1],
  ["A'ja Wilson usage ~33%", Math.abs(D.P.find(p=>p[1]==="A'ja Wilson")[16] - 33.2) < 0.5],
  ['shot fingerprints present', Object.keys(D.SHOTS.P).length > 100],
  ['zone freqs sum to ~100 per player', Object.values(D.SHOTS.P).every(p => Math.abs(p.f.reduce((a,b)=>a+b,0)-100) < 0.6)],
  ['league corner3 FG% > above-break FG%', D.SHOTS.LG.fg[3] > D.SHOTS.LG.fg[4]],
  ['team bio has Toronto multi-venue', D.TEAM_BIO['131935'].alt.length === 3],
  ['bundle embeds the data', js.includes("A'ja Wilson")],
  // Tripwire for a raw-pbp leak (~54 MB), not a tight budget; checks the largest
  // chunk, with headroom for the head-to-head game log (GHIST).
  ['bundle has no raw pbp leak', maxJs < 480000],
];
let bad = 0;
for (const [n, ok] of checks) { console.log(`  ${ok?'PASS':'FAIL'}  ${n}`); if(!ok) bad++; }
console.log(bad ? `\n${bad} FAILED` : '\nAll checks passed.');
process.exit(bad?1:0);
