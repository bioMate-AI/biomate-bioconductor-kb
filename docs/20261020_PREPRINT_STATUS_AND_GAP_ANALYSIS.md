# Preprint status & gap analysis — closed-loop cyclic-peptide design from execution-verifiable rewards

**Date:** 2026-10-20 · Internal, honest assessment. Not a marketing document and not the preprint itself.
Purpose: (a) a faithful record of what the research program has actually built and measured, and (b) a
rigorous gap analysis of what separates the current state from a credible preprint that would stand as a
good research paper. **The gap analysis (§5) is the centerpiece.**

**Status tags used throughout** (applied to every capability claim):
`MEASURED` (a real result/number exists, traceable to a committed artifact) ·
`BUILT-NOT-RUN` (code exists, validated on CPU/preflight, no real result yet) ·
`DISPATCHED-GATED` (submitted to compute, waiting on spot capacity) ·
`DESIGN-ONLY` (protocol/plan, no code run).

**Integrity rules obeyed here:** every quantitative claim traces to a file/commit or is marked
NOT-YET-MEASURED; no fabricated numbers or citations; the discredited in-distribution decomposition
"0.36→0.73" is **not** cited (leakage-inflated / in-distribution — excluded on principle); only
out-of-generator / held-out numbers are used as results.

---

## 1. Abstract / thesis (honestly scoped)

We describe a closed-loop system that is intended to *learn to design cyclic peptides from
execution-verifiable rewards*: an own (small, privately deployable) model proposes candidate
macrocycles (HELM/monomer sequences); a physics stack grades each candidate by what it objectively
*produces* — a Boltz-2 co-folded bound complex, an MM-GBSA relative binding ΔG, and, for the admissible
ranking, a relative FEP ΔΔG — and the graded runs become a dense, un-gameable training signal (RLVR),
inverting the field's usual dependence on scarce human-labeled affinity/co-structure data. The αvβ6
(RGD/MIDAS Mn²⁺ radioligand) and PD-L1 (PD-1/PD-L1 PPI blocker) macrocycle program is the demonstration
domain. **As of this writing the system is built and its components are individually validated, but the
central empirical claim — that the loop improves design against proper controls — is not yet
demonstrated with measured results.** This document states exactly what is and is not in hand.

---

## 2. Contributions & novelty positioning (vs the literature)

What is genuinely new vs where we apply known methods:

| Element | Prior art | Our position |
|---|---|---|
| **Execution-verifiable reward for peptide design** | RLVR / verifiable-rewards is established in code/math LLMs; in molecular design the dominant "oracle" is a self-consistency refold (verifier-biased; only ~43% of de-novo designs confirm experimentally; swapping the verifier changes the measured success rate — `20261005_INNOVATION_THESIS_CYCLIC_LLM.md` #4) | **Candidate contribution:** a reward derived from *what a physics run actually emitted* (contract-checked artifacts: `complex.cif`, `mmgbsa_result.json{dG_bind_kcal_mol,target}`, `assay_result.json`) mapped to a dense monotone scalar over an execution ladder — not a similarity/LLM judge and not a refold of the same prior. This is the piece most likely to be publishable *if* a result backs it. |
| **Boltz-2 / BoltzGen co-fold** | Boltz-2 triage-grade; **excludes peptides + protein–protein** from its affinity model; BoltzGen authors explicitly *do not* make the zero-shot claim | Applied as-is as the pose/geometry gate; we do **not** claim improvement to the folding model. Used as a weak structure prior, not the headline. |
| **REINVENT4 / Saturn generative design** | Established generative policies | **Not yet used** — `loop.revise` is still a symbolic stand-in; a policy swap is future work, not a contribution. |
| **OpenFE / pmx relative FEP** | Standard relative alchemical FEP | Applied, not invented. Our only wrinkle is combining it with a metal-bridged integrin interface + head-to-tail cyclic peptide (below). |
| **CaDA metal model (Duarte et al., *J. Phys. Chem. B* 2014, 118, 4351; octahedral nonbonded dummy, after Åqvist & Warshel 1990)** | Published, validated for MD + FEP | Applied verbatim (sourced parameters, no fabrication). Our contribution is only the *engineering* of getting it to grompp-parse in a cyclic-peptide + integrin assembly — not a new force field. |
| **Cyclic-peptide design SOTA / cross-target generalization** | Honest novel-target ceiling ~3–8% confirmed hit *with* motif-reuse/hotspots (BoltzProt-1 ~3.3→8.0%, RFdiffusion ~7%); RFpeptides canonical-only; permeability surrogates cap R²≈0.3–0.65 | We **reproduce the frontier bound**, not beat it (§4): our cross-target transfer is NULL/near-random, *consistent with the field*. The defensible regime is within-target multi-objective + closed-loop, which SOTA defers. |

**Honest novelty summary.** The defensible novel claim is the *method*: execution-verified reward as the
training signal for a chemistry-language peptide designer, closing an orthogonal-verification loop instead
of a self-consistency oracle. Everything else (co-fold, FEP, CaDA, generative policy) is applied prior art.
**The novelty is currently a system/architecture claim; it is not yet an empirical claim**, because no
measured result yet shows the loop changing design quality (§4–5).

---

## 3. System / methods — what is actually built (component by component)

All paths under `research/guangzhou_all_atom/` unless noted; grader/store under `evaluation/local_trial/`.

| Component | Path | What it does | Status | Evidence |
|---|---|---|---|---|
| Execution grader | `evaluation/local_trial/execution_grader.py` | Objective PASS/FAIL + tier ladder (`crashed→no_outputs→empty_outputs→missing_required→content_invalid→pass`) from what a run emitted; per-workflow CONTRACTS incl. `cyclic_peptide_cofold`→`complex.cif`, `cyclic_peptide_mmgbsa`→`mmgbsa_result.json{dG_bind_kcal_mol,target}`, `cyclic_peptide_assay`→`assay_result.json{target,binding_dG}` | `BUILT-NOT-RUN` (CPU-validated) | commit `ee3fea0ac`, `de1b087e6` |
| Graded-run store + reward | `evaluation/local_trial/graded_run_store.py` | SQLite store of graded runs; monotone `TIER_REWARD`∈[0,1] (asserted monotone along `TIERS`); `get_reward(run_id)` for RLVR | `BUILT-NOT-RUN` (CPU self-test) | commit `ee3fea0ac` |
| Loop↔reward bridge | `cyclic_llm/loop_grade_bridge.py` | `record_scored_run` / `record_round` → `run_from_outputs` seam → store; pending candidates skipped (no fabricated score); `--selftest` passes CPU end-to-end | `BUILT-NOT-RUN` (CPU self-test PASS) | commit `de1b087e6` |
| Loop driver | `cyclic_llm/loop_batch.py::run_round` | propose → cofold Batch dispatch → `fetch_result` → grade → reward; per-candidate `run_id` (distinct S3 prefix) | `DISPATCHED-GATED` | commits `5d244bfaa`, `d3226beab` |
| Cofold dispatch | `cyclic_llm/physics_batch.py`, `json_to_boltz_yaml.py` | Boltz-2 cofold to AWS Batch (spot), spec-derived input incl. metal (Mn) cofactors | `DISPATCHED-GATED` | commits `ba6908493`, `a51cbd91e` |
| FEP dispatch seam | `cyclic_llm/fep_batch.py` | GROMACS relative-FEP to Batch (spot); `--submit` **guarded** by a `FEP_INPUTS_READY` sentinel to prevent a predicted-failure spend | `BUILT-NOT-RUN` | commits `259e3b812`, `12c405919` |
| CaDA Mn topology | `fep/forcefield/cada_mn.itp` | Sourced Duarte 2014 octahedral Mn²⁺ dummy model; `fep/validate_cada_itp.py`→`GROMPP_EQUIV_OK` (7 atoms, 18 bonds, 15 angles {180°:3,90°:12}, net charge +2.000, mass 54.94) | `BUILT-NOT-RUN` (validated) | commit `60cbda260` |
| FEP full-complex preflight | `fep/preflight/preflight_in_container.sh` + `launch_preflight.sh` | In-container `gmx grompp` of peptide topology + head-to-tail cyclization + full receptor+CaDA-Mn complex | `BUILT-NOT-RUN` (preflight OK — see §4) | commits `0e982a024`→`12c405919` |
| Own-model SFT (DB-gold) | S3 `sft_gold_adapter` (Qwen3.5-9B QLoRA) | Supervised fine-tune on DB-gold; routing proposer | `MEASURED` | `20261015_BENCHMARK_COMPARISON_OWN_LLM_VS_FRONTIER.md` |
| GRPO (RLVR) | `evaluation/local_trial/train_grpo_decomp.py` | GRPO with gold-free structural/execution reward; start policy `sft_gold` | `DISPATCHED-GATED` (capacity-held; auto-fire armed) | `20261015_*` |
| Generative policy for `loop.revise` | — | REINVENT4/Saturn swap | `DESIGN-ONLY` | — |

**Design-only (protocol, not run):** the relative-FEP ΔΔG protocol itself (dual-topology, both legs,
12-window HREX, ≥5 ns/window, 3 replicas, A2 control-anchored) — `20261019_AVB6_CADA_AND_FEP_SETUP.md`,
`20261019_AVB6_FEP_CONTROL_EDGE_REVIEW.md`.

---

## 4. Current empirical status — the brutally honest results inventory

**What has actually produced a trustworthy number, and what has not.**

### 4.1 The closed-loop / FEP core — NO design result yet
- **FEP control edge (αvβ6, Trivehexin-mono↔avebehexin, Y1F+Y7F):** the full-complex `gmx grompp`
  **preflight passes** (`STAGE_Fgrompp:OK`, receptor+CaDA-Mn complex, 16,289 atoms; peptide topology +
  cyclization amide accepted, `STAGE_Dcyc:OK`). **This is a topology-validation milestone, NOT a ΔΔG.**
  The ΔΔG itself is **NOT-YET-MEASURED**: the pmx hybrid + solvated/equilibrated legs are not built, and
  `fep_batch.py --submit` is deliberately guarded until inputs are staged (commit `12c405919`). No FEP has run.
- **First closed-loop round (`avb6-r1-20261019`, 3 candidates):** `DISPATCHED-GATED` — 3 cofold Batch jobs
  RUNNABLE on spot, **nothing has scored**. `record_round` writes a real reward only when a `complex.cif`
  lands; none has. (`20261019_FIRST_CLOSED_LOOP_ROUND_REVIEW.md`, `20261019_round_avb6-r1_manifest.json`.)
- **GRPO (RLVR):** `DISPATCHED-GATED` — reconciled, reviewed, auto-fire armed on the spot ≥6 gate; **not run**.
  Expected deliverable is "the RLVR pipeline runs end-to-end," and the out-of-generator `decomposition_real`
  metric is expected **near-floor** (base/v3 ≈ 0.016/0.087); this is a low-EV pipeline-completeness run, not a
  headline. **The loop has never fed the reward store with a real run.** The whole closed-loop claim is
  therefore BUILT-NOT-FED.

### 4.2 Physics gating on the two targets — in-silico only, no wet-lab
- **αvβ6:** metal-aware cofold **validated** — controls' RGD Asp coordinates the MIDAS Mn (Trivehexin 0.8 Å,
  avebehexin 1.9 Å; ligand-ipTM ~0.90), the first physically valid αvβ6 binding setup (`MEASURED` as a
  geometry fact). Single-point MM-GBSA ranking is **INADMISSIBLE** (fixed-charge controls diverged 115
  kcal/mol; CaDA single-point also judged off-label) — **no αvβ6 affinity ranking is reported.** FEP/TI is
  the validated path and is pending (§4.1). The monomer scaffold is FTO-blocked (`CA2998968A1`), driving a
  scaffold-hop whose ranking depends on the pending FEP.
