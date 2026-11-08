# Reviewer B_methodology — openai/gpt-6-astra-pro
_(elapsed 140s; usage {'prompt_tokens': 79238, 'completion_tokens': 12171, 'total_tokens': 91409, 'cost': 1.259815, 'is_byok': False, 'prompt_tokens_details': {'cached_tokens': 21710, 'cache_write_tokens': 21710, 'audio_tokens': 0, 'video_tokens': 0}, 'cost_details': {'upstream_inference_cost': 1.259815, 'upstream_inference_prompt_cost': 0.651265, 'upstream_inference_completions_cost': 0.60855}, 'completion_tokens_details': {'reasoning_tokens': 2009, 'image_tokens': 0, 'audio_tokens': 0}})_

## VERDICT: MAJOR REVISION (confidence 0.98)

**The work demonstrates useful workflow integration, not validated binder discovery or binding-safe permeability redesign.** Its central inference repeatedly substitutes agreement with—or optimization of—an unvalidated computational score for evidence of biological improvement.

More seriously, the supplied code contains molecular-representation errors that directly affect the reported permeability objectives. The N-methyl force field is operational but not validated, and the manuscript’s explanation of single-trajectory energy cancellation is incorrect.

This review is based on the supplied documents and source inspection; the underlying structures, datasets, training code, and run artifacts were not available for independent execution.

## TOP 3 THINGS THAT ARE RIGHT

1. **Separating generator confidence from downstream evaluation is sensible engineering.** Automated cyclic topology construction, scoring, and candidate tracking could be a useful methods contribution. Reported completion on **32/32 structures** supports operational feasibility on this test set—though not physical accuracy.

2. **Several limitations are disclosed rather than hidden.** The manuscript identifies the lack of wet-lab validation, MM-GBSA size bias, out-of-distribution permeability prediction, and the unsuccessful two-environment experiment. Reporting unsuccessful approaches is valuable when their conclusions remain proportional to their statistical power.

3. **The correction from maximizing donor-removal “headroom” to minimizing post-redesign donor burden is directionally correct.** Maximizing ΔHBD rewards large, donor-rich starting molecules. Recognizing this objective-design failure is useful. Unfortunately, the corrected implementation still scores the wrong molecular state and does not establish permeability improvement.

## CRITICAL ISSUES (must-fix; each: claim/location -> problem -> concrete fix)

### 1. “Physics systematically reranks” becomes “physics is correct and non-optional”
**Claim/location →** Manuscript §§3.2, 3.9–3.10 and Discussion: top-iptm candidates fall to ranks **5–7/8**; Spearman **−0.04**; therefore physics verification is “non-optional,” identifies “true dual-optimal designs,” and confirms candidates are “sound.”

**Problem →** The results support **disagreement between two scores**, not superiority of either score. An inaccurate or size-biased score can systematically reorder a generator. Independence of the scoring formula does not establish independent predictive validity; the MM-GBSA calculations also inherit generator-produced poses.

The size confound is central, not a footnote. Longer peptides generally provide more interaction surface and more favorable extensive interaction energies. Within-target standardization does not remove this. Selecting smaller peptides can therefore worsen MM-GBSA even if iptm contains useful binding information.

**Concrete fix →**
- Benchmark both scores against measured affinities for cyclic peptides, including experimentally weak/nonbinding controls and size-/charge-matched comparators.
- Report per-target correlations and rankings, with uncertainty.
- Analyze dependence on length, MW, net charge, buried surface area, and contact count. Use matched-size comparisons and an adequately powered adjusted analysis; simple energy-per-residue normalization is not a complete solution.
- Until validation exists, replace “physics binding,” “true binders,” and “non-optional oracle” with **“minimized MM-GBSA score”** and **“complementary computational evaluator.”**

**Support assessment:** Score reranking: **yes, provisionally**. Better binder identification: **no**.

### 2. The molecular descriptors do not consistently describe cyclic, redesigned peptides
**Claim/location →** §§3.3, 3.6, 3.8–3.10; reported **36% fewer donors**, **30% lower MW**, and examples such as `GPFVPGL` with **one donor after redesign**.

**Problem →**
- `perm_generation_v3.py` explicitly computes descriptors on `Chem.MolFromSequence(seq)`: a **linear peptide**, not a head-to-tail macrocycle.
- `perm_redesign_v1.py` has an unsafe cyclization implementation that can remove the carbonyl oxygen instead of the hydroxyl oxygen, select a side-chain carboxyl group, or silently return the linear molecule.
- Neither script constructs the actual N-methylated product before reporting its MW, TPSA, or donor count.
- Each backbone N-methylation adds approximately **14.03 Da**. The proposed methylations add roughly **28–196 Da** across the stated 2–14-site range. This can materially change the optimization.
- RDKit donor counts on neutral acid-containing structures are not automatically physiologically relevant donor counts.

