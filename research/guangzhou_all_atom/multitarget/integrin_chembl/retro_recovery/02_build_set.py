"""Step 1b: build the FROZEN study set for the multi-target retrospective recovery study (PREREG amendments A1, A2).
Reads binding_affinity_v1.csv + data/uniprot_pfam.tsv; writes data/*.csv.gz + data/FROZEN_HASHES.json. NO scorer is run here.
Rules (all fixed here, before any scoring):
  compounds : cyclic_bool rows; largest ring >= 9; >= 3 backbone amides (C(=O)N[CX4]); largest fragment kept.
  affinity  : rows with affinity_nM finite and 0 < nM <= 1e9 kept (rows <=0 or >1e9 are unit/parse errors -> excluded and counted); relation '~' and '<<' excluded.
  pair label: per (compound, target) over its rows. '=' rows -> median nM; positive if median <= 1000; inactive if median > 10000; 1000 < median <= 10000 unlabeled.
              no '=' rows: '<'/'<=' with value <= 1000 -> positive; '>'/'>=' with value >= 10000 -> inactive; otherwise unlabeled.
              CONFLICT (min '=' <= 1000 and max '=' > 10000) -> dropped.
  target    : sorted UniProt accession set of the row (split on , ; whitespace); rows with null target dropped.
  family    : connected components over targets linked when Jaccard(Pfam-accession sets) >= 0.67 (an earlier 'share any non-promiscuous Pfam' rule chained 356 of 793 targets into one family and was rejected before any scoring); targets with no Pfam are singletons.
  eligible  : target has >= 5 positives with DISTINCT flat structures (stereoisomers collapse) -- stricter than A1's '>= 5 positives' because stereoisomer series are pseudo-replicates (A2).
  decoys    : M (matched cross-target) up to 20 per positive; I (same-target measured inactives, > 10 uM) for targets with >= 5 flat-distinct positives and >= 20 flat-distinct inactives.
"""
import os, re, json, hashlib, collections
import numpy as np, pandas as pd
import chem

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, "../../.."))
DATA = f"{HERE}/data"; SEED = 20261028; PROMISC_MAX = None; N_DECOY = 20; MIN_DECOY = 10
rng = np.random.default_rng(SEED)
LOG = {}

d = pd.read_csv(f"{ROOT}/data/raw/binding_affinity/binding_affinity_v1.csv", low_memory=False)
LOG["rows_total"] = len(d)
d = d[d.cyclic_bool == True].copy(); LOG["rows_cyclic_flag"] = len(d)
LOG["rows_null_target"] = int(d.target_uniprot.isna().sum()); d = d[d.target_uniprot.notna()]
bad_unit = (d.affinity_nM <= 0) | (d.affinity_nM > 1e9) | d.affinity_nM.isna()
LOG["rows_excluded_affinity_nonpositive_or_gt1e9_or_nan"] = int(bad_unit.sum()); d = d[~bad_unit]
LOG["rows_excluded_relation_tilde_or_ll"] = int(d.relation.isin(["~", "<<"]).sum()); d = d[~d.relation.isin(["~", "<<"])]
d["target_key"] = d.target_uniprot.astype(str).map(lambda s: ",".join(sorted({a for a in re.split(r"[,\s;]+", s) if a})))

# ---- compounds
smi_uniq = d.smiles.dropna().unique()
rec = {}
_cache = os.environ.get("RETRO_REC_CACHE")                      # optional pickle cache of the (deterministic, ~5 min) per-SMILES chemistry pass
if _cache and os.path.exists(_cache):
    import pickle; rec = pickle.load(open(_cache, "rb"))
for s in ([] if rec else smi_uniq):
    m = chem.parse(s)
    if m is None:
        continue
    dsc = chem.descriptors(m)
    if dsc["ring"] < 9 or dsc["amide"] < 3:
        continue
    iso, flat = chem.keys(m)
    c = chem.classify(m)
    rec[s] = dict(iso_smiles=iso, flat_key=flat, stratum=c["stratum"], n_alpha=c["n_alpha"], **dsc)
