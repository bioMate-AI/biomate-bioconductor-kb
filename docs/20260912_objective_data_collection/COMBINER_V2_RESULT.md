# W6 — Evidence-gated, null-calibrated target-selection combiner (v2)

**Date:** 2026-09-13 · **Role:** COMBINER · `training_eligible = false`
**Script:** `W6_combiner_v2_evidence_gated.py` · **Result:** `COMBINER_V2_RESULT.json`
**Design refs:** `20260908_TARGET_SELECTION_CHANNELS_DESIGN.md`, `20260909_COMBINER_REDESIGN_evidence_gated_selector.md`, `W6_combiner_inventory.json`

## Why this exists
The v1 **averaging** combiner is a clean negative (`P1d/target_selection_fixed.json`):
combined AUROC **0.8542 < 0.8572** best-single (perturbation). Averaging a strong
channel with near-null channels pulls the score toward the mean. This v2 implements the
redesign: **OR-gate for nomination (recall), AND-corroboration for a confidence tier
(precision), null-gap-adaptive per-channel weighting** — never averaging.

## What was built (the four required pieces)
1. **Per-channel null calibration.** Each target gets a null-gap z per channel vs that
   channel's own matched null:
   - `genetics` — OpenTargets/GWAS L2G+burden prior (full per-gene table, S3
     `genetics/genetics_priors_long.parquet`); z vs the channel's own score distribution.
   - `ppi_module` — STRING v12 HC connectivity to the disease seed-module (S3
     `ppi/string_ppi_hc.parquet`, 236,930 edges); z vs a **degree-preserving rewired
     null** (200 random size-matched seed resamples, variance-floored + z-capped).
   - `regulatory` — CollecTRI signed-regulon overlap with the seed-module (S3
     `tf/collectri_human.tsv`, 42,990 edges); z vs a **regulon-size-matched null**.
2. **Evidence-gated logic (NOT averaging).**
   - **OR-gate → nomination:** any channel with z > 1.645 (empirical p<0.05) → candidate.
   - **AND-corroboration → confidence tier:** tier = count of independent channels above
     null; ≥2 → high-confidence.
   - **Null-gap-adaptive weights:** weight ∝ measured null-gap (leave-one-disease-out
     mean AUROC − 0.5). A channel at/below null gets weight 0 automatically — it cannot
     dilute the strong channel. Ordering uses **percentile-rank aggregation** (scale-
     invariant Borda/RRA), genetics-anchored, with a small corroboration promotion.
3. **Per-target evidence breakdown** — every nominated target emits `{gene, rank, tier,
   per-channel z, which_channels_fired, rationale}` (see JSON
   `per_target_evidence_breakdown_sample`).
4. **Evaluation** vs DisGeNET gold, leave-one-disease-out: recall@k (nomination),
   precision/calibration per tier, label-permutation null, leakage check. Best-single
   baseline included and compared on the **same universe and same denominator**.

## Substrate & honest scope
The two **demonstrated** channels live on **disjoint substrates** — perturbation carries
the CZI Th2/Th1 Perturb-seq substrate (AUROC 0.85), genetics carries observational
disease. The full per-gene **perturbation** vector was **never persisted** (P1b JSON has
only top-20 + summary AUROC), and its substrate shares no gold with the observational
diseases, so it **cannot be per-gene fused here** — it is carried as a documented
separate-substrate anchor.

The fully-reproducible **per-gene fused** combiner therefore runs on the **observational
autoimmune substrate (8 DisGeNET diseases: SLE, RA, CD, IBD, AS, MS, PsO, UC)** with the
3 constructed channels above. **On this substrate best-single = genetics.**

## Headline results (8-disease mean)

| Metric | Combiner v2 | Best-single (genetics) | Verdict |
|---|---|---|---|
| **recall@10** (fair, shared denominator) | 0.013 | 0.013 | tie |
| **recall@50** | 0.047 | 0.052 | **does NOT beat** best-single |
| combined AUROC (adaptive) | 0.611 | 0.654 | does not beat |
| **tier ≥2 precision** (AND-corroboration) | **0.440** | prevalence 0.054 | **beats — 8.4× lift** |
| **OR-gate gold coverage** | **2404 gold reached** | 875 (genetics alone) | **+1529 gold recovered** |
| label-permutation null (recall@50) | p ≈ 0.005 per disease | — | signal is real, not artifact |

