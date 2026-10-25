# Enrichment-trained cyclic-peptide language models beat sequence-composition baselines but not an abundance null: a cautionary display-NGS benchmark and a preliminary cross-target generalization negative

*Working manuscript draft — computational study, no experimental validation. Guangzhou all-atom cyclic-peptide program. Date: 2026-10-21; rescoped 2026-10-24; committee-revision P0 2026-10-24.*

> **Scope and honesty note.** This draft reports the *own* cyclic-peptide language model (`research/guangzhou_all_atom/cyclic_llm/`). It is **distinct** from a separate adopted-BoltzGen "generate→verify→select" workflow that uses BoltzGen unchanged, and does not reuse its claims. Every quantitative claim below traces to a named artifact. We claim exactly two things: (i) a leakage-checked **within-target, beyond-sequence-composition** ranking result on one target (which does **not** clear an abundance null), and (ii) a **preliminary, underpowered cross-target** generalization *negative*. We do **not** claim cross-target generalization, a deployable within-target capability, or that score *disagreement* with an adopted generator is evidence of generator superiority.

> **RESCOPE APPLIED (2026-10-24).** The over-claims flagged by the rigor check `docs/20261021_CYCLIC_LLM_WITHIN_TARGET_SOTA_BENCHMARK.md` have now been folded into the title, abstract, §3.1 and §5 below; this note records what changed so reviewers can see the correction history. **(1) Within-target abundance null.** Because `is_binder` is essentially a threshold on display `enrichment_log2fc`, a trivial read-count/enrichment sort scores **AUC ≈ 1.0 on all four targets, and the LM does not beat this null on any** (LM AUC 0.266–0.997, below chance on hPCSK9 at 0.266). The AUC 0.94–0.96 therefore establishes "beats sequence-composition baselines on PADI4," **not** a SOTA or null-beating capability — the within-target eval is compromised by abundance/label-circularity. The defensible within-target claim now reads "beats composition baselines; does **not** beat the abundance null," and the deployable test requires a **non-circular label** (independent measured affinity, not enrichment) on **novel** sequences. **(2) "Physics-verified."** The closed-loop reward that has run (`methodology_close.py`) still uses a **measured-permeability ML oracle**, not FEP/MM-GBSA in the loop. However, as of 2026-10-24 the relative-FEP pipeline **executed one control edge** (not `dry_run`): ΔΔG = −0.18 ± 0.15 kcal/mol for the double-Y→F control, consistent with the expected ≈0 (`docs/20261022_CYCLIC_LLM_CLOSED_CYCLE_CONTROLS.md` §6c; artifacts `cyclic_llm/results/fep_ctrl_build1_ddg/`). This is a **null-bias check only** — not an accuracy or dynamic-range validation (single-replica BAR error; the edge does not perturb the MIDAS-coordinating RGD aspartate) — and the FEP reward is **not yet wired into the loop**. §4/§6 state exactly this. *(A committee peer review on 2026-10-24 — `docs/20261024_MANUSCRIPT_COMMITTEE_REVIEW.md` — drove a further P0 pass: title/abstract reframed, "rigorous" dropped, cross-target downgraded to underpowered, the positive scoped to PADI4, FEP wording tempered, artifacts committed.)*

---

## Abstract

