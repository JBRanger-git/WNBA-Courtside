# Session status & handoff

**Purpose:** resume point for a fresh Claude Code session. Read this + `CLAUDE.md`
first. Lives on the **default branch** so it survives dev-branch restarts.

---

## TL;DR — where things are right now

- **App:** WNBA Courtside (React + Vite + Capacitor → Android). Package
  `uk.co.courtside.wnba`. Contact `raiappsdev@gmail.com`.
- **Play Store:** in **Closed testing**. All of v6 + v7 + history is **merged to
  default**; a build carrying it (profile bio, "Team" label, live Wire, back-button +
  exit dialog, quarter scores, dark-mode fix, career arcs / team history) has been
  built and uploaded targeting **API 36 (Android 16)**. Bump `versionCode` above the
  highest in Play Console → App bundle explorer for each new upload.
- **⚠️ Newest features NOT yet in a build:** matchup **head-to-head** history and
  **local-timezone tip-off times** (#21) are merged to default but ship only in the
  *next* AAB. Rebuild + upload to put them in front of testers (recipe below — and
  **do the `npm run sync`**, or the AAB ships the old UI).
- **Gate to production:** testers are **secured** (full roster opted in) → after
  **14 continuous days** of active testing, *Apply for production*. Live count/date
  is only in Play Console → Test and release → Testing → Closed testing.
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

## What shipped to default (all merged, awaiting a build)

| PR | What |
|----|------|
| #21 | Matchup **head-to-head** (prior meetings + scores + series tally + playoff tag, from a new `GHIST` game log — merges past seasons with the current one) and **local-timezone tip-off times** on the schedule / upcoming-game pages. Backfill re-run so the branch/default carries real `GHIST` (1,432 games, 2020–2025) + real tip-offs on all 333 games — features are live-data on merge, no separate backfill dispatch needed. Also hardened the smoke bundle checks (scan all Vite chunks) |
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

- **build_data.py PRESERVES slow data** (bio, news, shots, **PHIST/THIST/GHIST**) from
  the previous snapshot when its source CSV is absent. So the daily refresh keeps the
  history and just updates the current-season numbers; the app appends the **live
  current season** as each career arc's / team timeline's last point.
- **`GHIST`** (head-to-head game log, `#21`) = past-season games `[date, homeId,
  awayId, hs, as, seasonType]`, built by `backfill_history.R` → `fact_games_hist.csv`
  and preserved like PHIST/THIST. The matchup page merges it with the current season
  (from `G`) for prior meetings; excludes the current season to avoid double-count.
- **Tip-off times:** `fetch_wnba.R` writes `game_datetime` (UTC) + `time_valid` into
  `dim_games.csv`; `build_data.py` emits it as the **11th element of each `G` row**
  (blank for TBD / older snapshots). The app renders it in the viewer's timezone.
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

## Local build recipe — the AAB, on your machine

Everything is on default and the icon tooling is committed, so pulls should be clean.
**Target API 36 (Android 16) is required by Aug 31, 2026** — the committed helper sets it.

**Lesson learned:** a version-code bump alone ships nothing new. You MUST
`git pull` + `npm run sync` so the latest web code is rebuilt and copied into
`android/`, or the AAB ships stale UI (this is how a build once had no Career/History
tabs even though the data had history).

```fish
cd ~/WNBA-Courtside
git checkout claude/wnba-android-app-4d4egw
git pull origin claude/wnba-android-app-4d4egw
# if a stray lockfile diff blocks the pull: git checkout -- package-lock.json; and git pull

archlinux-java set java-17-openjdk        # JDK 17 (not 21+); skip if already default
set -x ANDROID_HOME ~/Android/Sdk
set -x PATH $ANDROID_HOME/platform-tools $PATH

npm install --ignore-scripts              # skips native sharp build; app build doesn't need it
npm run sync                              # REBUILD web + cap sync — don't skip this

bash scripts/prep-android-api36.sh        # sets compile/target SDK 36 + suppress flag + installs API 36

# bump versionCode above the highest already uploaded (Play Console → App bundle explorer):
set -l cur (grep -oP 'versionCode\s+\K[0-9]+' android/app/build.gradle)
sed -i "s/versionCode $cur/versionCode "(math $cur + 1)"/" android/app/build.gradle
grep -n versionCode android/app/build.gradle

cd android && ./gradlew clean bundleRelease
jarsigner -verify app/build/outputs/bundle/release/app-release.aab   # expect "jar verified."
grep -n 'SdkVersion' variables.gradle     # confirm compile/target = 36
# → upload app/build/outputs/bundle/release/app-release.aab to Play Console → Closed testing
```

On-device smoke test (things only confirmable on a device): **hardware back button**
(levels + exit dialog), a **Wire headline tap** (opens the browser), a completed
game's **By quarter** table, a player's **Career** / team's **History** tab, and that the
top masthead / bottom tab bar aren't clipped by the status/nav bars (edge-to-edge).

Env gotchas (CachyOS/Arch): JDK 17 not 21+; **API 36 platform installed**
(`scripts/prep-android-api36.sh` does this / see §2a of `docs/play-store-release.md`);
if `./gradlew` errors that the Gradle plugin can't use compileSdk 36, bump AGP → 8.7.2
in `android/build.gradle` and the Gradle wrapper → 8.9 (the script prints this). Custom
launcher icons already in `android/app/src/main/res/mipmap-*/`; `android/` is gitignored
& disposable (regenerate with `npx cap add android`, then re-run the prep script).

---

## Outstanding / next steps

1. **Confirm the API-36 build is live in the testing track** and the "target API by
   Aug 31, 2026" warning has cleared. For any further update: `git pull` + `npm run
   sync` + `bash scripts/prep-android-api36.sh` + bump versionCode, then rebuild.
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

- `src/App.jsx` — the whole app (~2,000 lines). Screens are clean function boundaries.
  Theme `LIGHT`/`DARK` + `applyTheme()`; data via `getData()`; `computeTables()` builds
  `PHIST`/`THIST` etc.; `HeadToHead` (matchup history) + `fmtLocalTime` (tip-off times).
- `src/data/{dataSource,loadRemote}.js` — runtime data layer (cached ▸ network ▸ bundled).
- `scripts/fetch_wnba.R` · `fetch_news.R` · `fetch_lines.R` · `fetch_shots.R` ·
  `backfill_history.R` — the R fetches (all ESPN-backed → CI-only).
- `scripts/build_data.py` — CSV → `app-data.json`. The one place numbers are shaped.
- `.github/workflows/` — `refresh-data.yml` (daily), `refresh-shots.yml` (weekly),
  `backfill-history.yml` (manual).
- `CLAUDE.md` — project bible (data gotchas, imagery/legal boundaries, design system).
