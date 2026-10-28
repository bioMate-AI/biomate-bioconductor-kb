"""REQUIRED validity gate for every benchmark analysis (PREREG A7).
A benchmark is used to judge arms only if NO-TARGET controls are compatible with chance on it.
Controls (all carry no target information; they are computed from the compound alone):
  PRIMARY  (95 % family-cluster bootstrap interval must contain 0.5):
     C1 atom-LM typicality (WS1 AtomLMScorer mean per-token log-likelihood),
     C2 multi-proxy classifier: logistic regression on ALL proxies below (+ typicality), trained on the benchmark's own labels with
        leave-fold-out CV over data/folds_v1.csv (a model that can separate positives from decoys using compound-only information => benchmark invalid)
  SECONDARY (Bonferroni-adjusted interval, level 1 - 0.05/n_secondary, must contain 0.5):
     size (heavy atoms), net charge, N fraction, O fraction, S/halogen presence, ncAA fraction, aromatic rings, TPSA, logP, HBD, HBA, rotatable bonds, Fsp3,
     ring size, number of rings, corpus membership (exact SMILES in the atom-LM pretraining corpus), CycPeptMPDB membership.
AUC of a feature and of its negation are mirror images, so 'interval contains 0.5' is direction-free.
Aggregation = per-target AUC -> family mean -> bootstrap over families (B = 10,000). Items whose compound lacks a proxy value are dropped for that control (reported)."""
import os, sys
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; sys.path.insert(0, HERE)
import harness as H

SECONDARY = ["heavy", "charge", "n_frac", "o_frac", "has_s", "has_halogen", "ncaa_frac", "n_arom", "tpsa", "logp", "hbd", "hba", "rotb", "fsp3", "ring", "n_rings", "in_corpus", "in_cycpeptmpdb"]
MULTI = SECONDARY + ["typicality", "n_alpha"]


def load_proxies():
    return pd.read_csv(f"{DATA}/proxies.csv.gz").set_index("compound_id")


def _family_ci(per_target, tfam, level, B=10000, seed=5):
    d = per_target.merge(tfam[["target_key", "family"]], on="target_key"); d = d[d.auc.notna()]
    fm = d.groupby("family").auc.mean().values
    if len(fm) < 2: return dict(point=float(fm.mean()) if len(fm) else float("nan"), lo=float("nan"), hi=float("nan"), n_families=len(fm))
    rng = np.random.default_rng(seed); idx = rng.integers(0, len(fm), (B, len(fm))); m = fm[idx].mean(1); a = (1 - level) / 2 * 100
    return dict(point=float(fm.mean()), lo=float(np.percentile(m, a)), hi=float(np.percentile(m, 100 - a)), n_families=len(fm))


def control_auc(items, tfam, values: pd.Series, level):
    it = items.assign(score=items.compound_id.map(values)); n0 = len(it); it = it[it.score.notna()]
    rows = []
    for t, g in it.groupby("target_key", sort=True):
        rows.append(dict(target_key=t, auc=H.tie_aware_auc(g.label.values, g.score.values)))
    r = _family_ci(pd.DataFrame(rows), tfam, level); r["items_used_frac"] = round(len(it) / max(n0, 1), 3); return r


def multi_proxy_scores(items, tfam, prox, folds, flat=None, excl=None):
    """Leave-fold-out logistic regression on all proxies; returns a score per (target_key, compound_id) as a DataFrame."""
    from sklearn.linear_model import LogisticRegression
    from sklearn.preprocessing import StandardScaler
    X = prox[MULTI].astype(float); it = items.copy(); it["fold"] = it.target_key.map(tfam.set_index("target_key").family).map(folds)
    ok = X.notna().all(axis=1); it = it[it.compound_id.isin(ok[ok].index)]
    out = []
    for f in sorted(it.fold.unique()):
        tr = it[it.fold != f]; te = it[it.fold == f]
        if excl is not None: tr = tr[~tr.compound_id.map(flat).isin(excl[f])]               # A10 V-T: training rows must not share a structure with the held-out fold
        if tr.label.nunique() < 2 or len(tr) < 50: continue
        sc = StandardScaler().fit(X.loc[tr.compound_id].values)
        lr = LogisticRegression(C=0.1, max_iter=1000, class_weight="balanced").fit(sc.transform(X.loc[tr.compound_id].values), tr.label.values)
        out.append(te[["target_key", "compound_id"]].assign(score=lr.decision_function(sc.transform(X.loc[te.compound_id].values))))
    return pd.concat(out) if out else pd.DataFrame(columns=["target_key", "compound_id", "score"])


