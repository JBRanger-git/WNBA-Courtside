#!/usr/bin/env python3
"""
WNBA Courtside — player bio from Wikidata.

Why Wikidata: it's CC0 (public domain dedication). No attribution required, no
commercial restriction, no ToS to breach. It's the only major source for this
material that's unambiguously safe to redistribute in a shipped app — which is
exactly why it's worth the patchy coverage.

Pulls: college (P69), date of birth (P569), country (P27), and honours
received (P166). Deliberately does NOT pull "nominated for" (P1411) — it's
sparsely populated for basketball and the WNBA has no real nomination
structure, so it would be a field that's blank 95% of the time. Draft pick
(P647) isn't pulled either — WNBA draft picks are thinly documented on
Wikidata compared to college, so it would mostly render blank for no gain.

P69 ("educated at") is NOT college-only — it returns every school a player has
a Wikidata statement for, high school included, and there's no ordering that
puts college first. Verified via a CI diagnostic dump against real players
(A'ja Wilson, Breanna Stewart, Diana Taurasi, Caitlin Clark) before this was
built: every genuine college/university's `instance of` (P31) label contains
"university" or "college" (e.g. "public research university", "land-grant
university", plain "university"); every high school's does not (it's "high
school", "school", "private school", "religious school" instead). So the
query below only binds ?college when at least one of its P31 types matches
that pattern — this is what fixed A'ja Wilson previously showing "Heathwood
Hall Episcopal School" (her high school) instead of "University of South
Carolina".

Matching is by name, which is the weak link — see reconcile() below. Anything
unmatched is left blank rather than guessed. A blank bio field renders as
nothing; a wrong one poisons the whole app's credibility.

The roster comes from src/data/app-data.json (the P table), not dim_players.csv:
fetch_wnba.R doesn't write dim_players.csv on the daily run (see CLAUDE.md — core
bio is slow-changing and preserved from a one-time load), so a script that
required it could never actually run in the daily refresh. Reading the roster
already baked into the previous snapshot means this can run unconditionally,
every day, like the other enrichment fetches.

Usage:
    pip install requests
    python3 scripts/wikidata_bio.py src/data/app-data.json data/csv/dim_player_bio.csv
"""
import csv
import json
import re
import sys
import unicodedata
from pathlib import Path

import requests

ENDPOINT = "https://query.wikidata.org/sparql"
# Wikidata asks for a descriptive UA with contact info. Don't skip this — they
# throttle or block generic agents, and they're within their rights to.
HEADERS = {
    "User-Agent": "WNBACourtside/0.3 (https://github.com/YOURNAME/courtside; you@example.com)",
    "Accept": "application/sparql-results+json",
}

# One query, all WNBA players, rather than 200 per-player lookups. Kinder to a
# free public endpoint and roughly 200x faster.
QUERY = """
SELECT ?player ?playerLabel ?collegeLabel ?dob ?countryLabel
       (GROUP_CONCAT(DISTINCT ?honourLabel; separator="; ") AS ?honours)
WHERE {
  ?league rdfs:label "Women's National Basketball Association"@en .
  ?team wdt:P118 ?league .
  ?player wdt:P54 ?team .
  OPTIONAL {
    ?player wdt:P69 ?college .
    ?college wdt:P31 ?collegeType .
    ?collegeType rdfs:label ?collegeTypeLabelEn . FILTER(LANG(?collegeTypeLabelEn) = "en")
    # NOT CONTAINS "school" matters: some elite prep high schools are typed
    # "university-preparatory school" / "college-preparatory school" on
    # Wikidata, which otherwise pass the university/college substring check
    # (confirmed via a CI diagnostic — Jordin Canada's "Windward School" leaked
    # through as her college this way before this line was added).
    FILTER((CONTAINS(LCASE(?collegeTypeLabelEn), "university") ||
            CONTAINS(LCASE(?collegeTypeLabelEn), "college")) &&
           !CONTAINS(LCASE(?collegeTypeLabelEn), "school"))
  }
  OPTIONAL { ?player wdt:P569 ?dob . }
  OPTIONAL { ?player wdt:P27  ?country . }
  OPTIONAL {
    ?player wdt:P166 ?honour .
    ?honour rdfs:label ?honourLabel . FILTER(LANG(?honourLabel) = "en")
  }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
GROUP BY ?player ?playerLabel ?collegeLabel ?dob ?countryLabel
"""


