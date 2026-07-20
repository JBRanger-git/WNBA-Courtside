# Session status & handoff

**Purpose:** resume point for a fresh Claude Code session. Read this + `CLAUDE.md`
first. Last updated at the end of a long session that took the app from a
shipped bug all the way to a self-updating, themeable app in Play Store closed
testing.

---

## TL;DR — where things are right now

- **App:** WNBA Courtside (React + Vite + Capacitor → Android). Package
  `uk.co.courtside.wnba`.
- **Play Store:** in **Closed testing**. **v5 uploaded and in review.**
- **Gate to production (personal account):** **12 testers** opted in for
  **14 continuous days**, then *Apply for production* → Google review.
- **Data is now fetched at runtime** (this was "Future: going live" in CLAUDE.md —
  it's DONE). The daily GitHub Action refreshes data, publishes it to GitHub
  Pages, and installed phones fetch + hot-swap it. **No rebuild needed for data.**
- **One fix is merged but not yet shipped:** dark-mode shot-chart legibility
  (#13). It rides in the next build (**v6**) whenever you rebuild.

---

## Play Console facts

- Developer account: **personal**, verified. Contact `raiappsdev@gmail.com`.
- Store name: **WNBA Courtside**. Package `uk.co.courtside.wnba` (locked forever).
- **Privacy policy URL:** https://jbranger-git.github.io/WNBA-Courtside/
  (served by GitHub Pages from `docs/`; source `docs/privacy.html` + `PRIVACY.md`).
- **Data Safety:** declared **no data collected / no data shared** (still true —
  the runtime fetch pulls a public stats file and collects nothing).
- **Version codes used so far: 1–5.** Next build must be **6** or higher
  (source of truth: Play Console → Test and release → App bundle explorer).
- **Keystore (UNRECOVERABLE — back it up):** `android/app/courtside-release.jks`,
  wired via `android/keystore.properties` (both gitignored). Enrolled in **Play
  App Signing**. Passwords live in the owner's password manager (not in git).

---

## What was built this session (PRs on the default branch)

| PR | What |
|----|------|
| #2 | Privacy policy (`PRIVACY.md` + `docs/privacy.html`), release checklist (`docs/play-store-release.md`), store listing (`docs/play-store-listing.md`) |
| #3 | **Fixed the shipped phone-frame bug** (fake bezel + "9:41 5G" status bar); scoreboard shows latest games; games are tappable → new game page |
| #4 | **Fetch-at-runtime Phase 1** (`src/data/dataSource.js`, `loadRemote.js`; publish `app-data.json` to Pages) |
| #5 | **Phase 2** — live in-session data swap, instant render |
| #6/#7 | **§8 live score top-up** — pull recent finals from ESPN's live scoreboard so data is current-to-yesterday (in `fetch_wnba.R`) |
| #8/#9 | Postponement handling — past-no-result games show **"Awaiting data"** |
| #10 | **Box score + top performers** on the game page (`fact_game_box`/`fact_game_top` → `GB`) |
| #11 | **Light/Dark theme** toggle on About (dark = "Report" palette) |
| #12 | Skill `.claude/skills/no-shipped-device-frame/` (prevents the phone-frame bug recurring) |
| #13 | Dark-mode shot-chart legibility fix (court renders in fixed light palette) |

---

## Architecture (current, post-session)

**Data pipeline is fully automated end-to-end. No manual step for data.**

```
Daily 11:00 UTC · refresh-data.yml (GitHub Actions, R + wehoop)
  ├─ bulk load_wnba_player_box  ──┐
  ├─ §8 live scoreboard top-up  ──┤ recent finals the bulk feed lacks
  ▼                               ▼
  scripts/build_data.py → src/data/app-data.json  (+ GB per-game box, postponement flag)
  ▼
  commit + copy to docs/app-data.json
  ▼
  GitHub Pages serves https://jbranger-git.github.io/WNBA-Courtside/app-data.json  (CORS *)
  ▼
  App on launch: applyCache() (instant) → refreshFromNetwork() → live swap (Phase 2)
       fallback order: cached ▸ network ▸ bundled  (offline safe, no blank screen)
```

- Data currency shows on the Today screen: **"Data updated through <date>"**.
- `build_data.py` prints a **"postponed?"** line for any past game with no box score.
- Health check: a daily Routine fires ~11:30 UTC to verify the refresh run. **It
  targets the previous session id — if this is a new session, re-establish it**
  (ask Claude to "set up the daily data-refresh health check again").

---

## Branch & workflow conventions

- **Default branch:** `claude/wnba-android-app-4d4egw`
- **Dev branch:** `claude/play-store-deployment-4cv08q` — restart it from default
  for each new change (`git checkout -B <dev> origin/<default>`), commit, PR,
  **squash-merge to default**.
- **Commit trailers:** end messages with
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` and the Claude-Session line.
- **Tweak-and-test loop (established):** Claude changes code → renders a
  screenshot + pushes to the dev branch → **you** approve (screenshots or
  `npm run dev`) → Claude merges to default → **you** rebuild + upload when you
  want it live. Nothing reaches testers until you rebuild the AAB.

---

## Local build recipe (the only manual part left, all on your machine)

```fish
cd ~/WNBA-Courtside
git pull origin claude/wnba-android-app-4d4egw
grep -n versionCode android/app/build.gradle            # bump > last uploaded (→ 6)
sed -i 's/versionCode 5/versionCode 6/' android/app/build.gradle
npm run sync                                            # web build + cap sync
cd android && ./gradlew clean bundleRelease             # signed AAB
jarsigner -verify app/build/outputs/bundle/release/app-release.aab   # "jar verified."
# upload app/build/outputs/bundle/release/app-release.aab to Closed testing
```

Environment gotchas (CachyOS/Arch):
- **JDK 17** required (`archlinux-java set java-17-openjdk`), not 21+.
- `ANDROID_HOME=~/Android/Sdk`; **API 35** platform installed; `targetSdkVersion=35`
  in `android/variables.gradle` + `android.suppressUnsupportedCompileSdk=35`.
- **npm blocks install scripts** here (sharp, rsvg) — that's why launcher icon /
  screenshots were generated outside `@capacitor/assets`. The custom C-mark
  launcher icons are already dropped into `android/app/src/main/res/mipmap-*/`.
- `android/` is gitignored & disposable; regenerate with `npx cap add android` if lost.

---

## Outstanding / next steps

1. **Testers:** get **12** opted into the closed test → run **14 days** → *Apply
   for production*. This is the launch-gating item.
2. **v6 rebuild** (optional, when ready): carries the dark-fingerprint fix (#13)
   and every app-side feature (#3–#11). No urgency; v5 is fine for testing.
3. **Jul 16 DAL@NY** postponed game self-heals when ESPN reschedules it (shows
   "Awaiting data" until then). Nothing to do.
4. **Re-arm the daily data health check** in the new session (see Architecture).
5. **Future ideas (not started):** quarter-by-quarter scores on the game page;
   team identity/pace panel; full shot-coordinate scatter; wire §8 into
   `refresh-shots.yml`; copy the `no-shipped-device-frame` skill to
   `~/.claude/skills/` to apply it across all projects.

---

## Key files

- `src/App.jsx` — the whole app (~1,600 lines; screens are clean function
  boundaries). Theme tokens `LIGHT`/`DARK` + `applyTheme()`; data via `getData()`.
- `src/data/{dataSource,loadRemote}.js` — runtime data layer.
- `scripts/fetch_wnba.R` — daily R fetch (bulk + §8 top-up + per-game box).
- `scripts/build_data.py` — CSV → `app-data.json` (+ GB, postponement flag).
- `.github/workflows/refresh-data.yml` — the daily automation (+ Pages publish).
- `docs/` — privacy (`privacy.html`, `PRIVACY.md`), release/listing guides,
  `going-live-fetch-at-runtime.md` (now implemented), this file.
- `.claude/skills/no-shipped-device-frame/` — guard against the phone-frame bug.
- `CLAUDE.md` — project bible (data gotchas, imagery/legal boundaries, design system).