De novo cyclic-peptide binder design is gated by a data problem: per-target structural or affinity binder labels are scarce, whereas mRNA-display deep-sequencing (NGS) produces **enrichment** signal at scale. We train a small (~4.8M-parameter, nanoGPT-style) autoregressive language model (LM) on display-NGS enrichment, conditioned on an enrichment-level control token, and use it as a **binder selector** via the conditional log-likelihood ratio LLR(seq) = logP(seq | ⟨e_hi⟩) − logP(seq | ⟨e_lo⟩). We report three results, two of which are deliberately negative. **(i) Within-target, beyond composition.** On a sequence-held-out PADI4 test set (n = 4000; 67 binders; base rate 1.68%) the LM ranks held-out binders at **AUC 0.951**, and the signal is **not** an amino-acid-composition artifact and **not** a near-duplicate leakage artifact: on motif-distinct binders (3-mer Jaccard < 0.5) it scores **AUC 0.940** (leakage inflation −0.011) and **+0.077 AUC over the strongest trivial baseline** (2-mer logistic 0.864). **(ii) But the within-target eval has an abundance-null ceiling it does not clear.** Because the `is_binder` label is essentially a threshold on display enrichment, a trivial read-count/enrichment sort scores **AUC ≈ 1.0 on all four display targets, and the LM does not beat this null on any** (LM AUC 0.266–0.997; below chance on hPCSK9). The within-target capability is therefore "beats sequence-composition baselines," not SOTA or null-beating; a deployable claim needs a **non-circular** label (measured affinity on novel sequences). We report this abundance-circularity explicitly as a cautionary methodological finding for display-NGS binder evaluation. **(iii) Cross-target transfer is a preliminary, underpowered negative:** NULL for the enrichment-conditioned LM (a single held-out target from a two-target training set; conditioning effect Δ = 0.02–0.03, `target_features_matter: false`) and NEGATIVE for a BoltzGen fine-tune (mean Δiptm = −0.16 over 4 designs × 3 held-out targets, no CI). These are smoke-scale and cannot distinguish "no transfer" from "underpowered to detect transfer." We argue the defensible contribution is a cautionary display-NGS benchmark plus a preliminary map of where the cyclic cross-target data wall sits — and we specify, and have begun to build, the closed-loop experiment that would test whether that wall can be broken: its relative-FEP physics engine has **executed one control edge** (ΔΔG = −0.18 ± 0.15 kcal/mol, consistent with the expected ≈0 within a single-replica BAR error that understates true uncertainty — a null-bias check, **not** an accuracy or dynamic-range validation), and is **not yet wired as the closed-loop reward**, so the cross-target closed-loop test itself remains unrun.

---

## 1. Introduction

Cyclic and macrocyclic peptides occupy a therapeutic niche between small molecules and biologics, with the ability to engage flat protein–protein interfaces. Modern ML generators (e.g. BoltzGen, RFpeptides) produce pocket-conditioned cyclic designs, but the open, hard problem is **cross-target generalization** — producing binders for a target not seen in training — where reported hit rates sit in a low single-digit-to-~8% regime (program survey with primary citations: `docs/20261001_CYCLIC_PEPTIDE_SOTA_LANDSCAPE.md`; to be replaced by direct citations before submission). The obstacle is data: per-target structural/affinity binder labels are scarce and expensive, which caps supervised approaches.

mRNA-display selection inverts this scarcity. A single RaPID-style campaign yields deep NGS readout of how strongly each of ~10⁵–10⁶ sequences **enriches** across selection rounds — a binder-proportional signal that exists at scale without per-compound structural labels. Our thesis is that an own model trained on this *enrichment* signal is worth building precisely because it exploits the data source that actually scales, rather than adopting a generator trained on scarce structural priors.

This draft makes the narrow, defensible version of that thesis: the enrichment-trained LM is a **within-target** binder ranker that, on one target, beats sequence-composition baselines (the regime where display conditioning has signal) — though, as we show, it does **not** clear an abundance null — and we report, with controls, that it does **not** transfer cross-target, nor does a fine-tuned pocket-conditioned generator. We do not adopt-and-rerank BoltzGen and call that an innovation: reranking shows score *disagreement*, not validated superiority.

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

Two controls establish the result **on PADI4**:
- **Beyond composition.** The LM exceeds the strongest trivial baseline (2-mer logistic) by **+0.064 AUC on the full set and +0.077 on the motif-distinct subset**, and exceeds the composition logistic by ~+0.17. The win is not reducible to amino-acid frequency.
- **Not leakage.** Of 67 held-out binders, **0 are exact duplicates and 0 exceed 0.8 similarity** to any training binder; 18% exceed 0.5 (median Jaccard 0.30). Restricting to motif-distinct binders (similarity < 0.5), the LM's AUC falls by only **−0.011** (0.9511 → 0.9405). The ranking signal is a genuine display-**enrichment** signal beyond composition and near-duplicate memorization (enrichment convolves affinity with display/translation efficiency and stability, so it is not necessarily affinity).

