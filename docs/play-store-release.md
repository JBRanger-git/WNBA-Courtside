# Play Store release checklist

Everything between a clean `npm run verify` and a live listing. Steps marked
**[local]** need your machine (Android SDK + JDK 17); they cannot run in CI or a
cloud sandbox. Steps marked **[console]** happen in the Play Console web UI.
Steps marked **[decide]** are yours to settle before shipping.

---

## 0. Data source — decision recorded

Courtside's data is produced with `wehoop`, which wraps ESPN's undocumented
endpoints (see `CLAUDE.md` → "Future: going live" and `SETUP.md` Part 4).

**Decision: proceeding.** Courtside ships as a free, non-commercial fan project.
It carries **no team logos and no player headshots** — only publicly available
statistics — and makes no claim of affiliation with or endorsement by the WNBA
or any team (the listing and privacy policy both say so). We're going ahead on
that basis.

Keep it that way: the "no imagery" boundary is what keeps this simple, so don't
reintroduce crests, faces, or any third-party asset (`CLAUDE.md` → Imagery).

---

## 1. Version bump **[local]**

Set the marketing and internal versions before every release. Play rejects an
upload whose `versionCode` isn't strictly greater than the last one you shipped.

- `package.json` → `version` (marketing string, e.g. `1.0.0`).
- `android/app/build.gradle` → `versionCode` (integer, +1 each upload) and
  `versionName` (string shown to users).

`versionCode` is the one Play enforces — never reuse or decrease it.

---

## 2. Generate the Android project **[local]**

`android/` is gitignored and disposable — regenerate it on the machine that builds.

```bash
npm install
npm run verify                 # data -> build -> smoke, must be green
npx cap add android            # first time only, creates android/
```

### 2a. Target API level

Google requires **new apps and updates target API 35** (enforced since Aug 2025).
Capacitor 6 scaffolds targeting API 34, so bump it:

- `android/variables.gradle` → `compileSdkVersion` and `targetSdkVersion` to `35`.
- Keep `minSdkVersion` at Capacitor's default (22) unless you have a reason.

Then re-sync:

```bash
npx cap sync android
```

---

## 3. Icon & splash assets **[local]**

Source of truth is `assets/courtside-icon.svg` (font-free, rasterises cleanly).
Background must stay `#F4F2EC` everywhere so the native → web splash handoff is
invisible.

```bash
npm i -D @capacitor/assets
# 1024x1024 source expected:
rsvg-convert -w 1024 -h 1024 assets/courtside-icon.svg > assets/icon.png
cp assets/icon.png assets/splash.png
npx @capacitor/assets generate --android \
  --iconBackgroundColor '#F4F2EC' \
  --splashBackgroundColor '#F4F2EC'
npx cap sync android
```

See `assets/README.md` for the full rationale (monogram vs wordmark, etc.).

---

## 4. Keystore — the one unrecoverable step **[local]**

Play signs updates against your upload key. **Lose the keystore and you can never
update the listing** — you'd have to publish a new app and abandon your installs.

```bash
keytool -genkey -v -keystore courtside-release.jks \
  -alias courtside -keyalg RSA -keysize 2048 -validity 10000
```

- **Back up `courtside-release.jks` and its passwords** in at least two places
  (password manager + offline copy). Never commit it — it must not enter git.
- Opt into **Play App Signing** in the Console (recommended): you upload with
  *this* key, Google holds the final signing key, and can help recover if the
  upload key is lost. Still back yours up.

Wire it into `android/app/build.gradle` via a `signingConfigs` block (or, safer,
a local `keystore.properties` that is gitignored).

---

## 5. Build the signed bundle **[local]**

Play requires an **Android App Bundle (`.aab`)**, not an APK.

```bash
npm run sync                        # build web + cap sync
cd android
./gradlew bundleRelease
# -> android/app/build/outputs/bundle/release/app-release.aab
```

Sanity-check the same build as a debug APK on a real device first (`SETUP.md`
Part 2) so you catch a white screen before uploading.

---

## 6. Play Console setup **[console]**

1. **Create a Play Console account** — one-off $25 developer registration.
2. **Create the app** — name "Courtside", default language, free, "App" type.
3. **Privacy policy URL** — required. Host `docs/privacy.html` somewhere public
   (GitHub Pages works) and paste the URL. Contact email is already set to
   `raiappsdev@gmail.com`; use the same address for the Console's developer
   contact so they match.
4. **Data Safety form** — for Courtside this is almost entirely "No":
   - Does your app collect or share user data? **No.**
   - Data types collected: **none**.
   - No advertising ID, no analytics, no accounts, no network access.
   - Data encrypted in transit / deletion request flow: **N/A** — nothing is
     collected or transmitted.
   This near-empty form is a genuine selling point; the listing copy leans on it.
5. **Content rating** questionnaire — no violence, no user content, no ads →
   rates as *Everyone*.
6. **Target audience** — all ages is fine; the app collects nothing.
7. **App category** — Sports.
8. **Ads declaration** — "No, my app does not contain ads."

---

## 7. Store listing **[console]**

Copy lives in `docs/play-store-listing.md`. You'll also need graphics:

| Asset | Spec | Notes |
|---|---|---|
| App icon | 512×512 PNG | Same mark as the launcher icon. |
| Feature graphic | 1024×500 PNG | Cream `#F4F2EC` background, Chalk Court wordmark. |
| Phone screenshots | 2–8, min 1080px | Standings, a team page, a player fingerprint. Take on-device or in Chrome device mode. |

No third-party imagery in any screenshot or graphic — same rule as the app
(`CLAUDE.md` → Imagery).

---

## 8. Release **[console]**

1. Start with a **Closed** or **Internal testing** track — upload the `.aab`,
   add yourself as a tester, install via the opt-in link, verify on a real
   device.
2. Promote to **Production** once you're happy.
3. First review can take a few days; subsequent updates are usually faster.

---

## Quick gate before you upload

- [x] Data source — decision recorded, proceeding as a fan project (§0)
- [ ] `npm run verify` green
- [ ] `versionCode` incremented (§1)
- [ ] `targetSdkVersion = 35` (§2a)
- [ ] Icons/splash generated, no white screen on device (§3, §5)
- [ ] Keystore created **and backed up** (§4)
- [ ] Privacy policy hosted, contact email filled in (§6.3)
- [ ] Data Safety form completed as "no collection" (§6.4)
