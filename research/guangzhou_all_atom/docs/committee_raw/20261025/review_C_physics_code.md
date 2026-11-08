# Reviewer C_physics_code -- anthropic/claude-sonnet-5.5
_(elapsed 56s; usage {'prompt_tokens': 47110, 'completion_tokens': 4779, 'total_tokens': 51889, 'cost': 0.14201, 'is_byok': False, 'prompt_tokens_details': {'cached_tokens': 0, 'cache_write_tokens': 0, 'audio_tokens': 0, 'video_tokens': 0}, 'cost_details': {'upstream_inference_cost': 0.14201, 'upstream_inference_prompt_cost': 0.09422, 'upstream_inference_completions_cost': 0.04779}, 'completion_tokens_details': {'reasoning_tokens': 0, 'image_tokens': 0, 'audio_tokens': 0}})_

## 1. VERDICT ON OUR FINDINGS

**Right and worth keeping**
- Retracting the "ΔΔG≈0 control recovered" claim (Findings 1, 2) is correct. Sign right and magnitude ~5× low is a miss, not a validation.
- The Mn placement bug (editconf -c before Mn append) was real. The build gate, the validator and the post-rebuild check on `ionized.gro` are good practice.
- Ruling MM-GBSA inadmissible (115 kcal/mol spread between controls that should be nearly equal) is correct. Do not revisit it.
- The permeability-DPO close with a cluster-disjoint evaluator and a placebo is sound, but narrow.

**Wrong, overclaimed or missing**

1. **"Error −0.18 ± 0.15"** -> the analytic BAR error ignores sampling correlation. With independent windows, one replica and 0.5 ns/window on a 205k-atom system, it does not capture the real uncertainty. The edge changes two Tyr side chains far from the metal, and the experimental ΔΔG is −0.95. Experimental ELISA IC50s from one lab also have roughly 0.3–0.5 kcal/mol uncertainty. -> Needed: ≥3 independent replicas from different starting velocities and ideally different starting poses, a bootstrap or replica-spread error, and forward/reverse hysteresis. Report the miss as ΔΔG_calc − ΔΔG_exp with that error.
2. **Metal-model risks not yet examined** (CaDA brief/doc §5, §5b):
   - Dummy-atom cages with a 3×Mn site, a stiff cage (ε = 53.7 kJ/mol) and dt = 0.5 fs are expensive. They are also fragile under alchemical transformations that were never tested with the cage present.
   - LJ on the centre only, bonded versus virtual-site, and dt were never compared. Your doc does not show that the cage geometry reproduces Mn–O 2.1–2.2 Å and coordination number 6 in bulk water (hydration free energy, RDF).
   - Mn²⁺ in a classical force field also has no charge transfer or polarization. MIDAS binding is partly covalent, so a fixed-charge model will probably misrepresent the Asp–metal interaction.
   - The assay metal identity is unverified (to-do 6). An ELISA in Mn²⁺ versus Ca²⁺/Mg²⁺ buffer changes the ground truth.
3. **Restraint and relaxation design:** the sequence is reasonable, but kb = 2000 kJ/mol/nm² with b0 clamped at 0.205 nm will force a coordination geometry on Mn3 from a 0.82 Å clashed pose. If it relaxes unrestrained, fine. If the unrestrained 1 ns run holds coordination only because the restrained start was close, that is a weak test.
   - The unrestrained gate ("≥2 O for the whole run") is too lax. Require the full intended coordination (6 O for Mn1/Mn2) and a stable Mn–O RDF peak.
   - 1 ns is far too short to show stability of a metal that exchanges ligands slowly. Use ≥10 ns × 3 replicas.
4. **Sampling** (finding 8): independent λ windows with no HREX and 0.5 ns are inadequate for an edge with Tyr→Phe on a macrocycle with slow ring/loop rearrangement. The metal-dependent Asp→Ala edge (a ~2–3 charge-change edge) is much worse. Charged mutations need a 4-state or co-alchemical ion treatment and finite-size corrections.
5. **The admissibility gate keys off a metal-blind edge** (`physics_dispatch.py:144-165`). Passing it would manufacture false confidence. This is the most dangerous structural flaw.
6. **The live FEP path has no guard** (`fep_production.py`). The guard lives only in the superseded `fep_batch.py`. This is an integrity bug.