**Concrete fix →** Build one shared, atom-mapped molecular transformation library that:
1. Identifies terminal backbone atoms by residue and atom identity.
2. Forms the correct cyclic amide.
3. Applies the selected N-methylations.
4. Validates valence, stereochemistry, formula, charge, ring connectivity, and donor counts.
5. Computes all descriptors on that exact final molecule.

Recompute every affected table, candidate ranking, percentage improvement, and conclusion. Include tests for terminal Pro, Asp/Glu, charged side chains, and multiply methylated products.

**Support assessment:** The numerical permeability-objective improvements are **not currently reliable**.

### 3. “Binding preserved by construction” is chemically unjustified
**Claim/location →** §3.6 and redesign documentation: absence of a backbone-N/receptor contact within **3.5 Å** means methylation preserves binding; good binders are “side-chain-driven.”

**Problem →** Absence of one putative direct hydrogen bond does not imply a chemically neutral modification. N-methylation can change:
- backbone torsions and cis/trans populations;
- intramolecular hydrogen bonding and preorganization;
- steric packing against the receptor;
- hydration and desolvation;
- free- versus bound-state conformational populations.

The classifier treats **every receptor O and N as an acceptor**, without chemical typing or angular criteria. Many nitrogens are not acceptors. It does not evaluate methyl-group clashes or solvent exposure. “Not hydrogen-bonding to the receptor” is not equivalent to “exposed.”

Counting few backbone hydrogen bonds also does not establish that the binding free energy is side-chain-driven.

**Concrete fix →**
- Rename these positions **“candidate N-methylation sites lacking a detected direct backbone contact.”**
- Use chemically typed acceptors, hydrogen-bond geometry, conformational occupancy, intramolecular interactions, and modeled methyl sterics.
- Test individual methylations and selected combinations, including contact-disrupting controls.
- Measure matched-pair binding and permeability, or provide validated computational matched-pair benchmarks before claiming binding preservation.

**Support assessment:** Identifying candidate modification sites: **partially**. Binding-safe headroom: **no**. Donor removal is also not a universal necessary condition for permeability improvement.

### 4. The single-trajectory cancellation explanation is wrong
**Claim/location →** §3.7: complex and ligand energies increase by **+150 to +320 kcal/mol**, ΔΔG is **1–4%** of those changes, and therefore ligand strain “inflates apparent binding.”

**Problem →** Cancellation of intramolecular terms is an intended feature of single-trajectory MM-GBSA. With consistent topologies and shared coordinates, matching receptor and ligand internal terms cancel in

\[
\Delta E=E_{\mathrm{complex}}-E_{\mathrm{receptor}}-E_{\mathrm{ligand}}.
\]

A small residual relative to large component energies is **not itself evidence of numerical unreliability or methylation-induced strain inflation**. The real limitation is that this estimator omits the free-state reorganization cost and conformational population changes; it does not directly measure the asserted strain artifact.

The quoted ratio is not an uncertainty estimate. The claim that ΔΔG tracks methyl count rests on four heavily confounded examples.

Nor does an acknowledged unreliable calculation support “no binding degradation.” It supports **no reliable determination of binding change**.

**Concrete fix →**
- Correct the theoretical interpretation.
- Report force-component decompositions and atom-mapping checks demonstrating expected cancellation.
- Separate parameter errors, numerical precision, missing reorganization, and sampling uncertainty.
- Evaluate conformational ensembles and validated matched pairs.
- Treat three-trajectory MM-GBSA as a potentially noisy alternative, not an automatic remedy.

**Support assessment:** The calculation ran: **yes**. Binding preservation or the proposed explanation of its failure: **no**.

### 5. “Correct N-methyl parametrization is solved” is unsupported
**Claim/location →** Redesign v2 documentation and `peptide_nmethyl_mmgbsa.sh`: borrowed CHARMM terms and mirrored amide-H terms yield a “working N-methyl parametrization.”

**Problem →** Parameter completeness is not parameter validity. Replacing an amide hydrogen with a methyl group changes sterics, electronic structure, and torsional energetics. Terms that stop OpenMM from reporting missing parameters—including numerous zero-amplitude dihedrals—do not establish a physically accurate potential.

