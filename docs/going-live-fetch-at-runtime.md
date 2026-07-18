# Plan — fetch-at-runtime (daily-fresh data on installed phones)

**Status:** proposal, not yet implemented. Written for review before any code changes.

## Why
Installed Android apps never see the daily repo commits — an APK carries whatever
data shipped in *that* build. To give phone users daily-fresh standings/scores
without republishing the app, the app must **fetch its data at runtime** instead
of only reading the bundled copy.

Our data is a ~75 KB static JSON with **no secrets and no personal data**, so we
do **not** need the full backend/DB/API from `CLAUDE.md` ("Future: going live").
The right-sized version is: publish the JSON the daily Action already produces to
a public URL, and have the app fetch it with a bundled fallback.

```
daily Action builds app-data.json ──▶ publish to a public URL (CDN)
        └─ commit to repo (as today)        │
                                            ▼
                          app fetches on launch ──▶ falls back to
                          (cache ▸ network ▸ bundled)   bundled copy offline
```

This is the smallest change that reaches phones, and it reuses the entire
existing pipeline. **It does cross a v0 non-negotiable** ("no network, nothing to
declare") — see §6. That trade is the whole point of this doc.

---

## 1. How data flows today (what we're changing)
- `src/App.jsx:2` — `import DATA from "./data/app-data.json";` (static, build-time)
- `src/App.jsx:28` — `const RAW = DATA;`
- All the derived tables (`GAMES`, `TEAMS`, `STANDINGS`, `PLAYERS`, `SHOTS`, …)
  are **module-level constants computed once at import time** from `RAW`.

That last point drives the design: the cheapest correct change is to make sure
the freshest available data is in hand **before `App.jsx`'s module body runs**, so
none of the ~1,000 lines of derivation logic has to change.

---

## 2. The app change (Phase 1 — blocking bootstrap)
Three small edits, one new file. No change to any screen or derivation.

**New: `src/data/dataSource.js`** — single source of truth, defaults to bundled.
```js
import bundled from "./app-data.json";   // guaranteed offline fallback + first ship
let current = bundled;
export const setData = (d) => { current = d; };
export const getData = () => current;
```

**New: `src/data/loadRemote.js`** — cache ▸ network ▸ bundled, with a short timeout.
```js
import { setData } from "./dataSource";

const URL = import.meta.env.VITE_DATA_URL;      // e.g. https://data.courtside…/app-data.json
const KEY = "courtside:data:v1";
const TIMEOUT = 3000;

export async function loadRemote() {
  // 1) instant: last good cached copy if present (beats the possibly-older bundle)
  try {
    const cached = JSON.parse(localStorage.getItem(KEY));
    if (cached?.meta) setData(cached);
  } catch {}
  // 2) refresh from network, best-effort
  if (!URL) return;
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), TIMEOUT);
    const res = await fetch(URL, { signal: ctrl.signal, cache: "no-store" });
    clearTimeout(t);
    if (!res.ok) return;
    const data = await res.json();
    if (data?.meta && Array.isArray(data.T)) {   // shape sanity before trusting it
      setData(data);
      localStorage.setItem(KEY, JSON.stringify(data));
    }
  } catch { /* offline / slow / bad response → keep cached-or-bundled */ }
}
```

**Change `src/main.jsx`** — await the loader, then mount. Dynamically import `App`
*after* data is set so the module-level consts read the fresh data.
```js
import React from "react";
import ReactDOM from "react-dom/client";
import { loadRemote } from "./data/loadRemote";
import "./index.css";

await loadRemote();                              // cache/network, ≤3s, always resolves
const { default: App } = await import("./App.jsx");
ReactDOM.createRoot(document.getElementById("root"))
  .render(<React.StrictMode><App /></React.StrictMode>);
```

**Change `src/App.jsx:2` + `:28`**
```js
import { getData } from "./data/dataSource";
// …
const RAW = getData();
```

That's the whole app change. On a cold offline launch it renders the bundled data
instantly; online it swaps to the freshest within a few hundred ms; on a warm
cache it shows the last good data immediately even before the network answers.

### "Data as of" label (recommended)
`app-data.json`'s `meta` already carries `lastGame`. Add a `generatedAt` timestamp
in `build_data.py` and show a small "Updated {date}" line on the Today screen, so
users can see the snapshot's age. ~10 lines total.

### Phase 2 (optional, later)
Render bundled/cached instantly and swap in newer data *without* a launch await,
by threading `data` through React state/context instead of module consts. Nicer
UX, but it refactors the derivation layer — not worth it until Phase 1 is proven.

---

## 3. Hosting the JSON
Requirements: public URL, permissive **CORS** (`Access-Control-Allow-Origin: *`,
because the WebView's origin is `https://localhost`/`file://`), and low cache
staleness (updates daily).

| Option | CORS | CDN | Update path | Notes |
|---|---|---|---|---|
| **Cloudflare Pages / R2** (recommended) | ✅ | ✅ | Action uploads on each run | Free tier; set `Cache-Control` so daily updates aren't stuck behind a long TTL |
| Public GitHub repo + **jsDelivr** | ✅ | ✅ | Action pushes to a public data repo | Easiest, but jsDelivr caches up to ~12 h/7 d — needs a purge call to stay daily-fresh |
| **raw.githubusercontent.com** (public repo) | ✅ | ❌ | Action pushes to a public data repo | Simplest; not a real CDN, soft rate limits — fine for low volume to start |

The repo is **private**, so GitHub Pages would need a paid plan — prefer Cloudflare,
or a small **public** "courtside-data" repo holding only `app-data.json`.

**Recommendation:** Cloudflare Pages/R2 with a short `Cache-Control` (e.g.
`max-age=1800`). Start on GitHub raw if you want zero setup, migrate later.

---

## 4. Publishing from the daily Action
Add one step to `refresh-data.yml` (and `refresh-shots.yml`) after the gate passes,
alongside the existing repo commit:

- **Cloudflare:** `wrangler r2 object put` / Pages deploy of the single file
  (needs a Cloudflare API token in repo secrets).
- **Public data repo:** push `app-data.json` to `courtside-data` (needs a token
  with access to that repo).

The commit-to-this-repo step stays as-is (source of truth + your local `git pull`).
Publishing is purely the extra "make it reachable by phones" hop.

---

## 5. Android specifics
- **Permission:** Capacitor's default `AndroidManifest.xml` already includes
  `android.permission.INTERNET` — no manifest edit needed for the fetch.
- **Transport:** fetch over **HTTPS** only, so no cleartext/`usesCleartextTraffic`
  concerns. Capacitor 6 serves the app from `https://localhost` by default, so the
  request is HTTPS→HTTPS.
- **CORS:** the host must send `Access-Control-Allow-Origin: *` (all three options
  above do). This is the one thing that silently breaks fetches on device if missed.
- **Offline:** bundled copy guarantees the app always opens with real data; the
  `white screen ⇒ base:"./"` rule in SETUP.md is unaffected.

---

## 6. Privacy & Play Store impact (the real decision)
Fetching data adds exactly one outbound call. It stays **ad-free, no-tracking,
no-accounts, no-IAP** — none of the monetisation non-negotiables move. What changes:

- **Network permission** appears (already present via Capacitor).
- **Data Safety form** is no longer "no network calls." It stays nearly empty:
  no data *collected*, no personal info, no tracking/advertising ID. You declare a
  network connection used to fetch public sports statistics. That's it.
- **App privacy stance:** still strong — arguably a selling point — but it is no
  longer *literally zero network*. This is the v0 non-negotiable being revisited on
  purpose, for the daily-freshness goal. Your call to make explicitly.

---

## 7. ESPN terms-of-service (unchanged, but now the moment to settle it)
The data is ESPN-derived whether bundled or fetched, so fetch-at-runtime doesn't
worsen the ToS posture per se — but you'd be **publicly distributing** an app that
serves that data daily. This is the boundary `CLAUDE.md` flags for going public,
and it wants a decision before shipping. Fetching public stats you host yourself
(not hot-linking ESPN from the app) keeps the app one step removed, which is the
posture the "no logos/headshots" rules were designed to preserve.

---

## 8. Freshness follow-on (now worth doing)
Once phones fetch daily, the 1–3 day bulk-feed lag actually reaches users, so the
**live "recent finals" top-up** becomes worthwhile: in the daily Action, pull just
the last ~4 days of completed games from wehoop's live ESPN box endpoint to fill
the gap, layered on the reliable bulk backbone. The validation gate already means a
flaky live call just falls back to bulk — no bad data ships. Do this *after*
Phase 1, as a separate change.

---

## 9. Rollout & testing
1. **Browser:** set `VITE_DATA_URL` to the hosted file; confirm it fetches and the
   "Updated" date reflects the remote, not the bundle. Kill the network → confirm it
   falls back to cached/bundled with no blank screen.
2. **Offline-first launch:** clear cache + offline → bundled data renders instantly.
3. **Device:** build the APK, confirm the fetch works over HTTPS (this is where a
   missing CORS header shows up), and airplane-mode still opens the app.
4. **Gate unchanged:** `npm run verify` / the CI gates already protect the JSON's
   contents; this change only affects *delivery*, not shape.

---

## 10. Effort & risks
- **Effort:** app change ~half a day incl. device/offline testing; hosting + Action
  publish step ~2–3 h; plus the usual wehoop/CI iteration if we add §8 later.
- **Main risk:** CORS on device (mitigated: pick a host that sends `*`, test on
  device). Secondary: cache staleness on jsDelivr (mitigated: Cloudflare or a purge).
- **Reversible?** Yes — it's additive. Remove `VITE_DATA_URL` and the app is back to
  pure bundled behavior; no data-shape or screen changes to unwind.

---

## Decision points for you
1. **Go/no-go on crossing "zero network"** for daily-fresh phone data (§6).
2. **Host:** Cloudflare (recommended) vs public GitHub repo + jsDelivr vs GitHub raw (§3).
3. **Settle the ESPN public-distribution question** before shipping (§7).
4. **Phase 1 now, §8 live top-up later?** (recommended ordering.)