**Code bugs**
- `reward.py`: the `ddg_fep` term is `-ddg/3`, so more negative is better, but the edge ddG is relative to a *reference*. Comparing candidates from different reference edges, or with an unvalidated sign, gives an inconsistent ordering. The `selectivity_gap` normalization of 15 is arbitrary and untied to kcal/mol units.
- `reward.py`: `build_preference_pairs` can emit pairs where both members are "gated", from the reward difference alone. Marked `weak`, but the trainer is not told to down-weight them. The inner loop is O(n²) and can flood the set with trivially separable gate-failed negatives (all pairs `gated ≻ failed`), teaching only the gate.
- `score.py`: `rank_key` puts `b` (ddg or binding) in the tuple with a mixture of units and the placeholder `0.0` for pending. Pending candidates therefore tie in the middle of the ranking rather than sorting last, and a candidate with MM-GBSA −7 versus an FEP value is compared across incompatible scales. Also `rec["patent_id"]` can be `None` in a tuple compare, which raises TypeError.
- `score.py`: availability is silently skipped on any exception, so a missing module is invisible downstream.
- `loop.py`: `revise` repairs a gate failure by hard-coded substitution (F, Y, 2Nal) and is called "closed loop." It is a local rule search. `revise` rule 1 sets BOTH flanks to F, which reproduces the avebehexin monomer, which rule 2 then flags INFRINGING. This is a cycle risk.
- `peptide_availability.py`: the Kyte–Doolittle value for W (−0.9) and Y (−1.3) is the standard table, but treating `[dP]`/`[NMeK]` via "parent letter" mapping is approximate. `re.sub(r'^(NMe|Me|N-methyl-|d|D-)'...)` also strips a leading `d` from tokens like `Dap` or `dPro`, which are mislabelled. `base[:3].upper()` on a stripped token like "Phe4F" gives "PHE" (fine), but "2Nal" gives "2NA" (unknown, counted as ncAA, silent).
- `methodology_close.py`: `kb_admissible` fails open on exceptions, so a parse error inflates the admissible count. `vocab_canon` for the random baseline draws from the vocab uniformly, which does not match the generator's length distribution.

## 2. YOUR PROPOSAL FOR YOUR MANDATE AREA

1. **Guard first.** Add to `fep_production.py` a hard precondition reading a `mn_validation.json` (post-mode PASS, ≥10 ns unrestrained, per-Mn coordination 6/6/≥5). Refuse to submit otherwise.
2. **Rewrite the gate in `physics_dispatch.py`** so metal-dependent edges are admissible only if a metal-perturbing control (Asp→Ala, plus a non-metal-contact control) passes against measured data. Give the dispatcher an `edge_class` (metal_distal / metal_proximal / charge_changing).
3. **Metal-model bench before dynamics on the full system.** Add `fep/mn_bench.py`: Mn²⁺ in water (RDF, first-shell 6, Mn–O 2.15–2.22 Å, hydration free energy against the experimental value), and a small MIDAS-like fragment (Mn + acetate ×2 + Ser + water) compared against a short QM reference (DFT on the cluster, a few hundred geometries).
4. **Fix sampling** in `fep_production.py`: 3 replicas × 12 λ × ≥2 ns, with a proper bootstrap error and hysteresis check. Prefer a short pilot on the YY→FF edge first. HREX across λ (GROMACS `-replex`) is available if window-to-window overlap is poor. Overlap matrices from `gmx bar` or `alchemlyb` should be logged.
5. **Reward/score fixes:** in `score.py`, make `rank_key` use `float('inf')` for pending and a typed tuple `(gate, doe, state, value, patent_id or 1.0)`. Make `reward.py` take the binding term only from a record with `fep_validated: true` and an error bar, and use `ddg - 1.96*sigma` as a conservative reward (a lower confidence bound).
6. **Tests:** pytest cases for `rank_key` ordering with pending, for `revise` cycle detection (track visited sets by tokens), and for `_residues_from_helm` on `[dP]`, `[Dap]`, `[2Nal]`.

## 3. THE ONE INNOVATION YOU WOULD BET ON

**A metal-aware FEP "anchor ladder" with pre-registered calibration. Treat the measured Phe/Tyr 2×2 grid and the N-methyl scan as an open benchmark, with a calibrated, mixed-model error (replica + force-field).**