Using approximate charges “only for relative ΔΔG” does not remove their effect on relative solvation and binding. FEP using the same inaccurate parameters would not fix this.

**Concrete fix →**
- Prefer an established, compatible N-methyl-amide parameterization.
- Otherwise validate charges, torsional surfaces, amide planarity, cis/trans energetics, and representative conformational populations against appropriate reference data.
- Audit the cyclic closure and methylation topology for impropers, CMAP terms, exclusions, and native disulfides.
- Distinguish **“topology builds and minimizes”** from **“force field validated.”**

**Support assessment:** Operational topology construction: **yes**. Correct energetic model: **not demonstrated**.

### 6. Permeability predictions and negative model results are substantially overinterpreted
**Claim/location →** §§3.3–3.5: all candidates are poorly permeable “because” the generator optimizes binding; static descriptors have an empirical **0.45–0.55 ceiling**; mean N-methylation effect **+0.06 log units** proves 2D models “cannot see” the lever.

**Problem →**
- OOD model predictions of **−7.5 to −8.4** do not establish actual permeability or its cause.
- One model and literature comparisons cannot establish a representation ceiling.
- 2D descriptors explicitly encode donor removal, molecular size, polarity, and related methylation changes. A weak response from this fitted model may reflect training coverage, saturation, preprocessing defects, or averaging of opposing effects.
- The conformer-span comparison **0.246 versus 0.262** has no reported sample size, paired uncertainty, or matched baseline details.
- Failure of a cheap surrogate with **28 designs** cannot establish that physics is “not shortcut-able.”
- None of these failures localizes the remaining predictive advantage uniquely to expensive conformation-aware modeling.

**Concrete fix →**
- Supply training/evaluation code and split identities.
- Use deduplicated, series-/publication-/assay-grouped evaluation and an external test set.
- Evaluate experimentally measured parent/N-methyl matched pairs; report the distribution of predicted changes and the descriptor changes themselves.
- Report repeated-split uncertainty and paired ablations on identical molecules.
- Restrict negative conclusions to the tested model, features, dataset, and sample size.

**Support assessment:** Dataset-specific model performance may be valid but is **not auditable here**. A universal descriptor ceiling, inherent 2D blindness, causal generator failure, and impossibility of surrogates: **not supported**.

### 7. The selection experiment evaluates its own objective and mixes different chemical species
**Claim/location →** §§3.8–3.10: “permeable binders,” “genuine dual-optimal designs,” and generalization across target classes.

**Problem →**
- Selecting on low MW and donor count and then reporting lower MW and donor count is an expected optimization outcome, not independent permeability validation.
- The MM-GBSA scores in v3 concern **unmethylated parents**, whereas the donor objective concerns hypothetical **methylated products**. No single molecule has demonstrated both claimed properties.
- Only the **14-design union** of two top-eight sets is scored for 1yf4. These sets overlap and are not independent samples; the remaining pool is unverified.
- Differences of **−29.6 versus −38.9** and **−23.7 versus −22.4 kcal/mol** have no sampling or model uncertainty.
- The “deep pocket versus shallow interface” explanation is post hoc. Two targets do not establish a universal safeguard or target-class generalization.

**Concrete fix →**
- Score all candidates from repeated generation runs, not only selected unions.
- Compare against random selection, MW-only, donor-only, MM-GBSA-only, and length-matched baselines at equal generation and scoring budgets.
- Freeze weights before independent evaluation.
- Evaluate binding and permeability for the **same explicitly constructed final products**.
- Use additional held-out targets and independent experimental endpoints for the generalization claim.

**Support assessment:** Proxy-guided selection works operationally: **yes**. Discovery of strong, permeable final products: **no**.

## MAJOR CONCERNS

1. **The statistics do not establish orthogonality.**  
   A pooled Spearman correlation between iptm and within-target standardized energy is not the same as a properly stratified within-target association. With eight candidates per target, estimates are noisy; there are only four target-level replications. Report individual target estimates, uncertainty, stratified permutation analyses, and power to exclude scientifically meaningful associations. Failure to detect correlation is not evidence of independence.

2. **§3.1 conflates completion with robustness and accuracy.**  
   “32/32 built” supports completion on those inputs. It does not verify ring geometry, stereochemistry, native covalent connectivity, minimized force tolerance, or ranking reproducibility. Required controls include independently constructed reference topologies, structural geometry checks, deliberate malformed inputs, and independently initialized conformational sampling.

