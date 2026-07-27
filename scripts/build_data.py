#!/usr/bin/env python3
"""
Courtside — data build. CSV -> the single JSON the app imports.

This is the ONLY thing that writes src/data/. If a number appears in the app, it
comes from here. Run it after every R refresh:

    python3 scripts/build_data.py ./data/csv ./src/data

Applies the fixes documented in CLAUDE.md, each marked FIX: below. None of them
throw if removed — they just quietly produce wrong numbers, which is why they're
commented rather than left looking like arbitrary complexity.
"""
import csv, json, sys
from collections import Counter, defaultdict
from pathlib import Path

CONFERENCE = {
    "Atlanta Dream":"East","Chicago Sky":"East","Connecticut Sun":"East","Indiana Fever":"East",
    "New York Liberty":"East","Toronto Tempo":"East","Washington Mystics":"East",
    "Dallas Wings":"West","Golden State Valkyries":"West","Las Vegas Aces":"West",
    "Los Angeles Sparks":"West","Minnesota Lynx":"West","Phoenix Mercury":"West",
    "Portland Fire":"West","Seattle Storm":"West",
}
NATIONAL = {"ION","Prime Video","CBS","ESPN","NBA TV","Peacock","ABC","NBC","TSN"}
ZONES  = ["Restricted Area","In the Paint","Mid-Range","Corner 3","Above the Break 3"]
CREATE = ["spot","drive","offdrib","cut","post","putback"]
MIN_FGA, MIN_ZONE, MIN_GP = 60, 8, 5

def read(p):
    with open(p, newline="", encoding="utf-8") as f: return list(csv.DictReader(f))

def num(v, d=0.0):
    try: return float(v)
    except (TypeError, ValueError): return d

def creation_bucket(tt):
    """ESPN play-type text -> creation bucket. Clean strings in source; no regex archaeology."""
    t = tt.lower()
    if "free throw" in t: return None
    if "step back" in t or "pullup" in t or "pull-up" in t: return "offdrib"
    if "driving" in t or "running" in t or "finger roll" in t: return "drive"
    if "cutting" in t or "alley oop" in t: return "cut"
    if "putback" in t or "tip shot" in t: return "putback"
    if "turnaround" in t or "fadeaway" in t or "hook" in t: return "post"
    return "spot"

