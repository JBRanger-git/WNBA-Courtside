# Courtside — setup, start to finish

Written for **CachyOS** (Arch-based, `pacman` + AUR). Other distros differ mainly
in package names; the Arch-specific traps are flagged as **ARCH:**.

Work through in order. Each part ends with a check — don't move on until it's
green.

---

# Part 0 — Install the tools

### 0.1 Node

```bash
sudo pacman -S nodejs npm
node --version    # v20+ or v22+
```

### 0.2 JDK 17 — **the Arch trap**

Android's Gradle plugin wants **JDK 17**. Arch is rolling, so you almost
certainly have 21 or 24, and Gradle will fail with errors that never mention
Java. This is the single most likely thing to cost you an evening.

```bash
sudo pacman -S jdk17-openjdk
archlinux-java status                    # see what's installed and active
sudo archlinux-java set java-17-openjdk  # pin it
java -version                            # must say 17.x
```

**ARCH:** `archlinux-java` is the switcher — don't hand-edit `JAVA_HOME`. If a
future `pacman -Syu` pulls a newer JDK and Gradle breaks, run `archlinux-java
status` first. It's almost always this.

Keeping a newer JDK for other work is fine; just leave 17 as the active one, or
set `JAVA_HOME` per-shell when building Android.

### 0.3 Python

Already installed. `build_data.py` is **stdlib-only** — nothing to add.

```bash
python --version    # 3.9+
```

Only if you want the Wikidata college data later:

```bash
sudo pacman -S python-requests
```

**ARCH:** use pacman, not pip. Arch enforces PEP 668, so `pip install requests`
fails with "externally-managed-environment". Don't reach for
`--break-system-packages`.

### 0.4 Android SDK + Studio

```bash
paru -S android-studio        # or: yay -S android-studio
```

If you'd rather skip the AUR build, grab the tarball from
<https://developer.android.com/studio>, extract to `~/android-studio`, run
`./bin/studio.sh`. Same thing, no compile.

Launch it once and let it download the SDK — that's what you actually need.

### 0.5 Phone access — **the other Arch trap**

`adb` cannot see your phone without udev rules. Nothing warns you; the device
just never appears.

```bash
sudo pacman -S android-tools android-udev
sudo usermod -aG adbusers $USER
sudo usermod -aG kvm $USER        # only if you'll use the emulator
```

**Log out and back in** — group changes don't apply to your current session.

```bash
groups | grep -E 'adbusers|kvm'   # both should show after re-login
```

### 0.6 Claude Code

Anthropic deprecated the npm install in January 2026; the native installer is
the recommended path and needs no Node.

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Open a **new** shell, then:

```bash
claude --version
claude doctor
```

> Needs a Pro, Max, Team, Enterprise or Console account. The free plan doesn't
> include Claude Code.

### 0.7 R (optional)

Only if you'll refresh CSVs rather than copy your existing ones.

```bash
sudo pacman -S r gcc-fortran
R -e 'install.packages("wehoop", repos="https://cloud.r-project.org")'
```

### ✅ Check

```bash
node --version && java -version && python --version && claude --version && groups | grep adbusers
```

Java says **17**. `adbusers` is listed. Don't continue otherwise.

---

# Part 1 — Run it in a browser

95% of the work happens here. It's far faster than an emulator, and Capacitor is
only a wrapper — if it works in mobile Chrome/Firefox, it works on the phone.

```bash
unzip wnba-courtside-v1.0.zip -d ~/dev
cd ~/dev/courtside
```

### 1.1 Add your data

Copy your CSVs into `data/csv/`:

```
dim_teams.csv       dim_players.csv        dim_games.csv          dim_news.csv
fact_standings.csv  fact_team_box.csv      fact_player_season.csv
fact_player_box.csv fact_pbp.csv
```

`fact_pbp.csv` (~14 MB) drives the shot fingerprint. Without it everything else
works; the Fingerprint tab just reports "not enough shots".

### 1.2 Build

```bash
npm install
npm run verify
```

Expect:

```
  teams          15
  games          331  (175 completed, 156 upcoming, 1 teamless skipped)
  players        184
  shots          23,867 FG attempts -> 134 fingerprints
  validation     pbp FGA 23,867 vs box FGA 23,866  (0.00% drift)  ok
  wrote src/data/app-data.json  (74.6 KB)
  ...
  All checks passed.
```

**Read those numbers.** The pipeline hard-fails if pbp shot counts drift >1% from
box-score FGA, because every bug this project has hit produced confident wrong
numbers rather than an error.

### 1.3 Look at it