3. **A minimized single point is not a binding free energy.**  
   The supplied scripts run minimization, not MD sampling. Calling the output ΔG obscures omitted entropy, free-state ensembles, protonation equilibria, and model errors. Report the actual estimator and validate its ranking performance. Specify GB radii, dielectric constants, salt settings, cutoff sensitivity, and minimization convergence.

4. **The permeability dataset requires an assay audit.**  
   “8,466 peptides, log Papp” is insufficient. Document assay types, units, pH, detection limits, censored values, aggregation rules, repeated measurements, and chemical standardization. Similar random/scaffold scores of **0.45/0.41** do not by themselves demonstrate scaffold degeneracy; provide scaffold frequencies and cross-split chemical similarity.

5. **FEP is not a guaranteed “~1 kcal/mol arbiter.”**  
   N-methylated macrocycles can have slow conformational transitions. Relative transformations between different-length, sequence-diverse candidates may be difficult or inappropriate without carefully designed mappings. Specify the thermodynamic cycle, parameter validation, sampling diagnostics, replicate uncertainty, and applicable benchmark performance. FEP does not measure permeability.

6. **Oral exposure is not reducible to passive permeability.**  
   Solubility, efflux, metabolic stability, and formulation also matter. Nor is intracellular permeability necessarily a therapeutic requirement for the receptors studied. Separate a generic developability objective from target-specific pharmacological requirements.

7. **Reproducibility remains inadequate.**  
   A branch name and S3 paths are not immutable research artifacts. Release exact commit IDs, accessible data manifests, checksums, environment locks, generator seeds/configuration, inclusion/exclusion records, and commands that regenerate every table. Explain **28 versus 32** designs in the surrogate experiment and differences such as **−52.7 versus −52.4** for the reference candidate.

## MINOR ISSUES

- The v3 description says “Pareto,” but the supplied implementation is a **weighted scalar score**, not Pareto-front computation.
- The default comparator is selected by `final_rank`; the text repeatedly calls it “ranked by iptm.” Demonstrate that these are equivalent or correct the description.
- Proline is included in `keep_bb_donors` despite having no backbone NH donor.
- `HBD_redesign` is a donor-site count, not measured exposed polar surface area.
- The v3 JSON hypothesis still rewards increased ΔHBD despite the documented switch to an end-state objective.
- The redesign document’s bottom line says the N-methyl patch and selection wiring remain unbuilt after earlier sections report completion.
- Verify references and novelty claims before submission, especially claims about the field requiring interactive setup and a universal static-descriptor ceiling.
- Replace repeated assurances that interpretations are “honest” with explicit evidence grades and uncertainty.

## SPECIFIC CODE BUGS (file:approx-location -> bug -> fix; write 'none found' if so)

1. **`perm_redesign_v1.py: cyclic_mol()` → incorrect terminal oxygen selection.**  
   Both terminal carboxyl oxygens have degree one; the code removes the first encountered oxygen without testing bond order. Removing the double-bonded oxygen can produce incorrect chemistry that may still sanitize.  
   **Fix:** Identify and remove the singly bonded terminal hydroxyl oxygen explicitly; verify the resulting amide and molecular formula.

2. **`perm_redesign_v1.py: cyclic_mol()` → terminal carbon selection is not residue-specific.**  
   The loop accepts any carbon with two oxygen neighbors, including Asp/Glu side-chain carboxyls, and retains the last match.  
   **Fix:** Select backbone atom `C` of the final residue and backbone atom `N` of the first residue using residue metadata.

3. **`perm_redesign_v1.py: cyclic_mol()` → cyclization errors silently return a linear peptide.**  
   Downstream output labels this molecule cyclic regardless of transformation success.  
   **Fix:** Fail explicitly or mark the design invalid; assert closure connectivity and expected loss of H₂O.

