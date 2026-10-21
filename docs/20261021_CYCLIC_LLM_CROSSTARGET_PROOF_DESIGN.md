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

---

## 8. Slice-0 execution status (2026-10-21)

**First attempt to actually feed the loop the cross-target question — and it surfaced a real setup finding.**

- **Finding (important):** FIKK13 has **no prepped receptor `target_spec`** — `target_spec.load_spec("FIKK13")` → False, so the standard closed loop (`physics_batch.dispatch_cofold`) **cold-starts** on it. The loop was only ever wired for prepped αvβ6-type targets, **not the mRNA-display targets the LM trains on**. That is the concrete "built-not-fed" gap for the cross-target question: the cofold reward could not reach FIKK13 through the normal path.
- **Resolution (manual path, validated):** the FIKK13 target sequence **is** available (`data/display/target_proteins.json`: UniProt A0A143ZWL4, 561 aa). `cyclic_llm/slice0_fikk13_cofold.py` builds the cofold input manually (receptor chain A = FIKK13 + cyclic peptide chain P) and reuses `json_to_boltz_yaml.py` + `physics_batch._boltz_command` on the same spot GPU job-def. Boltz YAML build **validated locally** (rc=0).
- **Candidate manifest:** `results/slice0_fikk13_manifest.json` — 100 distinct candidates (**38 display binders + 62 length-matched non-binders**). Independent endpoint = display `is_binder`; training reward = cofold geometry (iptm/pTM) — kept separate (circularity control §5.2).
- **Cost:** full sample ≈ 100 cofolds × ~15 GPU-min (561-aa receptor) ≈ 25 GPU-hr ≈ **$38–50 spot** — within the Slice-0 budget.
- **Submitted (review-before-spend: smoke first):** 3-cofold smoke on `biomate-gpu-spot-queue` to prove the custom path runs end-to-end before the full sample — jobs `2eb297b8…` (B000 binder), `df02e0d5…` (B001 binder), `a99502bf…` (N000 nonbinder), all **RUNNABLE** (awaiting spot GPU). `results/slice0_fikk13_cofold_smoke_jobs.json`.
- **NULL baseline (established):** `cyclic_llm_v3_1_FIKK13_eval.json` — `cross_target_transfer: NULL`, `target_features_matter: false` (own-LM-without-loop does not discriminate FIKK13 binders cross-target).
- **Verdict: PENDING — cannot complete in one pass (honest).** The decisive read (does cofold-geometry rank the 38 display binders above the NULL/chance baseline on the independent endpoint?) requires the cofold jobs to COMPLETE (spot-gated) and `complex.cif`/iptm per candidate. Next steps once the smoke confirms the path: `--full` (100 cofolds), then AUC/enrichment of cofold-iptm vs display `is_binder` on the motif-distinct subset, vs NULL (~chance) and vs adopted-BoltzGen. **Flat vs NULL remains a valid refutation (publishable data-wall negative) — no fabricated improvement.**
- **n=1 fold caveat:** FIKK13 is one held-out target; this is a directional read, not the clean ≥3-same-chemistry-target claim (§5.1 — only 2 thioether targets exist today).

### 8.1 CIRCULARITY CORRECTION (2026-10-21) — the endpoint is severely circular; baseline is the abundance null, not chance

A within-target SOTA benchmark found `is_binder` is essentially a **threshold on display enrichment**, and a trivial **read-count/abundance null recovers it at AUC≈1.0**. The Slice-0 endpoint is the same FIKK13 `is_binder`, so "cofold beats chance (0.5)" would be meaningless and potentially circular. Measured on the FIKK13 data:

- `is_binder` is a clean enrichment threshold (**min binder enrichment 3.46 > max non-binder 3.32**).
- **Read count trivially separates:** binder median count **89** vs non-binder median **3**; an abundance null ≈ **AUC 1.0**.

**Fix applied** (`slice0_fikk13_cofold.py::load_candidates`): the eval set is now **abundance (read-count) matched** — restricted to the overlap window count∈[21,107] and **bin-equalized** so each count bin has equal binders/non-binders. This drives the **abundance-null AUC to 0.500** (verified), making cofold-geometry — which never sees read counts — a **non-circular** test. The baseline to beat is this abundance null, reported explicitly, **not** chance.

- **Circularity-safe set:** **13 binders + 13 non-binders** (n=26), abundance-null AUC = **0.500**, cost ≈ **$10–13 spot**. Manifest `results/slice0_fikk13_manifest.json` carries the `circularity` block (window, null AUC).
- **Honest cost of cleanliness:** forcing the null to 0.5 collapses the usable set to **n=13/class** — statistically **underpowered** (wide CIs; a cofold AUC would need to be large to exclude 0.5). The previous length-matched 100-candidate set was **circular** (abundance null ≈ 1.0) and is **not used**.
- **Key methodological finding:** a *well-powered* non-circular cross-target read is **not cleanly constructible from enrichment-labeled display sequences** — the only abundance-clean subset is tiny. A clean cross-target claim ultimately needs **measured-affinity ground truth or truly novel designs**, not display `is_binder`. This is a publishable methodological result in its own right.
- **Revised verdict rule:** cofold-iptm AUC is reported **against the 0.500 abundance null** on the matched set (with n=13/class CIs). Flat/at/below the null = valid data-wall negative, reported straight. A "win" that only beats chance, or that rides residual abundance/provenance, is **not** claimed. Read still PENDING cofold completion (smoke-gated, spot-gated).
