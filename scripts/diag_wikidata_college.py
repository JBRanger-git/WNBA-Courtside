import requests

ENDPOINT = "https://query.wikidata.org/sparql"
HEADERS = {
    "User-Agent": "WNBACourtside/0.3 (diagnostic; https://github.com/YOURNAME/courtside)",
    "Accept": "application/sparql-results+json",
}

# Dump EVERY "educated at" (P69) entry + "instance of" (P31) type for the
# WHOLE roster — same base pattern as the production query in wikidata_bio.py
# (proven to return rows: 65 real matches in prod), plus the P31 type. Filter
# for players of interest in Python afterward rather than in SPARQL — an
# earlier attempt with a SPARQL-side FILTER(?enLabel IN (...)) returned 0 rows,
# most likely an apostrophe-encoding mismatch against "A'ja Wilson" on
# Wikidata's side, not a data-absence issue.
QUERY = """
SELECT ?playerLabel ?collegeLabel ?collegeTypeLabel WHERE {
  ?league rdfs:label "Women's National Basketball Association"@en .
  ?team wdt:P118 ?league .
  ?player wdt:P54 ?team .
  ?player wdt:P69 ?college .
  OPTIONAL { ?college wdt:P31 ?collegeType . }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
"""

r = requests.get(ENDPOINT, params={"format": "json", "query": QUERY}, headers=HEADERS, timeout=120)
r.raise_for_status()
rows = r.json()["results"]["bindings"]
print(f"rows: {len(rows)}")
WATCH = ["wilson", "stewart", "taurasi", "clark"]
shown = 0
for b in rows:
    player = b.get("playerLabel", {}).get("value") or ""
    college = b.get("collegeLabel", {}).get("value")
    ctype = b.get("collegeTypeLabel", {}).get("value")
    if any(w in player.lower() for w in WATCH):
        print(f"  {player!r} | educated at: {college!r} | type: {ctype!r}")
        shown += 1
print(f"shown: {shown}")
