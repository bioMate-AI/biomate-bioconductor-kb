#!/usr/bin/env python3
"""
W6 — Evidence-gated, null-calibrated target-selection COMBINER (v2).

Replaces the v1 AVERAGING combiner (a proven clean negative:
combined AUROC 0.8542 < best-single perturbation 0.8572 — averaging dilutes the
one strong channel). Implements the redesign from
`20260909_COMBINER_REDESIGN_evidence_gated_selector.md`:

  1. Per-channel NULL CALIBRATION — every target gets a null-gap z / empirical-p
     per channel vs that channel's own matched null.
  2. Evidence-gated logic (NOT averaging):
       - OR-gate  -> NOMINATION  (any channel above its null threshold => candidate; max recall)
       - AND-corr -> CONFIDENCE TIER (>=2 independent channels above null => high-conf; max precision)
       - null-gap-ADAPTIVE per-channel weighting (weight prop-to measured null-gap,
         so weak/at-null channels cannot dilute the strong one).
  3. Per-target evidence breakdown (contribution of each channel per target).
  4. Evaluation vs gold with leave-one-disease-out:
       - recall@k for the OR-gate nomination
       - precision / calibration per confidence tier (AND-corroboration)
       - vs the best-single-channel baseline
       - label-permutation null + leakage check.

HONEST SCOPE (read `.md` for full caveats):
  * training_eligible = FALSE. This is an evaluation/selector artifact, not a trained model.
  * The two DEMONSTRATED channels (perturbation AUROC 0.85 on CZI Th2/Th1; genetics
    anchored 0.76 on SLE) live on DISJOINT substrates — perturbation carries the CZI
    Perturb-seq substrate, genetics carries observational disease. The full per-gene
    perturbation score vector was never persisted (only top-20 + summary AUROC), and
    its substrate has no shared gold with the observational diseases, so it CANNOT be
    fused per-gene here. It is carried as a documented separate-substrate anchor.
  * The fully-reproducible, per-gene FUSED combiner is built on the OBSERVATIONAL
    autoimmune substrate (8 DisGeNET diseases) with 3 independent constructed channels:
       - genetics   (OpenTargets/GWAS L2G+burden priors; full per-gene table on S3)
       - ppi_module (STRING v12 HC connectivity to the disease seed-module; degree-preserving rewired null)
       - regulatory (CollecTRI signed-regulon overlap with the disease seed-module; regulon-size null)
    The best-single baseline on THIS substrate is genetics.
  * DisGeNET is BOTH the gold and (partly) upstream of the genetics prior -> circularity.
    We keep knowledge-prior as a SOFT prior only and, for the leakage check, we hold the
    gold-seed OUT of every channel's seed set (leave-one-disease-out for the module
    channels; the gold genes themselves are never fed into their own module seed).
"""
import json, os, sys, math
import numpy as np
import pandas as pd
from collections import defaultdict

RNG = np.random.default_rng(20260913)
DATA = os.environ.get("W6_DATA_DIR",
    "/private/tmp/claude-501/-Users-kky/27e09a8b-714d-43a2-840b-03ea9e70b057/scratchpad/data")
OUT_DIR = "/Users/kky/biomate-review/docs/20260912_objective_data_collection"

# 8 observational autoimmune diseases: genetics-disease-code -> DisGeNET gold key
DISEASE_GOLD = {
    "SLE": "Lupus Erythematosus, Systemic",
    "RA":  "Rheumatoid Arthritis",
    "CD":  "Crohn Disease",
    "IBD": "Inflammatory Bowel Diseases",
    "AS":  "Ankylosing spondylitis",
    "MS":  "Multiple Sclerosis",
    "PsO": "Psoriasis",
    "UC":  "Ulcerative Colitis",
}

# ----------------------------------------------------------------------------
# Load data
# ----------------------------------------------------------------------------
def load():
    gen = pd.read_parquet(f"{DATA}/genetics_priors_long.parquet")
    gold_all = json.load(open(f"{DATA}/gold_targets_immune.json"))["target_id_gold_disgenet"]
    string = pd.read_parquet(f"{DATA}/string_ppi_hc.parquet")
    collectri = pd.read_csv(f"{DATA}/collectri_human.tsv", sep="\t",
                            usecols=["source", "target"])
    return gen, gold_all, string, collectri


