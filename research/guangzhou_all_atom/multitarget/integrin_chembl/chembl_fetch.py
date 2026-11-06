"""Polite cached ChEMBL REST fetcher. Cache dir: env INTEGRIN_CACHE."""
import os, json, time, hashlib, urllib.request, urllib.parse
CACHE = os.environ.get("INTEGRIN_CACHE", "/private/tmp/claude-501/-Users-kky-biomate-review/195b4da4-5c44-48ae-a4e1-005d493239c0/scratchpad/chembl")
BASE = "https://www.ebi.ac.uk"
def get(url, sleep=0.4):
    if url.startswith("/"): url = BASE + url
    p = os.path.join(CACHE, hashlib.md5(url.encode()).hexdigest() + ".json")
    if os.path.exists(p): return json.load(open(p))
    for a in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"Accept": "application/json"}), timeout=60) as r:
                d = json.load(r); break
        except Exception as e:
            time.sleep(2 * (a + 1)); d = None; err = e
    if d is None: raise RuntimeError(f"{url}: {err}")
    json.dump(d, open(p, "w")); time.sleep(sleep); return d
def paged(url, key):
    out = []
    while url:
        d = get(url); out += d[key]; url = d["page_meta"]["next"]
    return out