```bash
npm run dev     # http://localhost:5173
```

**F12 → Ctrl+Shift+M** for device emulation. Pick a Pixel. That's the dev loop.

### ✅ Check

Standings load, a team page opens, **Players → A'ja Wilson → Fingerprint** draws
a court.

---

# Part 2 — Get it on your phone

Only once the UI is settled. Don't iterate here; it's slow.

```bash
npx cap add android     # creates android/ — gitignored and disposable
npm run android         # build + sync + open Studio
```

First Gradle sync takes several minutes. Let it finish.

### 2.1 Real device

On the phone: **Settings → About phone → tap "Build number" ×7** → back →
**Developer options → USB debugging on**. Plug in USB, accept the prompt.

```bash
adb devices     # should list your phone as "device", not "unauthorized"
```

`unauthorized` = you didn't accept the on-phone prompt.
Nothing listed = udev/groups (§0.5) — check `groups`, and that you re-logged in.

Then **Run ▶** in Studio.

### 2.2 APK without opening Studio

Once the SDK exists, Gradle works standalone — often nicer on Linux:

```bash
npm run build && npx cap sync android
cd android && ./gradlew assembleDebug
# -> android/app/build/outputs/apk/debug/app-debug.apk
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

### ✅ Check

App opens on the phone, no white screen. (A white screen almost always means
`base: "./"` got removed from `vite.config.js` — Capacitor serves over `file://`
and absolute asset paths 404.)

---

# Part 3 — Hand it to Claude Code

```bash
cd ~/dev/courtside
claude
```

`CLAUDE.md` loads automatically. It documents every trap in this data — the
completion flag that lies, the usage column that's a fraction, the All-Star row
with no teams. **All of them fail silently.** It's the most valuable file here.

Good first tasks, in order:

1. `Run npm run verify, then split App.jsx into src/screens/*. It's ~1,500 lines and the screens are already clean function boundaries. Run npm run verify again when done.`
2. `Run scripts/wikidata_bio.py and wire the college field into BioStrip. It has never been executed — expect to debug it.`
3. `Add a team identity panel using pace, possessions and points_in_paint from fact_team_box. Read CLAUDE.md first — they're 350/350 filled and unused.`
4. `Build a shot scatter from coordinate_x/y in fact_pbp. Precompute in build_data.py — never ship raw plays to the client.`

**Always finish with: "run `npm run verify` and show me the output."** An agent
can't catch what doesn't throw, so make it prove the numbers still hold.

`scripts/backfill_history.R` and `scripts/wikidata_bio.py` have never been run.
First drafts, not finished tools.

---

# Part 4 — Play Store (later)

1. Play Console account — one-off $25.
2. **Build → Generate Signed Bundle / APK → Android App Bundle**.
3. Create a keystore. **Back it up.** Lose it and you can never update the
   listing — you'd publish a new app and abandon your installs. It's the one
   unrecoverable mistake here.
4. Upload the `.aab`, complete the **Data Safety** form. Yours is nearly empty:
   no ads, no accounts, no tracking, no network calls. That's a real advantage —
   say so in the listing.

### Settle before you ship

Data reaches this app via `wehoop`, which wraps ESPN's undocumented endpoints.
Fine for a private dashboard; for a publicly distributed app it's a
terms-of-service question, and it doesn't turn on whether you make money — ESPN's
terms restrict use of their service, not your margin. See CLAUDE.md
("Future: going live"). The app ships no logos and no headshots precisely so this
stays a one-variable problem.

---

## Quick reference

| Command | Does |
|---|---|
| `npm run verify` | data → build → smoke. **Before every commit.** |
| `npm run dev` | dev server on :5173 |
| `npm run data` | CSVs → `src/data/app-data.json` |
| `npm run bio` | Wikidata (CC0) → college data |
| `npm run android` | build + sync + open Studio |
| `claude` | Claude Code in the repo |

## When it breaks

| Symptom | Cause |
|---|---|
| Gradle errors not mentioning Java | wrong JDK. `archlinux-java status` |
| `adb devices` empty | udev/groups — §0.5, and re-login |
| `adb devices` says `unauthorized` | accept the prompt on the phone |
| White screen on device | `base: "./"` missing from `vite.config.js` |
| `pip` says externally-managed-environment | use pacman, not pip (§0.3) |
| `npm run data`: no CSV directory | CSVs aren't in `data/csv/` |
| Fingerprint empty for everyone | `fact_pbp.csv` missing |
| Build fails after editing app-data.json | never hand-edit it — `npm run data` |
| `claude` not found | open a new shell; PATH updates per-session |
