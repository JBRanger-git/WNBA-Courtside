# Courtside

Free, ad-free, no-tracking WNBA stats app. React + Vite + Capacitor → Android.

**New here? Follow [SETUP.md](SETUP.md)** — start to finish, tools to phone.

Read **CLAUDE.md** before touching data logic. It documents several failures that
don't throw errors, they just produce wrong numbers.

## Prerequisites

| Tool | Version | Needed for |
|---|---|---|
| Node.js | 18+ | Vite, Capacitor CLI |
| **Java JDK** | **17** | Android Gradle Plugin. On Arch: `archlinux-java set java-17-openjdk` |
| Android Studio | latest | SDK, emulator, signing |
| Python | 3.9+ | `scripts/build_data.py` |
| R + wehoop | 4.1+ | only to refresh the CSVs |

## End to end

```bash
# 0. CSVs. Either copy your existing ones into data/csv/, or refresh from wehoop:
Rscript scripts/backfill_history.R

# 1. install
npm install

# 2. data + build + verify, in one shot
npm run verify

# 3. develop in the browser — far faster than an emulator
npm run dev            # http://localhost:5173

# 4. Android, once the UI is settled
npx cap add android    # first time only
npm run android        # build + sync + open Android Studio
```

Then in Android Studio: **Build → Build Bundle(s)/APK(s)** for a test `.apk`, or
**Build → Generate Signed Bundle** for a Play `.aab`.

> Keep the keystore and its password somewhere safe and backed up. Lose it and
> you can never update the listing — you'd have to publish a new app and lose
> your install base. This is the single most unrecoverable mistake available.

## Scripts

| Command | Does |
|---|---|
| `npm run data` | `data/csv/*.csv` → `src/data/app-data.json` |
| `npm run bio` | Wikidata (CC0) → `data/csv/dim_player_bio.csv` — adds college |
| `npm run smoke` | asserts the data didn't silently break |
| `npm run verify` | data → build → smoke. **Run before every commit.** |
| `npm run dev` | browser dev server |
| `npm run android` | build + sync + open Android Studio |

## Working with Claude Code

```bash
cd courtside
claude
```

`CLAUDE.md` loads automatically. Good first tasks:

- *"Split App.jsx into src/screens/* — it's ~1,500 lines and the screens are already clean function boundaries."*
- *"Run scripts/wikidata_bio.py and wire the college field into BioStrip."*
- *"Add the team identity panel — pace, possessions, points in paint from fact_team_box. Read CLAUDE.md first."*
- *"Build a shot scatter using coordinate_x/y from fact_pbp, precomputed in build_data.py — never ship raw plays to the client."*

Ask it to run `npm run verify` before it tells you it's done.