- **PD-L1:** 1 fully-gated in-silico lead (**K-05**: cofold PASS, developability PASS, groove 93%, PD-L2
  selectivity PASS −15 kcal/mol). The documented bottleneck is **PD-L1/PD-L2 selectivity, not affinity**:
  G2 scored **0/8 selective**. All of this is MM-GBSA-relative + modeled PD-L2 — **in-silico; no wet-lab
  binding data exists.** (`20261014_CYCLIC_PEPTIDE_PROGRAM_MASTER.md`.)
- **Ground truth:** wet-lab binding/competition assays — **NOT-YET-MEASURED.** A CRO synthesis order is
  placed (`20261014_CRO_ORDER.csv`); no assay data has returned.

### 4.3 The own-model / system results — the only measured numbers, and they are about the *system*, not the loop
- **Catalog dividend (`MEASURED`, the one strong system result):** on held-out routing (n=200, one objective
  scorer), the BioMate catalog lifts *every* model by +34–64pp; largest for the smallest model (own 9B
  +63.5pp, 0.180→**0.815**), reproducible across 8 models. (`20261015_BENCHMARK_COMPARISON_OWN_LLM_VS_FRONTIER.md`.)
- **SFT (DB-gold) (`MEASURED`, modest):** routing +10.5pp (0.180→0.285); autofix/param at parity; no raw-capability
  win over frontier on any task (claims of "our model beats frontier" are **not supported**).
