// Prove the built bundle actually contains real data, not an empty shell.
import { readFileSync, readdirSync } from 'fs';
const f = readdirSync('dist/assets').find(x => x.endsWith('.js'));
const js = readFileSync('dist/assets/'+f, 'utf8');
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
  ['bundle has no raw pbp leak', js.length < 400000],
];
let bad = 0;
for (const [n, ok] of checks) { console.log(`  ${ok?'PASS':'FAIL'}  ${n}`); if(!ok) bad++; }
console.log(bad ? `\n${bad} FAILED` : '\nAll checks passed.');
process.exit(bad?1:0);
