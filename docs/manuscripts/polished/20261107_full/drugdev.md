# DrugDev Bench evaluates decisions from molecular discovery to dose selection

**Yaoyun Zhang**¹, **Andrew Dike**¹,²

¹ BioMate AI  
² BizBildr

**Correspondence:** Andrew Dike (a.dike@bizbildr.com); Yaoyun Zhang (yaoyun.zhang@biomate.ai).

*Preprint · 7 November 2026*

## Abstract

Drug development connects molecular predictions to decisions about candidates, exposure and the next experiment. Evaluating these decisions requires explicit reference policies and a distinction between plausible answers and successful execution. Here we present DrugDev-Bench, a four-track framework spanning molecular workflows, targets and perturbations, evidence retrieval, and cross-stage execution. Instantiated components include five stage benchmarks, eight relative binding free-energy series containing 264 ligands, and 30 decision tasks across nine archetypes. Model comparisons expose strong dependence on task construction. Across retained Claude Opus 5 runs, exact dose agreement ranges from 0.25–0.30 on 20 hand-authored scenarios to 0.95–1.00 on 20 generated scenarios; these are run ranges, not confidence intervals. An oracle with access to hidden toxicity curves matches 17 of 20 hand-authored labels, exposing disagreements between reference labels and the implemented policy. The highest reported pharmacokinetic agreement is 0.467 within twofold on 15 hand-authored cases. Offline scorer and workflow-composition checks provide complementary implementation evidence. DrugDev-Bench makes information access, reference provenance and execution requirements explicit, enabling task-specific comparisons without treating formula agreement as validated drug-development performance.

## Introduction

A drug-development programme requires decisions under constraints: which target warrants further study, which analogue should advance, whether exposure is sufficient, and which experiment or development step should follow. Accurate predictions of individual properties are useful inputs, but they do not establish that an agent can integrate those predictions into a defensible project decision. A benchmark should therefore identify the information available to the solver, the policy defining a correct decision and the evidence required to confirm its execution.

The external benchmark landscape is extensive. Therapeutics Data Commons provides tasks and datasets across therapeutic discovery and development [1]. TrialBench includes dose finding among its clinical-trial prediction tasks [2]. Molecular-property, docking, affinity, free-energy, synthesis, target-discovery and literature-retrieval resources provide further comparison points. DrugDev-Bench builds on this ecosystem; its contribution is the organization of development decisions and execution checks, not a claim that drug-development or dose-finding benchmarks were previously absent.

The suite combines four tracks: molecular-tool workflows; target and perturbation tasks; search and knowledge; and execution-grounded, cross-stage tasks (Fig. 1). Five stage benchmarks connect established molecular tasks to pharmacokinetics and dose selection. A relative binding free-energy benchmark reuses experimentally grounded ligand-series data, while a 30-item decision suite specifies nine recurring project decisions. Their ground-truth sources differ and must remain explicit: experimental affinity data, reference formulas, model-derived curves, curated policy labels and provisional class-level values are not interchangeable forms of evidence.

The study examines how reference policies, input specification and workflow compatibility shape the conclusions of an agent benchmark. The evaluation has two layers. Offline tests establish the behaviour of scorers, adapters and training exports. Model experiments then assess selected dose and pharmacokinetic tasks, with distinct hand-authored and generated tiers. Neither layer establishes that the entire four-track suite has been run across a model roster. The execution-grounded track specifies terminal-state and artifact checks; the reported composer diagnostics assess prerequisites for that track rather than completed drug-development outcomes.

![Four tracks and evaluation layers of DrugDev-Bench.](figures/drugdev_suite.png)

**Figure 1. DrugDev-Bench scope.** The four tracks retain molecular workflows, targets and perturbations, search and knowledge, and cross-stage execution. Stage benchmarks, the eight-series free-energy dataset and the nine-archetype decision suite provide instantiated components. Offline validation and selected model experiments are distinguished from full execution validation. The diagram describes the suite design, not uniform evaluation coverage.

## Results

### Two task tiers separate specified calculations from contextual decisions

Dose and pharmacokinetic experiments examine two complementary decisions within the broader suite. There are 20 hand-authored and 20 generated dose scenarios, plus 15 hand-authored and 15 generated PK cases. These are separate tiers, and the presence of 30 PK cases does not imply that the reported model leaderboard evaluates all 30. The comparison of hidden-reference access and solver-visible inputs is shown in Figure 2.

![Information access for dose decisions.](figures/drugdev_design.png)

**Figure 2. Dose-model and oracle conditions.** A model receives the scenario inputs and dose grid; the oracle receives the hidden toxicity curve. Both are checked against the selected-dose label, but their information differs. Generated labels use the same formula and decision policy as the oracle, so agreement there is a construction property. No claim of an input-matched mechanistic system comparison follows.

