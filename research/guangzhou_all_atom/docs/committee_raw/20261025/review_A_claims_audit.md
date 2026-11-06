# Reviewer A_claims_audit -- openai/gpt-6.1-sol-pro
_(elapsed 96s; usage {'prompt_tokens': 101211, 'completion_tokens': 7394, 'total_tokens': 108605, 'cost': 0.2334142, 'is_byok': False, 'prompt_tokens_details': {'cached_tokens': 30677, 'cache_write_tokens': 30677, 'audio_tokens': 0, 'video_tokens': 0}, 'cost_details': {'upstream_inference_cost': 0.2334142, 'upstream_inference_prompt_cost': 0.1594742, 'upstream_inference_completions_cost': 0.07394}, 'completion_tokens_details': {'reasoning_tokens': 672, 'image_tokens': 0, 'audio_tokens': 0}})_

## 1. VERDICT ON OUR FINDINGS

**The retractions are justified. Several replacement claims are still too strong.** I inspected the supplied code; numerical results, literature, trajectories and deployment changes not included as artifacts remain **reported, not independently verified**.

1. **“Measured ΔΔG = −0.95 kcal/mol; computed magnitude ~5× low” — brief §3.1 → conditional conversion presented as measurement → preserve the assay endpoint.**  
   The observed values are reportedly IC50 = 0.84 and 0.17 nM. At an **assumed 298 K**, \(RT\ln(0.17/0.84)\approx-0.95\) kcal/mol. This is an **IC50-derived apparent free-energy difference**, not directly measured thermodynamic ΔΔG. Equating the ratio to a binding-constant ratio requires compatible competitive-assay conditions and assumptions. Needed: primary table, compound identities, temperature, buffer, assay mechanism, replicates and uncertainties. Say “approximately fivefold potency improvement”; the ratio of computed/measured energy magnitudes is not a useful accuracy metric.

2. **“FEP missed; sign right” — brief §3.1 → acceptable numerical description, not established predictive performance → quantify all uncertainties.**  
   The point estimates differ by approximately **0.77 kcal/mol**. The ±0.15 is reportedly single-run analytic BAR uncertainty, excluding sampling, setup, pose and experimental uncertainty. One edge cannot establish accuracy or statistically reliable sign recovery. Needed: raw BAR output, overlap, time convergence, independent replicas and assay uncertainty. “Invalid setup yielded −0.18 ±0.15” is stronger scientifically than treating this as a calibrated FEP miss.

3. **“Metal never at the site; root cause confirmed; fixed” — brief §3.2 → strong artifact-specific evidence, excessive universal wording → distinguish stages.**  
   The reported EM/NVT/NPT distances and coordinate-frame reconstruction strongly support a placement bug in **build1’s inspected artifacts**. They do not directly inspect every production-window trajectory. Build2’s final solvated geometry supports correcting that placement bug, not validating the system. Its **0.82 Å Mn–O clash remains**; “0/3 failing” means a permissive pre-build gate passed. Needed: artifact hashes, reproducible measurements and final production TPR/trajectory checks. Missing metal has **not** been established as the cause of the numerical discrepancy.

4. **“Unrestrained ≥1 ns is the actual metal-model validation” — brief §§3.2, 4; metal document §6 → necessary screening mistaken for validation → narrow the verdict.**  
   Maintaining two receptor/ligand oxygens per Mn and an intact dummy cage shows short-term structural retention, not correct coordination chemistry, energetics or binding predictions. Restraints may select and preserve an incorrect geometry. Three Mn identities/occupancies are themselves unresolved. Needed: assay-matched ion assignment, site-specific reference geometry, independent starts/replicas and sensitivity to pose/model. Call a successful run **“passed structural-stability screen.”**

5. **“Only genuinely closed loop; real gradient DPO; cluster-disjoint, independent evaluator” — brief §2 → partially supported, materially overstated → repair implementation and evaluation.**  
   `methodology_close.py` does update parameters. However:
   - Greedy seed-neighbour clustering does **not guarantee** that every cross-split pair has Tanimoto <0.6.
   - Both oracles share features, model class and source data; different training rows do not make their errors independent.
   - `seq_logp()` selects each input token’s logit at the same position. This is a **potential autoregressive alignment bug**; inspect `model.forward()` before accepting the DPO implementation.
   - Shared vocabulary does not eliminate OOD combinations, order or conformational differences.
   
   Needed: exhaustive cross-split similarity checks, teacher-forcing unit tests, generator-training overlap audit and measured-label holdout evaluation.

6. **“+0.098; 6/6; p=0.031; placebo +0.014” — brief §2 → results unavailable and inconsistent summary → reconstruct the statistical unit.**  
   Two-sided exact signed-rank p≈0.031 is plausible for six nonzero same-direction differences. It does not establish physical improvement. Reveal §3 additionally reports **“placebo +0.124 vs +0.014, p=0.004”**, without explaining its relationship to +0.098. Needed: seed-level paired data, units, configurations, test specification, multiplicity and placebo comparison. In the supplied code, oracle splitting stays at default seed 0 across generation seeds. These are not six independent data-split replications.

