# Closed-cycle methods section (honest, methodology-scoped) — drop-in for the cyclic-LLM paper

*2026-10-22. This is the rescoped closed-cycle section: it claims a verified-reward optimization
**methodology** demonstrated on a measured **property** signal (permeability), with leakage, anti-circular,
and placebo controls. It explicitly does NOT claim binding, physics, or cross-target generalization.*

---

## Verified-reward generator optimization learns from a measured property signal

### Motivation

Given a generator of cyclic-peptide sequences and a *measured* property with a scalar oracle, can
preference-optimizing the generator against that oracle reliably improve the property of its samples
without collapsing diversity or reward-hacking the oracle? We answer this for membrane permeability — a
target-agnostic developability property with a large measured dataset (CycPeptMPDB) — and treat the result
as a methodology demonstration, not a binding or cross-target claim.

### Setup

- **Generator.** The collected cyclic-peptide language model (v4; `runs_helm/unified_cyclic_llm_v4.pt`),
  conditioned on an enrichment/property control token, sampled to produce valid HELM monomer sequences.
- **Signal + oracles.** Measured permeability (logP_app, CycPeptMPDB). We train **two** gradient-boosted
  oracles on **disjoint halves** of the data under a **cluster-disjoint split** (monomer-Tanimoto ≥ 0.6
  between clusters): a **reward oracle A** (used to build preference pairs) and an **independent evaluator
  oracle B** (used only to score before/after). Judging the method on B, trained on data A never saw,
  makes the evaluation anti-circular: a generator that merely games A's idiosyncrasies gains nothing on B.
- **Optimization.** Sample a pool, score with A, form preference pairs (higher-A chosen vs lower-A
  rejected), and run **DPO** on the LM (frozen reference, β = 0.1). Report Δ = evaluator-B mean after −
  before, with diversity, novelty, FCD-analog distribution match, a uniform-random-sequence baseline, and
  a PMO-style oracle-budget AUC.

### Results

- **The loop improves the generator on the independent evaluator.** Across 6 seeds (leakage-safe,
  gate-on config), Δ(evaluator B) = **+0.098 ± 0.011 (SE)**, 6/6 positive, Wilcoxon p = 0.031
  (`results/methodology_close_6seed_leakagesafe.json`). Diversity and novelty are retained, so the gain is
  not mode collapse.
- **It is not reward-hacking.** The reward oracle A predicts the evaluator B only weakly (R² ≈ 0.07–0.17),
  and the per-seed correlation between the reward-side gain and the evaluator-side gain is low
  (corr(dB, dA) = 0.19). The generator improves on an endpoint the reward it optimized does not tightly
  track — genuine generalization, not oracle-gaming.
- **Placebo control: the gain is reward-driven.** We permute the reward labels across candidates before
  building pairs, so chosen/rejected are random with respect to the true reward while the DPO machinery is
  unchanged. Across 5 seeds each (matched config), the **real reward** raises the evaluator by
  **+0.124** while the **permuted reward** does not (**+0.014**, within noise of 0); Mann-Whitney
  p(real > shuffle) = **0.004**, with complete rank separation and diversity held in both arms
  (`results/methodology_close_placebo_control.json`). DPO pressure alone does not move the evaluator; the
  verified property signal does.

### What this demonstrates — and what it does not

This establishes that verified-reward preference optimization against a *measured* property oracle
reliably and signal-attributably improves a cyclic-peptide generator, under leakage-safe, anti-circular,
and placebo controls. It is a **methodology** result on a **property** (permeability).

It is **not** a binding result, a physics result, or a cross-target result. The reward here is a measured
permeability oracle, not an execution-verified physics (FEP/MM-GBSA) reward — that machinery is wired but
unrun (no admissible αvβ6 ΔG exists; the control edge is unexecuted). And cross-target binder
generalization is, separately, **null** in our hands (leave-one-target-out conditioning Δ ≈ 0.02–0.03;
pocket-conditioned generator fine-tune Δiptm = −0.16; binding-model novel-target ceiling ≈ 0.42 Spearman).
Whether an execution-verified physics reward can carry this same verified-reward loop to break the
cross-target wall is the open question this methodology is built to test, and is stated as future work,
not a result.
