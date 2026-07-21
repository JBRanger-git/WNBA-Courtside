# Session status & handoff

**Purpose:** resume point for a fresh Claude Code session. Read this + `CLAUDE.md`
first. Lives on the **default branch** so it survives dev-branch restarts.

---

## TL;DR — where things are right now

- **App:** WNBA Courtside (React + Vite + Capacitor → Android). Package
  `uk.co.courtside.wnba`. Contact `raiappsdev@gmail.com`.
- **Play Store:** in **Closed testing**. **v5 (versionCode 5) is the last build
  uploaded.** Everything below (v6 + v7 + history) is **merged to default but not
  yet built/uploaded** — it all ships in the **next local AAB build (use
  versionCode 7)**.
- **Gate to production:** **12 testers** opted in for **14 continuous days**, then
  *Apply for production*. Live count is only in Play Console → Test and release →
  Testing → Closed testing (not tracked in this repo).
- **Data is fetched at runtime** from GitHub Pages (`docs/app-data.json`), rebuilt
  daily by GitHub Actions. No rebuild needed for *data* — only for app/UI changes.

---

## ⚠️ Read before doing any data work

- **ESPN and GitHub Pages are BLOCKED from the Claude sandbox** (403 at the agent
  proxy). Anything that fetches ESPN (`fetch_wnba.R`, `fetch_news.R`,
  `fetch_lines.R`, `backfill_history.R`) or reads the live Pages JSON can only run
  and be verified in **GitHub Actions**, never locally. Build the code, push, run
  the workflow, read the logs. The app itself falls back to **bundled** data in
  the sandbox (Pages unreachable), so local screenshots use bundled data.
- **workflow_dispatch needs the workflow on the DEFAULT branch first.** To test a
  brand-new workflow on a feature branch, add a temporary path-scoped `push`
  trigger, verify, then remove it (that's how `backfill-history.yml` was tested).
- **Claude feature branches drift from default over a long session.** Before
  merging, check `git diff --stat <default>..<branch>` and make sure it doesn't
  clobber `package.json` (icon tooling) or the `refresh-*.yml` workflows. If it
  does, rebuild the branch on current default carrying only the intended files.

---

## Play Console facts

- Developer account **personal**, verified. Store name **WNBA Courtside**.
- **Privacy policy URL:** https://jbranger-git.github.io/WNBA-Courtside/ (Pages
  from `docs/`; source `docs/privacy.html` + `PRIVACY.md`).
- **Data Safety:** no data collected / shared (still true).
- **Version codes used (uploaded): 1–5.** Next build must be **> 5**; use **7**.
- **Keystore (UNRECOVERABLE — back it up):** `android/app/courtside-release.jks`
  via `android/keystore.properties` (both gitignored). Enrolled in Play App Signing.

---

## What shipped to default this session (all merged, awaiting a build)

| PR | What |
|----|------|
| #14 (v6) | Player profile **bio line** (data-derived) + **"Club"→"Team"** label; **Wire** = live clickable ESPN news (`fetch_news.R`); SESSION-STATUS onto default |
| #15 (v7) | **Android back button**: navigate one level (search/detail pop), **"Exit Courtside?"** dialog on a top-level tab; **quarter-by-quarter scores** on the game page (`fetch_lines.R` → `GL`); **dark-mode fix** (root `color` so bare figures aren't invisible) |
| #16 | Commit **icon tooling** (`sharp`, `@capacitor/assets`, Capacitor 6.2.1) into `package.json` so it stops colliding with pulls; workflows use `npm ci --ignore-scripts` |
| #17 | **Historical seasons & career arcs (2020–present)** — player **Career** tab + team **History** tab, `backfill_history.R`, `PHIST`/`THIST` in `build_data.py`, `backfill-history.yml`; plus **polish** (standings #/STRK centred, 4-tab spacing, career-chart labels) |

Earlier (previous session): #2 privacy/listing; #3 phone-frame fix + game page; #4/#5
fetch-at-runtime; #6/#7 §8 live score top-up; #8/#9 postponements; #10 box score +
top performers; #11 light/dark theme; #12 device-frame skill; #13 dark shot chart.

---

## Data pipeline (current)

```
Daily 11:00 UTC · refresh-data.yml  (fetch_wnba.R + fetch_news.R + fetch_lines.R → build_data.py)
Weekly        · refresh-shots.yml   (fetch_shots.R → shot fingerprints)
Manual        · backfill-history.yml (backfill_history.R → PHIST/THIST) — dispatch from Actions tab
        │
        ▼  build_data.py → src/data/app-data.json (+ copy to docs/app-data.json)
        ▼  commit → GitHub Pages serves it → app fetches + hot-swaps (bundled fallback)
```

