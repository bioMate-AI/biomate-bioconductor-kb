# Reviewer E_loop_rlvr -- deepseek/deepseek-v4-pro-0813
_(elapsed 68s; usage {'prompt_tokens': 31902, 'completion_tokens': 6324, 'total_tokens': 38226, 'cost': 0.0194151, 'is_byok': False, 'prompt_tokens_details': {'cached_tokens': 0, 'cache_write_tokens': 0, 'audio_tokens': 0, 'video_tokens': 0}, 'cost_details': {'upstream_inference_cost': 0.0194151, 'upstream_inference_prompt_cost': 0.0143559, 'upstream_inference_completions_cost': 0.0050592}, 'completion_tokens_details': {'reasoning_tokens': 0, 'image_tokens': 0, 'audio_tokens': 0}})_

## 1. VERDICT ON OUR FINDINGS

**1.1 FEP control edge was not a validation (§3.1, §3.2, docs/20261025_SESSION_REVEAL §4.1).**
Claim: "control recovered expected ≈0 / anchor cleared" → Problem: measured ΔΔG is −0.95 kcal/mol, computed −0.18 ± 0.15; the claim was false on both the expected value and the validation status. Evidence needed: the corrected controls doc and manuscript wording already exist in the reveal doc §6; the committee brief §3.1 acknowledges the retraction. This is correctly handled.

**1.2 Metal was never at the binding site (§3.2, CaDA-Mn validation doc).**
Claim: CaDA-Mn model "dynamically validated" → Problem: all three Mn were free ions 31–37 Å from the receptor due to `editconf -c` before Mn append. Evidence needed: the validation doc §1–§4 provides quantitative confirmation (rigid translation 161 Å, residual std 0.14 Å; Mn centres at input coordinates). The fix and build-time gate are implemented and verified on build2 (§8). This is correctly handled, with one caveat: the unrestrained metal-model validation (to-do 4b) is still not run, so the CaDA-Mn force field itself remains unvalidated. The team correctly labels this.

**1.3 Leakage-inflated wins caught (§3.3, §3.4, reveal §4.2).**
Claim: display selector AUC 0.94–0.99, renal ρ 0.27, binding+availability 0.74 → Problem: all three collapse under proper held-out splits (below chance on hPCSK9; LOTO ρ −0.26; LODO 0.28). Evidence needed: the reveal doc §3 provides the corrected numbers. This is correctly handled and is the strongest methodological contribution of the session.

**1.4 Cross-context generalisation wall (§3.4).**
Claim: cross-target cyclic transfer NULL, target-aware ESM-2 NULL, novel-target affinity ceiling ρ ≈ 0.42, BoltzGen Δiptm −0.16, UniMoMo +0.0097 → Problem: none of these are overclaimed; they are honestly reported as failures. Evidence needed: none; the numbers are consistent with the field's known difficulty. The one signal that transfers (availability, LODO ρ 0.40) is correctly scoped as peptide-intrinsic and informational only.

**1.5 Availability model (§3.5, peptide_availability.py).**
Claim: "first-of-its-kind deployable availability-risk flag" → Problem: this is a modest claim and defensible; the model is OLS on 3 features, LODO ρ 0.40, and the doc explicitly states it is a ranking/triage tool, not an oracle. Evidence needed: none; the caveats are stated plainly. One missing item: the model is trained on canonical linear SH3 peptides; for cyclic/ncAA macrocycles it is an approximation. The code flags ncAA fraction but does not quantify the expected degradation. A calibration check on the team's own cyclic peptides against any available solubility/aggregation proxy would strengthen this.

**1.6 SynCraft prior art (§3.7).**
Claim: "LLM + rules + computation is not novel by itself" → Problem: correct. SynCraft (Li & Lai, Nature MI 2026) already does atom-level edit sequences + RDKit deterministic application + RAG + docking constraints. Evidence needed: none; the team correctly identifies this as prior art. The implication for the mandate area: the loop must be novel in its reward/oracle structure, not in the LLM+rules+computation combination.

**1.7 FEP guard on dead path (reveal §5).**
Claim: "Production FEP is gated until go" → Problem: `MDRUN_CMD_READY=False` lives only in superseded `fep_batch.py`; live `fep_production.py` has no guard. Evidence needed: the reveal doc §5 identifies this. This is a critical operational risk for the loop: any FEP edge submitted through the live path bypasses the readiness gate. The fix (to-do 7 in the CaDA-Mn doc) is not yet implemented.

