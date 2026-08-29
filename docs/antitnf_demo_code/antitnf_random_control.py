#!/usr/bin/env python3
"""
131-random-gene NEGATIVE CONTROL for the anti-TNF (infliximab) mechanism claim.

The headline M7 result is the leakage-free transfer train(GSE16879) -> test(GSE12251,
independent ACT1 cohort): the 131-gene TNF/NF-kB MECHANISM arm reaches AUROC 0.833,
edging out the full-transcriptome arm (0.780) at 15x fewer features.

The obvious reviewer objection: is 0.833 because these are the *right* (mechanism) genes,
or would ANY 131 genes do as well (a pure dimensionality effect)? This script answers it
with a same-dimension competitive null:

  For b = 1..B: draw 131 genes at random from the common gene pool, run the IDENTICAL
  pipeline (make_model("mechanism") == StandardScaler -> SelectKBest(k=20, f_classif)
  -> L2 logistic), fit on GSE16879 UC-pre, predict on GSE12251, record AUROC.

Reported: the mechanism point (0.833) vs the null (mean / 2.5 / 50 / 95 / 97.5 pct),
the one-sided empirical p = P(null AUROC >= mechanism), and a z-score. Everything else
(data, labels, cohorts, model, imputation) is imported verbatim from antitnf_pipeline so
the ONLY thing that changes between arm and control is which genes are used.

Draw pool = ALL common genes (competitive GSEA-style null, incl. the mechanism genes:
131 of ~12k, contamination negligible; the conservative choice). Seed fixed for repro.
"""
import os, sys, json, time
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import antitnf_pipeline as P
from sklearn.metrics import roc_auc_score

OUT = os.environ.get("ANTITNF_OUT", "/tmp/antitnf_out")
os.makedirs(OUT, exist_ok=True)
B = int(os.environ.get("CONTROL_B", "1000"))
SEED = int(os.environ.get("CONTROL_SEED", "42"))
TRAIN_GSE, TEST_GSE = "GSE16879", "GSE12251"


def log(*a):
    print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)


def build_cohorts():
    """Reproduce main()'s data build for the two transfer datasets (UC-pre, known response)."""
    annot_path = P.download(P.GPL570_ANNOT, os.path.join(OUT, "GPL570.annot.gz"))
    probe2gene = P.load_gpl570_map(annot_path)
    log("GPL570 probes mapped:", len(probe2gene))

    datasets = {}
    for gse in [TRAIN_GSE, TEST_GSE]:
        expr, labels = P.build_matrix(gse, OUT)
        gexpr = P.probes_to_genes(expr, probe2gene)
        datasets[gse] = (gexpr, labels)
        log(gse, "genes x samples:", gexpr.shape)

    def cohort(gse):
        gexpr, labels = datasets[gse]
        sel = labels[(labels.timepoint == "pre") & (labels.response.notna())]
        sel = sel[sel.disease.isin(("UC",))]
        gsms = [g for g in sel.index if g in gexpr.columns]
        y = sel.loc[gsms, "response"].astype(int).values
        Xg = gexpr[gsms].T  # samples x genes
        return Xg, y

    return cohort(TRAIN_GSE), cohort(TEST_GSE)


def fit_predict_auroc(Xtr, ytr, Xte, yte, cols):
    """The EXACT mechanism-arm transfer, restricted to `cols` (imputed with TRAIN means)."""
    Xtr2 = Xtr[cols].fillna(Xtr[cols].mean()).values
    Xte2 = Xte[cols].fillna(Xtr[cols].mean()).values  # impute test with TRAIN means (as in pipeline)
    m = P.make_model("mechanism", len(cols))
    m.fit(Xtr2, ytr)
    p = m.predict_proba(Xte2)[:, 1]
    return roc_auc_score(yte, p)


def main():
    (Xtr, ytr), (Xte, yte) = build_cohorts()
    common = [g for g in Xtr.columns if g in set(Xte.columns)]
    mech_common = [g for g in common if g in set(P.MECHANISM_GENES)]
    M = len(mech_common)
    log(f"common genes: {len(common)}  |  mechanism-common (arm size): {M}")
    log(f"train n={len(ytr)} (resp {int(ytr.sum())}/{len(ytr)})  test n={len(yte)} (resp {int(yte.sum())}/{len(yte)})")

    # the real mechanism arm (should reproduce 0.833)
    mech_auroc = fit_predict_auroc(Xtr, ytr, Xte, yte, mech_common)
    log(f"MECHANISM arm AUROC (reproduced): {mech_auroc:.3f}")

    # same-dimension random-gene null
    rng = np.random.default_rng(SEED)
    common_arr = np.array(common)
    null = np.empty(B)
    for b in range(B):
        cols = list(rng.choice(common_arr, size=M, replace=False))
        try:
            null[b] = fit_predict_auroc(Xtr, ytr, Xte, yte, cols)
        except Exception:
            null[b] = np.nan
        if (b + 1) % 100 == 0:
            log(f"  null draw {b+1}/{B}  running mean={np.nanmean(null[:b+1]):.3f}")

    null = null[~np.isnan(null)]
    p_emp = float((np.sum(null >= mech_auroc) + 1) / (len(null) + 1))  # +1 smoothing (Phipson-Smyth)
    z = float((mech_auroc - np.mean(null)) / np.std(null)) if np.std(null) > 0 else float("nan")
    pct = {q: float(np.percentile(null, q)) for q in (2.5, 5, 50, 90, 95, 97.5)}

    result = {
        "transfer": f"train {TRAIN_GSE} -> test {TEST_GSE} (independent ACT1)",
        "arm_size_genes": M,
        "n_common_genes": len(common),
        "n_random_draws": len(null),
        "seed": SEED,
        "draw_pool": "all common genes (competitive null, incl. mechanism genes)",
        "mechanism_auroc": float(mech_auroc),
        "mechanism_auroc_reported": 0.833,
        "null_mean": float(np.mean(null)),
        "null_std": float(np.std(null)),
        "null_percentiles": pct,
        "empirical_p_onesided": p_emp,   # P(random 131-gene AUROC >= mechanism)
        "z_score": z,
        "null_auroc_values": [round(float(x), 4) for x in null],  # for the figure
        "interpretation": (
            f"Mechanism AUROC {mech_auroc:.3f} vs same-dimension random-{M}-gene null "
            f"(mean {np.mean(null):.3f}, 95th pct {pct[95]:.3f}); one-sided empirical "
            f"p={p_emp:.3f}. Mechanism {'EXCEEDS' if mech_auroc > pct[95] else 'is WITHIN'} "
            f"the 95th percentile of the random null."
        ),
    }
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "random_control_result.json")
    with open(out, "w") as f:
        json.dump(result, f, indent=2)
    log("WROTE", out)
    print("=== CONTROL_JSON_BEGIN ===")
    print(json.dumps({k: v for k, v in result.items() if k != "null_auroc_values"}, indent=2))
    print("=== CONTROL_JSON_END ===")


if __name__ == "__main__":
    main()
