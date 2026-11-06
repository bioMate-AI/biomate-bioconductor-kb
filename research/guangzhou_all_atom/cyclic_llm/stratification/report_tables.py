"""Generate markdown tables for the Part B results section from data/*.csv|json. usage: python3 report_tables.py > data/report_tables.md"""
import os, json
import numpy as np, pandas as pd
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
def f3(x): return "–" if x is None or (isinstance(x, float) and np.isnan(x)) else f"{x:.2f}"
def ci(r, k="spearman"): return f"{r[k]:.2f} [{r['lo']:.2f}, {r['hi']:.2f}]"
out = []
# strata
s = pd.read_csv(os.path.join(D, "strata_perf.csv"))
for sc, title in (("grp_flat", "Grouped CV by flat structure (no stereoisomer sibling in training)"), ("grp_source", "Leave-labs-out (GroupKFold by source)")):
    out.append(f"\n**{title}** — Spearman [95 % cluster-bootstrap CI] per stratum; n = peptides, g = flat-structure groups. † n<30.\n")
    out.append("| stratifier | level | n | g | fp blind | fp chiral | descriptor | N-Me rule |\n|---|---|---|---|---|---|---|---|")
    sub = s[s.scheme == sc]
    for (st, lv), g in sub.groupby(["stratifier", "level"], sort=False):
        row = {m: g[g.model == m].iloc[0] if (g.model == m).any() else None for m in ("fp_blind", "fp_chiral", "desc", "nme_rule")}
        base = g.iloc[0]
        cells = [ci(row[m]) if row[m] is not None else "–" for m in ("fp_blind", "fp_chiral", "desc", "nme_rule")]
        out.append(f"| {st} | {lv} | {int(base.n)}{'†' if base.small else ''} | {int(base.n_groups)} | " + " | ".join(cells) + " |")
# lso
p = os.path.join(D, "lso_perf.csv")
if os.path.exists(p):
    l = pd.read_csv(p); out.append("\n**Leave-stratum-out** (train on all peptides outside the stratum, excluding flat groups that intersect it) — Spearman on the held-out stratum.\n")
    out.append("| stratifier | level | n test | n train | fp blind | fp chiral | descriptor |\n|---|---|---|---|---|---|---|")
    for (st, lv), g in l.groupby(["stratifier", "level"], sort=False):
        v = {m: g[g.model == m].spearman_lso.iloc[0] if (g.model == m).any() else np.nan for m in ("fp_blind", "fp_chiral", "desc")}
        out.append(f"| {st} | {lv} | {int(g.n_test.iloc[0])} | {int(g.n_train.iloc[0])} | {f3(v['fp_blind'])} | {f3(v['fp_chiral'])} | {f3(v['desc'])} |")
# mmp
e = pd.read_csv(os.path.join(D, "mmp_effects_pampa.csv")); e = e[e.n_pairs >= 30]
out.append("\n**Matched pairs (PAMPA, within source)** — directed rows: mean Δ log Papp (random-effects pooled [95 % CI]; pair-mean [cluster-bootstrap CI]); undirected rows: mean |Δ|. I² = between-source heterogeneity.\n")
out.append("| transformation | n pairs | sources | statistic | pooled [CI] | I² | pair mean [boot CI] | SD | share \\|Δ\\|>1 |\n|---|---|---|---|---|---|---|---|---|")
for _, r in e.iterrows():
    out.append(f"| {r.transformation} | {r.n_pairs} | {r.n_sources} | {r.statistic} | {r.pooled:.2f} [{r.meta_lo:.2f}, {r.meta_hi:.2f}] | {r.I2:.2f} | {r.pair_mean:.2f} [{r.boot_lo:.2f}, {r.boot_hi:.2f}] | {r.sd_delta:.2f} | {r.frac_abs_gt_1:.2f} |" if not np.isnan(r.pooled) else f"| {r.transformation} | {r.n_pairs} | {r.n_sources} | {r.statistic} | – | – | {r.pair_mean:.2f} [{r.boot_lo:.2f}, {r.boot_hi:.2f}] | {r.sd_delta:.2f} | {r.frac_abs_gt_1:.2f} |")