- **Cross-target generalization (`MEASURED` NULL):** v3/v3.1 cyclic-LLM cross-target transfer is NULL across
  all LOTO folds; binding predictor Spearman collapses 0.736→0.18 OOD; cold-start AUC 0.44–0.55 (≈random).
  This is **consistent with the SOTA frontier (~3–8% confirmed hit)**, not a unique defect — and it *bounds*
  the claim (kills any "our model generalizes across targets"). (`20261006_CROSS_TARGET_SOTA_COMPARISON.md`.)
  The one clean same-metric SOTA head-to-head (BoltzGen cyclic-FT LOTO) is still PENDING.

**One-line results reality:** the only measured, defensible numbers are (i) the catalog/system dividend and
(ii) a within-target/OOD characterization that reproduces the field's bound. **There is no measured result
yet for the paper's actual thesis — that the execution-verified loop improves peptide design.**

---

## 5. GAP ANALYSIS (centerpiece) — scored against a good-paper checklist

| Criterion | What we have | What is missing | Verdict |
|---|---|---|---|
| **(a) A clear, novel, defensible claim** | A well-motivated method (execution-verified reward escaping the self-consistency oracle), with the SOTA gap it addresses documented | The claim is currently *architectural*. A paper needs the claim to be *empirical* — "the loop measurably improves X" | **Partial.** Thesis is clear; it is not yet a tested hypothesis. |
| **(b) Reproducible methods** | Strong: all code committed with SHAs; sourced force-field params (Duarte 2014) with unit conversions shown; CPU self-tests; preflight harness with canaries/traps; grader contracts explicit | Dockerized/seed-pinned end-to-end reproduction script; environment manifests | **Strong.** This is the most paper-ready dimension. |
| **(c) RESULTS: baselines, controls, ablations, statistics/uncertainty, held-out eval** | For the *system* side: held-out routing eval with a baseline (bare vs +catalog) across 8 models, and a leakage-controlled LOTO cross-target NULL. For the *loop/design* side: **essentially nothing measured.** | **The dominant gap.** For the design thesis we have: no control-anchored ΔΔG (the control edge recovering the known Trivehexin-mono↔avebehexin gap — the archetype control a reviewer *will* demand — is NOT-YET-MEASURED); no scored closed-loop round; no ablation of the learned proposer vs a non-learning proposer; no uncertainty/replicate statistics on any design metric; no wet-lab held-out validation | **Weak — blocking.** A paper is mostly a RESULTS section; ours for the thesis is empty. |
| **(d) Honest limitations** | Extensive and candid: relative-not-absolute MM-GBSA, single receptor structure/target, approximate metal params, FTO caveats, cross-target NULL, oracle-circularity awareness | Consolidation into a single limitations section | **Strong.** |
| **(e) Figures / tables** | Data and logs exist (manifests, benchmark tables, preflight markers) | No assembled figures: no loop-improvement curve, no ΔΔG-vs-experiment correlation plot, no reward-ladder schematic with real data | **Weak.** Follows from (c). |

**The single sentence a reviewer would write:** *"Interesting, well-engineered system; where is the result
showing the loop works?"* The dominant, blocking gap is **measured design results with proper controls** —
specifically the control-anchored FEP ΔΔG and at least one closed-loop round that actually scores and shows
movement on a held-out metric.

---

## 6. Minimum experiment set to reach a credible preprint (prioritized)

These are bounded and tied to work already dispatched/gated; most are spot-GPU-capacity-gated, not
engineering-gated.

1. **[P0] Control-anchored FEP ΔΔG (the archetype control).** Build the pmx hybrid + solvated legs offline,
   stage, submit the single control edge; the ΔΔG **must recover the known small Trivehexin-mono↔avebehexin
   gap** within replicate error. *This is the gate for any αvβ6 affinity claim.* Then, only if admissible,
   the candidate ladder (M7/M11 ↔ control) → the first admissible αvβ6 ranking. (Preflight done;
   inputs-build pending; `fep_batch.py` guarded.)
2. **[P0] One real end-to-end closed-loop round that SCORES.** `avb6-r1` cofolds land → graded → rewards in
   `graded_run_store` (real, not synthetic). Then a *second* round whose proposer is updated from round-1
   rewards, with an **improvement measured on a held-out physics metric** — this is the empirical core of the
   thesis.
3. **[P1] Ablation: learned proposer vs non-learning proposer** (random/rule/fixed-prior) on the same
   held-out metric, with uncertainty. Without this, "learning from verifiable reward helps" is unsupported.
