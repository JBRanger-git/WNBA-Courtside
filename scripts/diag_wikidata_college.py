import requests

ENDPOINT = "https://query.wikidata.org/sparql"
HEADERS = {
    "User-Agent": "WNBACourtside/0.3 (diagnostic; https://github.com/YOURNAME/courtside)",
    "Accept": "application/sparql-results+json",
}

# For a few known players, dump EVERY "educated at" (P69) entry and its
# "instance of" (P31) type(s) — raw, unfiltered — so we can see the real shape
# that distinguishes a college/university from a high school.
QUERY = """
SELECT ?playerLabel ?collegeLabel ?collegeTypeLabel WHERE {
  ?league rdfs:label "Women's National Basketball Association"@en .
  ?team wdt:P118 ?league .
  ?player wdt:P54 ?team .
  ?player rdfs:label ?enLabel . FILTER(LANG(?enLabel) = "en")
  FILTER(?enLabel IN ("A'ja Wilson", "Breanna Stewart", "Diana Taurasi", "Caitlin Clark"))
  ?player wdt:P69 ?college .
  OPTIONAL { ?college wdt:P31 ?collegeType . }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
"""

r = requests.get(ENDPOINT, params={"format": "json", "query": QUERY}, headers=HEADERS, timeout=120)
r.raise_for_status()
rows = r.json()["results"]["bindings"]
print(f"rows: {len(rows)}")
for b in rows:
    player = b.get("playerLabel", {}).get("value")
    college = b.get("collegeLabel", {}).get("value")
    ctype = b.get("collegeTypeLabel", {}).get("value")
    print(f"  {player!r} | educated at: {college!r} | type: {ctype!r}")