**1.8 Fan-out is not HREX (reveal §5).**
Claim: mdp language says HREX → Problem: `fep_production.py` runs independent λ windows → `gmx bar`, with 0.5 ns/window and analytic BAR error only. Evidence needed: the reveal doc §5. This means the FEP error bars are optimistic; the loop cannot treat FEP ΔΔG as a precise reward signal until this is fixed (replica exchange or longer sampling).

**1.9 `neural_generator` is a re-ranker, not a generator (reveal §5).**
Claim: "neural proposer" → Problem: it scores ~80 enumerated flank triples by LM log-likelihood conditioned on permeability/null-target, not αvβ6 affinity. Evidence needed: the code in `neural_generator.py` confirms this. The loop's proposer is effectively a permeability-biased enumeration, not a learned policy. This is correctly labelled in the docstring but the naming is misleading.

**1.10 `methodology_close` is the only genuinely closed loop (reveal §5).**
Claim: "closed optimizer loop" → Problem: `loop.py`'s `revise()` is a hand-written deterministic rule-repair stand-in; no LLM or RL is wired. `methodology_close.py` is the only real gradient DPO loop, but it optimises a permeability ML oracle (R² 0.23–0.30), never binding. Evidence needed: the code confirms this. The permeability DPO result (+0.098, 6/6 seeds, p=0.031; placebo +0.014) is real but narrow; it does not transfer to binding.

**1.11 Missing from the findings.**
The team has not addressed: (a) how to calibrate the multi-fidelity oracle ladder against the measured anchors (Quigley 2×2 grid, Tomassi N-methyl scan) before trusting any FEP edge; (b) how to select which expensive FEP edges to run (active learning / uncertainty); (c) reward-hacking detection beyond the permeability placebo; (d) when the loop is allowed to claim an improvement. These are the mandate area of this review.

## 2. YOUR PROPOSAL FOR YOUR MANDATE AREA

The binding oracle is not validated. The loop must therefore be structured as a **calibration-first, multi-fidelity active-learning ladder** with explicit reward-hacking controls. The reward must be a **calibrated, uncertainty-aware, anchored score**, not a raw physics number.

### 2.1 Multi-fidelity oracle ladder

Define four fidelity levels, each with an explicit calibration gate before it can contribute to the reward:

- **F0 — Rule/developability/availability gates** (cheap, deterministic, already in `score.py`). These are not binding signals; they are feasibility filters. They contribute to the reward only as gate terms (pass/fail), never as continuous binding terms.
- **F1 — Measured-anchor interpolation** (cheap, new). Use the Quigley 2×2 Phe/Tyr grid (4 IC50 values: 0.17, 3.3, 2.8, 0.84 nM) and the Tomassi N-methyl scan (1.3 nM → >5000 nM) to build a **local SAR model** over the free positions (P1, P6, P7). This is a 4-point + 1-scan dataset; a simple additive model or Gaussian process with a Matérn kernel over the discrete free-position space is appropriate. This is the only binding signal that is **experimentally grounded today**. It must be used as the primary reward for any candidate within the scaffold's local neighbourhood.
- **F2 — Relative FEP ΔΔG** (expensive, GPU). Only admissible after: (a) the CaDA-Mn unrestrained validation passes (to-do 4b in the CaDA-Mn doc); (b) the YY→FF control edge reproduces the measured −0.95 kcal/mol within a pre-registered tolerance (proposal: sign correct and magnitude within ±0.5 kcal/mol, i.e. computed ∈ [−1.45, −0.45]); (c) the metal-perturbing Asp→Ala edge runs and shows a large, sign-correct ΔΔG (pre-register: |ΔΔG| > 2 kcal/mol, sign negative). Until all three pass, F2 contributes **zero** to the reward.
- **F3 — Wet-lab IC50** (not available; no wet lab). This is the eventual ground truth. The loop must be designed so that F3 can replace F1/F2 without structural changes.

### 2.2 Calibration against measured anchors

Add a new module `oracle_calibration.py` with these functions:

- `calibrate_f1(anchors: list[dict]) -> GPModel`: fit a Gaussian process or additive model on the Quigley + Tomassi anchors. Input: free-position descriptors (aromaticity, hydrophobicity, size, N-methylation). Output: predicted ΔΔG relative to the YY reference, with epistemic uncertainty.
- `calibrate_f2(fep_edges: list[dict]) -> CalibrationResult`: given a set of FEP edges with computed ΔΔG and (where available) measured ΔΔG, fit a **linear calibration** `measured = a * computed + b` with uncertainty. The control edge YY→FF (−0.95 measured, −0.18 computed) is one point; the Asp→Ala edge (once run) is a second. Until at least two anchors exist, F2 is not calibratable and contributes zero.
- `anchor_coverage(candidate) -> bool`: returns True only if the candidate's free positions are within the convex hull of the measured anchors. Outside the hull, F1 uncertainty is large and the reward must be down-weighted.

### 2.3 Uncertainty-aware reward

Modify `reward.py` to replace the current `reward()` with `calibrated_reward(rec, calibration_state)`:

- **F1 term**: `w_f1 * predicted_ddg / scale`, where `w_f1` is inversely proportional to the GP predictive variance: `w_f1 = w_f1_max / (1 + variance / variance_threshold)`. If the candidate is outside the anchor hull, `w_f1` is further reduced by a factor (proposal: 0.5).
- **F2 term**: only if `calibration_state.f2_calibrated` is True. Use the calibrated value `a * computed_ddg + b`, with weight `w_f2` proportional to the calibration R² and inversely to the FEP statistical error. If F2 is not calibrated, the term is **zero**, not a fallback to MM-GBSA.
- **MM-GBSA**: **must NOT be in the reward at all.** The reveal doc §4.3 shows MM-GBSA metal-free is invalid and metal-aware diverges 115 kcal/mol on controls. Any MM-GBSA term is a reward-hacking vector. Remove `binding_dG` from `reward.py` entirely; keep it only as an informational field in `score.py` with a `"status": "inadmissible"` flag.
- **Selectivity**: only from measured selectivity ratios (Quigley FF 2494× over αvβ3) or calibrated FEP selectivity edges. Until then, `selectivity_gap` contributes zero.
- **Uncertainty penalty**: add a term `-lambda_unc * total_uncertainty`, where `total_uncertainty` is the sum of F1 variance and F2 statistical error. This prevents the loop from chasing high-variance predictions.

### 2.4 Active learning for FEP edge selection

Add `fep_active_learning.py`:

- **Acquisition function**: expected improvement (EI) over the current best calibrated reward, with a cost penalty. `acquisition(candidate) = EI(candidate) / (fep_cost + lambda_batch * batch_penalty)`. FEP cost is ~$X per edge (the team knows the actual spot cost; use it).
- **Batch selection**: greedily select the top-k candidates by acquisition, with a diversity constraint (Tanimoto similarity between selected edges < 0.7).
- **Pre-registration**: every FEP edge must be pre-registered in `fep_prereg/` with: the edge definition, the expected sign and magnitude (from F1), the tolerance for "agreement", and the decision rule if the edge disagrees. No post-hoc interpretation.
- **Stopping rule**: stop running FEP edges when the expected improvement of the next edge is below a threshold (proposal: < 0.1 kcal/mol improvement in the 90th percentile of the reward distribution) or when the calibration R² of F2 stops improving over the last 3 edges.

### 2.5 Reward-hacking detection

Add `reward_hacking_detector.py`:

- **Placebo control** (already in `methodology_close.py` for permeability): run the loop with shuffled reward labels. The loop must show no improvement on the independent evaluator. Extend this to the F1 reward: shuffle the anchor labels and confirm the loop does not produce candidates that score well on the true anchors.
- **Adversarial probe**: generate candidates designed to maximise each reward term independently (e.g. maximise F1 by exploiting GP extrapolation, maximise FTO novelty by going far from patents). If any single term can be driven to its maximum while the others collapse, the reward is hackable.
- **Calibration drift monitor**: after every N loop iterations, re-evaluate the F1 model on the held-out anchors (leave-one-anchor-out). If the LOO error increases, the loop is overfitting the reward.
- **Diversity collapse monitor**: track the Tanimoto similarity distribution of the proposed candidates. If the 90th percentile similarity exceeds 0.9, the loop is mode-collapsing.
- **Reward vs. independent evaluator gap**: maintain a held-out set of candidates scored by both the reward and an independent evaluator (e.g. the F1 model trained on a subset of anchors vs. the full anchor set). If the gap grows, the reward is being gamed.