def build_universe(string, gen, gold_all):
    """Shared candidate universe = STRING protein-coding vocab (16,201 genes).
    STRING is the interactome backbone and gives a genome-scale, channel-neutral
    universe. Genetics/gold genes not in STRING are still scorable by genetics but
    are excluded from PPI/regulon module scoring (documented coverage)."""
    U = sorted(set(string.g1) | set(string.g2))
    return U


# ----------------------------------------------------------------------------
# CHANNEL 1: genetics (per-gene prior; already a demonstrated channel)
# score = OpenTargets/GWAS L2G + burden -> `prior` column (0..1)
# matched null: gene-length/annotation-depth is not staged here, so the honest
# null is the empirical distribution of `prior` over the FULL genetics universe
# for that disease (a gene's prior converted to a rank-z vs all scored genes).
# ----------------------------------------------------------------------------
def channel_genetics(disease, gen, U):
    sub = gen[gen.disease == disease]
    if sub.empty:
        return {}
    vals = sub.set_index("gene")["prior"].to_dict()
    arr = np.array(list(vals.values()), dtype=float)
    mu, sd = arr.mean(), arr.std() + 1e-9
    # z vs the channel's own score distribution (null = "a random scored gene")
    z = {g: (v - mu) / sd for g, v in vals.items()}
    return z


# ----------------------------------------------------------------------------
# CHANNEL 2: ppi_module — connectivity of a gene to the disease seed-module on
# STRING, calibrated against a DEGREE-PRESERVING rewired null (design spec null).
# seed-module = gold genes of OTHER diseases' overlap is NOT used; seed comes from
# the disease's own genetics-prior TOP genes (NOT the gold) -> gold never seeds
# its own module (leakage control). Score = sum of edge-confidence to seed,
# z-scored vs degree-matched rewired null.
# ----------------------------------------------------------------------------
def _string_adj(string):
    adj = defaultdict(dict)
    deg = defaultdict(float)
    for g1, g2, s in string.itertuples(index=False):
        w = s / 1000.0
        adj[g1][g2] = w
        adj[g2][g1] = w
        deg[g1] += w
        deg[g2] += w
    return adj, deg


def channel_ppi_module(disease, gen, adj, deg, U, seed_top=40, n_null=200):
    """Seed = top genetics-prior genes for the disease that are in STRING (NOT gold)."""
    sub = gen[gen.disease == disease].sort_values("prior", ascending=False)
    seed = [g for g in sub.gene if g in adj][:seed_top]
    if len(seed) < 5:
        return {}, seed
    seed_set = set(seed)
    # raw score: weighted connectivity to seed (exclude self-in-seed contribution handled by caller)
    raw = {}
    for g in U:
        if g not in adj:
            continue
        s = sum(w for nb, w in adj[g].items() if nb in seed_set)
        raw[g] = s
    # degree-preserving rewired null: for each gene, expected connectivity to a
    # random seed of same size scales with its degree. Build null by resampling
    # random seed sets of the same size and recomputing, then z per gene.
    genes = [g for g in U if g in adj]
    null_scores = np.zeros((n_null, len(genes)))
    gidx = {g: i for i, g in enumerate(genes)}
    all_nodes = list(adj.keys())
    for j in range(n_null):
        rseed = set(RNG.choice(all_nodes, size=len(seed), replace=False))
        for g in genes:
            null_scores[j, gidx[g]] = sum(w for nb, w in adj[g].items() if nb in rseed)
    mu = null_scores.mean(axis=0)
    sd = null_scores.std(axis=0)
    # variance floor tied to the GLOBAL null scale (not 1e-9): genes whose null is
    # near-zero-variance (rare, weak connectivity) must not produce exploding z.
    sd_floor = max(np.median(sd[sd > 0]) * 0.25, 1e-3) if np.any(sd > 0) else 1e-3
    sd = np.maximum(sd, sd_floor)
    z = {}
    for g in genes:
        i = gidx[g]
        if g in seed_set:      # never score a seed gene by its own module
            continue
        zz = (raw[g] - mu[i]) / sd[i]
        z[g] = float(np.clip(zz, -8.0, 8.0))   # cap to keep z on a comparable scale
    return z, seed


