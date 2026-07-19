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

    T = [[int(t["team_id"]), t["abbreviation"], t["team_display_name"], t["team_short_name"],
          "#"+t["color"].lstrip("#"), CONFERENCE.get(t["team_display_name"])] for t in teams_raw]
    print(f"  teams          {len(T)}")

    S = sorted([[int(s["team_id"]), int(s["wins"]), int(s["losses"]), round(num(s["win_pct"]),3),
                 num(s["ppg_for"]), num(s["ppg_against"]), int(s["point_differential"]),
                 s["streak"], s["last_ten"], s["home_record"], s["road_record"]] for s in stand_raw],
               key=lambda r:-r[3])
    print(f"  standings      {len(S)}")

    # FIX: dim_games.status_type_completed lags fact_team_box — the schedule feed and
    # box-score feed publish on different cadences. A game is completed iff its box
    # score exists. Scores come from fact_team_box, never dim_games.
    box = defaultdict(dict)
    for r in tbox: box[r["game_id"]][r["team_home_away"]] = int(r["team_score"])

    G, skipped = [], 0
    for g in games_raw:
        # FIX: dim_games carries the All-Star Game with home/away = "TBD" and no team
        # IDs. Left in, it renders as a phantom fixture on two team pages.
        if g["home_display_name"]=="TBD" or g["away_display_name"]=="TBD":
            skipped += 1; continue
        b = box.get(g["game_id"], {})
        done = "home" in b and "away" in b
        G.append([g["game_id"], g["game_date"], int(g["home_team_id"]), int(g["away_team_id"]),
                  b.get("home") if done else None, b.get("away") if done else None,
                  g["broadcast_name"], "N" if g["broadcast_name"] in NATIONAL else "L",
                  g["venue_address_city"], 1 if done else 0])
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
        if gp < MIN_GP: continue
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
        N = sorted([[n["headline"], n["byline"] or "", n["abbreviation"] or "", n["published_date"][:10]]
                    for n in news_raw], key=lambda r:r[3], reverse=True)[:5]
        print(f"  news           {len(N)}")

    # weight is only ~53% filled, so it's excluded rather than shown as a gap.
    if players_raw is None:
        # Preserve bios from the last snapshot, trimmed to the players still kept.
        BIO = {int(k): v for k, v in (PREV.get("BIO") or {}).items() if int(k) in keep}
        print(f"  player bio     {len(BIO)}  (preserved — no dim_players.csv)")
    else:
        bio_extra = {}
        bc = csv_dir/"dim_player_bio.csv"
        if bc.exists():
            for r in read(bc):
                if r.get("college"): bio_extra[int(r["athlete_id"])] = r["college"]
            print(f"  wikidata bio   {len(bio_extra)} with a college")
        else:
            print("  wikidata bio   (skipped — run scripts/wikidata_bio.py to add college)")
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
            if aid in bio_extra:                   e["college"] = bio_extra[aid]
            if e: BIO[aid] = e
        print(f"  player bio     {len(BIO)}")

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

    payload = {"meta":{"totalGames":len(G), "completedGames":completed,
                       "leagueAvgPpg":round(sum(int(r["team_score"]) for r in tbox)/len(tbox),1),
                       "lastGame":max((r[1] for r in G if r[9]), default=None)},
               "T":T,"S":S,"P":P,"G":G,"N":N,"BIO":BIO,"TEAM_BIO":TEAM_BIO,"SHOTS":SHOTS}
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