- **build_data.py PRESERVES slow data** (bio, news, shots, **PHIST/THIST**) from the
  previous snapshot when its source CSV is absent. So the daily refresh keeps the
  history and just updates the current-season numbers; the app appends the **live
  current season** as each career arc's / team timeline's last point.
- **Playoff finishes** (team History): champion + runner-up from each season's final
  game; semifinalists from the playoff calendar (robust to the 2020/2021 vs 2022+
  formats and byes). Validated: champions match reality 2020–2024.
- **Health check:** a daily Routine (~11:30 UTC) verifies the refresh run. It is
  bound to a **specific session id**, so on a NEW session it must be **re-armed**
  (delete the stale trigger, create a fresh one bound to the current session). Ask
  Claude to "re-arm the daily data-refresh health check."

---

## Branch & workflow conventions

- **Default branch:** `claude/wnba-android-app-4d4egw` (base for every PR).
- **Working branch:** a per-session Claude branch started fresh off default for each
  change → PR → **squash-merge to default**. Verify UI with a Playwright screenshot
  before merging; data changes verify via a GitHub Actions run.
- Commit trailers: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` + the
  Claude-Session line.

---

## Local build recipe — the next AAB (v7), on your machine

Everything is on default now, and the icon tooling is committed, so pulls should be
clean (no more `package.json` collisions).

```fish
cd ~/WNBA-Courtside
git checkout claude/wnba-android-app-4d4egw
git pull origin claude/wnba-android-app-4d4egw
# if a stray lockfile diff blocks the pull: git checkout -- package-lock.json && git pull

archlinux-java set java-17-openjdk        # JDK 17 required (not 21+); skip if already default
set -x ANDROID_HOME ~/Android/Sdk
set -x PATH $ANDROID_HOME/platform-tools $PATH

sed -i 's/versionCode [0-9]*/versionCode 7/' android/app/build.gradle
npm install --ignore-scripts              # skips native sharp build; app build doesn't need it
npm run sync                              # web build + cap sync (registers @capacitor/app)
cd android && ./gradlew clean bundleRelease
jarsigner -verify app/build/outputs/bundle/release/app-release.aab   # expect "jar verified."
# → upload app/build/outputs/bundle/release/app-release.aab to Play Console → Closed testing
```

On-device smoke test (things only confirmable on a device): **hardware back button**
(levels + exit dialog), a **Wire headline tap** (opens the browser), a completed
game's **By quarter** table, and a player's **Career** / team's **History** tab.

Env gotchas (CachyOS/Arch): JDK 17 not 21+; API 35 platform + `targetSdkVersion=35`;
custom launcher icons already in `android/app/src/main/res/mipmap-*/`; `android/` is
gitignored & disposable (regenerate with `npx cap add android` if lost).

---

## Outstanding / next steps

1. **Build & upload v7** (versionCode 7) — carries everything above.
2. **Testers:** 12 opted in → 14 continuous days → *Apply for production*. Launch gate.
3. **Backlog not yet done:** full shot-coordinate scatter (pbp has `coordinate_x/y`);
   team identity/pace panel (needs a team-box/pbp fetch); college & honours on player
   profiles (`wikidata_bio.py` written, unrun — fills the "out of {college}" slot that's
   already coded); wire §8 into `refresh-shots.yml`; copy `no-shipped-device-frame`
   skill to `~/.claude/skills/`.
4. **Playoff round labels** are exact for the modern bracket; a bye-year team that took a
   first-round bye and then lost could still under-state in 2020/2021 (champions + finalists
   + semifinalists are correct every year). Refine only if it matters.

---

## Key files

- `src/App.jsx` — the whole app (~1,900 lines). Screens are clean function boundaries.
  Theme `LIGHT`/`DARK` + `applyTheme()`; data via `getData()`; `computeTables()` builds
  `PHIST`/`THIST` etc.
- `src/data/{dataSource,loadRemote}.js` — runtime data layer (cached ▸ network ▸ bundled).
- `scripts/fetch_wnba.R` · `fetch_news.R` · `fetch_lines.R` · `fetch_shots.R` ·
  `backfill_history.R` — the R fetches (all ESPN-backed → CI-only).
- `scripts/build_data.py` — CSV → `app-data.json`. The one place numbers are shaped.
- `.github/workflows/` — `refresh-data.yml` (daily), `refresh-shots.yml` (weekly),
  `backfill-history.yml` (manual).
- `CLAUDE.md` — project bible (data gotchas, imagery/legal boundaries, design system).