### 2.6 When the loop is allowed to claim an improvement

Add `loop_claim_policy.py` with explicit gates:

1. **F1-only claim**: "The loop improved the F1-calibrated reward by ΔX with p < 0.05 (Wilcoxon on seeds), placebo Δ ≈ 0, diversity held, and LOO calibration error did not increase." This is a **methodological** claim, not a binding claim.
2. **F2-calibrated claim**: requires F2 calibration to pass (control edge within tolerance, Asp→Ala sign-correct, unrestrained metal validation passed). Then: "The loop improved the calibrated F2 reward by ΔY, and the improvement is consistent with the F1 prediction within uncertainty."
3. **Binding improvement claim**: **not allowed** without wet-lab F3 data. No FEP-only result can claim a binding improvement.

### 2.7 Files to change or add

- **Change `reward.py`**: remove MM-GBSA term; add F1 calibrated term with uncertainty weight; add F2 calibrated term (zero unless calibrated); add uncertainty penalty; add `calibration_state` parameter.
- **Change `score.py`**: mark `binding_dG` as `"inadmissible"` for αvβ6; add `f1_predicted_ddg` and `f1_uncertainty` fields; add `anchor_hull_coverage` field.
- **Add `oracle_calibration.py`**: GP/linear calibration, anchor coverage, LOO calibration.
- **Add `fep_active_learning.py`**: EI acquisition, batch selection, pre-registration, stopping rule.
- **Add `reward_hacking_detector.py`**: placebo, adversarial probe, drift monitor, diversity monitor, reward-evaluator gap.
- **Add `loop_claim_policy.py`**: explicit claim gates.
- **Change `loop.py`**: replace `revise()` with a call to the calibrated reward; the deterministic repair stand-in remains but the reward is now calibrated.
- **Change `physics_dispatch.py`**: add the F2 calibration gate; refuse to dispatch FEP edges unless the calibration pre-registration exists and the unrestrained metal validation has passed.

## 3. THE ONE INNOVATION YOU WOULD BET ON

**Anchor-calibrated, uncertainty-gated multi-fidelity reward with pre-registered FEP edge selection as an active-learning acquisition function.**

The novelty is not the multi-fidelity ladder (that is standard in Bayesian optimisation) nor the active learning (standard in drug discovery). The novelty is the **combination of three specific elements in a binding-oracle-unvalidated regime**:

1. **The reward is a calibrated interpolation over the measured anchors (F1), not a physics oracle.** With only 4 + 1 measured points, this is a deliberately weak model — but it is the only experimentally grounded binding signal. The reward's weight is inversely proportional to the GP variance, so the loop is forced to explore near the anchors before extrapolating.
2. **FEP edges are selected by expected improvement over the calibrated reward, with a cost penalty, and every edge is pre-registered with a falsifiable prediction.** This turns FEP from a validation afterthought into an active-learning acquisition step. The control edge YY→FF is not just a validation; it is the first acquisition, and its failure (−0.18 vs −0.95) is the signal that the F2 fidelity is not yet trustworthy.
3. **The loop's claim policy is tied to calibration state, not to the reward value.** The loop can claim a methodological improvement (F1) without claiming a binding improvement. This prevents the over-claiming pattern documented in the reveal doc (§4.1, §4.8).

**Prior art I know:**
- Multi-fidelity Bayesian optimisation (Kandasamy et al., 2016; Poloczek et al., 2017) — standard, but typically assumes the high-fidelity oracle is at least unbiased. Here the high-fidelity oracle (FEP) is known to be biased (5× low on the control edge).
- Active learning for FEP (e.g. Konze et al., 2019; Ghanakota et al., 2020) — exists, but typically uses FEP as the reward directly, not as a calibration target. [UNVERIFIED: whether any published work uses measured anchors to calibrate FEP before using it as a reward in a generative loop.]
- Reward hacking in RLHF (Skalse et al., 2022; Pan et al., 2022) — the placebo and adversarial probe are standard, but their application to a physics-based reward with a known-biased oracle is not common.
- Pre-registration in FEP (e.g. the SAMPL challenges) — exists for blind prediction, but not as an active-learning acquisition policy.

