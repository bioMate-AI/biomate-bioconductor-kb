#!/usr/bin/env python3
"""Writes the committed source-group definitions. usage: make_groups.py [v1|v2]  (EC2/Spark only; deterministic from source sizes).
v1 -> source_groups.json (amendment A1; kept for the robustness arm), v2 -> source_groups_v2.json (amendment A2)."""
import hashlib, json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import verifiers_e as VE
ver = sys.argv[1] if len(sys.argv) > 1 else "v2"
ann = VE.ANN_DEFAULT
d = VE.load_labelled(ann); groups = VE.source_groups(d, ver); d["g"] = d["Source"].map(groups)
sizes = d.groupby("Source").size().to_dict(); tot = int(sum(sizes.values()))
share = {"ABS"[0] if g == 0 else ("S" if g == 1 else "B"): None for g in (0, 1, 2)}
summ = VE.group_summary(d, groups)
for g, name in ((0, "A"), (1, "S"), (2, "B")):
    srcs = summ[g]["sources"]; n = summ[g]["n_peptides"]
    top = max(srcs, key=lambda s: sizes[s]); summ[g].update(share_of_total=round(n / tot, 4), top_source=top, top_source_share_within_group=round(sizes[top] / n, 4))
rule = {"v1": "sources with >=20 labelled PAMPA peptides; sort by (-n, name); round-robin pattern [0,1,2,2,1,0]; 0=A(train) 1=S(stop) 2=B(held-out)",
        "v2": "sources with >=20 labelled PAMPA peptides; 2020_Townsend and 2021_Kelly always A(train); other sources sorted by (-n, name) and dealt to S(1)/B(2) by snake draft pattern [1,2,2,1]; sources <20 excluded"}[ver]
out = dict(version=ver, rule=rule, annotation_file=os.path.basename(ann), annotation_sha256=hashlib.sha256(open(ann, "rb").read()).hexdigest(),
           min_labelled_per_source=VE.MIN_SRC, assay=VE.ASSAY, total_peptides=tot, n_sources=len(sizes), summary=summ,
           membership={str(s): dict(group="ASB"[g], n=int(sizes[s])) for s, g in sorted(groups.items(), key=lambda kv: (kv[1], kv[0]))})
body = json.dumps(out, indent=1, sort_keys=True)
out["membership_sha256"] = hashlib.sha256(json.dumps(out["membership"], sort_keys=True).encode()).hexdigest()
fn = os.path.join(HERE, "source_groups.json" if ver == "v1" else "source_groups_v2.json")
json.dump(out, open(fn, "w"), indent=1)
print(json.dumps({k: {kk: vv for kk, vv in v.items() if kk != "sources"} for k, v in summ.items()}, indent=1, default=str))
print("membership_sha256", out["membership_sha256"])