### The oracle exposes reference-policy disagreements

On the 20 hand-authored scenarios, the oracle reproduces 17 dose labels, for accuracy of 0.85. Its benchmark-defined safety score is 0.90 and its curve fidelity is 1.00, the latter following directly from access to the reference curve. Two disagreements concern no-safe-dose labels that are not triggered by the implemented elimination threshold; a third concerns closest-to-target selection and the reference's higher-dose choice. These cases require label-policy adjudication before they can be interpreted as solver errors.

The historical dose-only leaderboard and the structured-response evaluation use different denominators. The former excludes the two null-dose references and scores 18 scenarios; the latter includes all 20 and treats no-safe-dose decisions as outcomes. The earlier 0.11–0.50 model range therefore cannot be directly compared with the 17/20 oracle value as though both used an identical task definition. We retain structured-response results separately (Table 1) and do not combine the two protocols into a model ranking.

### Structured dose responses differ substantially between tiers

On the hand-authored tier, the retained Claude Opus 5 runs score 0.25 and 0.30, with curve fidelity of approximately 0.60–0.68 and no empty responses. The direct-provider GPT-6.1-sol runs both score 0.10 with fidelity approximately 0.01; they contain four and one empty responses, respectively. The tier comparison is summarized in Figure 3. These are run-level observations rather than precise estimates of a model's general dose-selection capability.

**Table 1. Recorded structured-response dose outcomes.** Each tier contains 20 scenarios. Ranges describe retained runs, not confidence intervals. Empty-response counts apply to the hand tier; an em dash denotes the oracle. Local models use reasoning-disabled serving. Recorded scores remain provisional pending the scorer and reference-policy reconciliation described in Methods.

| Model or reference | Hand outcome | Hand fidelity | Hand empties | Generated outcome |
|---|---:|---:|---:|---:|
| Oracle with hidden curve | 0.85 | 1.00 | — | 1.00 by construction |
| Claude Opus 5 | 0.25–0.30 | 0.60–0.68 | 0 | 0.95–1.00 |
| GPT-6.1-sol | 0.10 | ≈0.01 | 1–4 | 1.00 |
| Stock Qwen3.5-9B | 0.30 | 0.58 | 0 | 0.30 |
| BioMate 9B continued-pretrained | 0.50 | 0.74 | 0 | 0.05 |
| BioMate 9B fine-tuned | 0.30 | 0.31 | 0 | 0.10 |

With explicit generated-tier exposure–response parameters, a retained run of each of Claude Opus 5, GPT-6.1-sol and Gemini 3.1 Pro reaches 1.00 outcome and 1.00 fidelity with no empty responses. Three additional Opus runs have outcomes 1.00, 1.00 and 0.95. Thus, the generated task is not uniformly unsolved by language models. The tier contrast is consistent with sensitivity to specification, but differences in item construction and label consistency prevent attributing it solely to inferring an implicit exposure–response relation.

The continued-pretrained local 9B model scores 0.50 on the hand tier and 0.05 on the generated tier. This reversal argues against a simple capability ordering across the two item sets. Model scale, training and reasoning settings are not independently controlled, so these observations cannot establish which factor causes the difference.

![Dose agreement across hand-authored and generated tiers.](figures/drugdev_dose.png)

**Figure 3. Dose agreement depends on tier and information access.** Exact outcome agreement on two distinct sets of 20 scenarios reproduces Table 1. Left, the five model configurations with results on both tiers; a horizontal segment spans the minimum and maximum retained run scores, and a single marker denotes a single recorded value. These segments are not confidence intervals, and the item sets are not paired. Right, the hidden-curve oracle is separated because it receives privileged information; generated-tier agreement follows from the reference construction. Local models use reasoning-disabled serving. The results remain provisional pending reference-policy and scorer reconciliation; they do not establish a causal effect of model scale or input specification.

### PK agreement remains limited on hand-authored cases

After the target endpoint was specified as peak concentration in micromolar, the stored leaderboard reports a maximum within-twofold agreement of 0.467 on 15 hand-authored compounds (Table 2; Fig. 4). These results describe agreement with the benchmark reference values. They do not establish clinical accuracy, and the generated PK cases are not included in this table.

**Table 2. PK endpoint agreement on the hand-authored tier.** The endpoint is the benchmark's peak-concentration reference in micromolar; a prediction succeeds when its ratio to the positive reference lies between 0.5 and 2.0 inclusive. The denominator is all 15 reference cases, with missing or unparseable predictions counted as failures. Stored rounded values are reproduced without changing the original predictions.