7. **“Availability is intrinsic, therefore transfers; robust ρ=0.40; first-of-its-kind; calibrated” — brief §§3.5, 4 → limited within-study evidence expanded into mechanism, novelty and deployment validity → restrict scope.**  
   Seven held-out SH3 domains do not establish transfer to unrelated sequences, cyclic/ncAA chemistry, extracellular solubility or cell-penetrating peptides. Repeated peptides/families across domains need checking. The 0.23–0.49 range is not a confidence interval. Applying a measured-label quartile to predictions is not threshold calibration. “All 12 pass” and “correctly ranks the greasiest” provide no outcome validation; hydrophobicity is an input.  
   Needed: exact training population—**6,500+ total versus approximately 3,000 PCA1 records**—deduplication, nested sequence/domain splits, simple baselines, uncertainty and external data. “Binding doesn’t transfer,” “ceiling ~0.40,” and “no deployable predictor existed” are unsupported generalizations; novelty is **[UNVERIFIED]**.

8. **“Cheap gates / admissible physics / trustworthy FEP” — brief §2 → contradicted by supplied code → enforce typed evidence.**  
   `score()` accepts explicit numerical overrides without admissibility checks. `reward._num()` accepts booleans and nonfinite floats. Numeric presence is not scientific validity. Missing physics contributes zero, as do worsening ΔΔGs after clipping: ignorance and negative evidence become indistinguishable. Non-gate bonuses sum to **2.5** at their maxima, so the scalar reward does not guarantee gate dominance. Moreover, PD-L1 and GRPR receive `rule_pass=None`, hence fail this implementation’s hard gate. Needed: adversarial unit tests and target-specific policies.

9. **“Every reported performance / no component beats a published bar” — brief §§2–4 → heterogeneous, uncheckable comparisons → require one evidence record per metric.**  
   Parameter count, workflow count, dataset sizes, AUCs, correlations, R², DockQ, ipTM changes, confidence intervals, OOM counts and selectivity ratios lack underlying artifacts here. Some comparators are explicitly different tasks. “ρ=0.42 ceiling” is an observed result, not a ceiling. MM-GBSA controls need not converge when their potencies differ; the **115 kcal/mol separation** instead demands a decomposition/setup audit. Needed: dataset versions, denominators, splits, uncertainty, nulls and matched comparator protocols.

10. **“Ground truth / FTO-blocked / no experimental signal” — brief §§2, 3.6–7, 4 → unresolved provenance and scope contradictions → separate fact types.**  
    Published assays are experimental data; write **“no prospective in-house measurements.”** Absence of RGD means failure of your scaffold rule, not proof of nonbinding. Similarity/genus heuristics do not establish infringement or freedom to operate. A20FMDV2 and Roy-series corrections, structural assignments, SynCraft’s 28.4%/14.1%, and the Landry bibliographic claims remain **[UNVERIFIED]** against primary sources here. Confirm that “no co-structure for these members” is distinguished from “no cyclic-RGD structures.” CC BY-NC-ND warrants licensing review before model/data redistribution or commercial deployment.

## 2. YOUR PROPOSAL FOR YOUR MANDATE AREA

**Build an evidence compiler, not another confidence-producing score.**

Within `research/guangzhou_all_atom/`:

- **Add `cyclic_llm/claim_registry.py`.** Define `ClaimRecord`: statement, endpoint, units, population, source locator/hash, code commit, artifact hash, uncertainty type, assumptions, scope, dependencies and status. Use `reported`, `reproduced`, `screen_pass`, `calibrated_for_scope`, `retracted`—not generic `validated`.
- **Add `cyclic_llm/assay_evidence.py`.** Store IC50/Kd/Ki separately, with stereochemistry, monomer/trimer identity, censoring, buffer and temperature. `apparent_ddg()` must return its conversion assumptions; `>5000 nM` remains censored.
- **Change `score.py::score()` and `reward.py::reward()/build_preference_pairs()`.** Replace scalar physics inputs with evidence-bearing results. Require finite values, matching candidate/reference/target/protocol and passing admission certificates. Disallow uncertified binding preference pairs. Keep missingness explicit; apply gates lexicographically. Treat patent flags as legal-review referrals.
- **Change `methodology_close.py`.** Verify/fix `seq_logp()` alignment; replace claimed scaffold splitting with an audited similarity rule and explicit cross-split checks. Record generator overlap. Make parser failures `unknown`, not admissible. Report validity over **attempted** generations; current returned-sample validity is tautological. Separate uniqueness from chemical diversity.
- **Change `peptide_availability.py`.** Abstain on unsupported chemistry and parse failures; never return a safe-looking `False` flag alongside NaN. Preserve ncAA/mapping coverage in `score.py`. Test signed charge: the fitted equation does not say both charge signs reduce availability.
- **Change live `fep_production.py` submission checks.** Require certificates bound to exact topology, coordinates, restraints, ion assignment and protocol hashes. A marker file or existing `npt.gro` is insufficient. Retain build1 as explicitly invalid.
- **Add `tests/test_claim_contracts.py` and `render_decision_card.py`.** Every candidate output shows *known, assumed, computed, unsupported and next falsification test*. Generate manuscript metric tables from the same registry.

