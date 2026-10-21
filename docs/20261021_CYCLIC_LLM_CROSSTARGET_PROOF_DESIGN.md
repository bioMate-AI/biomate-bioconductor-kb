# Cross-target proof experiment — design & budget (DESIGN ONLY, not run)

**Date:** 2026-10-21 · Scope: the single experiment that would prove-or-refute the aspirational claim that **closed-loop execution-verified physics reward induces cross-target generalization** in the own cyclic-peptide LLM — the wall that multi-target conditioning (own-LM LOTO **NULL**) and generator fine-tuning (BoltzGen-FT LOTO **mean Δiptm −0.16**) did not break. Companions: `20261021_CYCLIC_LLM_INNOVATION_THESIS.md`, `20261021_CYCLIC_LLM_WITHIN_TARGET_RIGOR_CHECK.md`. No training/eval/GPU was run to produce this document.

---

## 1. Hypothesis

Training the own cyclic-peptide generator with a **closed-loop, execution-verified physics reward** (objective pass/fail + ΔG from *real* cofold/MM-GBSA runs, graded via `execution_grader.py` → `graded_run_store.py` → `loop_grade_bridge.py`, driven by `cyclic_llm/loop_batch.py`) on N−1 targets will produce **above-chance binder prioritization on a held-out target** — a richer, physics-grounded training signal than the display-enrichment conditioning (NULL) or iptm fine-tuning (−0.16) that failed.

This is a **high-risk** hypothesis: two prior levers on the same wall returned NULL / negative. The experiment is designed to give an honest verdict either way, because a clean negative is itself the publishable "cyclic cross-target data wall is deeper than target count / training signal" result.

## 2. Success / refutation criteria (sharp, decided before the run)

**Primary metric — held-out-target binder prioritization, leakage-safe.** On the held-out target's candidate pool, rank candidates by the trained model and measure **top-k hit-enrichment** (fraction of the top-k that are binders ÷ base binder rate) and **AUC (binder vs non-binder)**, computed ONLY on candidates **motif-distinct** from any training-target sequence (3-mer Jaccard < 0.5, the leakage-safe protocol validated in the rigor check). "Binder" on the held-out target is defined by the held-out target's own ground truth (display enrichment where available; otherwise the physics-independent label — see §5 circularity).

**SUCCESS** (all three, per-target with uncertainty, not pooled):
1. Held-out hit-enrichment **above the ~3–8% cross-target SOTA band**, by a margin exceeding its bootstrap 95% CI;
2. **Above adopted-BoltzGen** (unchanged) at equal generation+scoring budget;
3. **Above the own-LM-without-closed-loop** ablation (isolates the loop's contribution, not the base model's).

**REFUTATION** = held-out enrichment within or below the SOTA band, or not above both baselines. This outcome is reported as the honest data-wall finding; it is not a failure of the experiment.

**Powering.** 4 designs/target (the LOTO-smoke scale) is underpowered for a CI-backed claim; the real run uses ≥100 scored held-out candidates/target and ≥3 held-out targets (each as its own fold) so success is a *replicated* per-target effect, not a single lucky fold.

## 3. LOTO protocol

- **Targets.** Fold over the targets that have both (a) a trainable binder signal and (b) a structure for physics. Display-signal targets: **PADI4** (thioether), **hPCSK9** (photo-crosslink), **FIKK13** (thioether). Structural LOTO targets already exercised by the FT: **1xq7, 3g5v, 4b8y**. Minimum viable: 3 folds; preferred: 5.
- **Per fold:** (i) train the own/FT model on N−1 targets with the closed-loop execution-verified reward (`loop_batch.run_round`: propose → `physics_batch` cofold → `execution_grader` reward → update); (ii) generate for the held-out target; (iii) score the held-out candidates by the **real execution-verified physics** — NOT the cheap surrogate, which is near-chance here (`speed_surrogate_loto.json`: LOTO AUC 0.455–0.644).
- **Fixed budget parity:** every arm (trained model, BoltzGen, no-loop ablation, random) gets the **same** generation count and the **same** physics-scoring budget on the held-out target, so a win is not a budget artifact.

## 4. Metric definition (leakage-safe)

- Held-out candidate pool scored once by physics → binder labels (held-out ground truth).
- Model ranks the pool; compute AUC + top-5%/10% enrichment on the **motif-distinct subset** (sim < 0.5 to all training-target sequences), reusing `rescore_padi4_selector.py` + the similarity-stratification from the rigor check.
- Report per-target with bootstrap CIs; never pool across targets (the pooled-Spearman error the committee flagged).

## 5. Controls (a reviewer will demand all three)

