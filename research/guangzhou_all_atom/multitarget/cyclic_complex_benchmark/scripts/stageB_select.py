"""Stage B selection (fixed rule, committed BEFORE any Stage B sample is generated).
TRAIN = pre-cutoff, Boltz-runnable (all CCD codes in Boltz-2's library), <=600 tokens; at most 3 complexes per receptor cluster (deterministic: lowest md5(seed|id)).
TEST  = ALL post-cutoff eligible complexes (one-shot evaluation). Complexes already run in the pilot are kept (not rerun) except the 2 whose YAML was mistyped.
"""
import csv, hashlib, json, collections
SEED = "20261026"; PER_CLUSTER = 3
rows = {r["complex_id"]: r for r in csv.DictReader(open("manifest.csv"))}
elig = json.load(open("results/stageB_eligible.json"))
pilot_ok = set(json.load(open("results/pilot_results.json"))["per_complex"])
h = lambda c: hashlib.md5((SEED + "|" + c).encode()).hexdigest()
by = collections.defaultdict(list)
for c in elig["pre"]:
    by[rows[c]["receptor_cluster40"]].append(c)
train = sorted(c for cl in by.values() for c in sorted(cl, key=h)[:PER_CLUSTER])
test = sorted(elig["post"])
rerun = ["8XIP_6", "8XIR_6"]                      # YAML-mistyped CCD code (004); inputs regenerated
need_test = [c for c in test if c not in pilot_ok or c in rerun]
out = dict(seed=SEED, per_cluster=PER_CLUSTER, n_train=len(train), n_train_clusters=len(by), n_test=len(test),
           n_test_clusters=len({rows[c]["receptor_cluster40"] for c in test}), test_already_scored_in_pilot=len([c for c in test if c in pilot_ok and c not in rerun]),
           test_needs_generation=len(need_test), train=train, test=test, need_test=need_test)
json.dump(out, open("results/stageB_selection.json", "w"), indent=1)
open("results/stageB_to_generate.txt", "w").write("\n".join(train + need_test) + "\n")
print({k: v for k, v in out.items() if not isinstance(v, list)})
tr_cl = {rows[c]["receptor_cluster40"] for c in train}
novel = [c for c in test if rows[c]["receptor_cluster40"] not in tr_cl]
print("test complexes whose receptor cluster is NOT in the training set (novel-receptor subset):", len(novel), "in", len({rows[c]['receptor_cluster40'] for c in novel}), "clusters")
print("strict among train:", sum(rows[c]["runnable_strict"] == "1" for c in train), "| strict among test:", sum(rows[c]["runnable_strict"] == "1" for c in test))