| Model | Within twofold |
|---|---:|
| Claude Opus 5 | 0.467 |
| Gemini 3.1 Pro | 0.400 |
| GPT-5.6 | 0.200 |
| GPT-5.6-luna | 0.333 |
| Qwen3.8-Max | 0.000 |
| Qwen3.8-27B | 0.000 |
| GLM-5.2 | 0.267 |
| DeepSeek V4-pro | 0.067 |
| Kimi K3 | 0.000 |
| BioMate 9B (base) | 0.067 |
| BioMate 9B (SFT) | 0.000 |
| Biomni (A1 scaffold) | 0.000 |

The earlier endpoint-ambiguous prompt is excluded from conclusions about model capability. The correction illustrates why exposure benchmarks need an explicit analyte, units, dose, route, sampling context and reference provenance. The current cases still require stronger source documentation for those assumptions.

![Pharmacokinetic endpoint agreement across recorded models.](figures/drugdev_pk.png)

**Figure 4. Pharmacokinetic agreement remains limited after endpoint specification.** Points reproduce the stored rounded within-twofold agreement values in Table 2 for 15 hand-authored cases per row. Missing or unparseable predictions count as failures. Rows are ordered by score for readability; ties do not establish model equivalence. This is agreement with benchmark peak-concentration references in micromolar, not evidence of clinical prediction accuracy. Generated cases and earlier endpoint-ambiguous runs are excluded. No confidence intervals are inferred from the rounded aggregate values.

### Ligand ranking is a complementary but coarse endpoint

The historical shared export includes 15 ligand-ranking items and reports mean Spearman correlation of 0.696 across eight direct-model systems. A domain-agent value of 1.0 covers only four completed cases and is not a full-set result. With only three ligands in a ranking item, the possible correlations are coarse. Consequently, that result is evidence about a small ranking task; it does not demonstrate docking-pose accuracy, prospective affinity prediction or completion of a discovery programme. The ranking component is retained in the suite alongside the richer relative free-energy dataset, rather than discarded because its metric is limited.

### Offline validation establishes scorer consistency

The initial suite validation reports six relative binding free-energy scorer checks, 15 decision-scorer checks and five chain-scorer checks passing. The decision adapter passes 14 checks across the nine archetypes, together with seven lead-optimization exemplar checks. These counts describe the test cases used in the source validation, not independent scientific tasks or external evaluations. Dose-decision grading is also checked against its defined policy.

All 30 synthesized supervised-fine-tuning targets receive a score of 1.0 under their corresponding scorer. The export rejects a target scoring below 0.9. The training split contains 22 items and the evaluation split eight; the reported reward-contract test passes on all 22 training items. This checks that the exported gold completion scores above a trivial wrong completion. It does not establish that the reward resists adversarial optimization or that training improves model capability (Table 3).

Supplying the experimental relative free energies back to the free-energy scorer gives zero root-mean-square error and a composite of approximately 0.98. The residual below 1.0 reflects the implementation's Kendall-tau-a treatment of tied experimental values. This is a scorer consistency check, not a molecular prediction result. It illustrates why composite endpoints should disclose their treatment of ties and their expected value for a reference-perfect input.

**Table 3. Offline validation and its scope.** Counts reproduce the original design manuscript. Self-tests assess implementation contracts; they do not establish reference-label validity or model generalization.

| Component | Reported check | Interpretation |
|---|---|---|
| Relative free-energy scorer | 6/6 checks | Numeric and ranking score behaviour |
| Decision scorers | 15/15 checks | Decision-format and matching behaviour |
| Chain scorer | 5/5 checks | Coverage, ordering and gate logic |
| Decision adapter | 14/14; exemplar 7/7 | Dispatch and prompt-construction checks |
| Synthesized gold completions | 30/30 at score 1.0 | Internal consistency with the scorer |
| Training reward checks | 22/22 training items | Gold-versus-trivial-wrong ordering |
| Free-energy oracle input | RMSE 0; composite approximately 0.98 | Tie-sensitive composite behaviour |

### Composer diagnostics expose barriers to execution

The execution track depends on matching requested subtasks to compatible workflows and passing artifacts between them. Offline analysis of 68 topologies exposes distinct failure mechanisms. Under a perfect-decomposition assumption, every subtask clears the resolver's confidence threshold, yet agreement with fine-grained gold tool identities is only 4%. This contrast reflects a granularity mismatch: the resolver selects workflow-level units while the reference chains include individual Galaxy tools. A confidence threshold therefore cannot substitute for precision against the intended target representation.

Separately, 66% of the catalogued workflows use free-text parameter descriptions where structured input-type tokens are expected. This prevents those entries from acting as handoff destinations under the matcher. Replacing exact string matching with the specified semantic matcher increases the reported handoff fire rate from 4.4% to 38.2% on the 68 topologies. Residual failures include resolver errors and cross-ecosystem representation differences, such as a count matrix versus an ExpressionSet.

