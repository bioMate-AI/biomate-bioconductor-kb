"""Protein-level families and folds_v2 (PREREG A11 item 4). v1 files are NOT modified.
Families v2 = connected components of targets linked when (i) they share any UniProt accession, (ii) they share a gene symbol (case-insensitive; offline ortholog / same-gene proxy
from data/uniprot_pfam.tsv), or (iii) Jaccard(Pfam sets) >= 0.67 (the v1 rule). Folds: same LPT bin-packing on distinct compounds as folds_v1.
Writes data/targets_v2.csv, data/folds_v2.csv, data/folds_v2.json (stats + hashes)."""
import os, re, json, hashlib, collections
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; K = 5
T = pd.read_csv(f"{DATA}/targets.csv"); P = pd.read_csv(f"{DATA}/pair_labels.csv.gz"); pf = pd.read_csv(f"{DATA}/uniprot_pfam.tsv", sep="\t")
gene = {e: [g.upper() for g in str(n).split()] for e, n in zip(pf.Entry, pf["Gene Names"].fillna(""))}
ts = list(T.target_key); parent = {t: t for t in ts}
def find(x):
    while parent[x] != x: parent[x] = parent[parent[x]]; x = parent[x]
    return x
def union(a, b): parent[find(a)] = find(b)
accs = {t: [a for a in re.split(r"[,\s;]+", t) if a] for t in ts}
by_acc = collections.defaultdict(list); by_gene = collections.defaultdict(list)
for t in ts:
    for a in accs[t]:
        by_acc[a].append(t)
        for g in gene.get(a, [])[:1]: by_gene[g].append(t)               # primary gene symbol only
n_link = {"accession": 0, "gene": 0, "pfam": 0}
for a, tl in by_acc.items():
    for t in tl[1:]:
        if find(t) != find(tl[0]): n_link["accession"] += 1
        union(t, tl[0])
for g, tl in by_gene.items():
    for t in tl[1:]:
        if find(t) != find(tl[0]): n_link["gene"] += 1
        union(t, tl[0])
ps = {t: frozenset(p for p in str(T.set_index("target_key").pfam.get(t, "")).split(";") if p and p != "nan") for t in ts}
for i, a in enumerate(ts):
    if not ps[a]: continue
    for b in ts[i + 1:]:
        if ps[b] and len(ps[a] & ps[b]) / len(ps[a] | ps[b]) >= 0.67:
            if find(a) != find(b): n_link["pfam"] += 1
            union(a, b)
T2 = T.copy(); T2["family_v1"] = T2.family; T2["family"] = ["G" + hashlib.sha1(find(t).encode()).hexdigest()[:8] for t in ts]
P["family"] = P.target_key.map(dict(zip(T2.target_key, T2.family))); w = P.groupby("family").compound_id.nunique(); nt = T2.groupby("family").size()
order = sorted(w.index, key=lambda f: (-w[f], f)); load = [0] * K; assign = {}
for f in order:
    k = min(range(K), key=lambda i: (load[i], i)); assign[f] = k; load[k] += int(w[f])
F = pd.DataFrame(dict(family=order, fold=[assign[f] for f in order], n_targets=[int(nt[f]) for f in order], n_compounds=[int(w[f]) for f in order])); F.to_csv(f"{DATA}/folds_v2.csv", index=False)
T2["fold"] = T2.family.map(assign); T2.drop(columns=["fold"]).to_csv(f"{DATA}/targets_v2.csv", index=False)
v1 = pd.read_csv(f"{DATA}/folds_v1.csv"); fold1 = dict(zip(v1.family, v1.fold)); T2["fold_v1"] = T2.family_v1.map(fold1)
# diagnostics
accfam = collections.defaultdict(set); accfold = collections.defaultdict(set)
for t in ts:
    for a in accs[t]: accfam[a].add(T2.set_index("target_key").family_v1[t]); accfold[a].add(fold1[T2.set_index("target_key").family_v1[t]])
acc2 = collections.defaultdict(set); accf2 = collections.defaultdict(set)
for t in ts:
    for a in accs[t]: acc2[a].add(T2.set_index("target_key").family[t]); accf2[a].add(assign[T2.set_index("target_key").family[t]])
I = pd.read_csv(f"{DATA}/items_I.csv.gz"); M2 = pd.read_csv(f"{DATA}/items_M2.csv.gz")
def same_protein_other_fold(items, famcol, foldmap):
    """targets in the analysis that share an accession with another target (any, in the 793) that lies in a different fold"""
    out = 0
    for t in items.target_key.unique():
        mine = foldmap[T2.set_index("target_key")[famcol][t]]
        if any(foldmap[T2.set_index("target_key")[famcol][o]] != mine for a in accs[t] for o in by_acc[a] if o != t): out += 1
    return out
fold2 = assign
stats = dict(link_counts=n_link, families_v1=int(T2.family_v1.nunique()), families_v2=int(T2.family.nunique()), largest_family_v2=int(nt.max()),
             accessions_in_gt1_family_v1=int(sum(len(v) > 1 for v in accfam.values())), accessions_in_gt1_family_v2=int(sum(len(v) > 1 for v in acc2.values())),
             accessions_spanning_gt1_fold_v1=int(sum(len(v) > 1 for v in accfold.values())), accessions_spanning_gt1_fold_v2=int(sum(len(v) > 1 for v in accf2.values())),
             I_targets_with_same_protein_target_in_other_fold_v1=same_protein_other_fold(I, "family_v1", fold1), I_targets_with_same_protein_target_in_other_fold_v2=same_protein_other_fold(I, "family", fold2),
             M2_targets_with_same_protein_target_in_other_fold_v1=same_protein_other_fold(M2, "family_v1", fold1), M2_targets_with_same_protein_target_in_other_fold_v2=same_protein_other_fold(M2, "family", fold2),
             fold_compounds_v2=load, I_families_v1=int(I.target_key.map(dict(zip(T2.target_key, T2.family_v1))).nunique()), I_families_v2=int(I.target_key.map(dict(zip(T2.target_key, T2.family))).nunique()),
             I_fold_of_target_changed=int(sum(T2.set_index("target_key").fold_v1[t] != assign[T2.set_index("target_key").family[t]] for t in I.target_key.unique())))
av = T2[T2.genes.fillna("").str.upper().str.contains("ITGB6")]; stats["avb6_targets"] = av[["target_key", "genes", "family_v1", "family", "fold_v1"]].assign(fold_v2=[assign[f] for f in av.family]).to_dict("records")
iv = T2[T2.genes.fillna("").str.upper().str.contains("ITG")]; stats["integrin_targets_total"] = int(len(iv)); stats["integrin_families_v1"] = int(iv.family_v1.nunique()); stats["integrin_families_v2"] = int(iv.family.nunique())
stats["integrin_folds_v1"] = sorted(set(int(x) for x in iv.fold_v1)); stats["integrin_folds_v2"] = sorted(set(assign[f] for f in iv.family))
stats["hashes"] = {"folds_v2.csv": hashlib.sha256(open(f"{DATA}/folds_v2.csv", "rb").read()).hexdigest(), "targets_v2.csv": hashlib.sha256(open(f"{DATA}/targets_v2.csv", "rb").read()).hexdigest(), "19_folds_v2.py": hashlib.sha256(open(__file__, "rb").read()).hexdigest()}
json.dump(stats, open(f"{DATA}/folds_v2.json", "w"), indent=1, default=int); print(json.dumps(stats, indent=1, default=int))
