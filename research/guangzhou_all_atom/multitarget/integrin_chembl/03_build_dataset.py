"""Step 3: filter funnel + document-controlled dataset. Reads the scratchpad raw pickle; writes compact tables into data/."""
import os, json, math, itertools
import numpy as np, pandas as pd
from common import *
RAW = os.environ.get("INTEGRIN_CACHE", "/private/tmp/claude-501/-Users-kky-biomate-review/195b4da4-5c44-48ae-a4e1-005d493239c0/scratchpad") + "/raw_acts.pkl"
d = pd.read_pickle(RAW)
docs = json.load(open("data/documents.json"))
funnel = {}
def stat(df, label_col="target"):
    return {t: dict(n_act=int(len(g)), n_cmpd=int(g.cmpd_key.nunique()) if "cmpd_key" in g else int(g.molecule_chembl_id.nunique()), n_doc=int(g.document_chembl_id.nunique())) for t, g in df.groupby(label_col)}
INSCOPE = ["avb3","avb5","avb6","avb8","avb1","a5b1","aIIbb3","a8b1"]
# F0 raw as annotated by ChEMBL target id (in-scope heterodimer targets only)
funnel["F0_raw_annotated_inscope_targets"] = stat(d[d.in_scope])
# target remap rescue (assay description names exactly one heterodimer) for out-of-scope / mixed targets
d["target_final"] = np.where(d.in_scope, d.target, None)
resc = d[~d.in_scope].copy(); resc["resc"] = resc.assay_description.map(integrin_from_description)
d.loc[resc.index[resc.resc.notna()], "target_final"] = resc.resc[resc.resc.notna()]
d["remapped"] = (~d.in_scope) & d.target_final.notna()
funnel["F0b_remapped_from_other_chembl_targets"] = {t: int(n) for t, n in d[d.remapped].target_final.value_counts().items()}
funnel["F0b_remapped_from_which_chembl_target"] = {t: int(n) for t, n in d[d.remapped].target.value_counts().items()}
funnel["F0c_out_of_scope_not_rescued"] = int((~d.in_scope & ~d.remapped).sum())
d = d[d.target_final.notna()].copy(); d["target"] = d.target_final
funnel["F0d_after_remap_all_assay_types"] = stat(d)
d["rel"] = d.standard_relation.map(relation_class)
# F1 units / value / relation
f1 = d[(d.standard_units == "nM") & d.standard_value.notna() & (pd.to_numeric(d.standard_value, errors="coerce") > 0) & d.rel.notna()].copy()
f1["standard_value"] = pd.to_numeric(f1.standard_value); funnel["F1_nM_value_gt0_relation_in(=,<,>,<=,>=)"] = stat(f1)
f1b = f1.copy(); funnel["F1_dropped"] = dict(non_nM=int((d.standard_units != "nM").sum()), no_relation=int(d.rel.isna().sum()))
# F2 assay type
funnel["F2a_assay_type_counts"] = {str(k): int(v) for k, v in f1.assay_type.value_counts().items()}
f2 = f1[f1.assay_type == "B"].copy(); funnel["F2_assay_type_B_only"] = stat(f2)
# F3 validity
f3 = f2[f2.data_validity_comment.isna() & (f2.potential_duplicate.fillna(0).astype(int) == 0)].copy(); funnel["F3_validity_ok_not_potential_duplicate"] = stat(f3)
# F4 structures
cache = {}
def std(smi):
    if smi not in cache: cache[smi] = standardize_smiles(smi)[1:]
    return cache[smi]
f3[["smiles_std", "flat_key", "full_key"]] = [std(s) for s in f3.canonical_smiles]
f4 = f3[f3.flat_key.notna()].copy(); f4["cmpd_key"] = f4.flat_key; funnel["F4_structure_parsed"] = stat(f4)
f4["pact_raw"] = f4.standard_value.map(nM_to_pact)
f4["assay_class"] = [assay_class(a, t) for a, t in zip(f4.assay_description, f4.assay_type)]
# F5 uncensored
f5 = f4[f4.rel == "eq"]; funnel["F5_uncensored_equal_only"] = stat(f5)
funnel["F5_censored_counts"] = {k: int(v) for k, v in f4.rel.value_counts().items()}
# aggregate to (doc, cmpd, target, assay_class)
def agg(g):
    eq = g[g.rel == "eq"]
    if len(eq): return pd.Series(dict(pact=float(np.median(eq.pact_raw)), censor="eq", n_rec=len(eq), sd=float(eq.pact_raw.std(ddof=0)) if len(eq) > 1 else 0.0, smiles=g.smiles_std.iloc[0], full_key=g.full_key.iloc[0], year=g.document_year.iloc[0], remapped=bool(g.remapped.any())))
    gt = g[g.rel == "gt"]; lt = g[g.rel == "lt"]
    if len(gt) and not len(lt): return pd.Series(dict(pact=float(gt.pact_raw.max()), censor="gt", n_rec=len(gt), sd=0.0, smiles=g.smiles_std.iloc[0], full_key=g.full_key.iloc[0], year=g.document_year.iloc[0], remapped=bool(g.remapped.any())))
    if len(lt) and not len(gt): return pd.Series(dict(pact=float(lt.pact_raw.min()), censor="lt", n_rec=len(lt), sd=0.0, smiles=g.smiles_std.iloc[0], full_key=g.full_key.iloc[0], year=g.document_year.iloc[0], remapped=bool(g.remapped.any())))
    return None  # contradictory censoring, drop