if _cache and not os.path.exists(_cache):
    import pickle; pickle.dump(rec, open(_cache, "wb"))
LOG["smiles_unique_in_cyclic_rows"] = int(len(smi_uniq)); LOG["smiles_passing_macrocycle_peptide_filter"] = len(rec)
d = d[d.smiles.isin(rec)].copy()
for k in ("iso_smiles", "flat_key", "stratum"):
    d[k] = d.smiles.map(lambda s, k=k: rec[s][k])
comp = pd.DataFrame(list(rec.values())).drop_duplicates("iso_smiles").sort_values("iso_smiles").reset_index(drop=True)
comp["compound_id"] = comp.iso_smiles.map(lambda s: hashlib.sha1(s.encode()).hexdigest()[:12])
cid = dict(zip(comp.iso_smiles, comp.compound_id)); d["compound_id"] = d.iso_smiles.map(cid)
LOG["compounds"] = len(comp); LOG["flat_structures"] = int(comp.flat_key.nunique())
LOG["stratum_counts"] = comp.stratum.value_counts().to_dict()
LOG["rows_after_filter"] = len(d); LOG["assay_type_counts"] = d.affinity_type.value_counts().to_dict(); LOG["source_counts"] = d.source.value_counts().to_dict()


# ---- pair labels
def label_pair(g):
    eq = g[g.relation == "="].affinity_nM.values
    if len(eq):
        if eq.min() <= 1000 and eq.max() > 10000:
            return "conflict", float(np.median(eq))
        med = float(np.median(eq))
        return ("pos" if med <= 1000 else "inactive" if med > 10000 else "gray"), med
    lo = g[g.relation.isin(["<", "<="])].affinity_nM
    hi = g[g.relation.isin([">", ">="])].affinity_nM
    if len(lo) and lo.min() <= 1000:
        return "pos", float(lo.min())
    if len(hi) and hi.max() >= 10000:
        return "inactive", float(hi.max())
    return "gray", float(g.affinity_nM.median())


pairs = []
for (c, t), g in d.groupby(["compound_id", "target_key"], sort=True):
    lab, v = label_pair(g)
    pairs.append((c, t, lab, v, len(g), ";".join(sorted(g.affinity_type.unique())), ";".join(sorted(g.relation.unique()))))
P = pd.DataFrame(pairs, columns=["compound_id", "target_key", "label", "value_nM", "n_rows", "assay_types", "relations"])
LOG["pairs_all"] = len(P); LOG["pair_label_counts"] = P.label.value_counts().to_dict()
P = P[P.label.isin(["pos", "inactive"])].merge(comp[["compound_id", "flat_key", "stratum"]], on="compound_id")

# ---- families
pf = pd.read_csv(f"{DATA}/uniprot_pfam.tsv", sep="\t")
pf["pfam"] = pf.Pfam.fillna("").map(lambda s: [x for x in s.split(";") if x])
acc_pfam = dict(zip(pf.Entry, pf.pfam)); acc_gene = dict(zip(pf.Entry, pf["Gene Names"].fillna("").str.split().str[0].fillna("")))
targets = sorted(P.target_key.unique()); LOG["targets_with_labeled_pairs"] = len(targets)
tp = {t: sorted({p for a in t.split(",") for p in acc_pfam.get(a, [])}) for t in targets}
LOG["family_rule"] = "targets linked when Jaccard(Pfam sets) >= 0.67 (connected components); targets with no Pfam are singletons"
JACC = 0.67
pset = {t: frozenset(tp[t]) for t in targets}
parent = {t: t for t in targets}


def find(x):
    while parent[x] != x:
        parent[x] = parent[parent[x]]
        x = parent[x]
    return x


for i, a_ in enumerate(targets):
    if not pset[a_]:
        continue
    for b_ in targets[i + 1:]:
        if pset[b_] and len(pset[a_] & pset[b_]) / len(pset[a_] | pset[b_]) >= JACC:
            parent[find(a_)] = find(b_)