The diagnostics measure resolver and handoff behaviour under offline assumptions, not successful completion of biological analyses. Improving fire rate alone does not prove that transferred artifacts are semantically correct or that downstream outputs satisfy the scientific objective.

## Discussion

DrugDev-Bench evaluates the transition from molecular information to development decisions. Its four-track structure preserves tasks with different scientific roles: specialized property and structure predictions, target selection, evidence retrieval, and execution of linked decisions. The 30 decision items and the eight-series free-energy dataset instantiate parts of this design. Offline checks verify implementation behaviour, while selected dose and PK experiments illustrate how information access and reference construction affect model comparisons.

The dose experiment is particularly sensitive to its decision policy. An oracle using a true curve can disagree with author-assigned labels if tie handling or no-safe-dose criteria differ. Its 17/20 agreement therefore diagnoses the relationship between two definitions of the target; it is not a guaranteed upper bound or an end-to-end pipeline score. Generated scenarios improve internal consistency by deriving curves and labels from the same explicit rules, but they do not independently validate those rules. Differences between the tiers cannot be attributed solely to exposure–response inference, model scale or reasoning settings.

The suite also distinguishes experimental measurements from derived references. Relative free-energy labels originate in experimental affinity data, whereas generated dose and concentration values follow specified equations. Tissue exposure and special-population decision items include provisional class-level values. These evidence types require different validation procedures. Internal scorer agreement is useful but cannot confirm physiological accuracy or clinical utility.

Execution-grounded assessment remains a substantive part of the benchmark design. The composer analysis shows why it is necessary: confident matching can identify the wrong level of abstraction, and a compatible type label can conceal an incompatible scientific representation. A completed execution study must verify the actual files, terminal state, transformations and scientific endpoints, with stage-specific provenance. Neither a plan that names the right stages nor a high handoff rate is sufficient.

The decision seed is small, with two to six tasks per archetype. Template-separated training and evaluation reduce one form of leakage, but they do not establish independence across compounds, targets, formulas or authoring conventions. The free-energy track therefore specifies target-held-out evaluation, and structure-based tracks require task-specific similarity and temporal controls. The benchmark should preserve multiple endpoints rather than reduce scientific validity, feasibility and decision quality to an unexamined weighted score.

The reported comparisons are descriptive. The dataset is not a clinical decision tool, model configurations are not fully matched, and the malformed-response and reference-policy issues described in Methods remain relevant to the dose results. The present contribution is a broad, inspectable benchmark design with instantiated task sets, offline evidence and selected model measurements. Claims about reliable cross-stage drug development require completed execution experiments and external adjudication.

## Methods

### Four-track organization and stage benchmarks

The suite separates molecular workflows (T1), targets and perturbations (T2), search and knowledge (T3), and execution across stages (T4). Track membership is a design classification, not a statement that every task has a completed model sweep. Five stage benchmarks provide anchors (Table 4): absorption, distribution, metabolism, excretion and toxicity (ADMET); docking or ligand assessment; physiologically based pharmacokinetic (PBPK) tasks; dose selection; and target structure. The B3 label is retained for lineage, but its simple numeric endpoints should not be described as a validated PBPK simulator solely because of that name.

**Table 4. Stage benchmarks and free-energy component.** Counts describe available cases in the original suite. The later generated dose and PK tiers add 20 and 15 cases respectively. Scientific endpoints and evidence differ across rows.

| Component | Scope | Reference and evaluation |
|---|---|---|
| B1 ADMET | 20 compounds | Curated property and toxicity labels; provenance differs by endpoint |
| B2 docking and ligand assessment | 15 shared items | Structural/affinity references; reported model endpoint is ligand ranking |
| B3 PK | 15 hand-authored cases | Numeric exposure reference; endpoint and units specified by protocol |
| B4 dose selection | 20 hand-authored scenarios | Policy-based dose/no-dose references |
| B5 target structure | 10 targets | Sequence/structure inputs and pocket-residue references |
| N1 relative binding free energy | 8 series; 264 ligands | Experimental affinity-derived relative free energies |

ADMET references include hERG, drug-induced liver injury and Ames-related labels as well as rule-of-five descriptors. A rule-of-five calculation is not a measured assay, and mixed reference types must not be described collectively as experimental measurements. Data licensing and primary-source attribution should be retained at the component level.

### Relative binding free-energy evaluation

The N1 component reuses the Merck/Schindler free-energy benchmark [6], comprising eight congeneric series and 264 ligands. For a ligand and a designated reference in the same series, the relative free energy is defined as

$$\Delta\Delta G = \Delta G_{\mathrm{ligand}}-\Delta G_{\mathrm{reference}}.$$

