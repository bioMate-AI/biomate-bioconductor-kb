"""Pre-registered pilot selection (PREREG s2). usage: select_pilot.py CACHE_DIR INP_DIR OUT.json
Prep all post&runnable_ccd complexes (cheap), token cap 750 (receptor chains + peptide), seed 20261025:
(a) one random complex per STRICT receptor cluster, (b) then one random complex per other CCD-tier cluster until 40."""
import json, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prep_inputs as P
cache, inp, out = sys.argv[1:4]
rows = [r for r in P.load_manifest() if r["set"] == "post" and r["runnable_ccd"] == "1"]
ok, fail = [], {}
for r in rows:
    try:
        m = P.build(r, cache, inp)
        m["tokens"] = sum(len(s) for s in m["rec_seq"].values()) + len(m["peptide_seq"])
        ok.append((r, m))
    except Exception as e:
        fail[r["complex_id"]] = repr(e)[:200]
    c = os.path.join(cache, r["pdb_id"] + ".cif")
    if os.path.exists(c): os.remove(c)
cand = [(r, m) for r, m in ok if m["tokens"] <= 750]
rng = random.Random(20261025)
chosen, used = [], set()
strict_cl = sorted({r["receptor_cluster40"] for r, m in cand if r["runnable_strict"] == "1"})
for cl in strict_cl:
    pool = sorted([r["complex_id"] for r, m in cand if r["receptor_cluster40"] == cl and r["runnable_strict"] == "1"])
    chosen.append(rng.choice(pool)); used.add(cl)
rest = sorted({r["receptor_cluster40"] for r, m in cand} - used)
rng.shuffle(rest)
for cl in rest:
    if len(chosen) >= 40: break
    pool = sorted([r["complex_id"] for r, m in cand if r["receptor_cluster40"] == cl])
    chosen.append(rng.choice(pool))
json.dump(dict(chosen=chosen, n_candidates_ccd=len(rows), prep_ok=len(ok), prep_fail=fail, n_cand_le750=len(cand),
               strict_clusters_available=len(strict_cl), n_strict_chosen=sum(1 for c in chosen if dict((r["complex_id"], r) for r, _ in cand)[c]["runnable_strict"] == "1")),
          open(out, "w"), indent=1)
print(open(out).read()[:1500])
