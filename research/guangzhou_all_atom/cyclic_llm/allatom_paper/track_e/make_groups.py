#!/usr/bin/env python3
"""Writes the committed source-group definition (A=0 train, S=1 stop, B=2 held-out) used by every verifier and by U1's soft-rule mining.
Rule (amendment A1): sources with >= 20 labelled PAMPA peptides (post-source-fix annotation); sort by (-n_peptides, source name);
assign groups round-robin with the fixed pattern [0,1,2,2,1,0]. It uses only source sizes, never a score. EC2/Spark only."""
import hashlib, json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import verifiers_e as VE
ann = VE.ANN_DEFAULT
d = VE.load_labelled(ann); groups = VE.source_groups(d); d["g"] = d["Source"].map(groups)
sizes = d.groupby("Source").size().to_dict()
out = dict(rule="sources with >=20 labelled PAMPA peptides; sort by (-n, name); round-robin pattern [0,1,2,2,1,0]; group 0=A(train) 1=S(stop) 2=B(held-out)",
           annotation_file=os.path.basename(ann), annotation_sha256=hashlib.sha256(open(ann, "rb").read()).hexdigest(),
           min_labelled_per_source=VE.MIN_SRC, assay=VE.ASSAY, summary=VE.group_summary(d, groups),
           membership={str(s): dict(group="ASB"[g], n=int(sizes[s])) for s, g in sorted(groups.items(), key=lambda kv: (kv[1], kv[0]))})
json.dump(out, open(os.path.join(HERE, "source_groups.json"), "w"), indent=1)
print(json.dumps(out["summary"], indent=1, default=str)[:1500])
