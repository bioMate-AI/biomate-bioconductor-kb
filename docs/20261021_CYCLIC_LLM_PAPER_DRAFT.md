# An enrichment-trained cyclic-peptide language model: within-target ranking beyond sequence composition, its abundance-null ceiling, and a rigorous cross-target generalization negative

*Working manuscript draft — computational study, no experimental validation. Guangzhou all-atom cyclic-peptide program. Date: 2026-10-21; rescoped 2026-10-24.*

> **Scope and honesty note.** This draft reports the *own* cyclic-peptide language model (`research/guangzhou_all_atom/cyclic_llm/`). It is **distinct** from, and does not reuse the claims of, the adopted-BoltzGen "generate→verify→select" workflow manuscript (`research/guangzhou_all_atom/docs/MANUSCRIPT.md`), which uses BoltzGen unchanged and is under major revision. Every quantitative claim below traces to a named artifact. We claim exactly two things: (i) a measured, leakage-checked **within-target** binder-ranking result, and (ii) a rigorous **cross-target** generalization *negative*. We do **not** claim cross-target generalization, and we do not present score *disagreement* with an adopted generator as evidence of generator superiority.

> **RESCOPE APPLIED (2026-10-24).** The over-claims flagged by the rigor check `docs/20261021_CYCLIC_LLM_WITHIN_TARGET_SOTA_BENCHMARK.md` have now been folded into the title, abstract, §3.1 and §5 below; this note records what changed so reviewers can see the correction history. **(1) Within-target abundance null.** Because `is_binder` is essentially a threshold on display `enrichment_log2fc`, a trivial read-count/enrichment sort scores **AUC ≈ 1.0 on all four targets, and the LM does not beat this null on any** (LM AUC 0.266–0.997, below chance on hPCSK9 at 0.266). The AUC 0.94–0.96 therefore establishes "beats sequence-composition baselines on PADI4," **not** a SOTA or null-beating capability — the within-target eval is compromised by abundance/label-circularity. The defensible within-target claim now reads "beats composition baselines; does **not** beat the abundance null," and the deployable test requires a **non-circular label** (independent measured affinity, not enrichment) on **novel** sequences. **(2) "Physics-verified."** The closed-loop reward that has run (`methodology_close.py`) still uses a **measured-permeability ML oracle**, not FEP/MM-GBSA in the loop. However, as of 2026-10-24 the relative-FEP **control edge has now run** (not `dry_run`): ΔΔG = −0.18 ± 0.15 kcal/mol for the double-Y→F control, recovering the expected ≈0 (`docs/20261022_CYCLIC_LLM_CLOSED_CYCLE_CONTROLS.md` §6c). So the FEP engine is **execution-verified on a control edge** (the A2 anchor), but it is **not yet wired as the closed-loop reward** — §4/§6 are updated to say exactly this and nothing more.

---

## Abstract

De novo cyclic-peptide binder design is gated by a data problem: per-target structural or affinity binder labels are scarce, whereas mRNA-display deep-sequencing (NGS) produces **enrichment** signal at scale. We train a small (~4.8M-parameter, nanoGPT-style) autoregressive language model (LM) on display-NGS enrichment, conditioned on an enrichment-level control token, and use it as a **binder selector** via the conditional log-likelihood ratio LLR(seq) = logP(seq | ⟨e_hi⟩) − logP(seq | ⟨e_lo⟩). We report three results, two of which are deliberately negative. **(i) Within-target, beyond composition.** On a sequence-held-out PADI4 test set (n = 4000; 67 binders; base rate 1.68%) the LM ranks held-out binders at **AUC 0.951**, and the signal is **not** an amino-acid-composition artifact and **not** a near-duplicate leakage artifact: on motif-distinct binders (3-mer Jaccard < 0.5) it scores **AUC 0.940** (leakage inflation −0.011) and **+0.077 AUC over the strongest trivial baseline** (2-mer logistic 0.864). **(ii) But the within-target eval has an abundance-null ceiling it does not clear.** Because the `is_binder` label is essentially a threshold on display enrichment, a trivial read-count/enrichment sort scores **AUC ≈ 1.0 on all four display targets, and the LM does not beat this null on any** (LM AUC 0.266–0.997; below chance on hPCSK9). The within-target capability is therefore "beats sequence-composition baselines," not SOTA or null-beating; a deployable claim needs a **non-circular** label (measured affinity on novel sequences). We report this abundance-circularity explicitly as a cautionary methodological finding for display-NGS binder evaluation. **(iii) Cross-target transfer is a rigorous negative:** NULL for the enrichment-conditioned LM (leave-one-target-out conditioning effect Δ = 0.02–0.03; `target_features_matter: false`) and NEGATIVE for a BoltzGen fine-tune (mean Δiptm = −0.16 on held-out targets). We argue the defensible contribution is an honest map of where the cyclic cross-target data wall sits — and we specify, and have now begun to build, the execution-verified closed-loop experiment that would test whether that wall can be broken: its relative-FEP physics engine is **validated on a control edge** (ΔΔG = −0.18 ± 0.15 kcal/mol, recovering the expected ≈0), but is **not yet wired as the closed-loop reward**, so the cross-target closed-loop test itself remains unrun.

