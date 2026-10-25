# Reviewer H_red_team -- qwen/qwen3.8-max-prime
_(elapsed 51s; usage {'prompt_tokens': 32313, 'completion_tokens': 4655, 'total_tokens': 36968, 'cost': 0.185112, 'is_byok': False, 'prompt_tokens_details': {'cached_tokens': 0, 'cache_write_tokens': 0, 'audio_tokens': 0, 'video_tokens': 0}, 'cost_details': {'upstream_inference_cost': 0.185112, 'upstream_inference_prompt_cost': 0.129252, 'upstream_inference_completions_cost': 0.05586}, 'completion_tokens_details': {'reasoning_tokens': 744, 'image_tokens': 0, 'audio_tokens': 0}})_

## 1. VERDICT ON OUR FINDINGS

| # | Claim | Problem | Evidence needed |
|---|---|---|---|
| 1 | "FEP control edge: sign right, magnitude ~5× low" (§3.1) | The edge ran on a **metal-free pocket** (all Mn in bulk water). The computed −0.18 is not a measurement of the intended physical quantity. Calling it a "miss" still implies the pipeline was exercised — it was not. | Unrestrained MD of build2 showing Mn coordination holds ≥1 ns; then re-run the edge. Until then the number is uninterpretable. |
| 2 | "methodology_close works narrowly" (§3, §4 table) | True but misleading by proximity: it optimises a permeability oracle with R² 0.23–0.30 (SOTA 0.77). The Δ +0.098 on an independent evaluator is real but the **absolute oracle quality is poor** — the loop is improving generations toward a noisy target. The practical value is methodological demonstration, not drug design. | Report the absolute permeability of generated sequences vs. the measured distribution; show the top-10 generated are actually in a useful permeability range, not just "higher than before." |
| 3 | "Availability model works — LODO ρ 0.40" (§5, availability doc) | Correct and honestly scoped. However, the doc's own caveat §3 states it is only a **developability proxy** for the program's actual targets (extracellular αvβ6/PD-L1). Calling it "the one real deliverable" is accurate for the community but **does not advance the stated drug-design goal**. | A second dataset (non-SH3) to test whether ρ 0.40 holds outside the training family. |
| 4 | "No component beats a published bar" (§4 honest state) | Correct. But the brief still frames the ask as "a better LLM, a better optimisation loop, a better output, with genuine innovation." This framing **presumes the program should continue toward those goals** rather than asking whether the goals are achievable with the available data. | A power analysis: how many measured αvβ6 affinity points would be needed to train or validate *any* binding oracle to decision-grade? (My estimate: ≥50 diverse scaffolds with measured IC50/Kd, currently 4–10 exist.) |
| 5 | "neural_generator is a re-ranker, not a generator" (§2, §5) | Correct. The brief's title "knowledge + rules + computation LLM system" implies an LLM is doing something. **No LLM is in the loop.** The 4.8M-param model scores 80 pre-enumerated options. This is a lookup table with a neural scoring function. | Either wire a real generative model or rename the system honestly. |
| 6 | "reward.py is the RLVR reward" (§2) | It is a **specification**, not a reward in any operational sense. It has never been used to update any parameter. The weights are hand-set with no calibration data. | A single training run where reward.py drives a gradient update and the result is measured against a held-out set. |
| 7 | "CRO panelB 0/12 have RGD" (§4, error 7) | This is not just an error — it reveals that **the gate chain was not consulted before ordering**. The system's own rules would have caught this. The loop's value proposition (rules prevent bad designs) was not applied to its own output. | A post-hoc check: were the panel designs generated before or after the acceptance gate was written? |

**Overclaimed:** The phrase "closed cycle" appears in multiple docs. The only closed cycle is permeability-DPO. The binding/design cycle is **open** — it has no validated reward, no training, and no experimental feedback.

**Missing:** There is no document that answers: "What is the minimum evidence needed before we would send a molecule to a CRO, and how far are we from that evidence?" Without this, the program has no defined exit criterion and will continue indefinitely.

---

## 2. YOUR PROPOSAL FOR YOUR MANDATE AREA

**Mandate: RED TEAM — argue the strongest case to stop, narrow, or pivot.**

**The strongest case to STOP the current direction:**

The program's stated goal is to design cyclic-peptide binders for αvβ6/PD-L1/GRPR. After an extended effort, the program has:
- No validated binding signal for any target
- No wet-lab data
- A physics pipeline (FEP) that has never been run correctly on the intended system
- A "neural generator" that is a re-ranker over 80 options
- An LLM that is not in the loop
- A reward function that has never trained anything

The most likely failure mode is **confident wrong output**: the FEP pipeline gets rebuilt, the control edge gives a number within 2× of −0.95, the team declares "validated," runs 5–10 design edges, picks the top-ranked candidate, sends it to a CRO, and it does not bind. The cost of this path is ~$2,000–5,000 in GPU + CRO fees + months of effort. The probability of this outcome is high because:
1. The metal model (CaDA) has never been validated in unrestrained dynamics
2. 0.5 ns/window with independent λ windows on a 205k-atom system is almost certainly undersampled for a charged, metal-coordinated ligand
3. The force field (CHARMM36m + CaDA) has no published validation against integrin–ligand binding free energies
4. Even if FEP is perfect, ranking 5–10 candidates within a single scaffold (RGD-L-X-X-dPro-NMeK) with only 3 free positions gives at most ~80 options — the "design" space is so small that enumeration + rules already covers it

