# Courtside — WNBA stats app (Android)

Free, ad-free, no-tracking WNBA statistics app. React + Vite, wrapped for Android
with Capacitor. Sibling project to the "WNBA Courtside" Power BI report — shares
its data source and design system, but is **not** a port of it.

---

## Non-negotiables

These are settled decisions. Don't relitigate them without a reason.

1. **No monetisation.** No ads, no IAP, no tip jar. Adding any of these drags in
   Play Billing, a Data Safety declaration for the advertising ID, and — worst —
   would disqualify the project from "non-commercial" data terms.
2. **No third-party imagery.** No team crests, no player headshots, no ESPN
   assets. See "Imagery" below. This is a legal boundary, not a design gap.
3. **Never hot-link another party's CDN.** Not `a.espncdn.com`, not anyone's.
4. **A blank field beats a wrong one.** This app's only asset is that the numbers
   are true. Never fabricate, interpolate, or "reasonably assume" a stat. If the
   source doesn't have it, render nothing.

---

## Data pipeline

```
wehoop / sportsdataverse   (R, run manually)
        │
        ├── load_wnba_player_box / team_box / schedule / pbp
        │
        ▼
   R transform scripts  ──▶  data/csv/*.csv        (the Power BI report reads these too)
        │
        ▼
   scripts/build_data.py ──▶  src/data/*.json      (denormalised, screen-shaped)
        │
        ▼
   vite build            ──▶  dist/                (JSON bundled as static assets)
        │
        ▼
   npx cap sync android  ──▶  android/             (Android Studio project)
```

Data is **bundled at build time**, not fetched. That's a deliberate v0 choice:
no backend, no API key, no network permission, no privacy surface. The cost is
that fresh scores need a rebuild + release. If/when that becomes intolerable,
the upgrade path is documented in "Future: going live" below — but don't reach
for it prematurely.

### Regenerating data

```bash
# 1. refresh CSVs from R (see scripts/backfill_history.R)
# 2. rebuild the JSON:
npm run data
# 3. optional — player bio from Wikidata (CC0):
npm run bio
```

---

## Data gotchas (all of these have bitten; none of them error)

**`dim_games.status_type_completed` lies.** The schedule feed and the box-score
feed publish on different cadences. `dim_games` says 171 games completed;
`fact_team_box` has rows for 175. **A game is completed iff `fact_team_box` has
rows for it.** Same for scores — take them from `fact_team_box`, never from
`dim_games.home_score`/`away_score`. `build_data.py` already does this; don't
"simplify" it back.

**`fact_player_box.active` is not "played in this game".** Use
`did_not_play == FALSE`.