def norm(name: str) -> str:
    """Fold accents and punctuation so 'Valériane Ayayi' matches 'Valeriane Ayayi'."""
    s = unicodedata.normalize("NFKD", name)
    s = "".join(c for c in s if not unicodedata.combining(c))
    return "".join(c for c in s.lower() if c.isalnum() or c == " ").strip()


def fetch():
    r = requests.get(ENDPOINT, params={"format": "json", "query": QUERY},
                     headers=HEADERS, timeout=120)
    r.raise_for_status()
    return r.json()["results"]["bindings"]


def load_roster(app_data_json: Path):
    """Roster as [{"athlete_id", "athlete_display_name"}] from the P table of a
    built snapshot (element 0 = athlete_id, element 1 = display name)."""
    P = json.loads(app_data_json.read_text(encoding="utf-8"))["P"]
    return [{"athlete_id": str(p[0]), "athlete_display_name": p[1]} for p in P]


def reconcile(app_data_json: Path, out_csv: Path):
    roster = load_roster(app_data_json)
    print(f"Roster: {len(roster)} players")

    rows = fetch()
    print(f"Wikidata returned: {len(rows)} WNBA player records")

    wd = {}
    for b in rows:
        key = norm(b["playerLabel"]["value"])
        # Some players have multiple college statements (transfers). Keep the
        # first and note it — picking "the" college is a judgement call the
        # data doesn't make for you.
        if key in wd and wd[key].get("college"):
            continue
        # Occasionally the label service can't resolve an institution's English
        # label at all and collegeLabel falls back to the raw QID (e.g.
        # "Q1784748") — that's not a name, so treat it as no college rather
        # than showing a QID in the app.
        college = b.get("collegeLabel", {}).get("value")
        if college and re.fullmatch(r"Q\d+", college):
            college = None
        wd[key] = {
            "qid": b["player"]["value"].rsplit("/", 1)[-1],
            "college": college,
            "dob": b.get("dob", {}).get("value", "")[:10] or None,
            "country": b.get("countryLabel", {}).get("value"),
            "honours": b.get("honours", {}).get("value") or None,
        }

    out, matched, with_college = [], 0, 0
    for p in roster:
        hit = wd.get(norm(p["athlete_display_name"]))
        if hit:
            matched += 1
            if hit["college"]:
                with_college += 1
        out.append({
            "athlete_id": p["athlete_id"],
            "athlete_display_name": p["athlete_display_name"],
            "wikidata_qid": hit["qid"] if hit else "",
            "college": (hit or {}).get("college") or "",
            "date_of_birth": (hit or {}).get("dob") or "",
            "country": (hit or {}).get("country") or "",
            "honours": (hit or {}).get("honours") or "",
        })

    with open(out_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(out[0].keys()))
        w.writeheader()
        w.writerows(out)

    n = len(roster)
    print(f"\nMatched to Wikidata : {matched}/{n} ({matched/n*100:.0f}%)")
    print(f"With a college       : {with_college}/{n} ({with_college/n*100:.0f}%)")
    print(f"Wrote {out_csv}")

    unmatched = [r["athlete_display_name"] for r in out if not r["wikidata_qid"]]
    if unmatched:
        print(f"\nUnmatched ({len(unmatched)}) — expect rookies and "
              f"international players with no NCAA history:")
        for nm in unmatched[:25]:
            print("  ", nm)
        print("\nName matching is the weak link. Before hand-fixing these, check "
              "whether they exist in Wikidata at all — many genuinely don't, and "
              "a blank college is correct for anyone who went pro in Europe at 16.")


if __name__ == "__main__":
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("src/data/app-data.json")
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("data/csv/dim_player_bio.csv")
    reconcile(src, dst)