def fp_table(compound_ids):
    from rdkit import Chem, RDLogger
    from rdkit.Chem import AllChem
    RDLogger.DisableLog("rdApp.*")
    C = pd.read_csv(f"{DATA}/compounds.csv.gz").set_index("compound_id"); gen = AllChem.GetMorganGenerator(radius=2, fpSize=1024, includeChirality=False)
    return pd.DataFrame({c: gen.GetCountFingerprintAsNumPy(Chem.MolFromSmiles(C.loc[c, "iso_smiles"])).astype(np.float32) for c in sorted(set(compound_ids))}).T


def fp_scores(items, tfam, FP, folds, flat=None, excl=None):
    """C3: leave-fold-out logistic regression on Morgan count bits (chirality-free) -- NOT used for matching in M3, so it tests what matching did not balance."""
    from sklearn.linear_model import LogisticRegression
    it = items.copy(); it["fold"] = it.target_key.map(tfam.set_index("target_key").family).map(folds); out = []
    for f in sorted(it.fold.unique()):
        tr = it[it.fold != f]; te = it[it.fold == f]
        if excl is not None: tr = tr[~tr.compound_id.map(flat).isin(excl[f])]
        if tr.label.nunique() < 2 or len(tr) < 50: continue
        Xtr = np.log1p(FP.loc[tr.compound_id].values); Xte = np.log1p(FP.loc[te.compound_id].values)
        lr = LogisticRegression(C=0.05, max_iter=1000, class_weight="balanced").fit(Xtr, tr.label.values)
        out.append(te[["target_key", "compound_id"]].assign(score=lr.decision_function(Xte)))
    return pd.concat(out) if out else pd.DataFrame(columns=["target_key", "compound_id", "score"])


def run_gate(items, tfam, prox, folds, B=10000, FP=None, flat=None, excl=None):
    res = {"primary": {}, "secondary": {}}
    n_sec = len(SECONDARY); adj = 1 - 0.05 / n_sec
    res["primary"]["C1_atomlm_typicality"] = control_auc(items, tfam, prox["typicality"], 0.95)
    ms = multi_proxy_scores(items, tfam, prox, folds, flat=flat, excl=excl)
    if len(ms):
        rows = []                                                       # labels come from items for the same (target, compound)
        for t, g in ms.groupby("target_key"):
            m = items[items.target_key == t].merge(g, on=["target_key", "compound_id"]); rows.append(dict(target_key=t, auc=H.tie_aware_auc(m.label.values, m.score.values)))
        res["primary"]["C2_multiproxy_leave_fold_out"] = _family_ci(pd.DataFrame(rows), tfam, 0.95)
        res["primary"]["C2_multiproxy_leave_fold_out"]["folds_evaluated"] = sorted(int(x) for x in items.target_key.map(tfam.set_index("target_key").family).map(folds).unique())
    else:
        res["primary"]["C2_multiproxy_leave_fold_out"] = "not evaluable (too few training items)"
    if FP is None: FP = fp_table(items.compound_id)
    fs = fp_scores(items, tfam, FP, folds, flat=flat, excl=excl)
    if len(fs):
        rows = []
        for t, g in fs.groupby("target_key"):
            m = items[items.target_key == t].merge(g, on=["target_key", "compound_id"]); rows.append(dict(target_key=t, auc=H.tie_aware_auc(m.label.values, m.score.values)))
        res["primary"]["C3_morgan_fp_leave_fold_out"] = _family_ci(pd.DataFrame(rows), tfam, 0.95)
    else:
        res["primary"]["C3_morgan_fp_leave_fold_out"] = "not evaluable (too few training items)"
    for k in SECONDARY:
        res["secondary"][k] = control_auc(items, tfam, prox[k], adj)
    res["secondary_level"] = adj
    fails = [k for k, v in res["primary"].items() if isinstance(v, dict) and (v["lo"] > 0.5 or v["hi"] < 0.5)] + [f"secondary:{k}" for k, v in res["secondary"].items() if isinstance(v, dict) and v["lo"] == v["lo"] and (v["lo"] > 0.5 or v["hi"] < 0.5)]
    MIN_FAMILIES = 8
    for k, v in res["primary"].items():                       # a control that cannot be evaluated, or has an undefined / too-few-family interval, cannot certify validity
        if isinstance(v, str) or v["lo"] != v["lo"] or v["n_families"] < MIN_FAMILIES: fails.append(f"unverifiable:{k}")
    res["min_families_required"] = MIN_FAMILIES
    res["failed_controls"] = fails; res["VALID"] = len(fails) == 0
    res["note"] = "VALID means no control excludes chance; with few families the gate has low power -- see n_families and interval widths"
    return res