**`fact_player_season.usage_pct` is a fraction, not a percent.** 0.332 = 33.2%.
It needs `* 100` like the other pct columns — unlike `fg_pct`/`three_pct`, which
are *also* fractions. Everything in that table is a fraction. (This already cost
us one bug where A'ja Wilson rendered as 0.2% usage.)

**`dim_games` contains the All-Star Game.** Early in the season it appears with
`home_display_name = "TBD"` and no team IDs; **as the game approaches the feed
NAMES the squads and assigns synthetic team IDs** (e.g. 133383 / 133384) that
aren't real clubs. So the `"TBD"` test alone is NOT enough — `build_data.py`
filters games by **real-club membership** (team IDs present in `dim_teams` / `T`),
which catches both forms. Miss it and the app looks up an unknown team, gets
`undefined`, and the **Schedule screen crashes to blank** (this shipped once —
July 2026, All-Star in Chicago). `App.jsx` also drops unresolved-team games as a
backstop, and `smoke.mjs` asserts every game's teams are real clubs (a truthy-ID
check isn't enough — the synthetic IDs are truthy).

**The escalation: the leak reaches upstream of `build_data.py` entirely.**
`fetch_wnba.R`'s `regular()` keeps only `season_type == 2` rows, on the
assumption that's "regular season only" — but ESPN tags the All-Star Game's
`player_box`/`schedule` rows `season_type == 2` as well, so `regular()` doesn't
drop it. The named draft squads ("Team Spoon", "Team Coop" — captain-drafted,
different names every year) then flow straight into `dim_teams.csv` and
`fact_player_season.csv`. Once they're in `dim_teams`, the `build_data.py`
real-club-membership filter above stops working too, because the synthetic
teams now *are* members of `T` — so they showed up as two extra rows in the
team list and standings (undefeated 1-0 "TEAM SPOON" in the league table), and
any All-Star participant's season averages were quietly diluted by one extra
game. Fixed in `fetch_wnba.R` by excluding rows upstream of every derived
table, keyed on a signal that survives the yearly name change: a real club
always has a brand color and a normal display name; an All-Star squad has an
empty `team_color` and a `"Team <captain>"` name. `build_data.py` also gained
a belt-and-suspenders backstop — `T` is now filtered to `CONFERENCE`
membership (the hardcoded list of real franchises already used for East/West),
and `S`/`P` are filtered to `T`'s team ids. `smoke_refresh.mjs` asserts
`D.T.length <= 16` so a future leak like this fails CI instead of shipping.

**`dim_teams` is a *current* snapshot.** Golden State (129689) joined in 2025;
Toronto (131935) and Portland (132052) are 2026 expansion. Any historical view
must use season-scoped team data (`dim_team_season`), never this table.

**`dim_game_odds` is junk — deleted, do not reintroduce.** Every one of its 175
rows had `game_spread = 2.5`, `home_favorite = TRUE`, and
`game_spread_available = FALSE`. The pull returned defaults. `favorite_won` was
literally identical to "home team won" because the favourite was hardcoded.

**Some teams have multiple home venues.** Toronto play across four arenas in
three cities. Don't model "home arena" as a scalar.

**`weight` in `dim_players` is only 53% filled.** Dropped from the UI rather
than rendered as a gap. Height/age/experience are 93%+ and are used.

---

## Imagery

Team crests and player faces are **three separate rights**: trademark on the
mark, copyright on the photograph, right of publicity on the likeness. Being
free and non-commercial reduces exposure but grants no permission. No data
provider licenses WNBA imagery — SportsDataIO's licensed headshots cover NFL /
MLB / NBA / NHL only, and API-Sports explicitly disclaims all rights to the
logos it serves and pushes liability to the consumer.

So `src/App.jsx` has an **asset layer**:

```js
const ASSETS = {
  crestUrl: (_team) => null,   // → `https://cdn.yourdomain/crests/${t.abbr}.svg`
  faceUrl: (_player) => null,  // → `https://cdn.yourdomain/faces/${p.id}.webp`
};
```

Both return `null`, so `<Crest>` and `<Face>` render typographic monograms in
club colours — ours outright, and legible at 19px where a real crest wouldn't be.
If permission is ever granted, populate the resolvers (pointing at **your own**
CDN) and every call site lights up.

Crest text colour is chosen by **relative luminance**, not hardcoded white —
Portland `#cee5eb` and Las Vegas `#a7a8aa` are near-white and would vanish.

---

## Design system — "Chalk Court"

Ported from `wnba-chalk-court-theme.json`. The identity is **agate**: the dense
newspaper box-score page. Warm cream, condensed display type, hairline rules,
tabular numerals. Deliberately *not* the dark-navy-and-neon that every other
sports app uses — this is a reference almanac, not a TV graphic.

```
page #F4F2EC   card #ECEAE2   visual #FFFFFF   stripe #F7F6F1
border #DEDBD2 text #15151C   secondary #5B6472  muted #8A8F98
accent #FE5000   good #1E8F5E   bad #C23934
```

- **`#FE5000` is an accent only.** Never a data series colour. (This is inherited
  from the report's theme, where it's `tableAccent` and absent from `dataColors`.)
- **Fonts:** Oswald (display) — DIN isn't web-licensed and the original mockups
  already fell back to Oswald. Body is the system stack (Roboto on Android);
  do **not** force Segoe UI, it doesn't exist on Android.
- **Always `fontVariantNumeric: "tabular-nums"` on any figure.** Non-tabular
  digits make columns of numbers jitter. The `agate` style object does this.
- Club colour appears as a 3–4px spine or a monogram block, never as a large fill.

---

## Structure

