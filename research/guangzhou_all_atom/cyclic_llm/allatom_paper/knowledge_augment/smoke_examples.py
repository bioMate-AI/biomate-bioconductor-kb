"""EC2 smoke for the training-example generator: 40 examples per level from group-A rows, checks the source/neighbour/exclusion invariants, writes JSON."""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from knowledge_augment import levels as L, train_examples as TE  # noqa: E402

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
rows = TE.group_a_rows()
A = set(TE.group_a_sources())
exclude = frozenset(__import__("retrieval").canon(s)[1] for s, _, _ in rows[:25])           # planted exclusions: the first 25 rows must disappear everywhere
res = {}
for lv in L.LEVELS:
    ex, info = TE.make_examples(lv, 40, seed=0, cpm_exclude_flat=exclude, rows=rows)
    flats = {__import__("retrieval").canon(e["target"])[1] for e in ex}
    nbflats = {__import__("retrieval").canon(s)[1] for e in ex for s in e["neighbours"]}
    assert not (flats & exclude) and not (nbflats & exclude), "excluded molecule appeared"
    assert all(e["source"] in A for e in ex) and all(e["config_hash"] == info["config_hash"] for e in ex)
    assert all(__import__("retrieval").canon(e["target"])[1] not in {__import__("retrieval").canon(s)[1] for s in e["neighbours"]} for e in ex), "own flat key in neighbours"
    info["example_0"] = ex[0]
    res[lv] = info
    with open(os.path.join(out, "examples_%s.jsonl" % lv), "w") as f:
        f.write("\n".join(json.dumps(e) for e in ex))
json.dump(res, open(os.path.join(out, "smoke_examples.json"), "w"), indent=1)
print(json.dumps({k: {a: v[a] for a in ("n_group_a_rows", "n_dropped_cpm_exclusion", "n_store", "n_examples", "examples_sha256")} for k, v in res.items()}))