# cliffs
c = pd.read_csv(os.path.join(D, "cliffs_by_transformation.csv"))
out.append("\n**Cliffs (|Δz|>1 SD within source) and pair-ordering accuracy** (same-fold pairs = neither partner label in training; ties 0.5).\n")
out.append("| transformation | pairs | cliff rate [CI] | same-fold pairs | acc blind | acc chiral | acc descriptor |\n|---|---|---|---|---|---|---|")
for _, r in c.iterrows():
    out.append(f"| {r.transformation} | {r.n_pairs} | {r.cliff_rate:.2f} [{r.cliff_lo:.2f}, {r.cliff_hi:.2f}] | {r.n_same_fold} | {f3(r.acc_fp_blind_same_fold)} | {f3(r.acc_fp_chiral_same_fold)} | {f3(r.acc_desc_same_fold)} |")
# families
fm = pd.read_csv(os.path.join(D, "feat_family_models.csv"))
out.append("\n**Feature-family models** (descriptor GBM, grouped CV by flat structure).\n\n| model | features | Spearman [CI] |\n|---|---|---|")
for _, r in fm.iterrows(): out.append(f"| {r.model} | {r.n_features} | {r.spearman:.2f} [{r.lo:.2f}, {r.hi:.2f}] |")
p = os.path.join(D, "feat_perm_importance.csv")
if os.path.exists(p):
    pi = pd.read_csv(p); a = pi[pi.stratum == "ALL"]
    out.append("\n**Permutation importance by family** (drop in held-out Spearman; 30 permutations).\n\n| family | mean drop [2.5, 97.5 %] |\n|---|---|")
    for _, r in a.iterrows(): out.append(f"| {r.family} | {r.mean_drop:.3f} [{r.lo:.3f}, {r.hi:.3f}] |")
p = os.path.join(D, "feat_interaction_grid.csv")
if os.path.exists(p):
    gd = pd.read_csv(p); out.append("\n**N-methyl × D-residue grid** — mean within-source z [CI] (n).\n\n| N-Me \\ D | " + " | ".join(gd.n_D.unique()) + " |\n|---|" + "---|" * gd.n_D.nunique())
    for a_ in gd.n_methyl.unique():
        cells = []
        for b_ in gd.n_D.unique():
            r = gd[(gd.n_methyl == a_) & (gd.n_D == b_)]
            cells.append("–" if r.empty else f"{r.mean_z.iloc[0]:.2f} [{r.lo.iloc[0]:.2f}, {r.hi.iloc[0]:.2f}] ({int(r.n.iloc[0])})" if not np.isnan(r.lo.iloc[0]) else f"{r.mean_z.iloc[0]:.2f} ({int(r.n.iloc[0])})")
        out.append(f"| {a_} | " + " | ".join(cells) + " |")
p = os.path.join(D, "feat_interaction_models.csv")
if os.path.exists(p):
    im = pd.read_csv(p); out.append("\n**Additive vs interaction** (grouped CV Spearman)\n\n| model | Spearman [CI] |\n|---|---|")
    for _, r in im.iterrows(): out.append(f"| {r.model} | {r.spearman:.2f} [{r.lo:.2f}, {r.hi:.2f}] |")
p = os.path.join(D, "feat_source_confound.csv")
if os.path.exists(p):
    sc = pd.read_csv(p).sort_values("eta2_between_source", ascending=False)
    out.append("\n**Source confound** — features with highest between-source share of variance (eta²) and pooled vs within-source Spearman with raw log Papp.\n\n| feature | eta² | pooled ρ | within-source ρ (k) | confounded |\n|---|---|---|---|---|")
    for _, r in sc.head(14).iterrows(): out.append(f"| {r.feature} | {r.eta2_between_source:.2f} | {r.pooled_rho:.2f} | {f3(r.within_source_rho)} ({int(r.within_k)}) | {r.confounded} |")
    out.append(f"\nFeatures flagged source-confounded: {int(sc.confounded.sum())} of {len(sc)}.")
# enrichment
en = pd.read_csv(os.path.join(D, "enrich_all.csv")).sort_values("p")
out.append("\n**Substructure enrichment** (within-source standardised effect, random-effects across sources; BH 10 %). Top 14 by p.\n\n| feature | n present | sources | effect [CI] | I² | sources with + effect | q |\n|---|---|---|---|---|---|---|")
for _, r in en.head(14).iterrows(): out.append(f"| {r.feature} | {r.n_present} | {r.n_sources} | {r.effect:.2f} [{r.lo:.2f}, {r.hi:.2f}] | {r.I2:.2f} | {r.frac_sources_positive:.2f} | {r.q:.3f} |")
print("\n".join(out))