4. **`perm_generation_v3.py: analyze(), descriptor calculation → linear descriptors used for cyclic candidates.**  
   `MolFromSequence` leaves terminal groups present. Linear MW exceeds the corresponding head-to-tail cyclic MW by approximately **18.015 Da**; donor and TPSA values also differ.  
   **Fix:** Use the validated cyclic molecular builder.

5. **Both Python scripts: redesigned descriptor calculation → no actual methylated product.**  
   Donors are reduced arithmetically, while MW and TPSA remain parent descriptors. `max(0, ...)` can conceal inconsistent chemistry.  
   **Fix:** Apply atom-mapped methylation, recompute all descriptors, and assert donor changes rather than clipping invalid results.

6. **Both Python scripts: `parse_cif()` / chain selection → fragile CIF parsing and ambiguous peptide identification.**  
   Fixed token offsets assume column order; parse failures silently drop atoms. Smallest-chain selection can select a ligand, solvent chain, or unrelated short chain. Models and alternate locations are not handled explicitly.  
   **Fix:** Use Gemmi’s mmCIF reader, explicit chain/entity assignments, and sequence validation.

7. **Both Python scripts: receptor acceptor construction → all N/O atoms treated as acceptors.**  
   This misclassifies amide and protonated nitrogens and ignores hydrogen-bond directionality. With no receptor acceptors, the code also silently assigns no candidate sites.  
   **Fix:** Chemically type acceptors and distinguish valid no-contact cases from incomplete receptor inputs.

8. **Both shell scripts: `split()` → only the longest receptor chain is retained.**  
   Other protein chains and cofactors are discarded. This is particularly consequential for multichain receptors such as Fabs.  
   **Fix:** Explicitly specify the peptide and complete receptor assembly; preserve all relevant components with separate segment identities.

9. **Both shell scripts: topology construction → native and closure topology is insufficiently checked.**  
   There is no explicit disulfide patching. `CYCP` adds a bond and regenerates angles/dihedrals but does not explicitly restore closure-dependent impropers or CMAP terms.  
   **Fix:** Audit complete topology against a trusted cyclic reference, add required patches/terms, and test native disulfide connectivity.

10. **Both shell scripts: energy slicing → atom correspondence assumed from particle count.**  
    `P[:nrec_atom]` and the remainder assume separately built systems have identical atom order and internal topology. A matching count alone is insufficient.  
    **Fix:** Assert atom identity and ordering, bonds, exclusions, and particle parameters, or extract subsystems through explicit mappings.

11. **`peptide_nmethyl_mmgbsa.sh: result verdict → unsupported binding classification emitted automatically.**  
    `ddG <= 3` produces **“binding PRESERVED”**, directly contradicting the manuscript’s acknowledgment that these calculations are unvalidated.  
    **Fix:** Emit an unvalidated score difference with no biological verdict; remove the arbitrary threshold.

12. **Both shell scripts: exception handling and completion → failed calculations can be marked complete.**  
    Python catches calculation errors without returning failure; the shell proceeds to `nm_complete` or `v3verify_complete`. Missing CIFs can bypass the per-item checkpoint through `continue`.  
    **Fix:** Enforce success counts, checkpoint failures as well as successes, and exit nonzero on incomplete required outputs.

13. **`perm_generation_v3.py: metric joins → missing rankings and iptm values silently enter selection.**  
    Missing IDs receive rank `999`, and missing iptm contributes a neutral score. A missing metrics file can therefore produce a plausible-looking but invalid comparison. JSON may contain nonstandard `NaN`.  
    **Fix:** Require complete validated joins, finite values, unique IDs, and strict JSON serialization.

14. **`perm_redesign_v1.py: global scoring → cross-target energy normalization.**  
    `muG, sdG` pool energies across receptors despite the manuscript stating cross-target energies are not comparable. This also makes within-target trade-off strength depend on unrelated targets.  
    **Fix:** Normalize within target or use a separately validated calibration.

15. **Shell scripts: environment/provenance → incomplete parameter propagation and nonreproducible dependencies.**  
    Default `CIF_S3` is not exported to Python, so result provenance can become `"design"`; checkpoint uploads depend on `OUT_S3` being inherited. Dependencies are installed without version locks.  
    **Fix:** Pass configuration explicitly, store input hashes/full parameters, pin environments, and make shutdown behavior opt-in rather than unconditional.

## WHAT WOULD MAKE THIS PUBLISHABLE / PRODUCTION-READY

1. **Repair the molecular representations and rerun all dependent analyses.** This is a prerequisite, not an optional robustness check.
2. **Validate topology and force-field behavior independently**, including cyclic closure, disulfides, and N-methyl chemistry.
3. **Establish predictive validity on measured controls**, rather than treating MM-GBSA disagreement as validation.
4. **Run controlled, repeated selection experiments** with equal budgets, size-matched baselines, complete-pool scoring, and held-out targets.
5. **Evaluate the same final molecules for both objectives.** Parent binding scores cannot substantiate methylated-product dual optimality.
6. **For the current discovery claims, obtain matched-pair binding and permeability measurements.** Otherwise narrow the paper to a reproducible workflow and computational candidate-prioritization study.
7. **Release executable, immutable artifacts and fail-closed software** with chemical unit tests, strict schemas, checkpointing, and explicit uncertainty/status reporting.

A defensible current conclusion is: **“We integrated complementary scoring tools and