---

## 1. Introduction

Cyclic and macrocyclic peptides occupy a therapeutic niche between small molecules and biologics, with the ability to engage flat protein–protein interfaces. Modern ML generators (e.g. BoltzGen, RFpeptides) produce pocket-conditioned cyclic designs, but the open, hard problem is **cross-target generalization** — producing binders for a target not seen in training — where reported state of the art is a low single-digit-to-~8% hit regime. The obstacle is data: per-target structural/affinity binder labels are scarce and expensive, which caps supervised approaches.

mRNA-display selection inverts this scarcity. A single RaPID-style campaign yields deep NGS readout of how strongly each of ~10⁵–10⁶ sequences **enriches** across selection rounds — a binder-proportional signal that exists at scale without per-compound structural labels. Our thesis is that an own model trained on this *enrichment* signal is worth building precisely because it exploits the data source that actually scales, rather than adopting a generator trained on scarce structural priors.

This draft makes the narrow, defensible version of that thesis: the enrichment-trained LM is a strong **within-target** binder ranker (the regime where display conditioning has signal), and we report, with controls, that it does **not** yet transfer cross-target — nor does a fine-tuned pocket-conditioned generator. We do not adopt-and-rerank BoltzGen and call that an innovation; a prior internal review correctly noted that reranking shows score *disagreement*, not validated superiority.

## 2. Methods

**Model.** A character-level autoregressive LM over a 20-amino-acid vocabulary (nanoGPT-style; d_model = 256, 6 layers, 8 heads; ~4.8M parameters). Source: `cyclic_llm/train_cyclic_llm_v2.py`, `..._v3_1.py`.

**Training signal and conditioning.** Sequences are drawn from display-NGS data (`data/display/display_ngs_multitarget.csv.gz`; PADI4 RaPID, ~370k peptides × 5 rounds) and labeled by terminal enrichment (`enrichment_log2fc`). Each sequence is conditioned on an enrichment control token bucketed by absolute log2fc thresholds HI = 2.0 / LO = 0.0 (`cyclic_llm_selector.py`). A `--traj-train` option uses a trajectory-clean split: the "hi" bucket is monotonic clean binders and jackpot sequences are demoted to "mid", so the model learns the denoised enrichment signal rather than the ~50%-contaminated raw log2fc label.

**Selector (LLR).** Used as a binder selector, the trained LM scores each candidate by the conditional log-likelihood ratio
LLR(seq) = logP(seq | ⟨e_hi⟩) − logP(seq | ⟨e_lo⟩),
summed over **residues only** (EOS excluded, to remove a length-via-EOS confound; the sum may be length-normalized). A real binder should be more likely under the high-enrichment conditioning.

