# Why knowledge augmentation works in the literature but adds ~0 in our immune model

Recorded: 2026-11-08T09:05 CST. Corrects an earlier overstatement ("we didn't build training-time
priors / graphs / embeddings / retrieval") — **we built nearly all of them.** This is the measured
cross-program synthesis, grounded in code and committed result docs.

## What we actually built and measured (not "untested")

| Mechanism | Code | Measured result | Verdict |
|---|---|---|---|
| Pathway activity as **features** (Reactome/KEGG/GO, 9,543) | `immune_encoder.experiments`, knowledge bake-off | **+0.030 macro-F1** cross-axis cell-type annotation (null 0.035) | **small REAL win** |
| TF regulons as features (271) | same | +0.001 | ~nothing |
| P-NET structured-sparse pathway **bottleneck** | bake-off V4 | +0.006 | structure-as-mask < structure-as-feature |
| Knowledge **bottleneck v1** (mean-pool replaces z) | `immune_hybrid_llm.py knowledge2` | annotF1 **−0.092** (0.460→0.368); `knowledge2_linadv=0.018` | capacity destruction |
| expiMap masked-**decoder** (de-novo + learnable soft mask) | designed `20260915_KNOWLEDGE_INTO_ZCELL_INTEGRATION.md` §3-4; concept bottleneck v3 built | v3 held annotation (+0.034), did **not** fix stratification (−0.20) | partial |
| KG: MAP-KG / PrimeKG / STRING / PINNACLE | `research/knowledge/`, `char_kg.py`, KG_REGISTRY | PINNACLE mean-pool loses **96.3%** variance; free STRING/PrimeKG **node2vec beats** curated immune KG; combiner Δ≈0, n=3 underpowered (±0.10 > gaps) | KG **not** a differentiator |
| Genetics priors (OpenTargets/GWAS/GTEx) | `genetics_priors.py` | folded into V0 baseline; target-ID still fails degree-null | ~0 incremental |
| Retrieval / RAG | `build_rag_index.py`, `rag_query.py` | reasoning-side (cited evidence), never gated as a prediction lift | separate consumer |
| Today's direct knowledge-features probe (stimulation) | `20261108_knowledge_features_baseline/` | real sets **+0.035** over size-matched null, but **−0.036 vs raw RNA**, and raw+know ≈ raw | small real, redundant |

**The pattern is identical everywhere:** knowledge-as-a-feature gives a **small, real, reproducible
lift on annotation / cell-type-transfer tasks (~+0.03)** — the same order the literature reports — and
**adds ~0 (or hurts) everywhere else**: as a lossy replacement, as a KG embedding, and on the clinical
product endpoints (responder stratification, target-ID).

## Why ours doesn't give more — four measured causes

1. **Batch leakage is the deep blocker (~28× study-identity in z).** On the clinical endpoints the FM
   embedding loses to PCA (stratification −0.31). When we removed batch by conditional-mean centering,
   the leakage probe went 0.859→0.000 **and the responder signal vanished** — *the signal WAS the
   batch* (`strat_batch_leak_fix.py`). A knowledge channel added on top of a batch-confounded base is
   competing with leakage, not with biology.
2. **Lossy aggregation / replacement destroys capacity.** The pathway **mean** discards within-pathway
   gene resolution, non-pathway genes, and the fused backbone. v1's "z = MLP(P@expr)" cost −0.092 F1.
   The field's fix (expiMap/VEGA/P-NET) keeps **de-novo unconstrained latent + learnable soft mask +
   decoder-side constraint** so knowledge is a *regularizer*, not a replacement. We designed it late and
   only partially deployed it (concept bottleneck v3).
3. **Redundancy on in-distribution, well-powered endpoints.** Where raw expression already saturates
   (stimulation @ ~1,000 labelled cells, cell types seen in training), the knowledge summary is
   collinear with the raw input — today: +0.035 over null yet −0.036 vs raw, raw+know ≈ raw. Knowledge
   helps *least* exactly where there is abundant direct signal and no scarcity/OOV to bridge.
4. **Wiring + power.** Knowledge was often *inventoried/ingested* but not *optimized* — the canonical
   encoder had knowledge **BLOCKED** (`b2_1_xverse_encoder.py:302,310`), and the only knowledge-into-z
   path was the broken bypass. Several KG verdicts were n=3 with ±0.10 seed variance > the gap.

## Why it works for others — regime and mechanism, not magic

The literature wins are concentrated where we do **not** evaluate, via mechanisms we **under-built**:

- **Regime.** GEARS (graph → **unseen** perturbation combos), GenePT/scELMo (text embeddings for
  **data-poor / zero-shot** genes), GeneCompass (priors under scarcity). Knowledge is the *only bridge*
  when data is absent. Our evals are in-distribution and well-powered — the one place the surveys
  predict the smallest benefit. Our own `KNOWLEDGE_GUIDED_MODELS_SURVEY.md` and the reconciliation doc
  say this.
- **Mechanism.** They constrain a *flexible* latent (de-novo nodes + learnable mask + decoder-side),
  not a lossy mean-replacement. Our biggest knowledge effort used structure-as-feature (which *did*
  give +0.03) or the broken bottleneck (which hurt).
- **Batch-clean base.** Single-cell FM papers integrate batches (scVI/harmony) before the knowledge
  claim. Ours is ~28× confounded, so knowledge rides on leakage.
- **The clinical "knowledge that works" is the simple signature.** TIS/IFN-γ GEP, TIDE, IMPRES —
  transferable gene-set **signatures**, not embeddings — and those transfer **in our hands too** (PCA /
  gene-set 0.734 LCO, field-competitive). What fails is the learned-embedding integration, not the
  biological knowledge.

A secondary caveat, not the main point: some literature deltas are reported without leave-study-out /
degree-null / capacity-null controls; the surveys concede knowledge "can be decorative." A fraction of
the apparent gap is us applying stricter nulls — but the regime + mechanism + batch account is the
dominant, evidence-backed explanation.

## Direct confirmation (2026-11-08 09:40): the scarcity crossover

We tested the central survey claim — *knowledge compensates for data scarcity* — by sweeping the
labelled budget down from ~1,000 to ~60 cells (nested stratified subsamples of the registered
labelled pool; same splits; feature-level; best-over-C oracle applied **identically** to every arm,
so the oracle if anything *helps* raw). AUPRC, mean over 3 seeds
(`scarcity_sweep_20261108/`, runtime 447 s):

| labelled n | raw | know_real | know_shuf0 (null) | raw+know | **know_real − raw** |
|---:|---:|---:|---:|---:|---:|
| ~1000 | **0.887**±.008 | 0.865±.006 | 0.826±.021 | 0.879 | −0.022 |
| ~500 | **0.861**±.013 | 0.855±.012 | 0.809 | 0.854 | −0.006 |
| ~250 | 0.817±.030 | **0.831**±.022 | 0.784 | 0.833 | **+0.014** |
| ~125 | 0.680±.149 | **0.824**±.038 | 0.749±.092 | 0.781 | **+0.145** |
| ~60 | 0.447±.260 | **0.741**±.036 | 0.601±.125 | 0.646 | **+0.294** |

**A clean crossover around ~250 labelled cells.** Where labels are abundant (~1,000), raw expression
wins and knowledge is redundant — exactly the regime all our prior knowledge evals used. As labels
shrink, raw RNA (2,000-d) collapses from overfitting (0.447 at n=60, SD ±0.26 — unstable even at its
oracle C) while the knowledge features (768-d, structured) stay robust (0.741, SD ±0.036). **This is
the surveys' claim reproduced in our own model.**

**The shuffled-null control proves it is biological content, not dimensionality.** At every scarce
budget know_real beats the size-matched random-set null by a wide margin (n=60: 0.741 vs 0.601, +0.14;
n=125: 0.824 vs 0.749, +0.075). Random 768-d sets also regularize better than raw at low n (0.601 >
0.447), so *some* of the gain is dimensionality — but **real pathway/regulon membership adds a further
+0.08 to +0.14 on top of that**. Knowledge earns its place under scarcity.

So the earlier "knowledge adds ~0" was an **artifact of the evaluation regime**: at ~1,000 well-
measured in-distribution cells, raw expression saturates and knowledge is redundant. The literature's
wins are measured where knowledge is the bridge — and when we match that regime, our knowledge works
the same way.

**Hardened confirmation (09:53, `scarcity_power_20261108/`) — the two caveats are now closed.** Re-ran
with a **pre-registered fixed C=0.01** (no best-C oracle; identical for every arm/budget) and **30
paired subsample draws** (3 seeds × 10) for power and a paired test:

| labelled n | raw | know_real | **know−raw** (paired) | know−shuffled (paired) |
|---:|---:|---:|---:|---:|
| ~1000 | 0.882 | 0.846 | −0.036  (t=−75, 0/30 draws) | +0.030 (t=+11.6) |
| ~500 | 0.853 | 0.830 | −0.024  (t=−8.5) | +0.035 (t=+7.7) |
| ~250 | 0.786 | 0.815 | **+0.028  (t=+3.5, 22/30)** | +0.042 (t=+9.1) |
| ~125 | 0.631 | 0.784 | **+0.152  (t=+9.0, 29/30)** | +0.051 (t=+6.1) |
| ~60 | 0.645 | 0.789 | **+0.144  (t=+5.9, 29/30)** | +0.053 (t=+5.0) |

The crossover holds at ~250 cells under honest fixed C, with |t| 3.5–9 across 30 paired draws. The
fixed strong-C protects raw from its worst overfits (raw n=60 = 0.645 vs 0.447 under the oracle) and
knowledge **still wins +0.144** — so the crossover is not an artifact of letting raw overfit. The
biological-content margin over the size-matched null is positive and significant at **every** budget
(t=+5 to +11.6) and **grows** under scarcity (+0.030 → +0.053). (Remaining scope: one endpoint,
within-dataset scarcity as the low-data proxy, paired t is over 30 draws on the same cells not a
population claim; cross-study / unseen-gene regimes still to test.)

## The 2×2 (10:10): scarcity benefit is a cell-type regularizer, NOT a transfer mechanism

The scarcity win raised the obvious question — is it *scarcity* that helps knowledge, or *generalization
difficulty* generally? We decomposed it by crossing label budget with the generalization axis
(held-out cell type vs held-out tissue — tissue is the stronger batch/offset axis). Feature-level,
fixed C=0.01 (`crosstissue_20261108/`, `crosstissue_scarce_20261108/`). **know_real − raw AUPRC:**

| | held-out **cell type** | held-out **tissue** (domain shift) |
|---|---:|---:|
| **abundant labels** | −0.036 (loses) | −0.06 … 0.00 (loses/ties) |
| **scarce labels** (~60–125) | **+0.14 (WINS)** | −0.05 … −0.13 (loses *more* when scarce, for lung) |

The knowledge advantage is **not** a general "scarcity or shift" effect — it appears in exactly one
cell: **scarce labels + held-out-cell-type**. Under tissue shift it loses at every budget, and for
lung it loses *more* as labels shrink — the opposite of the cell-type-holdout crossover. (These are
paired same-test-set deltas, so the sign flip is robust to test-set difficulty; test-bootstrap 95% CIs
exclude 0 for the tissue-shift losses.)

**Mechanism — why the sign flips.** Knowledge here is a per-cell MEAN over each gene-set's members.
A mean inherits the compartment's baseline offset (the exact E2 flaw flagged in the 2026-09-02
`KNOWLEDGE_BOTTLENECK_V1_ERROR_ANALYSIS.md`: "the pathway mean still carries depth/technical
variation"). Across *cell types within the same tissue mix*, that offset is shared between train and
test, so the pathway means act as a low-variance **regularizer** that helps when the sample is tiny.
Across *tissues*, the offset shifts, so the knowledge features carry a tissue-batch term that **breaks
transfer** — while gene-level raw expression (CP10k + z-scored) stays comparatively tissue-invariant
for the stim signal.

**So our pathway-mean channel captures the REGULARIZATION slice of knowledge's value, but not the
TRANSFER slice.** The surveys' strongest claims (GEARS graph propagation, GenePT/scELMo embeddings)
are transfer mechanisms — and our mean-pooling is precisely the construction that cannot deliver
transfer, because it inherits the domain offset. The error analysis already prescribes the fix:
per-cell-normalize BEFORE aggregation (strip the offset) and use a learnable soft mask + de-novo nodes
(expiMap/VEGA), not a frozen mean. This is a sharper, more actionable version of the regime answer:
not merely "wrong regime," but "our construction captures sample-efficiency and structurally cannot
capture cross-domain transfer until the aggregation stops carrying the batch offset."

## Primary-literature grounding (10:40, verified by search — replaces "attributed to our surveys")

The "why others work" side was previously grounded in our internal survey docs. Checked against the
primary sources; they confirm the regime pattern and the fix:

- **Low-data / few-shot is where text/knowledge embeddings are pitched.** GenePT (Chen & Zou, bioRxiv
  2023.10.16.562533) and scELMo (Liu et al., bioRxiv 2023.12.07.569910 / *Patterns* 2025) present LLM
  gene/cell embeddings as alternatives to expression features **for few-shot and low-data** settings
  (scELMo explicitly motivated by expression sparsity where ranking fails). Matches our scarcity
  crossover.
- **Knowledge is the bridge for the UNSEEN / transfer regime.** GEARS (Roohani, Huang, Leskovec,
  *Nat Biotechnol* 2023, s41587-023-01905-6) uses GO + coexpression graphs to gain the "**unique
  ability to predict outcomes of perturbing genes never experimentally perturbed**." That is exactly
  the transfer slice our pathway-**mean** cannot deliver (it inherits the domain offset).
- **Simple baselines win in-distribution — the field says so too.** "Benchmarking Transcriptomics
  Foundation Models for Perturbation Analysis: one PCA still rules them all" (arXiv 2410.13956) and the
  2025 FM evaluations find PCA/simple baselines match or beat FMs on standard tasks, with FM priors
  helping specifically where large-scale prior info is required (in-silico treatment, imputation,
  cross-species). Direct confirmation of our redundancy-at-abundance result and of our own clinical
  null (PCA 0.734 beats the FM embedding).
- **The fix we prescribed IS the canonical method.** expiMap (Lotfollahi et al., *Nat Cell Biol* 2023,
  PMC9928587) is a conditional VAE with **de-novo programs + group-lasso learnable mask + linear
  decoder** — precisely the Gate-2 design (de-novo nodes + learnable soft mask + masked decoder) in
  `docs/20261108_1030_..._AGGREGATION_FIX_STAGED_PLAN.md`. Our fix is not novel guesswork; it is the
  established transfer-capable construction our mean-pooling lacks.

(These are the papers' central, stated results, confirmed from source abstracts/summaries; exact
quantitative figures were not re-derived here.)

## One-line answer

Our pathway-mean knowledge channel captures the **sample-efficiency** slice of knowledge's value but
not the **cross-domain transfer** slice. It wins in exactly one regime — scarce labels + held-out cell
type (−0.02 at ~1,000 cells → **+0.14** at ~60, beating a size-matched null by +0.05–0.11, so it is
biological content) — because the gene-set means regularize a tiny sample whose tissue baseline matches
the test. Under genuine domain shift (held-out tissue) it loses at every budget, because a MEAN inherits
the compartment offset and breaks transfer. Our prior "knowledge adds ~0" was an **evaluation-regime
artifact** (always measured at the saturated ~1,000-cell budget). The literature's wins live where
knowledge is the bridge (low-data) and, for transfer, via mechanisms our mean-pooling structurally
lacks (graph propagation, embeddings, learnable masks). The fix is per-cell-normalized aggregation +
the expiMap de-novo/learnable-mask decoder on a batch-clean latent — then test in the low-data AND the
cross-study regimes.

## What this makes the next experiment

Not "try knowledge again" generically. Two gated moves, in order:
1. **Fix the base first** — batch-clean latent (atlas/Track-D route) before any new knowledge claim;
   knowledge on a leaky base is untestable.
2. **Test in the regime knowledge is for** — unseen-gene / low-data cross-study / OOD-perturbation
   endpoints, with the expiMap de-novo+learnable-mask decoder, matched train-with/without-prior,
   degree/size nulls, ≥60-seed power. That is the only setup that can reproduce "knowledge helps."

Grounding: `biomate-immune-llm/docs/20260822_KNOWLEDGE_BAKEOFF_RESULTS.md`,
`.../program_control/KNOWLEDGE_BOTTLENECK_V1_ERROR_ANALYSIS.md`,
`.../20260915_KNOWLEDGE_INTO_ZCELL_INTEGRATION.md`, `.../KG_REGISTRY.md`; memory
`project_immune_llm_code_audit`; today `docs/20261108_0836_CST_IMMUNE_KNOWLEDGE_FEATURES_BASELINE.md`.