```
src/App.jsx        everything, currently. ~1000 lines. Splitting it is a
                   reasonable first refactor — screens are already clean
                   function boundaries (HomeScreen, TeamsScreen, PlayersScreen,
                   ScheduleScreen, TeamDetail, PlayerDetail, SearchOverlay).
src/lib/theme.js   design tokens
src/data/          generated JSON — DO NOT hand-edit, regenerate with `npm run data`
scripts/           build_data.py, wikidata_bio.py, backfill_history.R
```

Data is imported from `src/data/app-data.json`, generated by
`scripts/build_data.py`. **Never hand-edit that JSON** — regenerate it.
`npm run verify` runs build_data -> vite build -> smoke test end to end.

---

## Verify before you commit

```bash
npm run verify        # data build -> vite build -> smoke test
```

`scripts/smoke.mjs` asserts the things that break silently: usage is a percent
not a fraction, the teamless All-Star row is gone, completed-game count matches
box scores, zone frequencies sum to 100, and no raw pbp has leaked into the
bundle. `build_data.py` also hard-fails if pbp shot counts drift >1% from
box-score FGA — that reconciliation is the only thing standing between you and a
plausible-looking wrong fingerprint.

## Known stubs / next up

- **Shot chart (full coordinate scatter).** The zone fingerprint is BUILT. What's
  not built is plotting individual shots at their `coordinate_x/y`. Note the
  fingerprint is deliberately NOT a radar — see `ShotFingerprint` for why (spoke
  order is arbitrary, so the silhouette isn't stable).
  Background: `fact_pbp` has 23,867 field goal attempts
  with `shot_zone`, `shot_dist`, `coordinate_x/y` and `shot_result` — 100%
  complete (the shots with no zone are free throws, correctly). Five clean zones:
  Restricted Area, In the Paint, Mid-Range, Corner 3, Above the Break 3. League
  FG% by zone comes out sane (62.4 / 40.4 / 37.3 / 34.8 / 32.6), so the data is
  trustworthy. `type_text` gives shot *types* (Driving Layup, Pullup, Step Back,
  Turnaround, Floating, Putback) as clean strings — no regex archaeology needed.
  **Precompute these server-side/in-R.** 72k pbp rows is 54 MB as JSON; the app
  needs ~15 numbers per player, not the plays.
- **Historical seasons (2020–2026).** `scripts/backfill_history.R` is written but
  unrun. Blocked on nothing. Unlocks career arcs, which is the single biggest
  upgrade available. Note 2020 was the 22-game Bradenton bubble — flag it, don't
  silently mix it into all-time leaderboards.
- **Team identity panel.** `fact_team_box` has `pace`, `possessions`,
  `points_in_paint`, `fast_break_points`, `turnover_points`, `largest_lead`,
  `lead_changes` — all 350/350 filled, all unused. Pace especially: it says *how*
  a team plays, not just how well.
- **College / honours.** `scripts/wikidata_bio.py` is written but unrun (the
  sandbox it was authored in couldn't reach Wikidata). The `b.college` slot in
  `BioStrip` renders as soon as it's populated.

## Future: going live

Only if bundled data becomes intolerable. The shape:

```
licensed provider ──▶ ingest job (cron) ──▶ Postgres ──▶ your API ──▶ CDN ──▶ app
```

A backend is **mandatory** the moment a keyed provider is involved — an APK is
trivially decompiled, so the key cannot live in the app. Cache TTLs are the cost
lever: scoreboard 30s, standings 5m, player season 1h, fingerprint daily.

Do **not** scrape ESPN for this. `wehoop` wraps ESPN's undocumented endpoints,
which is fine for a private dashboard and not fine for a publicly distributed
app, monetised or not — their ToS restricts use of the service, not your margin.

---

## Conventions

- Verify against the data before asserting a fact about it. Every gotcha above
  was found by opening the table, and every one contradicted its column names.
- Prefer the simplest correct thing. If `LOOKUPVALUE`-equivalent logic can avoid
  a new relationship/join, do that.
- Any figure shown in the UI needs `tabular-nums`.
- Don't add a dependency to solve something 20 lines of code solves.
