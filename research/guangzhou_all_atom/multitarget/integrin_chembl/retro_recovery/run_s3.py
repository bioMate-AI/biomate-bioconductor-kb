"""S3 plug-in: evaluate a score file from workstream 1 (v4 / atom-LM) or from the workstream-2 loop replay (any round).
  python run_s3.py --name v4_fold_all --scores scores.csv [--round 3]
scores.csv columns: compound_id, score  (or target_key, compound_id, score).  Evaluated on analyses I and M2 (primary: I), each on
  (a) all items, (b) the contamination-controlled subset = items whose compound is NOT in the atom-LM pretraining corpus and not in CycPeptMPDB
      (data/contamination_flags.csv.gz; applied to positives and decoys alike), reported side by side.
Baselines are the frozen baseline score files (data/baseline_scores_{I,M2}.csv.gz). Partial folds are allowed: only items with a score are evaluated
and `coverage`/`folds_scored` are reported. Output results/s3_<name>[_round<k>].json."""
import argparse, json, os, sys
import pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; RES = f"{HERE}/results"; sys.path.insert(0, HERE)
import harness as H
ap = argparse.ArgumentParser(); ap.add_argument("--name", required=True); ap.add_argument("--scores", required=True); ap.add_argument("--round", type=int, default=None); ap.add_argument("--k", type=int, default=None, help="H4b: number of revealed labelled compounds of the target (score file must cover the REMAINING items; optional column `seed`)"); a = ap.parse_args()
if a.k is not None:
    import h4b_eval; h4b_eval.main(a); sys.exit(0)
sc = pd.read_csv(a.scores); out = dict(name=a.name, round=a.round, scores_file=os.path.basename(a.scores)); cf = pd.read_csv(f"{DATA}/contamination_flags.csv.gz").set_index("compound_id")
fold = pd.read_csv(f"{DATA}/folds_v1.csv").set_index("family").fold; T = pd.read_csv(f"{DATA}/targets.csv"); tf = dict(zip(T.target_key, T.family))
for which in ("I", "M2"):
    items, tfam = H.load(which); bl = pd.read_csv(f"{DATA}/baseline_scores_{which}.csv.gz"); names = sorted(bl.arm.unique())
    keycols = ["target_key", "compound_id"] if "target_key" in sc.columns else ["compound_id"]
    scored = items.merge(sc[keycols + ["score"]].drop_duplicates(keycols), on=keycols, how="inner")
    folds = sorted(set(scored.target_key.map(tf).map(fold)))
    res = {"folds_scored": [int(f) for f in folds], "items_scored_frac": round(len(scored) / len(items), 4)}
    for tag, mask in (("all_items", lambda d: d.compound_id.notna()), ("contamination_controlled", lambda d: ~d.compound_id.map(cf.in_atomlm_pretrain_corpus).fillna(False) & ~d.compound_id.map(cf.in_cycpeptmpdb).fillna(False))):
        it = scored[mask(scored)]
        # keep only targets that still have both classes
        ok = it.groupby("target_key").label.nunique(); it = it[it.target_key.isin(ok[ok == 2].index)]
        if it.empty: res[tag] = "no evaluable targets"; continue
        arms = {a.name: sc.rename(columns={}) [keycols + ["score"]]}
        for n, g in bl.groupby("arm"): arms[n] = g[["target_key", "compound_id", "score"]]
        r = H.evaluate(it[["target_key", "compound_id", "label"]], tfam, arms, names)
        res[tag] = dict(n_targets=r["arms"][a.name]["n_targets"], n_families=r["arms"][a.name]["auc"]["n_families"], auc=r["arms"][a.name]["auc"], ef5=r["arms"][a.name]["ef5"], strongest_baseline_auc=r["strongest_baseline_auc"],
                        vs_strongest_auc=r["vs_strongest_auc"][a.name], vs_strongest_ef5=r["vs_strongest_ef5"][a.name])
    out[which] = res
fn = f"{RES}/s3_{a.name}{'_round'+str(a.round) if a.round is not None else ''}.json"; json.dump(out, open(fn, "w"), indent=1); print(json.dumps(out, indent=1)[:3000]); print("wrote", fn)