**Evaluation protocol (and its controls, which are part of the contribution).** The model is trained on a **sequence-disjoint** split (`random.Random(0).shuffle`) and LLR is evaluated against `is_binder` on the held-out split: AUC (ranking quality) and binder lift in the top 5%/10% (practical selection enrichment). To test whether the result is a trivial-feature or leakage artifact we add two controls absent from the original result:
1. **Trivial baselines** on the identical split: a 2-mer logistic, an amino-acid-composition logistic, a per-AA log-odds sum, and length-only.
2. **Leakage stratification:** for each held-out binder we compute the maximum 3-mer Jaccard similarity to any training binder, and re-evaluate on the motif-distinct subset (similarity < 0.5), i.e. binders that cannot be recovered by near-duplicate memorization.

**Cross-target evaluation.** Leave-one-target-out (LOTO): train on N−1 display targets, evaluate conditioning effect and transfer on the held-out target. For the pocket-conditioned generator, a BoltzGen fine-tune was evaluated LOTO by held-out-target iptm change (`results/boltzgen_loto_smoke_summary.json`).

**Compute.** All LM training/scoring in this draft ran on CPU (torch 2.13.0; ~0.22 s/step; ~7.5 min total for the re-score). No GPU was used.

## 3. Results

### 3.1 Within-target binder ranking (PADI4) — beats composition baselines, but does not clear the abundance null

On the sequence-held-out PADI4 test set (n = 4000; 67 binders; base rate 1.68%), the enrichment-conditioned LM used as an LLR selector ranks held-out binders with **AUC 0.959** (original run) / **0.951** (re-trained instance; the original saved no checkpoint, so the gap is training-run variance, not a different result), with top-5% binder lift **14.9× / 13.4×** and top-10% lift 8.5×. Source: `results/cyclic_llm_selector_PADI4_trajtrain.json`, `results/cyclic_llm_selector_PADI4_perseq_scores.json`.

**This AUC does not establish a SOTA or deployable capability**, for a reason that is itself the main within-target finding. The `is_binder` label is essentially a threshold on display `enrichment_log2fc`, which is recorded for every test sequence — so a trivial sort by read count / enrichment *recovers its own label* and saturates the benchmark. Against that abundance null, across all four display targets (motif-distinct eval set; `docs/20261021_CYCLIC_LLM_WITHIN_TARGET_SOTA_BENCHMARK.md`):

| target | n (motif-distinct) | binders | **LM AUC** | count-null AUC | enrichment-null AUC |
|---|---|---|---|---|---|
| PADI4 | 3988 | 55 | 0.941 | **1.000** | **1.000** |
| Abeta42 | 3691 | 37 | 0.997 | **0.999** | **1.000** |
| hIAPP | 3919 | 128 | 0.588 | **1.000** | **1.000** |
| hPCSK9 | 2734 | 134 | 0.266 | **0.867** | **0.997** |

The LM is **below the abundance null on every target** and is erratic across targets (0.266–0.997, below chance on hPCSK9). The defensible within-target claim is therefore narrow: on PADI4 the LM **beats sequence-composition baselines** (§3.2) — it captures binding signal beyond amino-acid frequency and beyond near-duplicate memorization — **but it does not beat an abundance/enrichment sort**, because the label is abundance-circular. The deployable regime (ranking *novel* candidate sequences that have **no** read count) is exactly where the null is unavailable; demonstrating capability there requires an independent, non-circular affinity label and is future work (§5, §6). We report the circularity openly as a cautionary result for how display-NGS binder classifiers should be benchmarked.

### 3.2 The result is not composition and not leakage

| Scorer | Full AUC (67 binders) | Motif-distinct AUC (3-mer Jaccard < 0.5; 55 binders) |
|---|---|---|
| **LM length-normalized LLR** | **0.9511** | **0.9405** |
| 2-mer logistic | 0.8870 | 0.8638 |
| AA-composition logistic | 0.7814 | 0.7662 |
| per-AA log-odds sum | 0.7728 | — |
| length only | 0.4049 | — |

Source: `docs/20261021_CYCLIC_LLM_WITHIN_TARGET_RIGOR_CHECK.md`.