The scorer reports root-mean-square error, mean unsigned error, Kendall and Spearman rank measures, and the fraction within 1 kcal mol⁻¹ of the reference. A composite combines multiple signals, but its individual terms remain necessary to interpret accuracy and rank fidelity. Ligand structures are referenced to the source collection. The machine-learning variant specifies leave-target-out partitioning; this design requirement is distinct from a completed prospective or blinded FEP comparison.

A reference-perfect input can score below 1 on the composite when tied values deflate Kendall tau-a. That behaviour should be disclosed rather than interpreted as prediction error. No comparison against a specialized FEP method is inferred from the scorer's oracle check.

### Decision suite and reference policies

The decision suite contains 30 tasks across nine archetypes (Table 5; Fig. 5). Each item presents a project context, relevant inputs, constraints and a required decision. Prompts hide the reference conclusion. The adapter's leakage checks test known reference fields; they do not prove the absence of every indirect cue or template overlap.

**Table 5. Decision archetypes.** Counts sum to 30. The references combine measured inputs, formulas and curated policies. Tissue/organ and special-population references include provisional values that require source verification before definitive benchmarking.

| Archetype | Tasks | Decision | Reference basis |
|---|---:|---|---|
| C Lead-optimization triage | 3 | Advance or deprioritize analogues; identify liability | ADMET reference inputs and project policy |
| E FEP selection | 2 | Rank binders and select candidates | Experimental relative free energy |
| H Dose escalation | 3 | Select MTD and safety flags | Benchmark dose-selection policy |
| F1/G Dose projection | 3 | Starting-dose or human-clearance estimate | MRSD formula and allometric assumptions |
| F2 Tissue/organ exposure | 3 | Assess target-site exposure | Unbound partition/class-level references |
| F3 Dose schedule | 3 | Choose regimen from the PK/PD driver | Curated pharmacokinetic/pharmacodynamic class |
| F4 Special populations | 4 | Adjust for organ impairment or interactions | Label-derived or provisional class values |
| P Process knowledge | 6 | Identify gates and prerequisites | Curated development-process references |
| W Workflow chain | 3 | Order stages and enforce gates | Reference directed acyclic graph |

Six scoring entry points cover decision, categorical, set, numeric, dose and chain outputs. Decision scoring combines a deprioritization-set F1, best-pick agreement and liability or driver identification. Numeric scoring gives full credit within a specified fold band and partial credit within the squared band. Categorical grading uses a controlled vocabulary and negation guard; set scoring uses F1. Chain scoring combines stage coverage, longest-common-subsequence ordering and before/after gate adherence. These components measure agreement with the specified policy, not necessarily the uniqueness of a scientifically defensible answer.

Compound labels such as C1–C4 avoid collisions with common single-letter words. Token boundaries account for apostrophes to reduce false free-text matches. These implementation controls address specific scoring failure modes; they do not replace schema validation or expert adjudication of ambiguous decisions.

![Composition of the decision suite across nine archetypes.](figures/drugdev_coverage.png)

**Figure 5. The decision suite spans nine development archetypes.** Counts reproduce Table 5 and sum to 30 tasks. The largest group addresses process knowledge; the remaining groups cover candidate, experiment, dose, population and workflow decisions. This is dataset composition, not a model-performance plot. The eight free-energy series and their 264 ligands are a separate component and are not added to the decision-task denominator. The 22/8 training/evaluation partition applies to the 30-item decision suite.

### Training export and independence

Each decision item exports a supervised target and a group-relative-policy-optimization reward row containing the prompt, reference, scorer and labels. Gold completions are synthesized and verified before export. Numeric dose-projection tasks carry a route-to-engine policy rather than a requirement that the model perform the arithmetic unaided. The 22/8 train/evaluation split separates template sources and uses a fail-closed overlap guard.

The 30/30 full-credit check demonstrates consistency between synthesized completions and the scorer. The reward test demonstrates an ordering against trivial wrong answers on the 22 training rows. No reinforcement-learning or fine-tuning capability claim follows from these data checks. The later local-model dose comparison is a distinct experiment; it is not evidence that training on this 30-item export improved the suite as a whole.

### Dose and PK dataset composition and information access

The hand-authored tier contains 20 dose scenarios and 15 compounds. The generated tier adds 20 dose scenarios and 15 compound cases, giving 40 and 30 in total. Counts describe available datasets; they do not imply that every model was evaluated on both tiers. Dose inputs include a grid and a target probability of dose-limiting toxicity (DLT), with scenario-specific PK and exposure–response information. The reference toxicity curve is hidden from model solvers and supplied directly to the oracle.

### Benchmark dose-selection policy