fam = {t: "F" + hashlib.sha1(find(t).encode()).hexdigest()[:8] for t in targets}
fsize = collections.Counter(fam.values()); LOG["n_families"] = len(fsize); LOG["largest_family_targets"] = fsize.most_common(3)
LOG["targets_without_pfam"] = sum(1 for t in targets if not tp[t])

# ---- per-target tables
posf = P[P.label == "pos"].groupby("target_key").flat_key.nunique()
inaf = P[P.label == "inactive"].groupby("target_key").flat_key.nunique()
posn = P[P.label == "pos"].groupby("target_key").compound_id.nunique()
T = []
for t in targets:
    genes = ",".join(sorted({acc_gene.get(a, "") for a in t.split(",")} - {""}))
    T.append(dict(target_key=t, family=fam[t], genes=genes, pfam=";".join(tp[t]), n_pos=int(posn.get(t, 0)), n_pos_flat=int(posf.get(t, 0)), n_inactive_flat=int(inaf.get(t, 0))))
T = pd.DataFrame(T)
T["eligible_M"] = T.n_pos_flat >= 5
T["eligible_I"] = (T.n_pos_flat >= 5) & (T.n_inactive_flat >= 20)
LOG["targets_eligible_M_flat5"] = int(T.eligible_M.sum()); LOG["targets_eligible_M_if_count_compounds_5"] = int((T.n_pos >= 5).sum()); LOG["targets_eligible_I"] = int(T.eligible_I.sum())
LOG["families_eligible_M"] = int(T[T.eligible_M].family.nunique()); LOG["families_eligible_I"] = int(T[T.eligible_I].family.nunique())

# ---- decoys
pos_by_t = {t: g for t, g in P[P.label == "pos"].groupby("target_key")}
posts_of = P[P.label == "pos"].groupby("compound_id").target_key.apply(set).to_dict()
cinfo = comp.set_index("compound_id")


def ringbin(r):
    return 0 if r <= 12 else 1 if r <= 20 else 2


pool_ids = np.array(sorted(posts_of)); pool_meta = cinfo.loc[pool_ids]
pool_rb = np.array([ringbin(r) for r in pool_meta.ring.values]); pool_flat = pool_meta.flat_key.values
pool_fams = [{fam[x] for x in posts_of[c]} for c in pool_ids]
items_M = []; dropped = []
for t in T[T.eligible_M].target_key:
    fam_t = fam[t]; g = pos_by_t[t]; pos_flat = set(g.flat_key)
    bad = np.array([(fam_t in pool_fams[i]) or (pool_flat[i] in pos_flat) for i in range(len(pool_ids))])
    used = set()
    for _, p in g.drop_duplicates("flat_key").iterrows():
        pm = cinfo.loc[p.compound_id]
        items_M.append((t, p.compound_id, 1, "positive"))
        tol = max(3, int(round(0.10 * pm.heavy)))
        ok = (~bad) & (pool_meta.stratum.values == pm.stratum) & (np.abs(pool_meta.heavy.values - pm.heavy) <= tol) \
            & (np.abs(pool_meta.charge.values - pm.charge) <= 1) & (pool_rb == ringbin(pm.ring))
        cand = [c for c in pool_ids[ok] if c not in used]
        k = min(N_DECOY, len(cand))
        pick = list(rng.choice(cand, k, replace=False)) if k else []
        used.update(pick)
        for c in pick:
            items_M.append((t, c, 0, f"cross_target|matched_to:{p.compound_id}"))
        if k < MIN_DECOY:
            dropped.append((t, p.compound_id, k))
IM = pd.DataFrame(items_M, columns=["target_key", "compound_id", "label", "decoy_type"])
dp = {(t, c) for t, c, k in dropped}; LOG["positives_dropped_insufficient_decoys"] = len(dp)
IM["match_pos"] = IM.decoy_type.str.extract(r"matched_to:(\w+)")[0]
drop_mask = [((r.target_key, r.compound_id) in dp) if r.label == 1 else ((r.target_key, r.match_pos) in dp) for r in IM.itertuples()]
IM = IM[~np.array(drop_mask)].drop(columns="match_pos").reset_index(drop=True)
# targets left with < 5 positives after dropping are removed entirely
npos = IM[IM.label == 1].groupby("target_key").size(); keep = set(npos[npos >= 5].index)
IM = IM[IM.target_key.isin(keep)].reset_index(drop=True)