def build(csv_dir: Path, out_dir: Path):
    out_dir.mkdir(parents=True, exist_ok=True)
    # PREV is the last good snapshot. The daily refresh (scripts/fetch_wnba.R) only
    # regenerates the fast-moving CSVs; the slow/hard datasets — player bio, news
    # and the shot fingerprint — are PRESERVED from PREV when their source CSV is
    # absent, rather than risk generating them wrong. "A blank field beats a wrong
    # one" (CLAUDE.md). Provide the CSV and it takes over; omit it and PREV wins.
    prev_path = out_dir/"app-data.json"
    PREV = json.loads(prev_path.read_text(encoding="utf-8")) if prev_path.exists() else {}

    teams_raw   = read(csv_dir/"dim_teams.csv")
    games_raw   = read(csv_dir/"dim_games.csv")
    stand_raw   = read(csv_dir/"fact_standings.csv")
    tbox        = read(csv_dir/"fact_team_box.csv")
    season_raw  = read(csv_dir/"fact_player_season.csv")
    dp = csv_dir/"dim_players.csv"; players_raw = read(dp) if dp.exists() else None
    dn = csv_dir/"dim_news.csv";    news_raw    = read(dn) if dn.exists() else None

    # FIX: dim_teams is supposed to be regular-club-only, but the All-Star Game's
    # draft squads ("Team Spoon", "Team Coop"...) share the feed's season_type
    # with real games, so fetch_wnba.R's own filter can miss them (see CLAUDE.md).
    # CONFERENCE is the canonical list of real franchises — anything not in it
    # is not a club, backstop-dropped here so a leak upstream can't put a
    # synthetic squad in the team list, standings, or (via team_ids below) the
    # schedule.
    T = [[int(t["team_id"]), t["abbreviation"], t["team_display_name"], t["team_short_name"],
          "#"+t["color"].lstrip("#"), CONFERENCE[t["team_display_name"]]]
         for t in teams_raw if t["team_display_name"] in CONFERENCE]
    print(f"  teams          {len(T)}")

    team_ids = {r[0] for r in T}   # real clubs (this season's snapshot)

    S = sorted([[int(s["team_id"]), int(s["wins"]), int(s["losses"]), round(num(s["win_pct"]),3),
                 num(s["ppg_for"]), num(s["ppg_against"]), int(s["point_differential"]),
                 s["streak"], s["last_ten"], s["home_record"], s["road_record"]]
                for s in stand_raw if int(s["team_id"]) in team_ids],
               key=lambda r:-r[3])
    print(f"  standings      {len(S)}")

    # FIX: dim_games.status_type_completed lags fact_team_box — the schedule feed and
    # box-score feed publish on different cadences. A game is completed iff its box
    # score exists. Scores come from fact_team_box, never dim_games.
    box = defaultdict(dict)
    for r in tbox: box[r["game_id"]][r["team_home_away"]] = int(r["team_score"])
    G, skipped = [], 0
    for g in games_raw:
        # FIX: dim_games carries the All-Star Game. It USED to appear with home/away
        # = "TBD" and no team IDs; the feed now also publishes it with NAMED all-star
        # squads and synthetic team IDs (e.g. 133383/133384) that are not real clubs.
        # Either way it must stay out of team-scoped data — filter by real-club
        # membership, not just the "TBD" sentinel. Left in, the app hits an undefined
        # team (TEAM[133384]) and the Schedule screen crashes to blank.
        try:
            hid, aid = int(g["home_team_id"]), int(g["away_team_id"])
        except (ValueError, TypeError, KeyError):
            skipped += 1; continue
        if hid not in team_ids or aid not in team_ids \
           or g["home_display_name"]=="TBD" or g["away_display_name"]=="TBD":
            skipped += 1; continue
        b = box.get(g["game_id"], {})
        done = "home" in b and "away" in b
        # Tip-off as a UTC ISO string (element 10, optional). The app renders it in
        # the viewer's local timezone. Blank unless the schedule carries a real time
        # (time_valid FALSE = TBD → ESPN parks it at 00:00Z; a blank beats a wrong
        # midnight kickoff). Older snapshots have no game_datetime column → "".
        dt = (g.get("game_datetime") or "").strip()
        tv = str(g.get("time_valid", "")).strip().upper()
        iso = dt if ("T" in dt and tv != "FALSE") else ""
        G.append([g["game_id"], g["game_date"], hid, aid,
                  b.get("home") if done else None, b.get("away") if done else None,
                  g["broadcast_name"], "N" if g["broadcast_name"] in NATIONAL else "L",
                  g["venue_address_city"], 1 if done else 0, iso])
    G.sort(key=lambda r:r[1])
    completed = sum(r[9] for r in G)
    print(f"  games          {len(G)}  ({completed} completed, {len(G)-completed} upcoming, {skipped} teamless skipped)")

    # Postponement check: a game dated BEFORE the most recent final but with no
    # box score has almost certainly been postponed/rescheduled — its result will
    # never arrive on the original date. Surface it (never fabricate a score), so
    # a phantom past fixture doesn't sit silently in the schedule. The app hides
    # these from "upcoming" and shows them once the feed moves them to a new date.
    last_done = max((r[1] for r in G if r[9]), default=None)
    if last_done:
        abbr = {t[0]: t[1] for t in T}
        stale = [r for r in G if r[9] == 0 and r[1] < last_done]
        if stale:
            which = ", ".join(f"{abbr.get(r[3], r[3])}@{abbr.get(r[2], r[2])} {r[1]}" for r in stale)
            print(f"  postponed?     {len(stale)} past fixture(s) with no result (likely "
                  f"postponed/rescheduled): {which}")

    # FIX: every pct column in fact_player_season is a FRACTION, usage_pct included
    # (0.332 = 33.2%). Miss the *100 and A'ja Wilson renders as 0.3% usage.
    P = []
    for p in season_raw:
        gp = int(p["games_played"])
        # Backstop: fetch_wnba.R already excludes All-Star-squad rows before
        # aggregating fact_player_season, but a player whose primary team
        # somehow resolved to a non-club (synthetic All-Star team_id) should
        # still never surface here — matches the T/S/G real-club filtering above.
        if gp < MIN_GP or int(p["team_id"]) not in team_ids: continue
        P.append([int(p["athlete_id"]), p["athlete_display_name"], int(p["team_id"]),
                  p["athlete_position_abbreviation"] or "G", gp,
                  round(num(p["mpg"]),1), round(num(p["ppg"]),1), round(num(p["rpg"]),1), round(num(p["apg"]),1),
                  round(int(p["steals_total"])/gp,1), round(int(p["blocks_total"])/gp,1),
                  round(int(p["turnovers_total"])/gp,1),
                  round(num(p["fg_pct"])*100,1), round(num(p["three_pct"])*100,1),
                  round(num(p["ft_pct"])*100,1), round(num(p["ts_pct"])*100,1),
                  round(num(p["usage_pct"])*100,1), round(num(p["tpa_per_game"]),1)])
    P.sort(key=lambda r:-r[6])
    keep = {r[0] for r in P}
    print(f"  players        {len(P)}  (>= {MIN_GP} GP)")

    if news_raw is None:
        N = PREV.get("N") or []
        print(f"  news           {len(N)}  (preserved — no dim_news.csv)")
    else:
        # Row shape: [headline, byline, abbr, date, link]. abbr comes straight from
        # an `abbreviation` column if the source has one, else it's mapped from the
        # ESPN team_id (same id space as T). link may be blank — the app renders a
        # plain, non-clickable headline then.
        abbr_by_tid = {t[0]: t[1] for t in T}
        def _news_abbr(n):
            if n.get("abbreviation"): return n["abbreviation"]
            tid = (n.get("team_id") or "").strip()
            if tid:
                try: return abbr_by_tid.get(int(float(tid)), "")
                except (ValueError, TypeError): return ""
            return ""
        rows = []
        for n in news_raw:
            head = (n.get("headline") or "").strip()
            if not head: continue
            rows.append([head, (n.get("byline") or "").strip(), _news_abbr(n),
                         (n.get("published_date") or "")[:10], (n.get("link") or "").strip()])
        N = sorted(rows, key=lambda r:r[3], reverse=True)[:5]
        print(f"  news           {len(N)}  ({sum(1 for r in N if r[4])} with links)")

    # weight is only ~53% filled, so it's excluded rather than shown as a gap.
    if players_raw is None:
        # Preserve bios from the last snapshot, trimmed to the players still kept.
        BIO = {int(k): v for k, v in (PREV.get("BIO") or {}).items() if int(k) in keep}
        print(f"  player bio     {len(BIO)}  (preserved — no dim_players.csv)")
    else:
        BIO = {}
        for r in players_raw:
            aid = int(r["athlete_id"])
            if aid not in keep: continue
            e = {}
            if r["height"].strip():                e["h"] = r["height"].strip()
            if r["age"].strip():                   e["age"] = int(r["age"])
            if r["experience_years"].strip():      e["exp"] = int(r["experience_years"])
            if r["athlete_jersey"].strip():        e["no"] = r["athlete_jersey"].strip()
            if r["athlete_position_name"].strip(): e["posFull"] = r["athlete_position_name"].strip()
            if e: BIO[aid] = e
        print(f"  player bio     {len(BIO)}")

    # Wikidata extras (college/country/honours) — merged onto BIO regardless of
    # whether the core bio above was freshly built or preserved from PREV, since
    # dim_players.csv (core bio) is basically never present on the daily run but
    # dim_player_bio.csv (scripts/wikidata_bio.py) is meant to run every day.
    bc = csv_dir/"dim_player_bio.csv"
    if bc.exists():
        n_college = 0
        for r in read(bc):
            try: aid = int(r["athlete_id"])
            except (ValueError, KeyError): continue
            if aid not in keep: continue
            extra = {}
            if r.get("college"): extra["college"] = r["college"]; n_college += 1
            if r.get("country"): extra["country"] = r["country"]
            if r.get("honours"): extra["honours"] = r["honours"]
            if extra: BIO.setdefault(aid, {}).update(extra)
        print(f"  wikidata bio   {n_college} with a college")
    else:
        print("  wikidata bio   (skipped — run scripts/wikidata_bio.py to add college)")

    # Home venues + attendance from fixtures. Several clubs use more than one home
    # arena (Toronto play across four in three cities) so this is a list, not a scalar.
    venues, att = defaultdict(Counter), defaultdict(list)
    for g in games_raw:
        if g["home_display_name"]=="TBD" or g["neutral_site"]=="TRUE": continue
        tid = int(g["home_team_id"])
        venues[tid][f"{g['venue_full_name']}|{g['venue_address_city']}"] += 1
        if g["attendance"].strip() and int(g["attendance"])>0: att[tid].append(int(g["attendance"]))
    TEAM_BIO = {}
    for tid, v in venues.items():
        o = v.most_common(); a = att[tid]
        TEAM_BIO[tid] = {"arena": o[0][0].split("|")[0], "city": o[0][0].split("|")[1],
                         "alt": [{"n":k.split("|")[0], "c":k.split("|")[1], "g":n} for k,n in o[1:]],
                         "att": round(sum(a)/len(a)) if a else None, "attN": len(a),
                         "home": sum(n for _,n in o)}
    print(f"  team bio       {len(TEAM_BIO)}")

    # --- team identity (TADV): points in paint, fast break points, points
    # conceded off turnovers, largest lead, lead changes, and an estimated
    # possessions/game — averaged per team over completed games seen so far.
    # Fully optional: preserved from PREV when fact_team_advanced.csv is absent
    # (see scripts/fetch_team_advanced.R — the ESPN-live fetch that avoids the
    # same bulk-feed lag fetch_wnba.R already routes around for scores).
    ta_path = csv_dir/"fact_team_advanced.csv"
    if ta_path.exists():
        acc = defaultdict(lambda: defaultdict(list))
        for r in read(ta_path):
            try: tid = int(r["team_id"])
            except (ValueError, KeyError): continue
            if tid not in team_ids: continue
            for k in ("pip", "fbp", "tov_pts", "largest_lead", "lead_changes", "poss"):
                v = num(r.get(k), None)
                if v is not None: acc[tid][k].append(v)
        TADV = {}
        for tid, cols in acc.items():
            gp = max((len(v) for v in cols.values()), default=0)
            if gp == 0: continue
            row = {k: round(sum(v) / len(v), 1) for k, v in cols.items() if v}
            row["gp"] = gp
            TADV[tid] = row
        print(f"  team identity  {len(TADV)} teams")
    else:
        TADV = {int(k): v for k, v in (PREV.get("TADV") or {}).items() if int(k) in team_ids}
        print(f"  team identity  {len(TADV)}  (preserved — no fact_team_advanced.csv)")

    # 72k pbp rows in, ~15 numbers per player out. NEVER ship the plays to the
    # client — fact_pbp is ~54 MB as JSON and the app needs none of it.
    SHOTS = None
    pbp_path = csv_dir/"fact_pbp.csv"
    if pbp_path.exists():
        fg = [r for r in read(pbp_path)
              if r["shooting_play"]=="TRUE" and r["shot_zone"].strip() and r["athlete_id_1"].strip()]
        zi = {z:i for i,z in enumerate(ZONES)}
        per = defaultdict(lambda: {"z":[[0,0] for _ in ZONES], "c":Counter()})
        for r in fg:
            a = int(r["athlete_id_1"]); i = zi[r["shot_zone"]]
            per[a]["z"][i][0] += 1
            if r["shot_result"]=="Made": per[a]["z"][i][1] += 1
            b = creation_bucket(r["type_text"])
            if b: per[a]["c"][b] += 1
        lg = [[0,0] for _ in ZONES]
        for d in per.values():
            for i in range(len(ZONES)):
                lg[i][0]+=d["z"][i][0]; lg[i][1]+=d["z"][i][1]
        tot = sum(x[0] for x in lg)
        lgc = Counter()
        for d in per.values(): lgc.update(d["c"])
        tc = sum(lgc.values())
        LG = {"freq":[round(lg[i][0]/tot*100,1) if tot else 0 for i in range(len(ZONES))],
              "fg":  [round(lg[i][1]/lg[i][0]*100,1) if lg[i][0] else None for i in range(len(ZONES))],
              "create":[round(lgc[b]/tc*100,1) if tc else 0 for b in CREATE]}
        SP = {}
        for a,d in per.items():
            n = sum(x[0] for x in d["z"])
            if n < MIN_FGA or a not in keep: continue
            c = sum(d["c"].values())
            SP[a] = {"n":n,
                     "f":[round(d["z"][i][0]/n*100,1) for i in range(len(ZONES))],
                     "p":[round(d["z"][i][1]/d["z"][i][0]*100,1) if d["z"][i][0]>=MIN_ZONE else None
                          for i in range(len(ZONES))],
                     "a":[d["z"][i][0] for i in range(len(ZONES))],
                     "c":[round(d["c"][b]/c*100,1) for b in CREATE] if c else None}
        SHOTS = {"LG":LG, "P":SP}
        print(f"  shots          {len(fg):,} FG attempts -> {len(SP)} fingerprints (>= {MIN_FGA} FGA)")

        # Validation gate: pbp shooter counts must reconcile against box-score FGA.
        # If they drift, athlete_id_1 has stopped meaning "the shooter".
        pb = read(csv_dir/"fact_player_box.csv")
        box_fga = sum(int(r["field_goals_attempted"]) for r in pb if r["field_goals_attempted"].strip())
        drift = abs(len(fg)-box_fga)/max(box_fga,1)
        print(f"  validation     pbp FGA {len(fg):,} vs box FGA {box_fga:,}  ({drift*100:.2f}% drift)  "
              f"{'ok' if drift<0.01 else '*** CHECK athlete_id_1 ***'}")
        if drift >= 0.01:
            raise SystemExit("Shot data failed reconciliation — refusing to write a bad fingerprint.")
    else:
        # Preserve the last good fingerprint. The shot chart moves slowly and is the
        # riskiest thing to regenerate, so the daily refresh leaves it untouched and
        # carries it forward. Refresh it deliberately by dropping a fresh fact_pbp.csv
        # into data/csv and re-running this script.
        SHOTS = PREV.get("SHOTS")
        n = len(SHOTS["P"]) if SHOTS and SHOTS.get("P") else 0
        print(f"  shots          (no fact_pbp.csv — preserved {n} fingerprints from prior build)")

    # --- per-game box detail (completed games only): team totals + top scorers.
    # Compact, keyed by game_id with home/away. Absent for very recent live
    # top-up games that have no player box yet — the app shows the light view.
    def _opt(name):
        p = csv_dir/name
        return read(p) if p.exists() else []
    BOXCOLS = ("pts","reb","ast","stl","blk","tov","fgm","fga","tpm","tpa","ftm","fta")
    box_by = defaultdict(dict)                        # game_id -> team_id -> [stats]
    for r in _opt("fact_game_box.csv"):
        box_by[r["game_id"]][r["team_id"]] = [int(num(r[k])) for k in BOXCOLS]
    top_by = defaultdict(lambda: defaultdict(list))  # game_id -> team_id -> [[id,name,pts,reb,ast]]
    for r in _opt("fact_game_top.csv"):
        top_by[r["game_id"]][r["team_id"]].append(
            [r["athlete_id"], r["name"], int(num(r["pts"])), int(num(r["reb"])), int(num(r["ast"]))])
    GB = {}
    for g in games_raw:
        gid, hid, aid = g["game_id"], g["home_team_id"], g["away_team_id"]
        b = box_by.get(gid)
        if not b or hid not in b or aid not in b: continue
        GB[gid] = {"box": {"home": b[hid], "away": b[aid]},
                   "top": {"home": top_by[gid].get(hid, []), "away": top_by[gid].get(aid, [])}}
    print(f"  game box       {len(GB)} games with box detail")

    # --- per-quarter scores (linescores): game_id -> {home:[q..], away:[q..]}.
    # PRESERVED/merged from PREV so a transient fetch miss never drops a game.
    # RECONCILIATION GATE: a game's quarters must sum to its final box score on
    # BOTH sides or it's dropped — never render a quarter line that doesn't add
    # up to the score we show ("a blank field beats a wrong one", CLAUDE.md).
    GL = dict(PREV.get("GL") or {})
    line_by = defaultdict(dict)                        # game_id -> home_away -> [q..]
    for r in _opt("fact_game_line.csv"):
        vals = [int(x) for x in (r.get("line") or "").split("|")
                if x.strip().lstrip("-").isdigit()]
        if vals: line_by[r["game_id"]][r["home_away"]] = vals
    kept = dropped = 0
    for gid, sides in line_by.items():
        if "home" not in sides or "away" not in sides: continue
        b = box.get(gid, {})
        if b.get("home") == sum(sides["home"]) and b.get("away") == sum(sides["away"]):
            GL[gid] = {"home": sides["home"], "away": sides["away"]}; kept += 1
        else:
            GL.pop(gid, None); dropped += 1     # doesn't reconcile — drop any stale copy too
    if line_by:
        print(f"  game lines     {kept} games reconciled, {dropped} dropped (sum≠final), {len(GL)} total")
    else:
        print(f"  game lines     {len(GL)} (preserved — no fact_game_line.csv)")

    # --- historical seasons & career arcs (PHIST / THIST) --------------------
    # Populated by the one-off backfill (scripts/backfill_history.R -> *_hist.csv),
    # PRESERVED from the previous snapshot on daily runs that don't carry those
    # CSVs. Only completed PAST seasons are stored here (season < current); the
    # app appends the live current-season point from P / S so the arc tip never
    # goes stale. Trimmed to players/teams that exist in the app today.
    cur_season = int(last_done[:4]) if last_done else None
    keep_teams = {t[0] for t in T}
    anomalous = set()
    for r in _opt("dim_season.csv"):
        flag = str(r.get("is_anomalous", "")).upper() in ("TRUE", "1")
        if flag or r.get("season") == "2020":
            try: anomalous.add(int(r["season"]))
            except (ValueError, TypeError): pass
    abbr_season = {}                                  # (season, team_id) -> abbreviation
    cur_abbr = {t[0]: t[1] for t in T}
    for r in _opt("dim_team_season.csv"):
        try: abbr_season[(int(r["season"]), int(r["team_id"]))] = r.get("team_abbreviation") or ""
        except (ValueError, TypeError): pass

    ph_rows = _opt("fact_player_season_hist.csv")
    if ph_rows:
        PHIST = {}
        for r in ph_rows:
            try: aid, yr = int(r["athlete_id"]), int(r["season"])
            except (ValueError, TypeError, KeyError): continue
            if aid not in keep or (cur_season and yr >= cur_season): continue
            gp = int(num(r.get("games_played")))
            if gp <= 0: continue
            try: tid = int(float(r["primary_team_id"])) if r.get("primary_team_id") else None
            except (ValueError, TypeError): tid = None
            row = {"yr": yr, "tm": abbr_season.get((yr, tid)) or cur_abbr.get(tid) or "",
                   "gp": gp, "ppg": round(num(r.get("ppg")), 1), "rpg": round(num(r.get("rpg")), 1),
                   "apg": round(num(r.get("apg")), 1), "ts": round(num(r.get("ts_pct")) * 100, 1)}
            if yr in anomalous: row["bubble"] = 1
            PHIST.setdefault(aid, []).append(row)
        for v in PHIST.values(): v.sort(key=lambda x: x["yr"])
        print(f"  player history  {len(PHIST)} players ({sum(len(v) for v in PHIST.values())} season rows)")
    else:
        PHIST = {int(k): v for k, v in (PREV.get("PHIST") or {}).items() if int(k) in keep}
        print(f"  player history  {len(PHIST)}  (preserved — no *_hist.csv)")

    ts_rows = _opt("fact_team_season.csv")
    if ts_rows:
        playoff = {}                                 # (season, team_id) -> result label
        for r in _opt("fact_team_playoff.csv"):
            try: playoff[(int(r["season"]), int(r["team_id"]))] = r.get("result") or ""
            except (ValueError, TypeError): pass
        THIST = {}
        for r in ts_rows:
            try: tid, yr = int(r["team_id"]), int(r["season"])
            except (ValueError, TypeError, KeyError): continue
            if tid not in keep_teams or (cur_season and yr >= cur_season): continue
            row = {"yr": yr, "w": int(num(r.get("wins"))), "l": int(num(r.get("losses"))),
                   "pct": round(num(r.get("win_pct")), 3), "pf": round(num(r.get("ppg_for")), 1),
                   "pa": round(num(r.get("ppg_against")), 1), "note": playoff.get((yr, tid), "")}
            if yr in anomalous: row["bubble"] = 1
            THIST.setdefault(tid, []).append(row)
        for v in THIST.values(): v.sort(key=lambda x: x["yr"])
        print(f"  team history    {len(THIST)} teams ({sum(len(v) for v in THIST.values())} season rows)")
    else:
        THIST = {int(k): v for k, v in (PREV.get("THIST") or {}).items() if int(k) in keep_teams}
        print(f"  team history    {len(THIST)}  (preserved — no fact_team_season.csv)")

    # --- head-to-head history (GHIST) ----------------------------------------
    # A compact game log of PAST seasons (season < current) so a matchup page can
    # show prior meetings between the two clubs and their scores. The current
    # season's meetings live in G and are merged in by the app, so they're excluded
    # here (no double-count). Row: [date, home_id, away_id, home_score, away_score,
    # season_type] (season_type 3 = playoffs). Populated by the backfill
    # (fact_games_hist.csv), PRESERVED from PREV on daily runs that lack it — the
    # same contract as PHIST/THIST. Both clubs must still exist today (the app can
    # only render team_ids it has in T).
    gh_rows = _opt("fact_games_hist.csv")
    if gh_rows:
        GHIST = []
        for r in gh_rows:
            try:
                yr, hid, aid = int(r["season"]), int(r["home_id"]), int(r["away_id"])
                hs, as_ = int(num(r["home_score"])), int(num(r["away_score"]))
            except (ValueError, TypeError, KeyError): continue
            if cur_season and yr >= cur_season: continue
            if hid not in keep_teams or aid not in keep_teams: continue
            st = 3 if str(r.get("season_type", "")).strip() == "3" else 2
            GHIST.append([(r.get("game_date") or "")[:10], hid, aid, hs, as_, st])
        GHIST.sort(key=lambda x: x[0])
        pairs = len({tuple(sorted((r[1], r[2]))) for r in GHIST})
        print(f"  head-to-head    {len(GHIST)} past games across {pairs} club pairings")
    else:
        GHIST = PREV.get("GHIST") or []
        print(f"  head-to-head    {len(GHIST)}  (preserved — no fact_games_hist.csv)")

    # --- injury status (INJ) --------------------------------------------------
    # Keyed by athlete_id, {"status", "note", "updated"}. From ESPN via wehoop's
    # espn_wnba_injuries() (fetch_injuries.R), the same site.api.espn.com family
    # already called daily for news/lines — not a new class of request. PRESERVED
    # from the previous snapshot when the fetch comes back empty (transient miss
    # or a player's status just isn't listed), trimmed to players still kept.
    # Absence means "nothing reported", never asserted as "healthy".
    inj_rows = _opt("dim_injuries.csv")
    if inj_rows:
        INJ = {}
        for r in inj_rows:
            try: aid = int(r["athlete_id"])
            except (ValueError, TypeError, KeyError): continue
            if aid not in keep: continue
            status = (r.get("status") or "").strip()
            if not status: continue
            INJ[aid] = {"status": status, "note": (r.get("note") or "").strip(),
                        "updated": (r.get("updated") or "")[:10]}
        print(f"  injuries        {len(INJ)} player(s) on the report")
    else:
        INJ = {int(k): v for k, v in (PREV.get("INJ") or {}).items() if int(k) in keep}
        print(f"  injuries        {len(INJ)}  (preserved — no dim_injuries.csv)")

    payload = {"meta":{"totalGames":len(G), "completedGames":completed,
                       "leagueAvgPpg":round(sum(int(r["team_score"]) for r in tbox)/len(tbox),1),
                       "lastGame":max((r[1] for r in G if r[9]), default=None), "season":cur_season},
               "T":T,"S":S,"P":P,"G":G,"N":N,"BIO":BIO,"TEAM_BIO":TEAM_BIO,"SHOTS":SHOTS,"GB":GB,"GL":GL,
               "PHIST":PHIST,"THIST":THIST,"GHIST":GHIST,"INJ":INJ,"TADV":TADV}
    dst = out_dir/"app-data.json"
    dst.write_text(json.dumps(payload, separators=(",",":")))
    kb = dst.stat().st_size/1024
    print(f"\n  wrote {dst}  ({kb:.1f} KB)")
    if kb > 900:
        print("  WARNING: payload over 900 KB — something raw is leaking in. Check that "
              "fact_pbp is being aggregated, not passed through.")

if __name__ == "__main__":
    src = Path(sys.argv[1]) if len(sys.argv)>1 else Path("data/csv")
    dst = Path(sys.argv[2]) if len(sys.argv)>2 else Path("src/data")
    if not src.exists(): raise SystemExit(f"No CSV directory at {src}. Populate it from the R pipeline first.")
    print(f"Building from {src}")
    build(src, dst)