**What would falsify it:** If, after calibrating F2 on the YY→FF and Asp→Ala edges, the calibrated F2 reward does **not** improve the F1-only reward's ability to rank the held-out Quigley anchors (i.e. the F2 calibration adds no predictive power over F1 alone), then the innovation is not useful. Concretely: leave-one-anchor-out on the 4 Quigley points; if F1-only LOO ρ > F1+F2 LOO ρ, the F2 term is noise and the bet fails.

## 4. 30-DAY PLAN

Assume no wet lab. All steps are computational. Cheap = CPU/spot GPU < $50; expensive = spot GPU > $200.

1. **Day 1–3 (cheap): Implement `oracle_calibration.py`.** Fit GP on Quigley 2×2 + Tomassi scan. Gate: LOO Spearman on the 4 Quigley points ≥ 0.5 (if not, the F1 model is too weak; fall back to a simple additive model). **Go/no-go: LOO ρ ≥ 0.5 or documented fallback.**
2. **Day 2–4 (cheap): Modify `reward.py` and `score.py`.** Remove MM-GBSA term; add F1 calibrated term with uncertainty weight; add F2 calibrated term (zero unless calibrated); add uncertainty penalty. Gate: unit tests pass; reward on the Quigley anchors ranks FF > YF ≈ FY > YY (i.e. the measured order). **Go/no-go: reward ranking matches measured anchor order.**
3. **Day 3–5 (cheap): Implement `reward_hacking_detector.py`.** Placebo (shuffled anchors), adversarial probe (maximise each term), diversity monitor. Gate: placebo loop shows no improvement on true anchors; adversarial probe does not drive any single term to max without collapsing others. **Go/no-go: placebo Δ ≈ 0; adversarial probe fails to hack.**
4. **Day 5–7 (cheap): Run the F1-only loop on the αvβ6 scaffold.** Use `loop.py` with the calibrated reward. Gate: loop produces candidates within the anchor hull; diversity held (90th percentile Tanimoto < 0.9); LOO calibration error does not increase over 4 rounds. **Go/no-go: loop converges without diversity collapse or calibration drift.**
5. **Day 7–10 (expensive, ~$200–500): Run the unrestrained CaDA-Mn metal validation** (to-do 4b in the CaDA-Mn doc). This is the actual metal-model test. Gate: every Mn keeps ≥ 2 protein/ligand O for ≥ 1 ns; cage holds. **Go/no-go: metal validation passes; if it fails, F2 is blocked and the loop stays F1-only.**
6. **Day 10–14 (expensive, ~$300–800): Re-run the YY→FF control edge on the corrected build.** Pre-register: sign negative, magnitude ∈ [−1.45, −0.45] kcal/mol. Gate: computed ΔΔG within tolerance. **Go/no-go: control edge passes; if it fails, F2 is blocked and the loop stays F1-only.**
7. **Day 14–18 (expensive, ~$300–800): Run the Asp→Ala metal-perturbing edge.** Pre-register: |ΔΔG| > 2 kcal/mol, sign negative. Gate: sign-correct and large. **Go/no-go: metal edge passes; if it fails, the CaDA-Mn model is not validated for metal-dependent edges and F2 is limited to metal-insensitive edges only.**
8. **Day 18–21 (cheap): Calibrate F2.** Fit `measured = a * computed + b` on the two edges (YY→FF, Asp→Ala). Gate: calibration R² > 0.8 (with only 2 points, this is a weak test; document the limitation). **Go/no-go: F2 calibration exists; if R² < 0.8, F2 contributes zero and the loop stays F1-only.**
9. **Day 21–24 (cheap): Implement `fep_active_learning.py`.** EI acquisition with cost penalty; pre-registration templates. Gate: unit tests pass; acquisition selects the Asp→Ala edge as the first acquisition (it has the highest expected information gain about the metal model). **Go/no-go: acquisition function is sensible on the existing edges.**
10. **Day 24–28 (expensive, ~$200–500): Run 2–3 new FEP edges selected by active learning.** Pre-register each. Gate: each edge's computed ΔΔG is within the F1 prediction's 95% CI or the disagreement is documented. **Go/no-go: at least one edge agrees with F1 within uncertainty; if all disagree, F2 is not trustworthy and the loop stays F1-only.**
11. **Day 28–30 (cheap): Write the loop claim.** Based on `loop_claim_policy.py`, issue the appropriate claim: F1-only methodological improvement, F2-calibrated improvement, or no claim. Gate: the claim matches the calibration state. **Go/no-go: claim is issued with the correct scope.**

