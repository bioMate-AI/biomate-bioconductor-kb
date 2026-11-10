# DrugDev-Bench probes dose-selection decisions and modeled pharmacokinetic exposure

**Authors:** [To be completed]

**Affiliations:** [To be completed]

**Correspondence:** [Name and email to be completed]

*Preprint · author-review revision · 7 November 2026*

## Abstract

Evaluating language models for drug-development decisions requires explicit decision policies and well-defined reference outcomes. Here we present DrugDev-Bench, a methodological benchmark comprising dose selection and pharmacokinetic exposure tasks. The available datasets contain 40 dose scenarios and 30 compound cases, divided equally between hand-authored and generated tiers. An oracle selection rule supplied with the hidden toxicity curve agrees with 17 of 20 hand-authored dose labels; its three disagreements expose differences between the rule and reference-label policy. In structured-response experiments, reported hand-tier dose accuracy is 0.25–0.30 for Claude Opus 5 and 0.10 for GPT-6.1-sol. Both models attain 1.00 in a generated-tier run with explicit exposure–response parameters, although an additional Opus run scores 0.95. On 15 hand-authored pharmacokinetic cases, the best recorded within-twofold agreement is 0.467. These results reveal sensitivity to problem specification and reference construction. They support evaluating decision accuracy alongside curve agreement and response completeness, while distinguishing simplified modeled tasks from validated pharmacokinetic prediction or clinical dose-finding performance.

## Introduction

Drug development combines predictive models with decisions about exposure, toxicity and dose. A benchmark of such decisions must specify what information is available to a solver, which policy defines a correct answer and whether the reference is modeled or experimentally measured. Without these distinctions, a disagreement can reflect incompatible assumptions rather than inadequate reasoning.

Therapeutics Data Commons provides datasets and evaluation tasks across therapeutic discovery and development [1]. TrialBench includes clinical-trial prediction tasks, explicitly including dose finding [2]. DrugDev-Bench is complementary to these resources: it studies structured decisions under specified modeled references rather than claiming that dose-finding benchmarks do not exist. Its diagnostic outputs also draw on the emphasis on observable task outcomes in ScienceAgentBench [3].

The present study comprises hand-authored and generated dose-selection and pharmacokinetic (PK) tasks. We distinguish a solver that receives problem inputs from an oracle that receives a hidden reference toxicity curve (Fig. 1). The oracle is a reference-policy diagnostic, not a competing input-to-output system or a guaranteed upper bound on agreement with labels. A proposed cross-stage execution track remains outside the measured results.

![Information supplied to model and oracle conditions.](figures/drugdev_design.png)

**Figure 1. Information access and evaluation scope.** Language models receive the scenario inputs and dose grid; the oracle receives the reference toxicity curve. Both can be assessed against the selected-dose label, but their information differs. Generated-tier curves and labels follow the same explicit formula and decision policy, making oracle agreement correct by construction. The diagram describes dose selection only; the PK endpoint is evaluated separately.

## Results

### The oracle exposes reference-policy disagreements

On the 20 hand-authored scenarios, the oracle reproduces 17 dose labels, for accuracy of 0.85. Its benchmark-defined safety score is 0.90 and its curve fidelity is 1.00, the latter following directly from access to the reference curve. Two disagreements concern no-safe-dose labels that are not triggered by the implemented elimination threshold; a third concerns closest-to-target selection and the reference's higher-dose choice. These cases require label-policy adjudication before they can be interpreted as solver errors.

The original dose-only leaderboard and the structured-response evaluation use different denominators. The former excludes the two null-dose references and scores 18 scenarios; the latter includes all 20 and treats no-safe-dose decisions as outcomes. The earlier 0.11–0.50 model range therefore cannot be directly compared with the 17/20 oracle value as though both used an identical task definition. We retain structured-response results separately (Table 1) and do not combine the two protocols into a model ranking.

### Structured dose responses differ substantially between tiers

On the hand-authored tier, the retained Claude Opus 5 runs score 0.25 and 0.30, with curve fidelity of approximately 0.60–0.68 and no empty responses. The direct-provider GPT-6.1-sol runs both score 0.10 with fidelity approximately 0.01; they contain four and one empty responses, respectively. These are run-level observations rather than precise estimates of a model's general dose-selection capability.

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

### PK agreement remains limited on hand-authored cases