**Scope of the composition-beating result (important).** This is a **single-target** result. Across the four display targets the LM does **not** robustly beat the 2-mer logistic — it wins on 2 of 4 (PADI4, Abeta42); on hIAPP (0.588) and hPCSK9 (0.266) it is weaker, and the 2-mer never drops below ~0.60 while the LM ranges 0.27–0.98. The "beyond composition" claim is therefore specific to PADI4 (and, on AUC, Abeta42); an independent-target replication is required (see §5.1) before it can be stated as a general within-target property.

### 3.3 Cross-target generalization — a preliminary, underpowered negative

The same model does **not** show cross-target transfer in the (small-scale) tests we ran. All three probes below are **smoke-scale**: none carries a CI or a power analysis, so each is consistent with both "no transfer" and "underpowered to detect transfer." We report them as such.
- **Enrichment-conditioned LM (LOTO, held-out FIKK13; train PADI4 + hPCSK9 — a 2→1 probe):** conditioning effect Δ = 0.034 (hi vs lo) / 0.022 (held-out vs train-mean); `target_features_matter: false`. Transfer is **NULL** — but the same flag fires in-distribution (conditioning barely moves the model at all), so this is equally consistent with a model that underuses its control tokens. A single held-out target from a two-target train set cannot support a general claim. Source: `results/cyclic_llm_v3_1_FIKK13_eval.json`.
- **BoltzGen fine-tune (LOTO smoke, 3 targets × 4 designs = 12 designs total):** mean held-out **Δiptm = −0.16**, but the mean is driven by one target (per-target −0.079 / −0.093 / **−0.308**), with no CI; ipTM is a predicted-structure confidence metric, not binding. Suggestive of regression on unseen targets, not established. Source: `results/boltzgen_loto_smoke_summary.json`.
- **Cheap designability surrogate (LOTO; 7-target dataset, 5 targets evaluated, 1 NaN → 4 with AUC):** the result is **arm- and target-dependent, not uniformly near-chance**: sequence-feature AUC 0.455 / 0.482 / 0.638 / 0.644; design-feature AUC up to **0.873** (0.546 / 0.170 / 0.704 / 0.873); combined 0.021–0.846. We report all three arms; the surrogate is too unstable to serve as the held-out scorer in the §6 experiment. Source: `results/speed_surrogate_loto.json`.

Generation remains valid and novel in the cross-target eval (validity 0.998–1.000; novelty 0.962–1.000), so the negative is a *transfer* failure, not a generation failure — though for a character-level model over a 20-letter alphabet, validity ≈ 1 only shows well-formed strings, not foldable/cyclizable designs.

**Reading.** On these small-scale tests, neither multi-target enrichment conditioning nor naive generator fine-tuning produced cross-target transfer. We phrase this as a **preliminary indication** that the cyclic cross-target data wall is not closed by target count alone — a hypothesis for the powered §6 experiment, not an established result.

## 4. Discussion

What is **demonstrated** is that the enrichment-trained LM captures within-target binding signal **beyond sequence composition** and beyond near-duplicate memorization (established against trivial baselines and a leakage control). What is **not** demonstrated — and we state it plainly — is a deployable within-target *capability*: the LM does not clear the abundance/enrichment null on any of the four display targets (§3.1), because the `is_binder` label is abundance-circular. The within-target contribution is thus best read as (a) a signal-beyond-composition result on PADI4 and (b) a cautionary benchmarking finding: display-NGS binder classifiers must be scored against the abundance null, not only against composition baselines. What is **open** is cross-target generalization, which our own data shows is unsolved by the two approaches we tried.

We therefore position the **closed loop** (physics/assay rewards from real runs training the model) as the *proposed* route to attack the cross-target wall — still **unproven as a cross-target result**. Progress since the first draft: the loop's relative-FEP physics engine is **no longer hypothetical** — one control edge has run end-to-end on AWS Batch GPU-spot and recovered the expected null (ΔΔG = −0.18 ± 0.15 kcal/mol for the double-Y→F control; `docs/20261022_CYCLIC_LLM_CLOSED_CYCLE_CONTROLS.md` §6c). We are careful about what this shows: it is a **null-bias check** — the alchemical bookkeeping + CaDA-Mn metal model do not inject a large spurious bias on this one edge — **not** an accuracy or dynamic-range validation. The ±0.15 is a single-replica BAR analytical error that understates true uncertainty; the edge perturbs Tyr, not the RGD-aspartate that coordinates the MIDAS metal, so it does not exercise the metal model where a binding reward would depend on it; and a near-zero edge cannot show the engine *resolves* the 0.5–2 kcal/mol differences a ranking needs. A proper validation requires thermodynamic-cycle closure and a known-nonzero edge. The FEP reward is also **not yet wired into the DPO loop** (which still uses the permeability ML oracle), and the decisive cross-target closed-loop experiment (§6) remains deliberately **not run**.

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

