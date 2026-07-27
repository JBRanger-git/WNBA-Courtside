import requests

ENDPOINT = "https://query.wikidata.org/sparql"
HEADERS = {
    "User-Agent": "WNBACourtside/0.3 (diagnostic; https://github.com/YOURNAME/courtside)",
    "Accept": "application/sparql-results+json",
}

# Dump P31 types for the specific institutions that leaked through the
# university/college substring filter as "college" for real players — find out
# what type label is causing the false positive (hypothesis: something like
# "college-preparatory school", a real Wikidata class for some US high
# schools, which contains the substring "college").
NAMES = [
    "Winter Haven High School", "Sierra Canyon School", "Cardinal O'Hara High School",
    "Riverdale Baptist School", "Manasquan High School",
]
QUERY = """
SELECT ?instLabel ?typeLabel WHERE {
  VALUES ?name { %s }
  ?inst rdfs:label ?name .
  ?inst wdt:P31 ?type .
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
""" % " ".join(f'"{n}"@en' for n in NAMES)

r = requests.get(ENDPOINT, params={"format": "json", "query": QUERY}, headers=HEADERS, timeout=120)
r.raise_for_status()
rows = r.json()["results"]["bindings"]
print(f"rows: {len(rows)}")
for b in rows:
    print(f"  {b.get('instLabel',{}).get('value')!r} | type: {b.get('typeLabel',{}).get('value')!r}")