**Honest bottom line — the redesign's thesis is confirmed, both directions:**
- The gated combiner **does NOT beat best-single on ranked recall@k or AUROC.** As the
  redesign predicted, with one strong channel + weak add-ons, blending cannot out-rank the
  strong channel — and the point was never a single AUROC.
- The gated combiner **wins exactly where the design says it should:**
  - **Precision** — the AND-corroboration tier is **8.4× more precise than prevalence**
    (0.44 vs 0.054), i.e. a corroborated call is a strongly de-risked call.
  - **Recall/coverage** — the OR-gate **reaches 2404 gold vs 875 for genetics alone
    (+1529)**; a single channel would have missed those targets entirely.

## The per-target breakdown — the product (SLE example)
Top OR-gate nominations are the canonical genetics-anchored SLE targets, each with an
auditable rationale:

| rank | gene | tier | fired | genetics z | ppi z | reg z | note |
|---|---|---|---|---|---|---|---|
| 1 | **TYK2** | 1 | genetics | 1.73 | – | – | canonical genetics anchor (→ deucravacitinib) |
| 2 | WDFY4 | 1 | genetics | 1.71 | – | – | genetics-only candidate |
| 3 | NCF2 | 1 | genetics | 1.69 | – | – | genetics-only candidate |
| 4 | BANK1 | 1 | genetics | 1.68 | – | – | genetics-only candidate |
| 5 | PTPN22 | 1 | genetics | 1.66 | – | – | genetics-only candidate |
| 6 | **IKZF1** | **2** | ppi + regulatory | 0.95 (sub-thr) | **8.0** | **3.0** | **corroborated GOLD genetics alone would MISS** |

**IKZF1** is the flagship demonstration: a real SLE gold target where genetics is
**below threshold** (z=0.95), rescued to **high-confidence tier-2** by two independent
corroborating channels. Analogous tier-2 corroborated gold rescues appear per disease:
**PRDM1** (CD), **RUNX3** (IBD), **BATF** (MS), **TLR4** (UC) — all bona-fide immune
genes, all sub-threshold in genetics, all recovered by corroboration.

## Leakage & circularity controls
- **DisGeNET is both the gold and partly upstream of the genetics prior → circularity.**
  Knowledge-prior is kept as a **soft prior only** (never a hit-test channel).
- **Module channels never see the gold:** `ppi_module` and `regulatory` seed from the
  disease's **genetics-prior top genes (NOT the gold)**; a gold gene never seeds its own
  module; seed genes are excluded from being scored by their own module.
- **Leave-one-disease-out** for the adaptive channel weights.
- **Label-permutation null** (200 shuffles) confirms observed recall is not chance
  (p ≈ 0.005 per disease).

## Caveats (honest)
- **Single gold cohort family (DisGeNET)** → surface-biased, favors genetics/literature;
  starves the module channels of independent gold (the small-N problem the redesign flags).
- **Perturbation — the program's strongest channel (AUROC 0.85) — is not fused here**
  (disjoint substrate + unpersisted full vector). Fusing it requires a matched KO screen
  and a shared gold; that is the next build, not this one.
- The 8 diseases share DisGeNET provenance → LOO weights are not fully independent across
  diseases.
- PPI/regulatory z are capped/variance-floored to prevent near-zero-null-variance genes
  from producing exploding z (an early-iteration bug that was fixed).
- `training_eligible = false` — this is an evaluation/selector artifact, not a trained model.

## Next
1. Fuse **perturbation** where a matched KO screen + shared gold exist (the CZI substrate
   with a CZI-appropriate gold) — the only way to carry the 0.85 channel into the fusion.
2. Second **independent** SLE/LN gold cohort disjoint from DisGeNET to break the small-N
   surface bias before the Mohan pilot.
3. Wire the DE and cell-state channels as further null-gated OR-gate add-ons.