**Metrics / mandatory controls.** Primary: held-out hit-enrichment vs the ~3–8% cross-target SOTA band (sourced in `docs/20261001_CYCLIC_PEPTIDE_SOTA_LANDSCAPE.md`) *and* vs adopted BoltzGen unchanged, with per-target (not pooled) uncertainty; plus the within-target selector and random/size-matched selection at equal budget. **Success** = held-out enrichment above both the SOTA band and adopted-BoltzGen. **Refutation** = NULL/negative, reported as the data-wall result.

**Controls for the two central threats.** (a) **Chemistry confound:** in our only same-platform trio, cyclization chemistry co-varies with target, so a positive could be chemistry rather than target identity; a clean test needs ≥3 same-chemistry targets. (b) **Circularity:** the reward that *trains* must differ from the evaluator that *scores* (e.g. train on cofold-geometry reward, evaluate on independent MM-GBSA/FEP or display enrichment); wet-lab is the only fully non-circular endpoint.

**Cost/gating.** GPU; spot-only; review-before-spend; held until explicit go.

**Status (2026-10-24).** The relative-FEP pipeline **executed one control edge** on GPU-spot (ΔΔG = −0.18 ± 0.15 kcal/mol, consistent with the expected ≈0 for the double-Y→F edge; fan-out pipeline `cyclic_llm/fep_production.py`; artifacts `cyclic_llm/results/fep_ctrl_build1_ddg/`). This is a **null-bias check only** — it shows the engine runs and does not grossly misbehave on one null edge; it does **not** validate accuracy or dynamic range (single replica, 0.5 ns/window, BAR analytical error only), and the edge does not perturb the MIDAS-coordinating RGD aspartate. Before the §6 experiment can run we still need: (a) a true machinery validation (cycle closure + a known-nonzero edge, ideally moving the coordinating residue); (b) ≥3 **same-chemistry** targets for a confound-free LOTO; and (c) wiring the FEP ΔΔG as the training reward in place of the permeability oracle. None is done; the experiment stays unrun.

## 7. Reproducibility

All paths are repo-relative under `research/guangzhou_all_atom/`.
- Recipe: `cyclic_llm/cyclic_llm_selector.py`; re-score: `cyclic_llm/rescore_padi4_selector.py`.
- Data: `data/display/display_ngs_multitarget.csv.gz`.
- Per-sequence LLR scores: `results/cyclic_llm_selector_PADI4_perseq_scores.json`.
- Result artifacts: `results/cyclic_llm_selector_PADI4_trajtrain.json` (note: its stored verdict string "WIN" predates the abundance-null analysis and is **superseded** — see the SOTA benchmark doc), `results/cyclic_llm_v3_1_FIKK13_eval.json`, `results/boltzgen_loto_smoke_summary.json`, `results/speed_surrogate_loto.json`, and the per-target abundance-null evaluations `results/*_leakagesafe.json` (PADI4, Abeta42, hIAPP, hPCSK9).
- FEP control-edge ΔΔG: `cyclic_llm/results/fep_ctrl_build1_ddg/{ddg_result.json,bar_solvent.log,bar_complex.log}` (driver `cyclic_llm/fep_production.py`).
- Authoritative analysis doc: `docs/20261021_CYCLIC_LLM_WITHIN_TARGET_SOTA_BENCHMARK.md` (the abundance-null benchmark, which **supersedes** the earlier `docs/20261021_CYCLIC_LLM_WITHIN_TARGET_RIGOR_CHECK.md` "win is real and leakage-safe" conclusion); thesis context `docs/20261021_CYCLIC_LLM_INNOVATION_THESIS.md`.