A = f4.groupby(["document_chembl_id", "cmpd_key", "target", "assay_class"]).apply(agg, include_groups=False).dropna(subset=["pact"]).reset_index()
funnel["F6_aggregated_doc_cmpd_target_class_rows"] = stat(A.rename(columns={"document_chembl_id": "document_chembl_id"}))
# one row per (doc,cmpd,target): prefer eq over censored, then class priority
prio = {"solid_phase": 0, "homogeneous": 1, "spr": 2, "other_binding": 3, "cell": 4}
A["cp"] = A.assay_class.map(prio); A["ce"] = (A.censor != "eq").astype(int)
L = A.sort_values(["ce", "cp"]).drop_duplicates(["document_chembl_id", "cmpd_key", "target"]).copy()
L["doc"] = L.document_chembl_id
dy = lambda k: docs.get(k, {}).get("year"); L["doc_year"] = L.doc.map(dy); L["doc_doi"] = L.doc.map(lambda k: docs.get(k, {}).get("doi"))
L.drop(columns=["document_chembl_id", "cp", "ce"]).to_csv("data/long_all.csv.gz", index=False)
U = L[L.censor == "eq"]; funnel["F7_long_unique_doc_cmpd_target_uncensored"] = stat(U.assign(document_chembl_id=U.doc))
funnel["F7_long_unique_doc_cmpd_target_incl_censored"] = stat(L.assign(document_chembl_id=L.doc))
# paired: compound with >=2 targets within the same document (uncensored both), same assay class
Ae = A[A.censor == "eq"]; rows = []
for (doc, ck), g in Ae.groupby(["document_chembl_id", "cmpd_key"]):
    if g.target.nunique() < 2: continue
    for ta, tb in itertools.combinations(sorted(g.target.unique()), 2):
        ga, gb = g[g.target == ta], g[g.target == tb]
        shared = sorted(set(ga.assay_class) & set(gb.assay_class), key=lambda c: prio[c])
        if shared: c = shared[0]; ra, rb = ga[ga.assay_class == c].iloc[0], gb[gb.assay_class == c].iloc[0]; same = True
        else: ra, rb = ga.sort_values("cp" if "cp" in ga else "assay_class").iloc[0], gb.iloc[0]; same = False
        rows.append(dict(doc=doc, cmpd_key=ck, tA=ta, tB=tb, pA=ra.pact, pB=rb.pact, delta=ra.pact - rb.pact, same_class=same, class_A=ra.assay_class, class_B=rb.assay_class, smiles=ra.smiles))
P = pd.DataFrame(rows)
P.to_csv("data/pairs_all.csv.gz", index=False)
Pp = P[P.same_class]
funnel["F8_pairs_within_doc_uncensored_any_class"] = dict(n_pairs=len(P), n_cmpd=int(P.cmpd_key.nunique()), n_doc=int(P.doc.nunique()))
funnel["F8_pairs_within_doc_uncensored_same_class_PRIMARY"] = dict(n_pairs=len(Pp), n_cmpd=int(Pp.cmpd_key.nunique()), n_doc=int(Pp.doc.nunique()))
funnel["F8_pairs_per_target_pair_PRIMARY"] = {f"{a}-{b}": dict(n_pairs=int(len(g)), n_doc=int(g.doc.nunique()), n_cmpd=int(g.cmpd_key.nunique())) for (a, b), g in Pp.groupby(["tA", "tB"]) }
# paired long table: only (doc,cmpd,target) triples that participate in >=1 primary pair
keys = set(zip(Pp.doc, Pp.cmpd_key, Pp.tA)) | set(zip(Pp.doc, Pp.cmpd_key, Pp.tB))
Lp = U[[ (r.doc, r.cmpd_key, r.target) in keys for r in U.itertuples()]]
funnel["F9_long_rows_in_primary_paired_set"] = stat(Lp.assign(document_chembl_id=Lp.doc))
funnel["docs_with_avb6_data_uncensored_long"] = int(U[U.target == "avb6"].doc.nunique())
funnel["docs_with_avb6_in_primary_pairs"] = int(pd.concat([Pp[Pp.tA == "avb6"].doc, Pp[Pp.tB == "avb6"].doc]).nunique())
json.dump(funnel, open("data/funnel.json", "w"), indent=1)
print(json.dumps(funnel, indent=0)[:6000])
