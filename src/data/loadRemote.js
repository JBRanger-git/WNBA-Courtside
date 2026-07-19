// Fresh-data loader. Two halves so the app never waits on the network:
//   applyCache()        — synchronous, seeds the last good snapshot before paint
//   refreshFromNetwork() — async, best-effort, swaps in the latest and re-renders
// Both are safe to call unconditionally; neither throws. Offline, the app keeps
// its cached-or-bundled data. See docs/going-live-fetch-at-runtime.md.
import { setData } from "./dataSource";

// Public, CORS-enabled URL of the snapshot the daily Action publishes.
// Overridable at build time with VITE_DATA_URL; defaults to the GitHub Pages copy.
const REMOTE_URL =
  import.meta.env.VITE_DATA_URL ||
  "https://jbranger-git.github.io/WNBA-Courtside/app-data.json";

const CACHE_KEY = "courtside:data:v1";
const TIMEOUT = 3000;

// Only trust a payload that looks like our snapshot, so a stray HTML error page
// or a truncated response can never replace good data.
const looksValid = (d) => d && d.meta && Array.isArray(d.T) && Array.isArray(d.G);

// Synchronous: apply the last good cached copy (usually newer than the bundled
// one) before first paint, so warm users see the freshest data with no wait.
export function applyCache() {
  try {
    const cached = JSON.parse(localStorage.getItem(CACHE_KEY));
    if (looksValid(cached)) setData(cached);
  } catch { /* no/broken cache — keep bundled */ }
}

// Async, time-boxed: fetch the latest snapshot and swap it in live. On any
// failure the app keeps whatever it already has.
export async function refreshFromNetwork() {
  if (!REMOTE_URL) return;
  try {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), TIMEOUT);
    const res = await fetch(REMOTE_URL, { signal: ctrl.signal, cache: "no-store" });
    clearTimeout(timer);
    if (!res.ok) return;
    const data = await res.json();
    if (looksValid(data)) {
      setData(data);
      try { localStorage.setItem(CACHE_KEY, JSON.stringify(data)); } catch {}
    }
  } catch { /* offline / slow / bad response → keep current */ }
}
