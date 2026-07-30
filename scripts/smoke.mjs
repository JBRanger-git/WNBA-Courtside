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
  ['games reference only real clubs (All-Star filtered)',
    (() => { const ids = new Set(D.T.map(t => t[0])); return D.G.every(g => ids.has(g[2]) && ids.has(g[3])); })()],
  ['completed count matches box scores', D.G.filter(g=>g[9]).length === D.meta.completedGames],
  ['usage is a percent not a fraction', D.P[0][16] > 1],
  ["A'ja Wilson usage ~33%", Math.abs(D.P.find(p=>p[1]==="A'ja Wilson")[16] - 33.2) < 0.5],
  ['shot fingerprints present', Object.keys(D.SHOTS.P).length > 100],
  ['zone freqs sum to ~100 per player', Object.values(D.SHOTS.P).every(p => Math.abs(p.f.reduce((a,b)=>a+b,0)-100) < 0.6)],
  ['league corner3 FG% > above-break FG%', D.SHOTS.LG.fg[3] > D.SHOTS.LG.fg[4]],
  // PG (per-game shot data) doesn't exist in every snapshot yet — it's new and
  // only populated once the daily refresh runs fetch_shots.R again. Passes
  // trivially until then; once present, actually checks its shape. Accepts
  // both the pre-FT shape (11: pts + 5 zone pairs) and the current one (13:
  // + trailing ftm,fta) since the committed snapshot may still be mid-rollout.
  ['per-game shots well-formed (if present)', !D.SHOTS.PG || Object.values(D.SHOTS.PG).every(games =>
    Object.values(games).every(row => (row.length === 11 || row.length === 13)
      && row.every(x => Number.isFinite(x) && x >= 0)
      && [0,1,2,3,4].every(i => row[2+i*2] <= row[1+i*2])
      && (row.length < 13 || row[11] <= row[12])))],
  ['team bio has Toronto multi-venue', D.TEAM_BIO['131935'].alt.length === 3],
  ['bundle embeds the data', js.includes("A'ja Wilson")],
  // Tripwire for a raw-pbp leak (~54 MB), not a tight budget; checks the largest
  // chunk, with headroom for the head-to-head game log (GHIST) and per-game shot
  // data (SHOTS.PG, added ~134KB with 210/332 games completed — real number from
  // the 2026-07-30 catch-up refresh, run 30537074823, which is what caught the
  // old 480000 ceiling being too tight the moment PG had real data behind it).
  // 900000 leaves headroom for PG to grow through the rest of the season while
  // staying two orders of magnitude below an actual leak.
  ['bundle has no raw pbp leak', maxJs < 900000],
];
let bad = 0;
for (const [n, ok] of checks) { console.log(`  ${ok?'PASS':'FAIL'}  ${n}`); if(!ok) bad++; }
console.log(bad ? `\n${bad} FAILED` : '\nAll checks passed.');
process.exit(bad?1:0);
