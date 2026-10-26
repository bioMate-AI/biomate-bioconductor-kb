"""Per-document diagnostics under S2 + document counts per integrin. Writes perdoc_S2.csv and doc_counts.json."""
import json, numpy as np, pandas as pd
from metrics import rmse
R = json.load(open("results.json")); docs = json.load(open("data/documents.json"))
b1 = R["claims"]["T1"]["best_model_selected_on_S2"]; b2 = R["claims"]["T2"]["best_model_selected_on_S2"]
t1 = pd.read_csv("data/preds/S2_t1.csv.gz"); t2 = pd.read_csv("data/preds/S2_t2.csv.gz"); n1 = R["S2"]["T1"]["strongest_null"]; n2 = R["S2"]["T2"]["strongest_null"]
rows = []
for d in sorted(t2.doc.unique()):
    a = t1[t1.doc == d]; b = t2[t2.doc == d]; rows.append(dict(doc=d, year=docs.get(d, {}).get("year"), title=(docs.get(d, {}).get("title") or "")[:70], n_cmpd=a.ck.nunique(), targets=";".join(sorted(set(a.t))),
        n_rows=len(a), T1_model=rmse(a[b1], a.y), T1_null=rmse(a[n1], a.y), n_pairs=len(b), T2_model=rmse(b[b2], b.delta), T2_null=rmse(b[n2], b.delta), T2_Z=rmse(b.Z, b.delta), T2_delta_sd=float(b.delta.std(ddof=0))))
P = pd.DataFrame(rows); P["T2_model_better"] = P.T2_model < P.T2_null; P.round(3).to_csv("perdoc_S2.csv", index=False)
print("T2 best model", b2, "vs null", n2, ": better in", int(P.T2_model_better.sum()), "of", len(P), "docs; T1", b1, "vs", n1, ": better in", int((P.T1_model < P.T1_null).sum()), "of", len(P))
U = pd.read_csv("data/long_all.csv.gz"); U = U[U.censor == "eq"]; Pp = pd.read_csv("data/pairs_all.csv.gz"); Pp = Pp[Pp.same_class]
cnt = {t: dict(docs_uncensored_long=int(g.doc.nunique()), compounds=int(g.cmpd_key.nunique())) for t, g in U.groupby("target")}
for t in cnt: cnt[t]["docs_in_primary_pairs"] = int(pd.concat([Pp[Pp.tA == t].doc, Pp[Pp.tB == t].doc]).nunique())
a6 = Pp[(Pp.tA == "avb6") | (Pp.tB == "avb6")]; cnt["avb6_pair_docs_by_partner"] = {p: int(a6[(a6.tA == p) | (a6.tB == p)].doc.nunique()) for p in ["avb3", "avb5", "avb8", "a5b1", "avb1", "aIIbb3"]}
top = U[U.target == "avb6"].groupby("doc").size().sort_values(ascending=False); cnt["avb6_rows_top_docs"] = {k: int(v) for k, v in top.head(5).items()}; cnt["avb6_rows_total"] = int(top.sum())
cnt["avb6_remapped_rows"] = int(U[(U.target == "avb6") & (U.remapped == True)].shape[0])
pairs_per = {f"{a}-{b}": dict(n_pairs=int(len(g)), n_docs=int(g.doc.nunique())) for (a, b), g in Pp.groupby(["tA", "tB"])}; cnt["pairs_per_target_pair"] = pairs_per
json.dump(cnt, open("doc_counts.json", "w"), indent=1); print(json.dumps({k: v for k, v in cnt.items() if k != "pairs_per_target_pair"}, indent=0))