Two controls establish the result:
- **Beyond composition.** The LM exceeds the strongest trivial baseline (2-mer logistic) by **+0.064 AUC on the full set and +0.077 on the motif-distinct subset**, and exceeds the composition logistic by ~+0.17. The win is not reducible to amino-acid frequency.
- **Not leakage.** Of 67 held-out binders, **0 are exact duplicates and 0 exceed 0.8 similarity** to any training binder; 18% exceed 0.5 (median Jaccard 0.30). Restricting to motif-distinct binders (similarity < 0.5), the LM's AUC falls by only **−0.011** (0.9511 → 0.9405). The ranking signal is genuine display-binding biochemistry the LM captures, not near-duplicate memorization.

### 3.3 Cross-target generalization — a controlled negative result

The same model does **not** transfer across targets:
- **Enrichment-conditioned LM (LOTO, held-out FIKK13; train PADI4 + hPCSK9):** conditioning effect Δ = 0.034 (hi vs lo) / 0.022 (held-out vs train-mean); the evaluation's own flag is `target_features_matter: false`. Transfer is **NULL**. Source: `results/cyclic_llm_v3_1_FIKK13_eval.json`.
- **BoltzGen fine-tune (LOTO smoke, 3 targets × 4 designs):** mean held-out **Δiptm = −0.16** (per-target −0.079 / −0.093 / −0.308); designability degrades. Fine-tuning *regresses* on unseen targets. Source: `results/boltzgen_loto_smoke_summary.json`.
- **Cheap designability surrogate (LOTO, 7 targets):** AUC 0.455 / 0.482 / 0.638 / 0.644 — near-chance to weak. Source: `results/speed_surrogate_loto.json`.

Generation remains valid and novel in the cross-target eval (validity 0.998–1.000; novelty 0.962–1.000), so the negative is a *transfer* failure, not a generation failure.

**Reading.** The cyclic cross-target data wall is deeper than target count: neither multi-target enrichment conditioning nor naive generator fine-tuning produces transfer, and the latter is actively harmful on unseen targets. This is reported as a finding, not hidden.

## 4. Discussion

What is **demonstrated** is that the enrichment-trained LM captures within-target binding signal **beyond sequence composition** and beyond near-duplicate memorization (established against trivial baselines and a leakage control). What is **not** demonstrated — and we state it plainly — is a deployable within-target *capability*: the LM does not clear the abundance/enrichment null on any of the four display targets (§3.1), because the `is_binder` label is abundance-circular. The within-target contribution is thus best read as (a) a signal-beyond-composition result on PADI4 and (b) a cautionary benchmarking finding: display-NGS binder classifiers must be scored against the abundance null, not only against composition baselines. What is **open** is cross-target generalization, which our own data shows is unsolved by the two approaches we tried.

We therefore position the execution-verified **closed loop** (physics/assay rewards from real runs training the model) as the *proposed* route to attack the cross-target wall — still **unproven as a cross-target result**. Progress since the first draft: the loop's relative-FEP physics engine is **no longer hypothetical** — its control edge has run end-to-end on AWS Batch GPU-spot and recovered the expected null (ΔΔG = −0.18 ± 0.15 kcal/mol for the double-Y→F control; `docs/20261022_CYCLIC_LLM_CLOSED_CYCLE_CONTROLS.md` §6c), validating the pmx + CaDA-Mn + BAR pipeline as an admissible reward *estimator*. But the FEP reward is **not yet wired into the DPO loop** (which still uses the permeability ML oracle), and the decisive cross-target closed-loop experiment (§6) remains deliberately **not run** — the honest prerequisite is a clean, controlled cross-target test, not another uncontrolled claim.

## 5. Limitations