**Concrete changes to this codebase:**

1. **`fep_production.py`**: Add a hard gate that refuses to submit any production edge until `validate_mn_coordination.py --mode post` passes on an unrestrained ≥1 ns trajectory. Currently the guard is only in the superseded `fep_batch.py`. (File: `fep_production.py`, add import + check before `submit()`.)

2. **`loop.py` → `revise()`**: This function is a finite-state repair over 3 failure classes on 3 free positions. The entire "optimisation loop" is a **constraint-satisfaction solver**, not an optimiser. Rename it `constraint_repair.py` and remove the "optimizer" framing. The actual design space (4 flanks × 5 knobs × 4 flanks = 80 candidates) is fully enumerable — the loop adds no value over `gen_avb6(80)` + `score()` + sort.

3. **`reward.py`**: Add a `calibration_status` field that returns `"UNCALIBRATED"` until at least one training run has used this reward to update parameters and the result has been measured. Currently the weights are arbitrary.

4. **New file: `decision_gate.py`**: A single function `ready_for_cro(candidate) -> (bool, list[str])` that returns True only if: (a) FEP control edge matches measured ΔΔG within 1 kcal/mol, (b) metal coordination validated in unrestrained MD, (c) candidate passes all hard gates, (d) selectivity vs αvβ3/5/8 computed. This makes the exit criterion explicit and auditable.

5. **`neural_generator.py`**: Delete or archive. It scores 80 options with a permeability-conditioned LM. The same information is available by sorting the 80 options by hydrophobicity. The model adds no signal for the actual design question (αvβ6 affinity).

---

## 3. THE ONE INNOVATION YOU WOULD BET ON

**Proposal: FEP-guided active learning on a measured αvβ6 affinity series as a community benchmark, not as a design tool.**

The insight: this program has accidentally assembled something rare — a **small, chemically coherent, measured affinity series** (the 2×2 Phe/Tyr grid + the N-methyl scan) for a cyclic-peptide target with a known metal-dependent binding mechanism. No public benchmark exists for cyclic-peptide FEP against integrins. The innovation is not to *design* new molecules but to **rigorously validate and publish the FEP protocol** (or demonstrate its failure) as a community resource.

**Why this is novel:** Published cyclic-peptide FEP benchmarks are essentially nonexistent for metal-dependent targets. The CaDA model [UNVERIFIED — I cannot confirm whether CaDA has been validated against any experimental binding free energy] has not been tested in this context. A honest "here is where FEP fails for cyclic RGD integrin ligands, and why" paper would be more impactful than a design paper with no wet-lab validation.

**Prior art I know:** FEP+ (Schrödinger) has been validated on small-molecule kinase inhibitors [UNVERIFIED for cyclic peptides]. The pmx/CHARMM36m hybrid approach is published for protein–protein interactions but not for cyclic-peptide–integrin with explicit metals. The Li–Merz Mn model was ruled inadmissible here (115 kcal/mol control divergence), which is itself a publishable negative result if contextualised.

**Falsification:** If the rebuilt, metal-validated FEP reproduces the measured −0.95 kcal/mol within ±0.5 kcal/mol on the YY→FF edge AND the N-methyl scan trend (1.3 → >5000 nM) is directionally captured by the Asp→Ala edge, then the protocol works and the design program can proceed. If it fails (magnitude off >2×, or sign wrong on any edge), the program should be declared **not decision-grade for binding** and pivoted entirely to the rule/FTO/developability filter + availability model.

---

## 4. 30-DAY PLAN