After the target endpoint was specified as peak concentration in micromolar, the stored leaderboard reports a maximum within-twofold agreement of 0.467 on 15 hand-authored compounds (Table 2). These results describe agreement with the benchmark reference values. They do not establish clinical accuracy, and the generated PK cases are not included in this table.

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

## Discussion

DrugDev-Bench provides an initial setting for evaluating modeled dose decisions and PK endpoints with transparent scoring. Its most informative result is the dependence of conclusions on reference construction: an oracle can disagree with author-defined labels, while models that struggle on implicitly specified scenarios can solve formula-defined scenarios. The oracle therefore diagnoses policy consistency; it does not demonstrate that a deployable mechanistic system outperforms models given the same inputs.

The benchmark is small, with 20 dose scenarios and 15 PK cases per tier. Generated items provide internal consistency but do not replace external validation, independently authored scenarios or clinically grounded references. The current structured-response results also require stricter validation of missing and contradictory outputs before use in a definitive ranking. A future comparison should freeze the decision policy, rescore all systems with one validated scorer and separate response failures from wrong substantive answers without excluding either from task-level performance.

Cross-stage decisions, docking, synthesis and ligand ranking are not measured contributions of this paper. The proposed cross-stage track requires its own execution protocol and results. An earlier three-ligand ranking probe has coarse rank-correlation resolution and is excluded from the main evaluation. The present results should be understood as methodological probes, not evidence of clinical utility or a completed end-to-end drug-development agent.

## Methods

### Dataset composition and information access

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

A scorer audit identifies a consequential validation limitation: in a no-dose reference case, an absent dose field can currently receive credit even without an explicit valid no-dose declaration. Probability bounds and contradictory output fields are not comprehensively validated. The recorded scores are preserved here rather than silently recalculated under a new policy. Final publication requires a versioned schema, regression cases and rescoring from retained raw responses; aggregate outcome receipts alone cannot resolve every malformed response.

### Serving conditions and statistical reporting

The source draft reports a 20,000-token budget for later structured-response runs, whereas an earlier scorecard runner specifies 12,000 tokens. Per-run manifests are needed to verify the budget associated with each retained artifact. The superseded smaller-budget scorecard figure is excluded. Empty-response counts are reported explicitly; they describe performance under the recorded harness and are not automatically a lower bound on an unobserved intrinsic capability.

The local-model experiment uses a deployment configuration with reasoning disabled. Model names follow the recorded artifacts, and similarly named provider variants are not merged. The results are descriptive: small denominators, nonuniform repeats and differing serving conditions do not support fine-grained model rankings or causal claims about scale and reasoning. Repeated-run variation and sampling uncertainty should be reported separately in a finalized analysis.

## Data and code availability

Datasets, generators, scorers and retained predictions have been assembled for release. The source draft proposes CC-BY-4.0 for benchmark materials. Public repository and archival identifiers, the final code license and the complete run manifest require author confirmation; public release is not asserted before these are supplied.

## Ethics and competing interests

This is a nonclinical methodological benchmark using modeled references and synthetic scenarios, not a clinical dosing tool. The source manuscript reports no patient data. The authors developed the benchmark and an evaluated local model. Author contributions, funding and the formal competing-interest declaration remain to be completed.

## References

1. Huang, K. et al. Therapeutics Data Commons: Machine Learning Datasets and Tasks for Drug Discovery and Development. *NeurIPS Datasets and Benchmarks* (2021). https://arxiv.org/abs/2102.09548
2. Chen, J. et al. TrialBench: Multi-Modal Artificial Intelligence-Ready Clinical Trial Datasets. Preprint (2024; revised 2025). https://arxiv.org/abs/2407.00631
3. Chen, Z. et al. ScienceAgentBench: Toward Rigorous Assessment of Language Agents for Data-Driven Scientific Discovery. *ICLR* (2025). https://arxiv.org/abs/2410.05080
4. Liu, S. & Yuan, Y. Bayesian optimal interval designs for phase I clinical trials. *J. R. Stat. Soc. C* **64**, 507–523 (2015).
5. Yuan, Y., Hess, K. R., Hilsenbeck, S. G. & Gilbert, M. R. Bayesian Optimal Interval Design: A Simple and Well-Performing Design for Phase I Oncology Trials. *Clin. Cancer Res.* **22**, 4291–4301 (2016). https://pmc.ncbi.nlm.nih.gov/articles/PMC5047439/