1. **The within-target eval is abundance-circular and does not clear its own null.** The `is_binder` label is a threshold on display enrichment, so a trivial read-count/enrichment sort scores AUC ≈ 1.0 and the LM beats it on **no** target (§3.1). The within-target result is therefore "signal beyond sequence composition," not a deployable binder-ranking capability; across four targets the LM is also erratic (0.266–0.997). A defensible deployable claim requires a **non-circular** label (independent measured affinity) on **novel** sequences that carry no read count. The leakage-checked composition-beating result is also on **PADI4 only**; an independent-target within-target replication is required before submission.
2. **Training-run variance.** Re-trained LM AUC 0.9511 vs original 0.9592; the original selector saved no checkpoint. We now store a checkpoint and per-sequence scores, but report the result as a two-instance range, not a point estimate with a tight CI.
3. **Split design.** The held-out split is random-by-sequence; the motif-distinct (similarity < 0.5) stratification is the leakage control, not a from-scratch motif-clustered retrain. A cluster-held-out retrain is the stronger design and is noted as future work.
4. **Cross-target is unsolved.** NULL (own LM) / negative (fine-tune). We make no cross-target claim.
5. **No wet-lab validation.** Every endpoint here is computational; display enrichment is the training label, and a minimized MM-GBSA score (used elsewhere in the program) is a computational evaluator, not a measured affinity. Wet-lab remains the only non-circular endpoint.
6. **HELM/ncAA-native LM conditioning effect is not yet measured** (`train_helm_monomer_llm.py` builds; effect sizes NOT MEASURED), so ncAA-native generation is reported as capability-in-form, not a measured result.

## 6. The one experiment that would test the aspirational claim

**Question.** Can an execution-verified physics reward (MM-GBSA/FEP on real runs) break the cross-target data wall that enrichment conditioning (NULL) and BoltzGen fine-tuning (−0.16) could not?

**Design.** LOTO across ≥3 targets, ideally same display chemistry (we currently have 2 same-chemistry targets — see confound below). Train the own/fine-tuned model with the closed-loop reward on N−1 targets; generate for the held-out target; score held-out designs by the **real execution-verified physics** (not the cheap surrogate, which is near-chance).

**Metrics / mandatory controls.** Primary: held-out hit-enrichment vs the ~3–8% cross-target SOTA band *and* vs adopted BoltzGen unchanged, with per-target (not pooled) uncertainty; plus the within-target selector and random/size-matched selection at equal budget. **Success** = held-out enrichment above both the SOTA band and adopted-BoltzGen. **Refutation** = NULL/negative, reported as the data-wall result.

**Controls for the two central threats.** (a) **Chemistry confound:** in our only same-platform trio, cyclization chemistry co-varies with target, so a positive could be chemistry rather than target identity; a clean test needs ≥3 same-chemistry targets. (b) **Circularity:** the reward that *trains* must differ from the evaluator that *scores* (e.g. train on cofold-geometry reward, evaluate on independent MM-GBSA/FEP or display enrichment); wet-lab is the only fully non-circular endpoint.

**Cost/gating.** GPU; spot-only; review-before-spend; held until explicit go.

**Status (2026-10-24).** The physics-reward *estimator* is now validated: the relative-FEP **control edge is cleared** (ΔΔG = −0.18 ± 0.15 kcal/mol ≈ 0 for the double-Y→F edge; the A2 anchor that makes any candidate ΔΔG ladder admissible), run entirely on GPU-spot with the fan-out pipeline in `cyclic_llm/fep_production.py`. What remains before the §6 experiment can run is **not** the FEP engine but (a) ≥3 **same-chemistry** targets for a confound-free LOTO and (b) wiring the FEP ΔΔG as the training reward in place of the permeability oracle. Neither is done; the experiment stays unrun.

## 7. Reproducibility

- Recipe: `cyclic_llm/cyclic_llm_selector.py`; re-score: `cyclic_llm/rescore_padi4_selector.py`.
- Data: `data/display/display_ngs_multitarget.csv.gz`.
- Per-sequence LLR scores stored: `results/cyclic_llm_selector_PADI4_perseq_scores.json`.
- Result artifacts: `results/cyclic_llm_selector_PADI4_trajtrain.json`, `results/cyclic_llm_v3_1_FIKK13_eval.json`, `results/boltzgen_loto_smoke_summary.json`, `results/speed_surrogate_loto.json`.
- Supporting analysis docs: `docs/20261021_CYCLIC_LLM_INNOVATION_THESIS.md`, `docs/20261021_CYCLIC_LLM_WITHIN_TARGET_RIGOR_CHECK.md`.

*The discredited in-distribution decomposition figure is deliberately not used anywhere in this draft. No training/eval/GPU was run to produce this document.*