1. **Chemistry confound (the hard one).** Cyclization chemistry co-varies with target: PADI4 & FIKK13 are **thioether**, hPCSK9 is **photo-crosslink** (`cyclic_llm_v3_1_FIKK13_eval.json`: `train_cyc=[thioether, photo_crosslink]`, `same_chem_train=false`). A cross-target "win" on a mixed-chemistry fold could be the model learning *chemistry*, not *target transfer*. **Mitigation:** the headline fold must be **same-chemistry** — hold out FIKK13 (thioether) training on *thioether-only* targets. We currently have only **2 thioether targets (PADI4, FIKK13)**, so a clean ≥3 same-chemistry LOTO is **underpowered today**; acquiring/curating ≥1 more thioether-display target (or restricting the claim to the 2-target same-chem fold with explicit caveat) is a prerequisite. Mixed-chemistry folds are reported only as stratified secondary analyses.
2. **Circularity (train-reward ≠ eval-metric).** If the physics that *trains* the model is the physics that *scores* the held-out set, a "win" is tautological. **Separation enforced:** train the loop reward on **cofold-geometry + MM-GBSA** (`cyclic_peptide_cofold`, `cyclic_peptide_mmgbsa` contracts); **evaluate** the held-out set on an **independent endpoint** — either (a) **held-out display enrichment** (orthogonal experimental signal, where available) or (b) **FEP ΔΔG** on a held-out shortlist (a different estimator than the MM-GBSA training reward). Wet-lab remains the only fully non-circular endpoint and is flagged as the eventual validation.
3. **Baselines (equal budget):** adopted BoltzGen (unchanged), own-LM-without-closed-loop (the published NULL model), composition/2-mer trivial baseline (held the within-target signal to −0.077 below the LM; must be beaten cross-target too), and random/size-matched selection.

## 6. Compute budget (for the later go/no-go)

Dominated by cofold on the held-out candidate pools; MM-GBSA on shortlists; FEP reserved as the independent evaluator on a few top candidates only (FEP is far too expensive to screen with).

| Item | Unit cost (spot) | Count | Subtotal |
|---|---|---|---|
| LM/FT closed-loop training | small GPU, hours (model is ~few-M params) | 3–5 folds | ~1–2 GPU-days |
| Cofold scoring (Boltz) | ~3–6 GPU-min/candidate | ~100–300/target × 3–5 targets ≈ 500–1500 | ~4–12 GPU-days |
| MM-GBSA (shortlist) | ~GPU-min–hr/candidate | top ~20/target × 3–5 | ~1–3 GPU-days |
| FEP (independent evaluator, top only) | ~1–2 GPU-days/edge | ~2–4 edges total | ~3–8 GPU-days |
| **Total** | — | — | **~10–25 GPU-days spot ≈ $150–600** (GPU FEP legs dominate the upper end) |

**Staging (cheap → expensive; stop-early gates):**
- **Slice 0 (≈1–2 GPU-days, ~$30–60):** ONE same-chemistry held-out fold (FIKK13), ~100 candidates, **cofold-only** reward + cofold/MM-GBSA eval. Early read: does closed-loop training move held-out ranking **at all** above the NULL baseline? If flat (consistent with the NULL prior), **stop** — report the reinforced data-wall negative. This is the recommended first commitment.
- **Slice 1:** if Slice 0 shows signal, expand to ≥3 folds + the independent FEP/display evaluator for the circularity-clean verdict.
- Spot-only, self-terminating, review-before-spend, guarded until explicit go (consistent with the αvβ6 FEP gating already in place).

## 7. Risks & honest odds

- **Prior is against us.** Conditioning → NULL (Δ 0.02–0.03), FT → −0.16, surrogate → near-chance. The closed-loop reward is a *genuinely different* (richer, physics-grounded, iteratively-selected) signal, so it is not strictly the same lever — but the data wall is real. **Honest odds of a clean SOTA-beating cross-target win: low, ~15–30%.** More likely: partial or NULL.
- **A negative is still worth the Slice-0 spend** (~$30–60): it converts "we didn't try" into "closed-loop execution-verified reward also does not break the cyclic cross-target wall at this scale/chemistry" — a defensible, publishable frontier result that strengthens the honest thesis rather than weakening it.
- **Confound + power** (§5) mean even a positive needs the same-chemistry ≥3-target fold before it can be claimed; today's 2 thioether targets cap the clean claim.
- **Do not let a positive Slice-0 short-circuit the controls** — circularity (§5.2) and chemistry (§5.1) must clear before any cross-target claim is made externally.

---

*Design only. Every target/number traces to `research/guangzhou_all_atom/results/` artifacts. The within-target contribution (AUC 0.9405 leakage-safe, +0.077 over baseline) stands independently and is not contingent on this experiment.*