| Day | Step | Cost | Go/No-Go Gate |
|---|---|---|---|
| 1–2 | Run unrestrained MD continuation of build2 (1 ns, complex leg only). Check Mn coordination with `validate_mn_coordination.py --mode post`. | ~$8–15 (spot GPU, 1 ns on 205k atoms ≈ 6–12 h on g4dn.xlarge) | **GO** if all 3 Mn maintain ≥2 protein/ligand O within 2.0–2.6 Å for the full trajectory. **STOP FEP** if any Mn dissociates. |
| 3–5 | If GO: run YY→FF FEP edge (12 λ windows × 2 legs × 2 ns/window). Compare to measured −0.95 kcal/mol. | ~$80–150 (24 windows × 2 ns each) | **GO** if |computed − measured| ≤ 0.5 kcal/mol. **NARROW** if within 1.0. **STOP** if >1.0 or sign wrong. |
| 6–8 | If GO/NARROW: run Asp→Ala edge (the metal-perturbing control). This is the decisive test of whether the metal model matters. | ~$80–150 | **GO** if sign is correct (Ala should be dramatically weaker). **STOP** if sign is wrong or magnitude is unphysical. |
| 9–10 | Write up the FEP validation as a standalone protocol paper (or negative result). Submit to a methods journal or preprint. | Free (writing time) | N/A — this is the deliverable regardless of outcome. |
| 11–15 | If FEP validated: enumerate all 80 scaffold variants, run FEP on the top 10 by rule+FTO+developability. Rank. Apply `decision_gate.py`. | ~$400–800 | **GO to CRO** only if `decision_gate.py` returns True for ≥3 candidates. |
| 11–15 | If FEP failed: pivot. Archive FEP code. Focus on: (a) availability model extension (second dataset), (b) rule/FTO/developability filter as a standalone tool, (c) write the "what we learned about cyclic-peptide FEP failure" paper. | Free | N/A |
| 16–25 | Community benchmark: package the measured series + protocol + results (positive or negative) as an open benchmark. | Free | N/A |
| 26–30 | Decision: if CRO-ready candidates exist, prepare the order. If not, write the program close-out report with honest conclusions. | Free | Final gate: does the program have a decision-grade output? If no, recommend closure or fundamental pivot (e.g., wet-lab collaboration to generate training data). |

**Total compute budget:** $170–1,100 depending on path. **Cheap steps:** days 1–2 (decisive), days 9–10, 16–30. **Expensive steps:** days 3–8 (FEP edges), days 11–15 (design FEP).

---

## 5. STOP DOING

1. **Stop calling `neural_generator.py` a generator or the loop an "optimiser."** The design space is 80 candidates. Enumeration + sort is equivalent. The neural re-ranker adds no information for the binding question. Maintaining it creates false complexity and misleads reviewers/funders about what the system does.

2. **Stop building `reward.py` / RLVR infrastructure.** There is no training data for binding. The reward function has never been used to update parameters. Building more reward infrastructure before having a validated binding signal is building the roof before the foundation.

3. **Stop pursuing cross-target generalisation for binding.** The program has now demonstrated this fails in 5 independent tests (cyclic transfer, ESM-2, affinity ceiling, BoltzGen, UniMoMo). A sixth attempt will also fail. The lesson is clear: binding is target-specific. Accept it.

4. **Stop ordering CRO panels without running the gate chain first.** PanelB (0/12 RGD) is a process failure that reveals the system's own rules are not being applied to its own outputs. This should be impossible if `decision_gate.py` existed.

5. **Stop writing "closed cycle" or "closed loop" in any document referring to binding/design.** The only closed cycle is permeability-DPO. Using the phrase for the binding pipeline is misleading and will be caught by reviewers.

---

## 6. BIGGEST RISK WE ARE MISSING

**The program will produce a confident, wrong FEP ranking that gets sent to a CRO, fails, and the failure is attributed to "biology is hard" rather than to the known, documented, unfixed deficiencies in the physics pipeline.**

Quantitatively: the current FEP setup has three independent, known, unvalidated failure modes stacked:
1. **Metal model unvalidated in dynamics** (CaDA has never been shown to maintain coordination in an unrestrained run of this system)
2. **Severe undersampling** (0.5 ns/window, independent λ windows, no replica exchange, on a 205k-atom system with a charged metal-coordinated ligand — published FEP studies on smaller systems use 5–20 ns/window with REST2 or HREX)
3. **Force field unvalidated for this chemistry** (CHARMM36m + CaDA for integrin–cyclic-RGD has no published precedent)

Each of these alone could cause a >1 kcal/mol error. Stacked, the probability that the YY→FF edge (already 5× off in magnitude on a broken system) will be within 0.5 kcal/mol of measured after the rebuild is **low** — I would estimate <30% [UNVERIFIED — this is my subjective assessment based on the known error sources, not a calculated probability].

If the edge comes back at, say, −0.4 kcal/mol (within 2× of measured), the team will likely declare "validated within expected FEP error" and proceed to design. But the N-methyl scan (1.3 → >5000 nM, a >4.5 kcal/mol effect) and the selectivity data (2494×) involve much larger perturbations where the stacked errors will compound. The design candidates will be ranked by a pipeline that cannot distinguish a 10× affinity difference, and the top pick will be sent to a CRO with confidence.

**The cheapest decisive experiment** is Day 1–2 of the plan above: one unrestrained 1 ns MD run (~$10) that either shows the metal stays coordinated or doesn't. If it doesn't, the entire FEP approach is dead and the program saves itself months of wasted GPU time and a failed CRO campaign. If it does, the YY→FF edge (~$100) is the next gate. These two experiments cost <5% of the program's total compute budget and will determine whether the physics pipeline is decision-grade or not.

**What would change my mind:** If the unrestrained MD shows stable metal coordination AND the YY→FF edge reproduces −0.95 ± 0.5 kcal/mol AND the Asp→Ala edge gives the correct sign with a magnitude consistent with the >5000× loss, I would accept that the FEP pipeline is validated for this scaffold and the design program can proceed. That is a high bar, but it is the minimum bar for a system that claims to be "decision-grade."