Let $p_j$ be the DLT probability at ordered dose $d_j$ and $\tau$ the target probability. The implemented benchmark rule declares no dose if $p_1>\tau+0.10$. Otherwise it selects the admissible dose minimizing $|p_j-\tau|$, where admissibility means $p_j\leq\tau+0.10$; ties select the higher indexed dose. The implementation uses a small numerical tolerance at the threshold.

This is a deterministic reference-curve policy. It must not be described as the full Bayesian optimal interval (BOIN) trial design [4,5]: it does not simulate sequential patient allocation, estimate toxicity from accumulating patient outcomes or implement the full posterior elimination and final-selection procedure. The fixed 0.10 band is a benchmark choice, not a universal BOIN safety criterion.

### Generated exposure and toxicity references

Generated dose cases use bioavailability $F$, dose $D$, molecular weight $M$, distribution volume $V$ and specified Emax-response parameters. With $D$ in milligrams, $M$ in grams per mole and $V$ in litres, the numerical reference is

$$C_{\mathrm{nM}} = 10^6\frac{FD}{MV}.$$

$$p(C) = E_0+E_{\max}\frac{C}{EC_{50}+C}.$$

The generator rounds probabilities to three decimal places before applying the same dose-selection rule to create the label. Consequently, agreement of that oracle with generated labels is a construction property, not independent validation. The concentration equation describes a simplified instantaneous-distribution quantity; without a dosing interval, clearance dynamics or accumulation model, it should not be called a steady-state exposure.

The generated PK cases use $C_{\mathrm{\mu M}}=10^3FD/(MV)$, rounded to three decimals. Although the data label this quantity as oral peak concentration, the formula does not model absorption kinetics, time to peak or elimination. It therefore defines a simplified concentration-calculation task rather than a validated oral peak-concentration model. Hand-authored PK references require separate source and unit verification; no experimental validation is inferred from the generated formula.

### Outcomes, safety and curve agreement

The structured dose outcome is exact agreement with the reference dose, including no-dose cases. The safety score checks no-dose agreement and whether a selected dose remains within the reference-curve elimination band. It is a benchmark constraint check, not a measure of patient safety. Fidelity is the mean, across scenarios, of the fraction of dose levels whose predicted probability lies within twofold of the reference. Missing levels count as misses; the existing implementation uses a special tolerance when the reference is zero. High fidelity under this coarse metric does not prove a correct mechanistic derivation.

A scorer audit identifies a consequential validation limitation: in a no-dose reference case, an absent dose field can currently receive credit even without an explicit valid no-dose declaration. Probability bounds and contradictory output fields are not comprehensively validated. The recorded scores are preserved here rather than silently recalculated under a new policy. The scores remain provisional under this implementation; aggregate outcome receipts alone cannot resolve every malformed response.

### Serving conditions and statistical reporting

The source draft reports a 20,000-token budget for later structured-response runs, whereas an earlier scorecard runner specifies 12,000 tokens. Per-run manifests are needed to verify the budget associated with each retained artifact. The superseded smaller-budget scorecard figure is excluded. Empty-response counts are reported explicitly; they describe performance under the recorded harness and are not automatically a lower bound on an unobserved intrinsic capability.

The local-model experiment uses a deployment configuration with reasoning disabled. Model names follow the recorded artifacts, and similarly named provider variants are not merged. The results are descriptive: small denominators, nonuniform repeats and differing serving conditions do not support fine-grained model rankings or causal claims about scale and reasoning. Repeated-run variation and sampling uncertainty should be reported separately in a finalized analysis.

### Execution criteria and relationship to RealBio

Execution-grounded tasks require a terminal run state and output artifacts that can be checked against the scientific task. Cross-stage tasks additionally require valid dependencies: the output of one step must have the appropriate identity, units, representation and provenance for the next. The suite specifies end-to-end and cross-stage tasks, while the present execution evidence is limited to the offline composer diagnostics. The 4.4% and 38.2% handoff rates are not success rates for complete development programmes.

RealBio evaluates general workflow decisions. DrugDev-Bench evaluates drug-development outputs and decisions, including the three shared legacy PK, dose and ligand-ranking exports. Their shared storage or scoring entry point does not make them independent replicated datasets. Shared items are identified rather than counted twice in a combined headline.

## Related work and comparison framework

The landscape motivating DrugDev-Bench spans molecular prediction, scientific agents and clinical-trial datasets. Tables 6 and S1 retain those comparison families. They define which external results would be relevant to each component; they are not a claim that all named systems have been run on DrugDev-Bench. Reported scales from older surveys are not carried forward as verified current counts.

**Table 6. External comparison families and their role.** The comparison is organized by scientific endpoint. A valid numerical head-to-head requires compatible inputs, splits, labels and metrics, beyond belonging to the same family.

