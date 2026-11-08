#!/usr/bin/env python3
"""Direction check of literature rules against our own labels, restricted to source group A (train group). RUNS ON EC2.

usage: direction_check.py KB.json ANNOTATIONS.csv.gz GROUPS.json OUTDIR

Reads group A membership from GROUPS.json ('summary'['0']['sources']); rows from every other source are dropped while reading, so
group S and B labels are never loaded into the analysis. Label = raw PAMPA value; the statistic is the WITHIN-SOURCE Spearman rho
(rank-based, hence identical to using the within-source z-scored label). Bootstrap = cluster bootstrap over flat-structure groups
(stereoisomer sets) inside each source, B = 300, seeded. Descriptive only: no multiplicity correction, no claim of significance.
Classes per feature and source: agree / weak_agree (right sign, CI includes 0) / weak_disagree / disagree (wrong sign, CI excludes 0).
"""
import hashlib, json, os, sys
import numpy as np
import pandas as pd
from scipy.stats import spearmanr

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from knowledge_loader import KnowledgePotential, load_kb  # noqa

FEATMAP = {"tpsa": "tpsa", "hbd": "hbd", "hba": "hba", "mw": "mw", "clogp": "logp", "alogp": "logp", "nrotb": "rotb",
           "n_heavy_atoms": "heavy", "n_nme": "n_nme_final", "n_dres": "n_D"}
B = 300


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def load_group_a(groups_path, ann_path):
    g = json.load(open(groups_path))
    srcs = list(g["summary"]["0"]["sources"])
    need = ["Source", "pampa", "flat_smiles"] + sorted(set(FEATMAP.values()))
    parts = []
    for ch in pd.read_csv(ann_path, index_col=0, usecols=lambda c: c in need or c == "Structurally_Unique_ID", chunksize=4000):
        ch = ch[ch["Source"].isin(srcs) & ch["pampa"].notna()]
        if len(ch):
            parts.append(ch)
    df = pd.concat(parts)
    assert set(df["Source"].unique()) <= set(srcs), "non-group-A source leaked into the analysis"
    return df, srcs, g


def rho_ci(x, y, cl, rng):
    ok = np.isfinite(x) & np.isfinite(y)
    x, y, cl = x[ok], y[ok], cl[ok]
    if len(x) < 30 or np.std(x) == 0:
        return None
    r = spearmanr(x, y)[0]
    uniq, inv = np.unique(cl, return_inverse=True)
    members = [np.where(inv == k)[0] for k in range(len(uniq))]
    bs = []
    for _ in range(B):
        pick = rng.integers(0, len(members), len(members))
        idx = np.concatenate([members[k] for k in pick])
        if np.std(x[idx]) == 0:
            continue
        bs.append(spearmanr(x[idx], y[idx])[0])
    lo, hi = np.percentile(bs, [2.5, 97.5]) if bs else (np.nan, np.nan)
    return dict(n=int(len(x)), n_clusters=int(len(uniq)), rho=float(r), lo=float(lo), hi=float(hi))


def classify(rho, lo, hi, sign):
    s = rho * sign
    excl = (lo > 0) or (hi < 0)
    if s > 0:
        return "agree" if excl else "weak_agree"
    return "disagree" if excl else "weak_disagree"


