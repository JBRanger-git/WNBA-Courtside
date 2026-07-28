import requests

ENDPOINT = "https://query.wikidata.org/sparql"
HEADERS = {
    "User-Agent": "WNBACourtside/0.3 (diagnostic; https://github.com/YOURNAME/courtside)",
    "Accept": "application/sparql-results+json",
}

# Jordin Canada's college now leaked as "Windward School" (her LA prep school,
# not UCLA). Dump every P69 entry + P31 type for her specifically to see the
# real type label causing "Windward School" to pass the university/college
# substring filter.
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
shown = 0
for b in rows:
    player = b.get("playerLabel", {}).get("value") or ""
    if "canada" in player.lower():
        college = b.get("collegeLabel", {}).get("value")
        ctype = b.get("collegeTypeLabel", {}).get("value")
        print(f"  {player!r} | educated at: {college!r} | type: {ctype!r}")
        shown += 1
print(f"shown: {shown}")