**Total estimated cost: $1,000–$2,600** (spot GPU), plus CPU time. This is within the stated compute budget.

## 5. STOP DOING

1. **Stop using MM-GBSA as a binding signal.** It is invalid for αvβ6 (metal-free ruled invalid; metal-aware diverges 115 kcal/mol). Any reward term based on MM-GBSA is a reward-hacking vector. Remove it from `reward.py` entirely.
2. **Stop calling `neural_generator` a "neural proposer" or "generator".** It is a permeability-biased re-ranker over ~80 enumerated triples. Rename it to `permeability_reranker.py` or similar, and update all docs. The misleading name risks over-claiming in the manuscript.
3. **Stop running FEP edges through `fep_production.py` until the readiness guard is fixed.** The live path has no `MDRUN_CMD_READY` guard (reveal §5). Any edge run now is wasted compute and risks manufacturing false confidence.
4. **Stop treating the permeability DPO result (+0.098) as evidence that the loop works for binding.** It is a narrow ML-oracle result. It is methodologically sound but does not transfer to binding. Do not cite it as a binding-loop success.
5. **Stop enumerating candidates outside the measured anchor hull and expecting the reward to be meaningful.** The F1 model is a local interpolation; outside the Quigley/Tomassi hull, its uncertainty is large and the reward is noise. The loop must be constrained to the hull until more anchors exist.
6. **Stop writing "FEP control recovered ≈0" anywhere.** The measured value is −0.95 kcal/mol. The reveal doc §6 already requires this correction; ensure it propagates to all docs, manuscripts, and committee records.

## 6. BIGGEST RISK WE ARE MISSING

**The F1 anchor set is too small and too narrow to support any loop claim beyond "the loop can rank the 4 Quigley points."** With 4 IC50 values (2×2 Phe/Tyr grid) and 1 N-methyl scan, the F1 model has at most 5 effective degrees of freedom. The loop's free-position space is 3 positions (P1, P6, P7) with a palette of ~5 × 5 × 5 = 125 combinations. The GP will have enormous epistemic uncertainty over most of this space. The loop will either (a) collapse to the 4 anchors and produce nothing new, or (b) extrapolate wildly and produce candidates whose reward is noise. The team's own cross-context generalisation wall (§3.4) shows that binding does not transfer even across related targets; expecting a 4-point local model to guide a generative loop is optimistic by at least an order of magnitude.

**Quantitative estimate:** With 4 anchors, the GP's 95% CI on a candidate one free-position edit away from the nearest anchor is likely ±1–2 kcal/mol (depending on kernel lengthscale). The measured range of the anchors is ~1.3 kcal/mol (0.17 to 3.3 nM ≈ 1.3 kcal/mol). So the uncertainty is comparable to the entire signal range. The loop cannot distinguish improvement from noise.

**Mitigation:** The loop must be explicitly scoped as a **calibration and methodology exercise**, not a binder-discovery exercise. The 30-day plan above does this: the F1-only loop's claim is methodological, not binding. But the team must resist the temptation to present any F1-ranked candidate as a "designed binder" — it is a "candidate within the anchor hull ranked by a 4-point local model." The wet lab is the only exit from this regime.

**Second risk:** The FEP calibration may never pass. The control edge is 5× low (−0.18 vs −0.95). The Asp→Ala edge may also be attenuated. If both edges show a systematic bias (e.g. FEP under-predicts by 5×), the calibration `measured = a * computed + b` with only 2 points will have huge uncertainty in `a`. The loop would then be stuck in F1-only mode indefinitely. The team should pre-commit to a decision rule: if F2 calibration fails after 3 edges (control + Asp→Ala + 1 active-learning edge), the program either (a) invests in better FEP sampling (HREX, longer windows, more replicas) or (b) abandons FEP as a reward and relies on F1 + wet lab only. This decision must be made before spending more compute.