4. **[P1] Cross-target claim stated against SOTA honestly** — already measured NULL; add the pending BoltzGen
   cyclic-FT LOTO as the one same-metric SOTA-path datapoint. Frame as a *bound*, not a win.
5. **[P2] Wet-lab validation of ≥1 lead** (PD-L1 K-05 and/or an αvβ6 scaffold-hop) — the true ground truth;
   CRO order placed. Not required for a *methods/in-silico* preprint, but it is what converts the claim from
   "in-silico loop" to "validated loop."

**Scope decision implied:** a *defensible first preprint* is the **method + the P0/P1 results** (execution-
verified reward; one scored loop round with a measured improvement; the control-anchored ΔΔG; the honest
cross-target bound). Wet-lab (P2) is a stronger second paper. Do **not** write the paper around cross-target
generalization (it is NULL for us and the field) or around an αvβ6 ΔG ranking until the control edge is
recovered.

---

## 7. Risks to publishability / honest threats

- **Circularity (the field's #6, and our sharpest risk).** If the reward physics and the proposer share the
  same structure prior, a measured "improvement" may be self-consistency, not real signal
  (`feedback_circular_target_more_data`: if the feature ⊂ the target, a positive is circularity). The
  execution-verified reward *partially* mitigates this (it grades emitted artifacts, not a refold), but
  cofold/MM-GBSA remain in-silico and prior-adjacent. **Only FEP (an independent physics) and wet-lab truly
  break the circle.** A reviewer will probe this; the ablation (§6.3) and the FEP control (§6.1) are the defenses.
- **Synthetic-only loop / BUILT-NOT-FED.** No real round has scored; the loop's benefit is asserted by
  construction, not shown. Until §6.2 exists there is no empirical thesis.
- **Data scarcity.** The cyclic co-structure data wall (~hundreds of real co-structures; ~19 de-novo cyclic
  co-crystals) and the absence of display-scale data in hand cap the generative model; the "invert the data
  dependency" thesis depends on data not yet collected (`20261005_INNOVATION_THESIS_CYCLIC_LLM.md`).
- **Metal-FEP validity.** CaDA is validated by its authors for MD + FEP, not single-point MM-GBSA (we
  correctly ruled the latter inadmissible). FEP is the right use, but its validity on *this* metal-bridged
  integrin interface is unproven until the control edge recovers the known gap — i.e. the method's
  trustworthiness is itself one of the pending results.
- **Single-target n / generality.** αvβ6 is one target; PD-L1 is in-silico-only; cross-target is unsolved.
  A claim of generality needs ≥2 targets with scored loops, not one.

---

## 8. Bottom line (verdict)

**We are at "method + infrastructure complete and individually validated; empirical core pending."** The
system is real and reproducible, the limitations are honestly characterized, and the one strong measured
result (the catalog/system dividend) is defensible — but it is about the *system*, not the *loop*. For the
thesis of the paper there is **no measured design result with controls yet.** A credible preprint is
reachable with a bounded, mostly capacity-gated experiment set (§6 P0/P1), but it is **not** writable today.

**Distance to a submittable methods preprint:** the §6 P0 items (control-anchored FEP ΔΔG that recovers the
known gap + one closed-loop round that scores and shows a held-out improvement) plus the §6.3 ablation.

**Top 3 gaps:**
1. **No measured design result with controls** — the control-anchored FEP ΔΔG (recovering the
   Trivehexin-mono↔avebehexin gap) and a real scored closed-loop round are both NOT-YET-MEASURED.
2. **No demonstrated loop benefit** — no ablation of the learned proposer vs a non-learning proposer on a
   held-out metric; the closed-loop claim is BUILT-NOT-FED.
3. **No wet-lab ground truth** — all physics is in-silico; the only external anchor (a CRO synthesis order)
   has returned no assay data.

---

*Record pointers:* `20261014_CYCLIC_PEPTIDE_PROGRAM_MASTER.md`, `20261019_AVB6_CADA_AND_FEP_SETUP.md`,
`20261019_AVB6_FEP_CONTROL_EDGE_REVIEW.md`, `20261019_FIRST_CLOSED_LOOP_ROUND_REVIEW.md`,
`20261005_INNOVATION_THESIS_CYCLIC_LLM.md`, `20261006_CROSS_TARGET_SOTA_COMPARISON.md`,
`20261015_BENCHMARK_COMPARISON_OWN_LLM_VS_FRONTIER.md`; code under `research/guangzhou_all_atom/cyclic_llm/`
and `evaluation/local_trial/{execution_grader,graded_run_store}.py`.