def main():
    kb_path, ann_path, groups_path, out = sys.argv[1:5]
    os.makedirs(out, exist_ok=True)
    doc = load_kb(kb_path)
    df, srcs, g = load_group_a(groups_path, ann_path)
    rng = np.random.default_rng(0)
    res = {"meta": {"groups_file": os.path.basename(groups_path), "groups_sha256": sha(groups_path), "groups_version": g.get("version"),
                    "group_A_sources": srcs, "annotation_sha256": sha(ann_path), "kb_sha256": sha(kb_path),
                    "n_by_source": {s: int((df["Source"] == s).sum()) for s in srcs}, "bootstrap": f"cluster bootstrap over flat_smiles, B={B}, seed 0",
                    "label": "raw PAMPA; within-source Spearman (rank-based, equals z-scored)"}, "rules": {}}
    kp = KnowledgePotential(doc, lam=1.0, stats={})
    for e in doc["rules"]:
        out_r = {"id": e["id"], "kind": e["kind"], "direction": e["direction"], "outcome_class": e.get("outcome_class"), "per_feature": {}, "per_source": {}}
        tested = False
        if e.get("outcome_class") != "permeability":
            out_r["rule_status"] = "not_testable"; out_r["reason"] = "rule outcome is not permeability: the PAMPA label cannot test it"
            out_r["n_agree_cells"] = 0; out_r["n_cells"] = 0
            res["rules"][e["id"]] = out_r
            continue
        # directional features
        if e["direction"] in ("+", "-", "multi") and e.get("feat_mapped"):
            for f, sgn in e["feat_mapped"].items():
                col = FEATMAP.get(f)
                if col is None or sgn == 0:
                    out_r["per_feature"][f] = {"status": "not_testable", "reason": "no 2D column or non-directional" if col is None else "sign 0"}
                    continue
                per = {}
                for s in srcs:
                    d = df[df["Source"] == s]
                    r = rho_ci(d[col].astype(float).values, d["pampa"].astype(float).values, d["flat_smiles"].astype(str).values, rng)
                    if r:
                        r["class"] = classify(r["rho"], r["lo"], r["hi"], sgn)
                        r["expected_sign"] = int(sgn)
                    per[s] = r
                out_r["per_feature"][f] = {"status": "tested", "proxy": f in e.get("feat_proxy", []), "per_source": per}
                tested = True
        # window rules: inside-vs-outside contrast of the literature window
        if e["direction"] == "window" and e.get("window"):
            per = {}
            for s in srcs:
                d = df[df["Source"] == s]
                inside = []
                for _, row in d.iterrows():
                    feats = {"mw": row["mw"], "hbd": row["hbd"], "hba": row["hba"], "clogp": row["logp"], "tpsa": row["tpsa"]}
                    inside.append(kp._window_penalty(feats, e["window"]) == 0)
                inside = np.array(inside)
                y = d["pampa"].astype(float).values
                cl = d["flat_smiles"].astype(str).values
                if inside.sum() < 30 or (~inside).sum() < 30:
                    per[s] = {"status": "not_testable", "n_inside": int(inside.sum()), "n_outside": int((~inside).sum())}
                    continue
                uniq, inv = np.unique(cl, return_inverse=True)
                members = [np.where(inv == k)[0] for k in range(len(uniq))]
                diff = float(np.median(y[inside]) - np.median(y[~inside]))
                bs = []
                for _ in range(B):
                    idx = np.concatenate([members[k] for k in rng.integers(0, len(members), len(members))])
                    ii = inside[idx]
                    if ii.sum() < 10 or (~ii).sum() < 10:
                        continue
                    bs.append(np.median(y[idx][ii]) - np.median(y[idx][~ii]))
                lo, hi = np.percentile(bs, [2.5, 97.5]) if bs else (np.nan, np.nan)
                per[s] = {"status": "tested", "n_inside": int(inside.sum()), "n_outside": int((~inside).sum()), "median_diff_inside_minus_outside": diff,
                          "lo": float(lo), "hi": float(hi), "class": classify(diff, lo, hi, +1), "expected": "inside window = higher permeability"}
                tested = True
            out_r["window_contrast"] = per
        # inverted-U (peak) lipophilicity rules
        if e["direction"] == "window" and not e.get("window") and "alogp" in (e.get("feat") or {}):
            per = {}
            for s in srcs:
                d = df[df["Source"] == s]
                x = d["logp"].astype(float).values
                y = d["pampa"].astype(float).values
                cl = d["flat_smiles"].astype(str).values
                ok = np.isfinite(x) & np.isfinite(y)
                x, y, cl = x[ok], y[ok], cl[ok]
                z = (x - x.mean()) / (x.std() or 1.0)
                def quad(idx):
                    A = np.c_[np.ones(len(idx)), z[idx], z[idx] ** 2]
                    return np.linalg.lstsq(A, y[idx], rcond=None)[0][2]
                uniq, inv = np.unique(cl, return_inverse=True)
                members = [np.where(inv == k)[0] for k in range(len(uniq))]
                c = float(quad(np.arange(len(z))))
                bs = [quad(np.concatenate([members[k] for k in rng.integers(0, len(members), len(members))])) for _ in range(B)]
                lo, hi = np.percentile(bs, [2.5, 97.5])
                per[s] = {"status": "tested", "n": int(len(z)), "quad_coef": c, "lo": float(lo), "hi": float(hi),
                          "class": classify(-c, -hi, -lo, +1), "expected": "negative quadratic (peak)"}
                tested = True
            out_r["peak_test"] = per
        # rule-level status
        classes = []
        for fv in out_r["per_feature"].values():
            if fv.get("status") == "tested":
                classes += [v["class"] for v in fv["per_source"].values() if v]
        for key in ("window_contrast", "peak_test"):
            for v in out_r.get(key, {}).values():
                if v.get("status") == "tested":
                    classes.append(v["class"])
        if not tested or not classes:
            out_r["rule_status"] = "not_testable"
        elif all(c in ("agree", "weak_agree") for c in classes) and any(c == "agree" for c in classes):
            out_r["rule_status"] = "agree"
        elif any(c == "disagree" for c in classes) and not any(c == "agree" for c in classes):
            out_r["rule_status"] = "disagree"
        elif all(c in ("agree", "weak_agree") for c in classes):
            out_r["rule_status"] = "weak_agree"
        else:
            out_r["rule_status"] = "mixed"
        out_r["n_agree_cells"] = sum(1 for c in classes if c in ("agree", "weak_agree"))
        out_r["n_cells"] = len(classes)
        res["rules"][e["id"]] = out_r
    summary = {}
    for r in res["rules"].values():
        summary[r["rule_status"]] = summary.get(r["rule_status"], 0) + 1
    res["summary"] = summary
    json.dump(res, open(os.path.join(out, "direction_check_results.json"), "w"), indent=1)
    rows = [(i, r["kind"], r["rule_status"], r["n_agree_cells"], r["n_cells"]) for i, r in res["rules"].items()]
    pd.DataFrame(rows, columns=["id", "kind", "status", "agree_cells", "cells"]).to_csv(os.path.join(out, "direction_check_summary.csv"), index=False)
    print(json.dumps({"summary": summary, "n_by_source": res["meta"]["n_by_source"]}, indent=1))


if __name__ == "__main__":
    main()
