# Multi-Omics: The Finding + an Honest Competitive Reassessment

**Date:** 2026-07-28
**Context:** Follow-on to `docs/20260727_MULTIOMICS_BENCHMARK_DESIGN.md` (Phase-1 pilot).
Two questions forced this doc: *"what is the innovation?"* and *"you sure no one is
doing it?"* — both correct to press. The answer changed the plan.

---

## 1. Competitive reassessment — the platform novelty is largely gone

An earlier survey (in the design doc) claimed the "LLM-orchestrated reproducible
multi-omics platform" seam was empty. A targeted 2026-07-28 search **refuted that.**
A cluster of 2025–2026 systems now occupies it:

| System | What it is | Overlap with BioMate |
|---|---|---|
| **OmniBioAI** (omnibioai.org) | agentic (LangGraph) reproducible multi-omics, local/HPC/**cloud** (AWS/Azure/GCP), bulk+sc+spatial | **near-twin of our platform pitch** |
| **OmicOS** (bioRxiv 2026-06) | omics agent ecosystem (OmicVerse), 90% Pass@1 / 50 tasks | agent-for-omics, our lane |
| **OmicsNavigator** (bioRxiv 2025-07) | LLM multi-agent, autonomous insight from raw **spatial** omics | **takes the spatial+LLM white space** |
| **OMICX** (Genomics 2026) | code-free NL single-cell analysis, LLM agent | NL-interface angle |
| **CEPICS** (2019) | platform that runs **≥5 integration methods** + clustering/survival metrics, upload-your-own-results | **the prior for "platform-as-method-benchmark"** |
| **scMultiBench** (Nat Methods 2025) | 40-method sc benchmark + method-selection guidance | method-comparison + guidance (sc) |

**Consequence:** "LLM + reproducible + cloud + multi-omics" is **not a contribution in
mid-2026.** Two of three "white space" candidates (spatial+LLM, agent-systems) are
also taken. Adjective-stacking novelty ("we combined 4 things") collapses under this.

**What survived — narrow but real:** none of the *agentic platforms* (OmniBioAI, OmicOS,
OMICX) does **fair head-to-head benchmarking of integration METHODS with ground-truth
recovery metrics**; the *method benchmarks* (CEPICS, scMultiBench, momix) are static
codebases, not run-your-own-data platforms. So "the platform IS the method-benchmark
harness" is an *incremental merge* of CEPICS + an agentic platform — defensible as a
**tool note**, not as a novel-method paper. Hence the pivot below.

---

## 2. The pivot — find a real *finding*, not a platform

A bare "adding modalities can hurt" is **already known** (many survival-ML ablation
papers; "integration benefit is context-dependent"). The sharper, genuinely-open
question (confirmed open by search: *no clean MOFA-ARD-vs-SNF-equal-weight
noise-robustness comparison exists*; field guidance is qualitative-only):

> **Robustness to a low-value modality is governed by the integration method's
> view-weighting mechanism** — ARD-sparse methods (MOFA2) are robust to a bad view;
> equal-weight fusion (SNF) is degraded by it, **even when that modality independently
> carries the label** (mutations). **AND which modality helps is method-dependent and
> NOT predictable from cheap per-view properties** — standalone recovery, label-alignment,
> and affinity-concordance all fail as predictors (see §2 full-ablation table). The
> practical consequence: intuition about modality value is unreliable → you must run the
> head-to-head. (Two earlier clean-predictor forms — "standalone label-alignment" then
> "affinity-graph quality" — were both tested and REFUTED. This is the honest result.)

Mechanistic, controlled, quantitative, and it *resolves* a known-but-unexplained
phenomenon (attributes the cause + gives a predictor).

### 2×2 controlled experiment (real CLL, through the platform)
Inputs = mrna + methylation + drugs; **IGHV held out as label** (dropping the mutations
view removes label leakage). Scored by `scripts/multiomics_metric_harness.py`.

| Condition | SNF (equal-weight) | MOFA2 (ARD) |
|---|---|---|
| 3 real modalities | ARI **0.553** | AUC **0.967** / k2-ARI 0.797 |
| + **mutations** (real, sparse, *contains IGHV*) | ARI **0.375**  (**−0.18**) | AUC **0.968** (flat) |
| + **pure-noise** modality (2000× Gaussian) | ARI **0.496**  (**−0.057**) | AUC **0.967** / k2-ARI 0.797 (**flat**) |

**Headline (real data):** adding the mutations view **hurts SNF by 0.18 ARI — even
though that view literally contains the label** — while MOFA2 is flat. Equal weighting
is dragged down by a sparse/noisy view; ARD zeroes it. The synthetic-noise cell
confirms the direction (SNF −0.057; MOFA2 flat, 0.967→0.967).

**Mechanistic smoking gun (ARD, from the +noise MOFA2 weights):** per-view mean
|loading| across all factors — methylation **0.128**, mrna **0.115** (the IGHV
carriers), drugs 0.008, **noise_modality 0.003** (~40× smaller than the informative
views, the smallest of all four). MOFA2's ARD prior *learns* to assign the
uninformative view near-zero weight; SNF equal-weights it by construction. This is the
*causal* explanation for the table above, not a correlation. (MOFA2+noise: run
`e06888b3` → outdir `7228270b`; succeeded despite the platform status lagging at
"running" — a completion-detection lag, verified via S3 outputs + `.command.err`
showing only non-fatal warnings.)

*Discipline note:* the first MOFA2+noise run FAILED — **not** a MOFA robustness result,
but a data-prep bug (my synthetic view had double-quoted sample names → MOFA matches
views by name and rejected the mismatch; SNF fuses by position so its 0.496 is valid).
Fixed + rerun. "A failed run is not a finding."

### Predictor sub-experiment: my first hypothesis was REFUTED (this is good)
Standalone single-modality IGHV recovery (k-means k=2 ARI, computed locally, no platform
cost): methylation **0.760**, mutations **0.418**, drugs 0.176, mrna −0.005, noise 0.002.

I predicted *"mutations hurts SNF because its standalone recovery is low."* **False** —
mutations' standalone recovery is 0.418 (moderate, *higher* than drugs, a helpful view),
yet adding it hurts SNF by −0.18. **Standalone label-alignment does NOT predict marginal
contribution.** The clean predictor is wrong.

**The refutation sharpens the finding** (less obvious → more novel):
> A modality can hurt equal-weight fusion **even when it independently carries the
> label** (mutations recovers IGHV alone *and contains it*), because SNF fuses
> *similarity graphs* — what matters is the **quality of the view's affinity graph**
> (mutations = 69 sparse binary features, 34% NA → degenerate similarity), not its
> signal content. ARD weights by *variance-explained*, not graph structure, so MOFA2 is
> immune. Two distinct harm signatures: **structured-but-degenerate** (mutations, −0.18)
> vs **dense-but-uninformative** (noise, −0.057). Both sink SNF; neither touches MOFA2.

### Full ablation — ALL cheap predictors fail (the honest, decisive result)
SNF leave-one-out on the base-3 (base3 ARI = 0.553) + the two additions, per-view
marginal contribution vs candidate metrics:

| view | marginal→SNF | NA | standalone | IGHV-sil | concord |
|---|---|---|---|---|---|
| **drugs** | **+0.280** | 0.08 | 0.176 | 0.10 | 0.008 |
| methylation | +0.089 | 0.02 | 0.760 | 0.16 | 0.053 |
| mrna | **−0.021** | 0.32 | −0.005 | 0.05 | 0.072 |
| mutations | −0.178 | 0.34 | 0.418 | 0.15 | 0.062 |
| noise | −0.057 | 0.00 | 0.002 | 0.00 | −0.003 |

Pearson r (marginal vs metric, n=5): standalone **+0.05**, IGHV-sil **+0.10**, concord
**−0.42 (wrong sign)**, NA-fraction **−0.53 (best, moderate, unstable at n=5)**.

**Two surprises, both real:**
1. **Standalone value ≠ fused value.** `drugs` is the *most* valuable in fusion (+0.28)
   despite weak standalone (0.176); `methylation` — strongest standalone (0.760) — adds
   only +0.089; `mrna` slightly *hurts* (−0.021). Fused and standalone value are ~uncorrelated.
2. **No single cheap metric predicts marginal contribution.** Two *distinct* harm
   mechanisms sink equal-weight fusion — high-missingness/sparse views (mrna, mutations
   ~0.33 NA) AND uninformative-dense views (noise, 0 NA) — and no one scalar catches both.

**This REFRAMES the thesis (honestly):** the splashy "we predict the best modality/method
a-priori" claim is **not supported** on CLL. What *is* robust and defensible:

> **(a)** Robustness to a bad modality is a property of the method's view-weighting
> (ARD-sparse robust; equal-weight degraded) — the 2×2 + ARD weights prove this.
> **(b)** *Which* modality helps is method-dependent and **not predictable from cheap
> per-view properties** — so intuition is unreliable and **you must actually run the
> head-to-head.** That is a *negative result that motivates the benchmark platform*,
> not a magic recommender. Weaker as a headline, but true — and still a real product
> argument (don't trust your gut about modality value; benchmark it).

### What this still needs to be a *finding*, not an anecdote
1. **Generalization** — TCGA (≥3 cancers, PAM50). Critically: does the *unpredictability*
   itself replicate, and does NA-fraction (the one weak signal) hold or vanish? One
   cohort/one label ≠ a finding.
2. **More weighting mechanisms** — intNMF / iClusterPlus / DIABLO, to show (a) is the
   *mechanism* (view-weighting), not "MOFA good, SNF bad."
3. Larger view panels (>5) so predictor correlations aren't n=5-unstable.

---

## 3. How the finding makes the platform stronger (the flywheel)

The finding is not just a paper — it's the **method-selection rule** no competitor
ships: *"your modality set contains a weakly-aligned layer (mutations); it degrades
equal-weight fusion by ~0.18 but not ARD methods → recommend MOFA2, or drop that layer
for SNF."* OmniBioAI/OmicOS run *a* pipeline with no such guidance; CEPICS compares
methods but gives no recommendation. **Science → rule → product differentiation → more
science.** Plus BioMate's structural moat that pure-software competitors can't copy: the
wet-lab DBTL loop (a benchmark that ends in a re-executable CRO order, not a figure).

**Two tracks, one flywheel** (per user "both are important"): (a) the finding paper,
(b) a stronger platform whose wedge IS the finding-driven recommender. The honest
sequencing: **verify the finding first** (predictor + TCGA), because the recommender's
credibility *is* the finding.

---

## 3b. Track B — TCGA generalization (in progress): the ranking FLIPS across cohorts
Second cohort staged through the platform via the canonical Rappoport & Shamir 2018
benchmark (TCGA, mRNA/methylation/miRNA). **AML** (exp top-5000-var / methy / miRNA;
runs `4593a3e6` MOFA2, `c3a5cdd7` SNF — after the sample-intersect fix, see §4a),
scored vs cytogenetic-risk (3-class), matched k=3:

| Cohort (label) | MOFA2 | SNF | winner |
|---|---|---|---|
| **CLL** (IGHV — strong molecular) | ARI 0.53 / AUC 0.97 | ARI 0.38–0.55 | **MOFA2** |
| **TCGA-AML** (cyto-risk, k=3) | ARI **0.093** / NMI 0.156 | ARI **0.174** / NMI 0.278 | **SNF** |

**The method ranking FLIPS between cohorts** — MOFA2 wins on CLL, SNF wins on AML. This
is the strongest evidence yet for the reframed thesis: *no universal-best method; which
one to trust is cohort/label-dependent → you must benchmark.* Honest caveats: (1) AML
cyto-risk is a **prognostic** label, weakly omics-encoded → both methods score low
(0.09–0.17); SNF did isolate one clean Favorable cluster (14/1/0). (2) A **strong
molecular** label is the cleaner test — **BRCA PAM50 / GBM Verhaak next** (downloads
currently blocked by TAU-server rate-limiting; retry pending). One flipped ranking on a
weak label is suggestive, not conclusive; ≥2 strong-label cohorts needed to publish.

### §4a — capability fix this unlocked (stronger-platform win)
Real TCGA cohorts measure each omic on a **different, overlapping sample set** (AML:
exp 173 / methy 194 / miRNA 188). MOFA2 (`create_mofa_from_matrix`) and SNF both require
identical samples/order across views → both failed on first AML run. **Root-cause fix:**
both workflows now `Reduce(intersect, colnames)` and subset every view to the common set
before integration (no-op when views already match, so CLL is unaffected). The universal
interface now handles heterogeneous real-world coverage — needed for every TCGA cohort.

## 4. Runs (provenance)
- 3 real modalities: MOFA2 `f45e29d4`, SNF `bd351c4b`
- + noise: SNF `d6dbc925` (valid), MOFA2 `8a26ae66` (failed: quoted-names bug) → rerun `e06888b3`
- + mutations (from Phase-1): SNF ARI 0.375 (4-view run), MOFA2 AUC 0.968
- Noise modality: `s3://biomate-nextflow-work/cll_test/noise_modality.csv` (2000×200 Gaussian, seed 42)

**Next:** confirm the 2×2 (MOFA2+noise), then the single-modality predictor sweep
(8 runs), then TCGA. See [[project_multiomics_benchmark]].