| Family | Resources considered | Relation to the suite |
|---|---|---|
| Properties and ADMET | TDC/TDC-2, ADMET-AI, ADMETlab, PharmaBench, MoleculeNet | Property endpoints underlying triage decisions |
| Structure and docking | PDBbind, CASF, PoseBusters, PLINDER, PINDER, DockGen, PoseBench | Structural validity and task-specific generalization |
| Screening | DUD-E, DUDE-Z, LIT-PCBA, MUV, DEKOIS, BayesBind | Enrichment and bias-sensitive screening comparisons |
| Free energy | Merck/Schindler, OpenFE, JACS-FEP | Affinity-derived accuracy and ranking references |
| Generation and synthesis | GuacaMol, MOSES, PMO, GenBench3D, PaRoutes, Syntheseus | Feasibility and validity beyond a single reward |
| Targets and perturbations | Open Targets, PrimeKG, GEARS, PerturBench, Virtual Cell Challenge | Target prioritization and perturbation-response tasks |
| Evidence and knowledge | PaperQA2, LitQA2, STaRK-PRIME, ChemBench, MoleculeQA, BioKGBench | Retrieval, synthesis and knowledge-grounded decisions |
| Trials and dose | TrialBench; BOIN and related designs | Dataset-based predictions distinguished from trial-design methods |
| Scientific and therapeutic agents | Biomni, TxAgent, TxGemma, BixBench, DMPKBench, DrugAgent | Agent-level comparisons with matched task conditions |

Therapeutics Data Commons supplies standardized therapeutic datasets and evaluation tools [1]. TrialBench explicitly contains dose-finding prediction data [2], making an absolute claim of no prior dose benchmark inappropriate. ScienceAgentBench grades scientific programs and execution outcomes [3], providing a methodological precedent for observable-output evaluation. BOIN is a sequential trial-design methodology [4,5]; it is not interchangeable with the simplified reference-curve rule used here.

Structure and affinity tasks motivate similarity-aware and temporal partitions, while docking validity and molecular-generation studies motivate multiple scientific checks. These are design requirements in DrugDev-Bench, rather than demonstrated achievements across every track. A good affinity score cannot establish geometric validity, synthetic feasibility or a suitable development profile. Likewise, a scientifically plausible written rationale cannot substitute for retrieved evidence or an executed calculation.

The comparison programme preserves target discovery, perturbation, search and knowledge as first-class tasks. These areas have substantial external work and do not support a blanket novelty claim. The distinctive emphasis here is linking inputs, decisions and execution evidence across stages under explicit policies. A systematic claim that no comparable cross-stage benchmark exists would require a complete, current literature review; it is not inferred from the present comparison set.

## Data and code availability

The suite package contains datasets, scorers, adapters, generators and retained predictions. Experimental free-energy data are attributed to the Merck/Schindler collection [6]; other components require their own reference and licensing records. The source drafts specify CC-BY-4.0 for benchmark materials. A verified public repository and archival identifier are not supplied in this preprint, and public availability is not asserted without them.

## Ethics and competing interests

This is a nonclinical methodological benchmark. Modeled dose and exposure references are not dosing recommendations, and internal consistency is not clinical validation. The benchmark authors also develop BioMate, an evaluated system. Y.Z. and A.D. are affiliated with BioMate AI; A.D. is additionally affiliated with BizBildr. These relationships are declared as competing financial interests.

## Supplementary information

### S1 Expanded comparison coverage

Table S1 preserves additional comparison families from the broader landscape study. It is a research-positioning inventory, not a scored comparison or a systematic-review claim. Inclusion identifies relevant scientific domains; it does not assert a particular benchmark's current size, license or superiority.

**Table S1. Extended external comparison inventory.** No performance values are transferred between these benchmarks and DrugDev-Bench. Name collisions among DrugAgent systems require bibliographic disambiguation before any head-to-head study.

| Area | Further resources or systems in the comparison plan |
|---|---|
| Therapeutic and chemistry agents | ToolUniverse, TxBench-PP, ChemCrow, Coscientist, ChemToolAgent |
| Experimental design | BioDiscoveryAgent, CRISPR-GPT, GenoTEX |
| Target and mechanism evidence | DrugMechDB, TxGNN, BindingDB, DAVIS, KIBA, BIOSNAP |
| Structure–activity relationships | MoleculeACE, DrugBAN, TDC DTI-DG, PLATINUM |
| Affinity data and split controls | LP-PDBBind, CleanSplit/GEMS, MISATO, PLAS-5k, SAIR |
| Pose and prospective structure assessment | Astex Diverse, PoseCheck, CASP ligand assessments, Runs N' Poses |
| Structure-based generation | CrossDocked2020, TargetDiff, CBGBench |
| Literature and retrieval | MIRAGE/MedRAG, BioASQ, SciFact, PubMedQA, TREC-COVID and clinical-trial retrieval |
| Biomedical and chemical knowledge | MedQA, MedMCQA, MMLU subsets, MedBullets, MultiMedQA, HealthBench, SciEval, SciQ |
| Molecular instruction and reasoning | SMolInstruct/LlaSMol, ChemLLMBench, GPQA, HLE |
| Additional development endpoints | Formulation/stability, manufacturing, intellectual-property novelty, absolute binding free energy, antibody developability |