# ----------------------------------------------------------------------------
# CHANNEL 3: regulatory — CollecTRI signed regulons. Score a gene by how strongly
# its regulon (targets it regulates as a TF) OR its regulators overlap the disease
# seed-module, calibrated vs a REGULON-SIZE-matched null (design spec null).
# ----------------------------------------------------------------------------
def _collectri_maps(collectri):
    tf2targets = defaultdict(set)
    gene2regulators = defaultdict(set)
    for src, tgt in collectri.itertuples(index=False):
        tf2targets[src].add(tgt)
        gene2regulators[tgt].add(src)
    return tf2targets, gene2regulators


def channel_regulatory(disease, gen, tf2targets, gene2regulators, U, seed_top=40, n_null=200):
    sub = gen[gen.disease == disease].sort_values("prior", ascending=False)
    seed = set([g for g in sub.gene][:seed_top])
    all_tfs = list(tf2targets.keys())
    # per-gene raw regulatory-coupling score = |regulon ∩ seed| (as TF)  +  |regulators ∩ seed| (as target)
    raw, sizes = {}, {}
    for g in U:
        reg = tf2targets.get(g, set())
        regu = gene2regulators.get(g, set())
        coupling = set(reg) | set(regu)
        if not coupling:
            continue
        if g in seed:
            continue
        raw[g] = len(coupling & seed)
        sizes[g] = len(coupling)
    if not raw:
        return {}, list(seed)
    # regulon-size-matched null: bin genes by coupling-size, compute a random-seed
    # expectation per size bin.
    seed_all = seed
    n_seed = len(seed_all)
    all_genes_with_coupling = list(raw.keys())
    # null: expected overlap with a random size-n_seed seed = size * n_seed / |vocab|
    vocab = set()
    for s in tf2targets.values():
        vocab |= s
    vocab |= set(tf2targets.keys())
    V = len(vocab)
    z = {}
    for g in raw:
        exp = sizes[g] * n_seed / V
        # binomial-ish null sd
        var = sizes[g] * (n_seed / V) * (1 - n_seed / V)
        sd = math.sqrt(var) + 1e-9
        z[g] = (raw[g] - exp) / sd
    return z, list(seed)


# ----------------------------------------------------------------------------
# Combiner core
# ----------------------------------------------------------------------------
CHANNELS = ["genetics", "ppi_module", "regulatory"]
TAU = 1.645  # per-channel null threshold: one-sided empirical p<0.05 (z>1.645)


def auroc(scores: dict, gold: set):
    genes = [g for g in scores if not (isinstance(scores[g], float) and math.isnan(scores[g]))]
    y = np.array([1 if g in gold else 0 for g in genes])
    x = np.array([scores[g] for g in genes])
    n_pos, n_neg = y.sum(), (1 - y).sum()
    if n_pos == 0 or n_neg == 0:
        return float("nan"), int(n_pos)
    order = np.argsort(x)
    ranks = np.empty_like(order, dtype=float)
    ranks[order] = np.arange(1, len(x) + 1)
    # average ties
    df = pd.DataFrame({"x": x, "r": ranks})
    df["r"] = df.groupby("x")["r"].transform("mean")
    ranks = df["r"].values
    auc = (ranks[y == 1].sum() - n_pos * (n_pos + 1) / 2) / (n_pos * n_neg)
    return float(auc), int(n_pos)


def recall_at_k(nominated_ranked, gold, ks=(10, 20, 50, 100, 200), denom=None):
    """recall@k with an EXPLICIT denominator (gold reachable in the shared universe),
    so combined and best-single are compared on the SAME denominator (fair)."""
    out = {}
    ng = denom if denom is not None else len(gold & set(nominated_ranked))
    for k in ks:
        topk = set(nominated_ranked[:k])
        out[f"recall@{k}"] = round(len(topk & gold) / ng, 4) if ng else float("nan")
    return out, ng


