"""Typicality-shortcut validity check for ANY score file (coordinator rule 2026-10-28; M2 showed a target-blind typicality score separating positives from decoys).
On the SAME items the score file covers, computes (a) the AUC of the atom-LM typicality score (results/scores_A2_atomlm.csv; no target information) with a family-cluster bootstrap CI,
(b) the pooled Spearman between the score file and typicality. FLAG = typicality AUC CI excludes 0.5 (items are shortcut-separable: results on them must not be interpreted as target recovery)
or |Spearman(score, typicality)| > 0.5 (the score file is mostly typicality).
usage: python3 typicality_check.py --scores FILE.csv --which I|M2|M3 [--out OUT.json]   (run from v4_eval/; read-only use of retro_recovery harness)"""
import argparse, json, os, sys
import numpy as np, pandas as pd
from scipy.stats import spearmanr
HERE = os.path.dirname(os.path.abspath(__file__)); W3 = f"{HERE}/../../multitarget/integrin_chembl/retro_recovery"; sys.path.insert(0, W3)
import harness as H


def check(scores_csv, which, typ_csv=f"{HERE}/results/scores_A2_atomlm.csv", out=None):
    sc = pd.read_csv(scores_csv); typ = pd.read_csv(typ_csv)
    items, tfam = H.load(which); keycols = ["target_key", "compound_id"] if "target_key" in sc.columns else ["compound_id"]
    scored = items.merge(sc[keycols + ["score"]].drop_duplicates(keycols), on=keycols, how="inner")
    scored = scored.merge(typ.rename(columns={"score": "typ"}), on="compound_id", how="inner")
    ok = scored.groupby("target_key").label.nunique(); scored = scored[scored.target_key.isin(ok[ok == 2].index)]
    res = {"which": which, "scores_file": os.path.basename(scores_csv), "n_items": int(len(scored)), "n_targets": int(scored.target_key.nunique())}
    if scored.empty: res["flag"] = "NO_EVALUABLE_ITEMS"; return res
    tf = dict(zip(tfam.target_key, tfam.family))
    pt, _ = H.per_target(scored[["target_key", "compound_id", "label"]], scored[["target_key", "compound_id", "typ"]].rename(columns={"typ": "score"}))
    # per-target AUC of typicality -> family means -> bootstrap CI
    pt["family"] = pt.target_key.map(tf); fmean = pt.groupby("family").auc.mean(); b = H.boot_mean(fmean)
    res["typicality_auc"] = {k: round(v, 4) if isinstance(v, float) else v for k, v in b.items()}
    rho = float(spearmanr(scored.score, scored.typ)[0]) if scored.score.nunique() > 1 else 0.0
    res["spearman_score_vs_typicality"] = round(rho, 4)
    shortcut = (b["lo"] > 0.5) or (b["hi"] < 0.5)
    res["flag"] = "TYPICALITY_SHORTCUT" if (shortcut or abs(rho) > 0.5) else "ok"
    res["flag_reasons"] = [r for r, c in (("typicality_auc_ci_excludes_0.5", shortcut), ("score_mostly_typicality(|rho|>0.5)", abs(rho) > 0.5)) if c]
    if out: json.dump(res, open(out, "w"), indent=1)
    return res


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--scores", required=True); ap.add_argument("--which", required=True); ap.add_argument("--out"); a = ap.parse_args()
    print(json.dumps(check(a.scores, a.which, out=a.out), indent=1))