The 2×2 grid (IC50 0.17/3.3/2.8/0.84 nM) gives a thermodynamic cycle with a closure check (FF−YF−FY+YY, i.e. non-additivity), which is a rare internal consistency test. Compute all four legs as a closed cycle. The experimental closure is about 0.6 kcal/mol, so the model must reproduce non-additivity, not just ranks. Report calibrated slope/intercept of calc versus expt with CI, and publish the setup, inputs and failed runs.

Prior art: relative FEP benchmarks (Wang et al. 2015 FEP+ [UNVERIFIED on details]) and metal-ion parameter work (Li–Merz 12-6-4, cationic dummy models by Åqvist/Pang lineage [UNVERIFIED]). A *metal-integrin* FEP benchmark with pre-registered failures is, as far as I know, not published.

**Falsifier:** if, with ≥3 replicas, the YY→FF value stays outside ±0.5 kcal/mol of −0.95, or the cycle closure error exceeds 1 kcal/mol, or the result is insensitive to switching Mn parameters (CaDA versus 12-6-4), the setup cannot rank this series and the anchor ladder fails.

## 4. 30-DAY PLAN

1. **Days 1–3 (cheap).** Guards, `rank_key` fixes, tests. *Gate:* the live path refuses without a validation JSON; tests pass.
2. **Days 3–7 (cheap).** `mn_bench.py` in water and with a fragment, and the verified assay buffer metal. *Gate:* first-shell 6 at 2.1–2.25 Å, and hydration ΔG within ~10 kcal/mol (the experimental value for Mn²⁺ is large, so compare with a literature value I will not quote [UNVERIFIED]). Failure: switch to a bonded model or 12-6-4.
3. **Days 5–12 (moderate).** Restrained then unrestrained, 3 × ≥10 ns, with the dt choice justified. *Gate:* all Mn keep their intended coordination for the full run, ligand Asp stays within 2.6 Å of the metal, and RMSD of the RGD is stable. Failure: re-pose from 8TCG/9XMM.
4. **Days 10–20 (expensive, ~$100s on spot).** YY→FF, 3 replicas, longer windows. *Gate:* error from replicas ≤0.3 and overlap OK. Report the signed deviation from −0.95.
5. **Days 18–26.** Remaining 2×2 legs, closure check, and the Asp→Ala positive control (must give a large positive ΔΔG, i.e. a strong loss of binding, because the RGD Asp ligates the metal). *Gate:* the sign is right and the magnitude is reported.
6. **Days 26–30.** Decide go/no-go. If gates 3 and 4 fail, move to option B below. Write up the negative result either way.

Option B (expensive, cluster-sized): QM/MM or an ML potential (MACE/AIMNet-type models with metals [UNVERIFIED availability for Mn]) on the first coordination shell only, as a correction. Warranted *only if* the classical model fails the cluster bench in step 2. Do not start with it: for a 200k-atom relative FEP it is out of budget, and a short-range reweighting (MM→ML/MM) correction on a few hundred snapshots is the realistic form.

## 5. STOP DOING

- Citing the analytic BAR error as the uncertainty.
- Any MM-GBSA discussion beyond a footnote.
- Presenting `loop.py` as a closed loop or an optimizer. It is a rule repair demo.
- Using the Asp→Ala edge only as a stub. Run it, or do not claim metal awareness.
- The number-shopping across test sets for PepGLAD and similar.
- Pursuing further generalization experiments on binding while no oracle exists.

## 6. BIGGEST RISK WE ARE MISSING

The single anchor edge cannot validate anything. Even a perfect match on YY→FF would be consistent with a model that ignores the metal, since the edge is distal. The more insidious risk is that the system *passes* the control through luck (one edge with a ~0.5 kcal/mol window is a ~25–30% chance event for a noisy method) and the resulting "admissible" flag is wired into `score.py`/`reward.py`, so the RL reward then optimises noise. Add to that the unstated assumption that the cofold pose (with a 0.82 Å clash at Mn3) is the true binding mode: FEP only measures free energy *within* the basin you started in, and there is no co-structure for the cyclic series. A wrong pose gives a precise wrong answer with a small error bar. Require pose-ensemble robustness (several starting poses must give consistent ΔΔG within error) before any ΔΔG is used as a reward.