These families should be compared through their original tasks or carefully aligned transfer tasks. Reusing names as a list of competitors does not supply the matched experiments needed to establish superiority. In particular, proprietary therapeutic agents, open model weights, datasets and evaluation methodologies belong to different categories and should not be ranked together as systems.

### S2 Instantiated seeds and designed extensions

In addition to the stage benchmarks and 30 decision tasks, the reviewed export contains two-item seeds for QSAR, retrosynthesis and target identification (Table S2). Their presence updates the older design manuscript's statement that these families were wholly unbuilt. Two-item seeds are insufficient for inferential ranking. Generation, stability, freedom-to-operate, regulatory narratives, end-to-end execution and cross-stage designs remain part of the suite's coverage plan without being assigned model results.

**Table S2. Additional seeds and extension status.** Dataset presence is separated from measured evaluation. These rows do not increase the reported 30-item decision-suite denominator.

| Component | Available evidence | Interpretation |
|---|---|---|
| QSAR | Two instantiated items | Seed task set; no suite-wide model claim |
| Retrosynthesis | Two instantiated items | Seed task set; no suite-wide model claim |
| Target identification | Two instantiated items | Seed task set; distinct from ten target-structure cases |
| Molecular generation | Design/manifest entry | No reported roster-wide result here |
| Stability and manufacturing | Design scope | Requires defined endpoints and independently sourced references |
| Novelty and freedom to operate | Design scope | Requires explicit evidence and policy boundaries |
| Regulatory narrative | Design scope | Requires factual and documentary evaluation criteria |
| End-to-end pipeline and cross-stage tasks | Design plus offline composer diagnostics | No completed roster-wide execution result |
| Perturbation, retrieval and knowledge | Track-level design and external comparison plan | No inferred evaluation from manifest membership |

### S3 Interpretation of the model comparisons

The historical dose-only leaderboard uses 18 non-null labels, whereas the structured-response study includes 20 outcomes. Both are retained as protocol versions and must not be pooled. The generated-dose oracle uses the same formula and policy that created the answers, so its correctness cannot serve as independent evidence of scientific validity. The hand-tier oracle uses privileged curve information and is not a model supplied with the same inputs.

The local 9B comparison changes training and serving characteristics together; reasoning is disabled for the reported local configuration. Its hand-tier advantage over another configuration does not identify which factor caused the difference, particularly because the ordering reverses on the generated tier. The three additional Opus generated runs score 1.00, 1.00 and 0.95 in retained-file order. These repeats describe observed variation; they do not establish uniform stability across the suite.

PK values must be interpreted by analyte, concentration type, units, route, dose, formulation and time context. A simplified amount-over-volume calculation is not a full oral peak or steady-state prediction. The clinical provenance of the hand-authored references is a separate scientific validation question from the reproducibility of scoring against those references.

## References

1. Huang, K. et al. Therapeutics Data Commons: Machine Learning Datasets and Tasks for Drug Discovery and Development. NeurIPS Datasets and Benchmarks (2021). https://arxiv.org/abs/2102.09548. Resource: https://tdcommons.ai/.
2. Chen, J. et al. TrialBench: Multi-Modal AI-Ready Datasets for Clinical Trial Prediction. Scientific Data (2025). https://doi.org/10.1038/s41597-025-05680-8.
3. Chen, Z. et al. ScienceAgentBench: Toward Rigorous Assessment of Language Agents for Data-Driven Scientific Discovery. ICLR (2025). https://arxiv.org/abs/2410.05080.
4. Liu, S. & Yuan, Y. Bayesian optimal interval designs for phase I clinical trials. J. R. Stat. Soc. C 64, 507–523 (2015).
5. Yuan, Y., Hess, K. R., Hilsenbeck, S. G. & Gilbert, M. R. Bayesian Optimal Interval Design: A Simple and Well-Performing Design for Phase I Oncology Trials. Clin. Cancer Res. 22, 4291–4301 (2016). https://pmc.ncbi.nlm.nih.gov/articles/PMC5047439/.
6. Schindler, C. E. M. et al. Large-Scale Assessment of Binding Free Energy Calculations in Active Drug Discovery Projects. J. Chem. Inf. Model. 60, 5457–5474 (2020). Data: https://github.com/MCompChem/fep-benchmark.