items_I = []
inact = P[P.label == "inactive"].drop_duplicates(["target_key", "flat_key"])
for t in T[T.eligible_I].target_key:
    for _, p in pos_by_t[t].drop_duplicates("flat_key").iterrows():
        items_I.append((t, p.compound_id, 1, "positive"))
    pos_flat = set(pos_by_t[t].flat_key)
    for _, r in inact[(inact.target_key == t) & ~inact.flat_key.isin(pos_flat)].iterrows():
        items_I.append((t, r.compound_id, 0, "same_target_inactive"))
II = pd.DataFrame(items_I, columns=["target_key", "compound_id", "label", "decoy_type"])
LOG["items_M"] = len(IM); LOG["items_M_positives"] = int((IM.label == 1).sum()); LOG["targets_in_M_after_drop"] = int(IM.target_key.nunique())
LOG["items_I"] = len(II); LOG["items_I_positives"] = int((II.label == 1).sum()); LOG["targets_in_I"] = int(II.target_key.nunique())
LOG["families_in_M"] = int(T[T.target_key.isin(set(IM.target_key))].family.nunique()); LOG["families_in_I"] = int(T[T.target_key.isin(set(II.target_key))].family.nunique())


def frac_rgd(ids):
    return float(cinfo.loc[list(ids), "rgd"].mean())


LOG["rgd_fraction_M_positives"] = frac_rgd(IM[IM.label == 1].compound_id); LOG["rgd_fraction_M_decoys"] = frac_rgd(IM[IM.label == 0].compound_id)
LOG["rgd_fraction_I_positives"] = frac_rgd(II[II.label == 1].compound_id); LOG["rgd_fraction_I_decoys"] = frac_rgd(II[II.label == 0].compound_id)
LOG["stratum_M_positives"] = cinfo.loc[IM[IM.label == 1].compound_id, "stratum"].value_counts().to_dict()
LOG["stereo_pairs_opposite_labels_same_target"] = int((P.groupby(["target_key", "flat_key"]).label.nunique() > 1).sum())
ab = T[T.genes.str.contains("ITGB6|ITGAV|ITGB3|ITGA5", regex=True)]
LOG["integrin_targets"] = ab[["target_key", "genes", "n_pos_flat", "n_inactive_flat", "eligible_M", "eligible_I"]].to_dict("records")

# ---- freeze
os.makedirs(DATA, exist_ok=True)
files = {"compounds.csv.gz": comp, "pair_labels.csv.gz": P, "targets.csv": T, "items_M.csv.gz": IM, "items_I.csv.gz": II}
H = {}
for f, df in files.items():
    path = f"{DATA}/{f}"
    if f.endswith(".gz"):
        df.to_csv(path, index=False, compression=dict(method="gzip", mtime=0))
    else:
        df.to_csv(path, index=False)
    H[f] = hashlib.sha256(open(path, "rb").read()).hexdigest()
H["uniprot_pfam.tsv"] = hashlib.sha256(open(f"{DATA}/uniprot_pfam.tsv", "rb").read()).hexdigest()
H["02_build_set.py"] = hashlib.sha256(open(__file__, "rb").read()).hexdigest(); H["chem.py"] = hashlib.sha256(open(f"{HERE}/chem.py", "rb").read()).hexdigest()
json.dump(dict(hashes=H, seed=SEED, params=dict(JACC=JACC, N_DECOY=N_DECOY, MIN_DECOY=MIN_DECOY)), open(f"{DATA}/FROZEN_HASHES.json", "w"), indent=1)
json.dump(LOG, open(f"{DATA}/build_log.json", "w"), indent=1, default=str)
print(json.dumps(LOG, indent=1, default=str))