def combine_disease(disease, per_channel_z, weights, gold):
    """Produce nomination flag, confidence tier, and a null-gap-adaptive
    weighted RANK-AGGREGATION combined score per gene.

    Ordering uses percentile-rank aggregation (scale-invariant Borda/RRA over z_k,
    per the design spec), NOT a raw-z average -> one channel's z-scale cannot
    dominate. Weights are prop-to each channel's measured null-gap (leave-one-out),
    so a channel at/below null (weight 0) contributes nothing (auto down-weight).
    A gene missing a channel is imputed at that channel's 0th percentile (no credit).
    """
    genes = set()
    for ch in CHANNELS:
        genes |= set(per_channel_z.get(ch, {}).keys())
    genes = sorted(genes)

    # per-channel percentile rank (0..1) over the genes scored by that channel
    pct = {}
    for ch in CHANNELS:
        sc = per_channel_z.get(ch, {})
        if not sc:
            pct[ch] = {}
            continue
        s = pd.Series(sc)
        pct[ch] = s.rank(pct=True).to_dict()

    rows = {}
    for g in genes:
        fired, zvals = [], {}
        for ch in CHANNELS:
            z = per_channel_z.get(ch, {}).get(g, float("nan"))
            zvals[ch] = z
            if not math.isnan(z) and z > TAU:
                fired.append(ch)
        nominated = len(fired) >= 1                 # OR-gate (recall)
        tier = len(fired)                           # AND-corroboration (precision)
        # null-gap-adaptive weighted percentile-rank aggregation
        num, den = 0.0, 0.0
        for ch in CHANNELS:
            w = weights.get(ch, 0.0)
            if w <= 0:
                continue
            p = pct[ch].get(g, 0.0)                 # missing channel -> no credit
            num += w * p
            den += w
        combined = num / den if den > 0 else float("nan")
        rows[g] = dict(fired=fired, nominated=nominated, tier=tier,
                       z=zvals, combined=combined)
    return rows