The LLM should propose structured edits and evidence requests. It may summarize certificates; it must not manufacture or upgrade them. Without a binding oracle, reward **valid representation and verified constraint satisfaction**, not inferred affinity. Keep deterministic enumeration as the baseline.

## 3. THE ONE INNOVATION YOU WOULD BET ON

**Counterfactual evidence certificates: test whether the claimed justification is actually necessary for the system’s conclusion.**

For each binding/ranking claim, automatically perturb one dependency:

- remove assay provenance;
- substitute trimer for monomer;
- replay an obsolete topology;
- move metals while preserving the peptide junction;
- change a measured result to an unsupported numerical override.

The compiler must withdraw or downgrade the dependent claim, invalidate cached rankings and block preference emission. The important advance is **end-to-end propagation from physical evidence to training eligibility**, not merely generating an audit report.

Known prior art includes software contracts, data lineage, proof-carrying code, mutation testing and selective prediction. The packet’s SynCraft description is **[UNVERIFIED]** and already defeats generic novelty claims for LLM-plus-rules. I do not know whether this exact molecular-design implementation exists; priority is **[UNVERIFIED]**.

**Falsification:** on a frozen, hidden corruption suite, certificates fail to reduce unsupported accepted claims relative to ordinary provenance checks at matched coverage and review cost—or achieve safety only by abstaining on everything. This tests audit innovation, not improved affinity.

## 4. 30-DAY PLAN

1. **Days 1–4: freeze and inventory — cheap CPU/reviewer work.**  
   Register every numerical and “validated/fixed/confirmed” claim in the supplied documents.  
   **Gate:** 100% have a primary artifact/source or explicit `reported/unverified` status. Otherwise freeze manuscript and binding claims.

2. **Days 5–8: reconcile primary evidence — cheap, human-intensive.**  
   Verify assay tables, chemical identities, conversion assumptions, cited publications and licenses. Reconcile DPO result variants and model-training counts.  
   **Gate:** every benchmark anchor has complete identity and endpoint metadata; unresolved anchors cannot calibrate physics.

3. **Days 9–14: repair evaluator and admission code — cheap/moderate CPU.**  
   Test DPO token alignment, all cross-split similarities, overrides, nonfinite values, unsupported targets and parsing.  
   **Gate:** zero known admission bypasses; any failed alignment/split test triggers retraction and rerun of affected summaries.

4. **Days 15–20: retrospective evaluation — moderate compute, no wet lab.**  
   Refit availability with nested sequence/domain holdouts; compare against hydrophobicity-only and charge-only baselines. Rerun DPO with repaired evaluation and shuffled rewards.  
   **Gate:** retain “transfer benefit” only if a preregistered clustered confidence interval for improvement over the relevant baseline excludes zero; otherwise label inconclusive.

5. **Days 21–26: conditional physics screen — expensive GPU work.**  
   First resolve ions, live dispatch and structural criteria. Run restrained assembly followed by unrestrained replicas; profile throughput before approving FEP expenditure.  
   **Gate:** no production FEP until all preregistered structural screens pass. Success authorizes further testing—not “metal-model validation.”

6. **Days 27–30: hidden corruption audit and release — cheap/moderate.**  
   Test at least 20 frozen corruption cases plus valid controls against a provenance-only baseline.  
   **Gate:** zero accepted critical corruptions, at least 90% valid-control acceptance, and lower unsupported-claim acceptance at matched coverage. Otherwise release only the registry, failures and corrected evidence cards.

## 5. STOP DOING

- Calling numerical hooks “trustworthy arbiters.”
- Treating an independent ML fit as independent experimental confirmation.
- Training affinity preferences from uncertified physics or legal heuristics.
- Calling sorted outputs “Pareto sets” without nondominance computation.
- Reporting post-filter validity, unmatched SOTA comparisons or unspecified-unit improvements.
- Using short trajectory retention, correct prediction of a build log or a parser success as scientific validation.
- Replacing overconfident positive narratives with equally universal “binding never transfers” narratives.

## 6. BIGGEST RISK WE ARE MISSING

**The benchmark may expose a coupled binding-mode/conformational problem, not a simple calibration offset.**

Using the reported 2×2 IC50 grid, the **IC50-derived apparent interaction contrast** at assumed 298 K is:

\[
RT\ln\frac{IC50_{FF}IC50_{YY}}{IC50_{FY}IC50_{YF}}
=RT\ln\frac{0.17\times0.84}{2.8\times3.3}
\approx-2.47\ \text{kcal/mol}.
\]

This is not yet thermodynamic epistasis: assay comparability and errors remain unresolved. But it warns against extrapolating one double-mutation edge into an affinity oracle. Strong coupling could reflect conformational selection, alternate poses or assay effects. FEP cycle closure alone cannot establish correctness.

**Audit the entire four-corner grid before optimizing new binders.** Otherwise a more capable LLM will simply search a miscalibrated oracle more effectively.