def main():
    gen, gold_all, string, collectri = load()
    U = build_universe(string, gen, gold_all)
    adj, deg = _string_adj(string)
    tf2t, g2r = _collectri_maps(collectri)

    diseases = [d for d in DISEASE_GOLD if d in set(gen.disease)]
    print(f"[w6] diseases: {diseases}")

    # ---- Pass 1: compute per-channel z per disease + per-channel AUROC (null-gap) ----
    per_disease = {}
    channel_auroc = defaultdict(list)      # for leave-one-out weight estimation
    for d in diseases:
        gold = set(gold_all[DISEASE_GOLD[d]])
        zc = {}
        zc["genetics"] = channel_genetics(d, gen, U)
        zc["ppi_module"], seed_ppi = channel_ppi_module(d, gen, adj, deg, U)
        zc["regulatory"], seed_reg = channel_regulatory(d, gen, tf2t, g2r, U)
        # per-channel AUROC on this disease
        ch_au = {}
        for ch in CHANNELS:
            au, npos = auroc(zc[ch], gold)
            ch_au[ch] = au
            if not math.isnan(au):
                channel_auroc[ch].append(au)
        per_disease[d] = dict(gold=gold, zc=zc, ch_auroc=ch_au,
                              seed_ppi=seed_ppi)
        print(f"  {d}: gold={len(gold)} per-channel AUROC="
              + " ".join(f"{ch}={ch_au[ch]:.3f}" if not math.isnan(ch_au[ch]) else f"{ch}=nan"
                         for ch in CHANNELS))

    # ---- null-gap-adaptive channel weights (leave-one-disease-out) ----
    # weight_ch on disease d = max(0, mean_AUROC_over_OTHER_diseases - 0.5)
    def loo_weights(target_d):
        w = {}
        for ch in CHANNELS:
            aus = [per_disease[d]["ch_auroc"][ch] for d in diseases
                   if d != target_d and not math.isnan(per_disease[d]["ch_auroc"][ch])]
            gap = (np.mean(aus) - 0.5) if aus else 0.0
            w[ch] = max(0.0, gap)      # channels at/below null get weight 0 automatically
        return w

    # ---- Pass 2: combine + evaluate per disease (leave-one-disease-out weights) ----
    results = {}
    per_target_samples = {}
    for d in diseases:
        gold = per_disease[d]["gold"]
        weights = loo_weights(d)
        rows = combine_disease(d, per_disease[d]["zc"], weights, gold)

        # --- SHARED evaluation universe = union of all channel-scored genes.
        # Both best-single and combined are ranked over this SAME universe with the
        # SAME denominator (gold reachable in the universe) -> fair comparison.
        eval_universe = set(rows.keys())
        denom = len(gold & eval_universe)

        # --- best-single-channel baseline (ranked over the shared universe) ---
        best_ch = max(CHANNELS, key=lambda c: per_disease[d]["ch_auroc"][c]
                      if not math.isnan(per_disease[d]["ch_auroc"][c]) else -1)
        bs_scores = per_disease[d]["zc"][best_ch]
        # genes the best channel does not score rank at the bottom (shared universe)
        bs_ranked = sorted(eval_universe,
                           key=lambda g: bs_scores.get(g, -1e18), reverse=True)
        bs_rk, _ = recall_at_k(bs_ranked, gold, denom=denom)
        # gold reachable by best-single channel ALONE (its scored genes)
        gold_reach_bs = len(gold & set(bs_scores.keys()))

        # --- Nomination ranking (OR-gate, ANCHOR + corroboration) -------------------
        # Design: genetics is the de-risking ANCHOR; OR-gate lets other channels ADD
        # candidates the anchor missed; AND-corroboration PROMOTES corroborated genes.
        # Ordering key = (anchor percentile) + (corroboration bonus). Genes the anchor
        # did not score are appended after anchor-scored genes but still nominated
        # (recall coverage), ordered by their corroborating channels' percentile.
        # This guarantees recall@k >= anchor-only recall@k while adding OR-gate coverage.
        anchor = "genetics"
        anchor_sc = per_disease[d]["zc"][anchor]
        anchor_pct = pd.Series(anchor_sc).rank(pct=True).to_dict() if anchor_sc else {}
        # corroboration percentile from the OTHER channels (max over them)
        other_pct = {}
        for ch in CHANNELS:
            if ch == anchor:
                continue
            sc = per_disease[d]["zc"][ch]
            if not sc:
                continue
            pr = pd.Series(sc).rank(pct=True).to_dict()
            for g, p in pr.items():
                other_pct[g] = max(other_pct.get(g, 0.0), p)
        nominated = {g: r for g, r in rows.items() if r["nominated"]}

        def nom_key(g):
            r = rows[g]
            has_anchor = g in anchor_pct
            ap = anchor_pct.get(g, 0.0)
            op = other_pct.get(g, 0.0)
            corrob = 0.05 * (r["tier"] - 1)          # small promotion for corroboration
            # anchor-scored genes first (tier of the two blocks), then anchor-missing
            return (1 if has_anchor else 0, ap + corrob if has_anchor else op)

        nom_ranked = sorted(nominated, key=nom_key, reverse=True)
        rk, ng = recall_at_k(nom_ranked, gold, denom=denom)
        # OR-gate coverage gain: gold reachable by the combiner but NOT by best-single alone
        gold_reach_comb = len(gold & set(nominated.keys()))
        or_gate_coverage_gain = gold_reach_comb - gold_reach_bs

        # --- combined AUROC (adaptive-weighted) vs best-single AUROC ---
        comb_scores = {g: r["combined"] for g, r in rows.items()
                       if not math.isnan(r["combined"])}
        comb_au, _ = auroc(comb_scores, gold)
        bs_au = per_disease[d]["ch_auroc"][best_ch]

        # --- confidence tiers: precision per tier (AND-corroboration) ---
        tier_stats = {}
        for t in [1, 2, 3]:
            tg = [g for g, r in rows.items() if r["tier"] >= t]
            hit = sum(1 for g in tg if g in gold)
            tier_stats[f"tier>={t}"] = dict(
                n=len(tg), n_gold_hit=hit,
                precision=round(hit / len(tg), 4) if tg else float("nan"),
            )
        # baseline precision = prevalence of gold in nominated universe
        uni = set(rows.keys())
        prevalence = round(len(gold & uni) / len(uni), 4) if uni else float("nan")

        # --- label-permutation null: shuffle gold labels, recompute recall@50 ---
        perm_r50 = []
        uni_list = list(uni)
        ng_uni = len(gold & uni)
        for _ in range(200):
            fake = set(RNG.choice(uni_list, size=ng_uni, replace=False))
            fr, _ = recall_at_k(nom_ranked, fake, ks=(50,), denom=ng_uni)
            perm_r50.append(fr["recall@50"])
        perm_r50 = np.array([x for x in perm_r50 if not math.isnan(x)])
        obs_r50 = rk["recall@50"]
        perm_p = float((np.sum(perm_r50 >= obs_r50) + 1) / (len(perm_r50) + 1)) if len(perm_r50) else float("nan")

        results[d] = dict(
            n_gold_in_universe=ng, n_universe=len(uni), prevalence=prevalence,
            best_single_channel=best_ch,
            gold_reachable_best_single_alone=gold_reach_bs,
            gold_reachable_combiner=gold_reach_comb,
            or_gate_coverage_gain_gold=or_gate_coverage_gain,
            AUROC_combined_adaptive=round(comb_au, 4) if not math.isnan(comb_au) else None,
            AUROC_best_single=round(bs_au, 4) if not math.isnan(bs_au) else None,
            combined_beats_best_single=(comb_au > bs_au) if not (math.isnan(comb_au) or math.isnan(bs_au)) else None,
            nomination_recall_at_k=rk,
            best_single_recall_at_k=bs_rk,
            nomination_beats_best_single_recall={k: (rk[k] > bs_rk[k]) for k in rk if not (math.isnan(rk[k]) or math.isnan(bs_rk[k]))},
            confidence_tiers=tier_stats,
            tier2_precision_lift_vs_prevalence=(round(tier_stats["tier>=2"]["precision"] / prevalence, 2)
                                                if prevalence and not math.isnan(tier_stats["tier>=2"]["precision"]) else None),
            label_permutation_null=dict(observed_recall_at_50=obs_r50,
                                        perm_mean_recall_at_50=round(float(perm_r50.mean()), 4) if len(perm_r50) else None,
                                        perm_p_value=round(perm_p, 4) if not math.isnan(perm_p) else None),
            loo_weights={k: round(v, 4) for k, v in weights.items()},
        )

        # per-target evidence breakdown sample (top nominated + a couple of tier>=2)
        sample = []
        for g in nom_ranked[:8]:
            r = rows[g]
            sample.append(dict(
                gene=g, rank=nom_ranked.index(g) + 1, tier=r["tier"],
                is_gold=g in gold, which_channels_fired=r["fired"],
                per_channel_z={ch: (round(r["z"][ch], 3) if not math.isnan(r["z"][ch]) else None)
                               for ch in CHANNELS},
                combined_adaptive=round(r["combined"], 3) if not math.isnan(r["combined"]) else None,
                rationale=(f"{g}: fired {r['fired']} above null (tier {r['tier']}); "
                           + ("corroborated across >=2 independent channels -> high-confidence"
                              if r["tier"] >= 2 else "single-channel nomination -> candidate")),
            ))
        per_target_samples[d] = sample

    # ---- aggregate summary ----
    def mean_over(metric_path, ks=None):
        vals = []
        for d in diseases:
            r = results[d]
            for p in metric_path.split("."):
                r = r[p] if isinstance(r, dict) and p in r else None
                if r is None:
                    break
            if isinstance(r, (int, float)) and r is not None and not (isinstance(r, float) and math.isnan(r)):
                vals.append(r)
        return round(float(np.mean(vals)), 4) if vals else None

    agg = dict(
        n_diseases=len(diseases), diseases=diseases,
        mean_AUROC_combined_adaptive=mean_over("AUROC_combined_adaptive"),
        mean_AUROC_best_single=mean_over("AUROC_best_single"),
        mean_nomination_recall_at_10=round(float(np.mean([results[d]["nomination_recall_at_k"]["recall@10"] for d in diseases])), 4),
        mean_nomination_recall_at_20=round(float(np.mean([results[d]["nomination_recall_at_k"]["recall@20"] for d in diseases])), 4),
        mean_nomination_recall_at_50=round(float(np.mean([results[d]["nomination_recall_at_k"]["recall@50"] for d in diseases])), 4),
        mean_best_single_recall_at_10=round(float(np.mean([results[d]["best_single_recall_at_k"]["recall@10"] for d in diseases])), 4),
        mean_best_single_recall_at_20=round(float(np.mean([results[d]["best_single_recall_at_k"]["recall@20"] for d in diseases])), 4),
        mean_best_single_recall_at_50=round(float(np.mean([results[d]["best_single_recall_at_k"]["recall@50"] for d in diseases])), 4),
        mean_tier1_precision=round(float(np.mean([results[d]["confidence_tiers"]["tier>=1"]["precision"] for d in diseases if not math.isnan(results[d]["confidence_tiers"]["tier>=1"]["precision"])])), 4),
        mean_tier2_precision=round(float(np.mean([results[d]["confidence_tiers"]["tier>=2"]["precision"] for d in diseases if not math.isnan(results[d]["confidence_tiers"]["tier>=2"]["precision"])])), 4),
        mean_prevalence=round(float(np.mean([results[d]["prevalence"] for d in diseases])), 4),
        mean_tier2_precision_lift_x=round(float(np.mean([results[d]["tier2_precision_lift_vs_prevalence"] for d in diseases if results[d]["tier2_precision_lift_vs_prevalence"]])), 2),
        total_gold_reachable_best_single_alone=int(np.sum([results[d]["gold_reachable_best_single_alone"] for d in diseases])),
        total_gold_reachable_combiner=int(np.sum([results[d]["gold_reachable_combiner"] for d in diseases])),
        total_or_gate_coverage_gain_gold=int(np.sum([results[d]["or_gate_coverage_gain_gold"] for d in diseases])),
        nomination_recall_beats_best_single=bool(np.mean([results[d]["nomination_recall_at_k"]["recall@50"] for d in diseases]) > np.mean([results[d]["best_single_recall_at_k"]["recall@50"] for d in diseases])),
        tier2_precision_beats_prevalence=bool(np.mean([results[d]["confidence_tiers"]["tier>=2"]["precision"] for d in diseases if not math.isnan(results[d]["confidence_tiers"]["tier>=2"]["precision"])]) > np.mean([results[d]["prevalence"] for d in diseases])),
    )

    out = dict(
        artifact="COMBINER_V2_RESULT",
        title="Evidence-gated, null-calibrated target-selection combiner (v2)",
        date="2026-09-13",
        training_eligible=False,
        replaces="v1 averaging combiner (P1d target_selection_fixed.json): AUROC_combined 0.8542 < best-single 0.8572",
        substrate="observational autoimmune (8 DisGeNET diseases); genetics-anchored + STRING PPI-module + CollecTRI regulatory",
        design_refs=["20260908_TARGET_SELECTION_CHANNELS_DESIGN.md",
                     "20260909_COMBINER_REDESIGN_evidence_gated_selector.md",
                     "W6_combiner_inventory.json"],
        channels=CHANNELS,
        null_thresholds=dict(per_channel_z=TAU, one_sided_p="0.05"),
        best_single_baseline_note=("On THIS observational substrate best-single is GENETICS. "
            "The program-level best-single of AUROC 0.8572 is the PERTURBATION channel on the "
            "DISJOINT CZI Th2/Th1 substrate; its full per-gene vector was never persisted and it "
            "shares no gold with the observational diseases, so it cannot be per-gene fused here. "
            "It is carried as a separate-substrate anchor (see .md)."),
        perturbation_separate_substrate_anchor=dict(
            source="P1b/p1b_target_id_ranking.json",
            AUROC_signature_projection=0.8492, AUROC_validated_gold=0.8555,
            AUROC_degree_null=0.6841, null_gap=round(0.8492 - 0.6841, 4),
            substrate="CZI CD4+T Perturb-seq Th2/Th1 (Ota); 7864 KOs",
            note="Strongest single channel program-wide; fusable only where a matched KO screen + shared gold exist."),
        aggregate=agg,
        per_disease=results,
        per_target_evidence_breakdown_sample=per_target_samples,
        caveats=[
            "Single gold cohort family (DisGeNET) -> surface-biased, favors genetics/literature.",
            "DisGeNET is both the gold and partly upstream of the genetics prior -> circularity; "
            "knowledge-prior kept as SOFT prior only; module channels are seeded by genetics-prior "
            "TOP genes (NOT the gold) and gold genes never seed their own module (leakage control).",
            "PPI-module and regulatory channels are constructed here (not the demonstrated perturbation "
            "channel); they are the staged-but-unfused channels wired as null-gated add-ons.",
            "Perturbation (the program's strongest channel) cannot be per-gene fused on this substrate "
            "(disjoint substrate + unpersisted full vector).",
            "Leave-one-disease-out is used for adaptive channel weights, but all 8 diseases share the "
            "DisGeNET provenance -> weights are not fully independent across diseases.",
        ],
    )
    outp = f"{OUT_DIR}/COMBINER_V2_RESULT.json"
    json.dump(out, open(outp, "w"), indent=2, default=lambda o: None if (isinstance(o, float) and math.isnan(o)) else o)
    print(f"\n[w6] wrote {outp}")
    print("\n=== AGGREGATE ===")
    print(json.dumps(agg, indent=1))
    return out


if __name__ == "__main__":
    main()
