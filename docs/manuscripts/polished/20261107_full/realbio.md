# RealBio evaluates the decisions underlying bioinformatics workflow automation

**Yaoyun Zhang**¹, **Andrew Dike**¹,²

¹ BioMate AI  
² BizBildr

**Correspondence:** Andrew Dike (a.dike@bizbildr.com); Yaoyun Zhang (yaoyun.zhang@biomate.ai).

*Preprint · 7 November 2026*

## Abstract

Biomedical workflow automation requires reliable choices at several stages, from selecting an analysis to specifying its parameters and responding to failures. Comparisons are difficult when systems receive different information or are assessed with different scoring rules. Here we present RealBio, a benchmark with 610 items across five workflow tasks, deterministic reference-based scoring and separate measurements of model and system performance. The broader evaluation framework includes resource routing, robustness probes, latency, token use and cross-published drug-development tasks. In the principal workflow-routing comparison, providing a candidate catalog improves a locally served nine-billion-parameter model from 0.180 to 0.905 accuracy and Claude Opus 5 from 0.615 to 0.990 on 200 requests. Parameter extraction, failure classification, workflow specification and quality-control decisions show different performance profiles; no system leads uniformly. Historical pharmacokinetic results further demonstrate how an ambiguous endpoint can change the interpretation of a benchmark. RealBio provides a reproducible framework for comparing workflow decisions while distinguishing catalog-assisted selection, rule-assisted extraction and execution. The results support explicit reporting of task definitions, information access and scoring versions when evaluating biomedical agents.

## Introduction

Bioinformatics analyses require a sequence of decisions that connect a scientific request to an executable procedure. An assistant must identify the appropriate workflow, infer only justified parameters, recognize relevant quality-control criteria and respond to errors. A plausible workflow name or convincing explanation is insufficient if the resulting configuration cannot be executed or does not answer the scientific question. Evaluating these decisions separately can reveal which parts of an automation system contribute to its performance.

Existing biomedical and scientific-agent benchmarks address complementary capabilities. BixBench evaluates biological data analysis, LAB-Bench examines practical biology research skills, ScienceAgentBench evaluates scientific programs and their outputs, BioAgent Bench tests bioinformatics pipelines under perturbations, and BiomniBench assesses biomedical research processes [1–5]. These resources differ in task format, information access and grading. Their scores therefore cannot be interpreted as measurements on a common scale. Deterministic scoring is useful when a task admits explicit answers, whereas richer scientific tasks may require execution checks or expert-informed rubrics.

RealBio fixes workflow-level requests and reference answers and applies the same task-specific scoring implementation to each system. Its five core tasks comprise routing, parameter extraction, failure-category classification, workflow specification and protocol quality control. The principal comparison supplies the same model with or without a candidate catalog. A retrieval-only product and a domain-agent scaffold provide additional system comparisons. The experimental conditions are distinct: a system result is not an ablation of a language model.

The study asks three questions: how candidate context changes workflow selection, whether deterministic rules complement parameter extraction, and whether performance transfers across different workflow decisions. Upstream resource routing, five evaluation dimensions and three tasks shared with DrugDev-Bench extend this analysis, with separate denominators and protocol versions. The original combined export contains 660 items: 610 core workflow items and 50 drug-development items. This is an inventory count, not a single pooled performance endpoint; the legacy dose scorer evaluates 18 of its 20 items. The framework is summarized in Figure 1.

![RealBio task and condition design.](figures/realbio_design.png)

**Figure 1. RealBio evaluation design.** Five core workflow tasks are evaluated separately. Direct-model, catalog-assisted and retrieval-only conditions differ in information and computation. Resource-routing probes and shared DrugDev tasks extend coverage without being pooled into one score. Latency and token use complement task performance; repeated-run stability and systematic hallucination assessment remain separate evaluation dimensions.

## Results

### Catalog context improves workflow routing

The reported routing results improve for every language model with paired entries (Table 1; Fig. 2). BioMate 9B base improves from 0.180 to 0.905, and Claude Opus 5 improves from 0.615 to 0.990. Catalog-assisted accuracy spans 0.735–0.990 across the reported language models, rather than converging to a uniformly high level. These are descriptive comparisons on 200 requests; they do not establish equivalence between model families.

**Table 1. Reported RealBio results.** Routing uses 200 items, parameter extraction 170, failure-category classification 100 and quality-control (QC) decisions 100. Values reproduce the source manuscript and stored leaderboard. Parameter F1 is the benchmark-defined aggregate key–value score. An em dash indicates an unavailable result or an inapplicable condition. Catalog provenance varies across rows, as described in Methods. The Biomni scaffold receives a catalog in both columns, so its entries are not a direct-versus-catalog experiment. The retrieval-system row is a separate system result.

| Model (version) | Routing, direct | Routing, catalog | Parameter F1 | Failure category | QC action |
|---|---|---|---|---|---|
| Claude Opus 5 | 0.615 | 0.990 | 0.805 | 0.870 | 0.330 |
| GPT-6.1-sol-pro | 0.590 | 0.985 | 0.718 | 0.870 | 0.450 |
| Gemini 3.1 Pro | 0.580 | 0.975 | 0.757 | 0.880 | 0.630 |
| Kimi K3 | 0.495 | 0.970 | 0.672 | 0.770 | 0.360 |
| GLM-5.3-prime | 0.375 | 0.955 | 0.682 | 0.820 | 0.550 |
| GLM-5.2 | 0.400 | 0.950 | 0.691 | 0.830 | 0.440 |
| GPT-5.6-luna | 0.355 | 0.950 | 0.667 | 0.830 | 0.340 |
| DeepSeek V4-pro | 0.415 | 0.850 | 0.691 | 0.800 | 0.420 |
| Qwen3.5-27B | 0.240 | 0.935 | 0.719 | — | — |
| BioMate 9B (on-prem, base) | 0.180 | 0.905 | 0.703 | 0.870 | 0.430 |
| Qwen3.5-9B | 0.120 | 0.830 | 0.600 | — | — |
| Qwen2.5-7B | 0.140 | 0.735 | 0.499 | — | — |
| BioMate 9B (on-prem, fine-tuned) | 0.285 | 0.810 | 0.716 | 0.850 | 0.430 |
| Biomni (A1 scaffold) | 0.950 | 0.950 | 0.746 | 0.950 | 0.500 |
| BioMate retrieval system (no model) | 0.965 | — | — | — | — |

![Routing accuracy under direct and catalog-assisted conditions.](figures/realbio_routing.png)

**Figure 2. Routing accuracy with and without candidate context.** All 13 language-model rows with paired conditions in Table 1 are shown. Grey points denote direct responses and blue points denote responses with candidate context. Connecting lines identify the same recorded model; they do not imply repeated-run uncertainty. The Biomni scaffold and retrieval-only system are excluded from this paired display because they do not share the intervention. These are catalog-selection results, not estimates of deployed retrieval recall or workflow execution success.


The difference between direct and catalog-assisted conditions includes both access to the candidate labels and any descriptions provided with them. It does not isolate the value of a retrieval algorithm. Larger absolute gains among low-scoring direct models are compatible with greater remaining headroom on a bounded accuracy scale; the comparison does not establish a causal inverse relationship between parameter count and benefit from context.

### Parameter extraction and deterministic inference

Raw parameter-extraction F1 spans 0.499–0.805 in Table 1. The raw local base model scores 0.703, compared with 0.716 for its supervised-fine-tuned variant. These columns exclude the deterministic parameter layer. An offline combination of rules and model predictions increases the measured score to 0.843 (Table 2; Fig. 3). Rules alone have high precision and lower recall. Their contribution is consequently different from the candidate-context intervention in routing.

**Table 2. Offline parameter-layer comparison.** All configurations use the 170-item parameter set. Precision and recall follow the local experiment's key–value convention. The merged configuration uses an answer-informed allowable-field schema and a local value matcher; these values are exploratory and do not establish production-backend performance under the shared scorer.

| Configuration | F1 | Precision | Recall |
|---|---:|---:|---:|
| Raw local 9B | 0.703 | 0.785 | 0.636 |
| Rules alone | 0.470 | 0.960 | 0.311 |
| Rules plus local 9B | 0.843 | 0.900 | 0.793 |

The merged output reduces recorded forbidden-field violations from 53 to 27. Thus, a higher aggregate F1 does not imply that unsupported parameter filling has been eliminated. A small additional deterministic probe correctly fills 15 of 17 expected values in covered classes and has no forbidden-field violations. Two further out-of-coverage organism values remain unfilled. These are value-level counts from an author-created probe, not 17 independent biological analyses or proof of generalization across workflows.

![Offline parameter extraction configurations.](figures/realbio_parameters.png)

**Figure 3. Parameter extraction under three offline configurations.** Precision, recall and F1 reproduce Table 2; every point is an aggregate score on 170 items. Rules alone emphasize precision, while the merged configuration increases recall. These are distinct metrics, not replicate measurements. The combined score is an offline diagnostic, with answer-informed schemas and a local matcher, rather than a validated estimate of the live system. Forbidden-field violations remain after merging.

The cross-task profile reveals why a routing leaderboard cannot stand in for workflow competence (Fig. 4). The highest catalog-routing score belongs to Claude Opus 5, whereas the highest reported QC score belongs to Gemini 3.1 Pro. Each endpoint measures a separate decision; their common numeric range does not justify averaging them into a composite score.

![Task-specific performance across the core model comparison.](figures/realbio_profiles.png)

**Figure 4. Task-specific strengths across workflow decisions.** Cells reproduce the language-model rows of Table 1. Columns show catalog-routing accuracy (200 items), benchmark-defined parameter F1 (170), failure-category accuracy (100) and protocol-QC accuracy (100). Printed values preserve the exact reported scores. Grey cells indicate unavailable results. Colour encodes the reported value within each endpoint; the four metrics are not interchangeable. Scaffold and retrieval-only systems remain in Table 1 as distinct system conditions. No uncertainty or composite ranking is inferred.

### Workflow specification and other core tasks

The 40 workflow-generation items contain two forms of response: analysis-category selection and key-tool enumeration, with 20 items in each subset. These are tests of workflow specification, rather than evidence that the resulting pipeline ran successfully. A later subset summary distinguishes thresholded success from mean key-tool recall. For example, the reported Opus tool-subset success is 0.95 at a recall threshold of 0.5, whereas mean recall is 0.8167; the corresponding small 7B values are 0.35 and 0.3658. Thresholded success and mean recall therefore describe different aspects of specification quality. Supplementary Table S1 retains the historical aggregate endpoint, whose values near 0.500 for most systems cannot distinguish these behaviours.

Failure-category accuracy ranges from 0.770 to 0.950 among the reported systems, whereas protocol-QC accuracy ranges from 0.330 to 0.630 (Table 1). A correct failure category does not demonstrate that a repair was applied successfully. Likewise, a PASS, WARN or FAIL response is a decision under the benchmark's reference policy, not a complete assessment of an analysis. Gemini 3.1 Pro has the highest reported QC accuracy in this comparison; the Biomni scaffold has the highest failure-category value, with the pilot coverage described in Methods. These results preserve task-specific strengths without defining an overall winner.

### Upstream resource routing

A complementary 84-item probe asks which resource should handle a request before a workflow is selected. Its seven channels are workflow, tool search, database lookup, literature, code execution, knowledge answer and dataset discovery. Drug-development queries account for approximately 64% of this seed set. The available paired comparisons improve with channel definitions or context (Table 3; Fig. 5). The largest gain among the six fully tabulated pairs is 0.214 for Qwen3.5-9B. The separate on-premises 9B drug-development subset improves from 0.778 to 0.982, but its subset denominator is not specified in the source summary and it is not pooled with the 84-item comparisons.

**Table 3. Resource-routing comparisons on the 84-item seed set.** Rows reproduce the available paired values from the suite integration draft. The source describes a seven-model roster but provides six complete full-set pairs; no seventh row is inferred. These results concern resource channels rather than the 200-item workflow-selection task.

| Model | Direct | With channel context | Absolute gain |
|---|---:|---:|---:|
| Qwen3.5-9B | 0.750 | 0.964 | 0.214 |
| GLM-5.2 | 0.821 | 1.000 | 0.179 |
| DeepSeek | 0.833 | 0.976 | 0.143 |
| Kimi | 0.845 | 0.988 | 0.143 |
| Gemini 3.1 | 0.893 | 0.988 | 0.095 |
| Claude Opus 5 | 0.905 | 1.000 | 0.095 |

The seed distribution is not an estimate of production request prevalence. Channel routing is included as a complementary capability, and neither its task count nor its accuracy is added to the core workflow leaderboard.

![Resource-channel accuracy with and without context.](figures/realbio_channels.png)

**Figure 5. Context also changes upstream resource selection.** Paired point estimates reproduce the six complete comparisons in Table 3 on 84 requests across seven resource channels. These are resource-routing decisions, distinct from the 200-item workflow-routing task in Figure 2. The model roster is limited to the complete pairs; neither an unreported seventh model nor the separately reported drug-development subset is included. Lines connect conditions and are not confidence intervals.

### Shared drug-development comparisons and endpoint sensitivity

The original combined evaluation includes 15 pharmacokinetic cases, 20 dose scenarios and 15 ligand-ranking tasks shared with DrugDev-Bench. The historical eight-model means are 0.075 within-twofold PK agreement, 0.271 exact-dose agreement on 18 scorable scenarios and 0.696 ligand-rank correlation. These values are preserved in Supplementary Table S1 as results of the original protocol. They do not measure one common notion of drug-development competence.

The historical PK prompt did not specify which endpoint to predict. An error analysis found responses numerically close to another recorded PK quantity rather than the scored peak concentration; for Gemini 3.1 Pro, nine of 15 responses met that alternative-endpoint criterion. Numerical proximity alone does not prove that the model computed the alternative endpoint correctly, but it identifies an important ambiguity. After the prompt named the endpoint, the later DrugDev comparison reported a best within-twofold score of 0.467. The original mean of 0.075 should therefore not be interpreted as an intrinsic inability to simulate PK.

The BioMate same-item historical PK result is 0.200 (3/15; reported Wilson interval 0.071–0.452), tying two direct-model results in that protocol. An earlier 18/18 result used a different disease-state ratio task and is not comparable. The historical Biomni ligand-ranking value of 1.0 is based on only four completed items, with 11 unavailable responses, and is not a full-set result. These differences illustrate why sample coverage and endpoint definitions must accompany each comparison.

### Failure modes and evaluation dimensions

The qualitative taxonomy separates invalid workflow names, valid-but-wrong selections, responses without a parseable answer, possible endpoint mismatches and off-scale numeric answers. These categories are more informative than treating every failure as the same reasoning defect. However, taxonomy counts are protocol-specific: a legacy routing classification uses different correctness totals from the later normalized scorer, so its counts must not be combined with Table 1. The historical claim that the retrieval-only entrant had exclusively discrimination errors is also inconsistent with its saved taxonomy table. Supplementary information preserves these source-version distinctions.

Task performance is only the first of five proposed dimensions. The framework also records repeated-run stability, time, cost and hallucination-related behaviour (Table 4). Latency and token-usage summaries exist for 20 stored system rows; they aggregate heterogeneous task coverage and serving conditions. Local rows record output-token values of zero despite substantive predictions, indicating incomplete token accounting rather than zero computational cost. No cost-normalized superiority is inferred from those summaries. The per-model stability and systematic hallucination sweeps are not reported as completed experiments.

**Table 4. Evaluation dimensions and interpretation.** A dimension's implementation is distinct from a completed, comparable model sweep. Diagnostic output validity is also distinct from the broader judged hallucination dimension.

| Dimension | Measures | Evidence and limits |
|---|---|---|
| D1 Performance | Task accuracy, F1, recall or numeric agreement | Reported by task; metrics and denominators differ |
| D2 Stability | Repeat agreement, Cohen's kappa, flip rate | Framework defined; no complete roster-wide repeated-run result |
| D3 Time | Median and 95th-percentile latency | Stored summaries exist; serving and task mixtures differ |
| D4 Cost | Input/output tokens and price-based cost | Stored usage summaries; incomplete local token logging |
| D5 Hallucination | Grounded, unsupported or unverifiable statements; citation checks | Separate judged or verification procedures; not established by deterministic task accuracy |

## Discussion

RealBio supports an experimentally useful distinction between model capabilities and the information supplied by a surrounding system. Candidate catalogs substantially increase workflow-selection accuracy on the evaluated requests. Parameter rules address a different problem, constraining inference and normalizing values. Failure classification, QC policy and workflow specification each retain their own performance profile. These findings argue for reporting the behaviour of individual components before attributing a system result to a model's scale or training.

The catalog comparison does not isolate descriptions from labels, nor does it test unrestricted retrieval. A names-only control with the same catalog and serving configuration is necessary to distinguish those effects. An operational retrieval study must freeze a catalog independently of test labels, retrieve per query, measure candidate recall and score all queries including retrieval misses. The approximate end-to-end value of 0.80 mentioned in an earlier draft has not been linked to the same 200 requests and is not used as an estimate for this experiment.

The shared DrugDev tasks extend the scientific context without being substitutes for workflow evaluation. Their history shows that reference construction is itself an empirical question: a changed endpoint specification can alter scores, and a dose-selection policy can disagree with author-assigned labels. Such cases require explicit protocol versions rather than retrospective pooling. Similarly, a high three-ligand rank correlation does not establish successful docking or an end-to-end discovery programme.

Open, deterministic scoring improves auditability but does not establish neutrality. The authors developed both the benchmark and one evaluated system. Original task authorship does not rule out contamination, and public items may later enter training data. Independent annotation, adjudication of ambiguous cases and prospectively collected tasks would strengthen external validity. The small author-created parameter probe is useful for checking rule behaviour but cannot substitute for those controls.

The wider framework retains execution, stability, cost and grounding as distinct targets of evaluation. A valid selection is a necessary step toward successful execution; it is not execution itself. Future comparisons should test configurations and repairs in held-out environments, verify computational and biological outputs, and report repeated-run variability alongside uncertainty across items. The present results justify improving and documenting task context without claiming that biomedical automation is solved or that small and frontier models are equivalent.

## Methods

### Task composition and reference construction

The core suite contains 200 workflow-routing requests, 170 parameter-extraction items, 100 failure-category cases, 40 workflow-specification items and 100 protocol-QC decisions (Table 5). Routing references include acceptable alternatives where defined. Parameter references include expected key–value pairs and fields that should remain unfilled. Failure cases have fixed categories; workflow specification uses category labels or key-tool sets. The reference action for QC is conditional on the stated protocol and situation.

**Table 5. Core and shared task inventory.** The first five rows comprise the 610-item RealBio core. The final three rows contribute 50 shared DrugDev items to the historical 660-item export. Item count is distinguished from the effective scoring denominator and does not imply that every system completed every item.

| Task | Items | Reference or scored endpoint |
|---|---:|---|
| Workflow routing | 200 | Canonical workflow or accepted alternative |
| Parameter extraction | 170 | Expected values and forbidden fields |
| Failure classification | 100 | Reference fix category |
| Workflow specification | 40 | Category or key-tool coverage |
| Protocol QC | 100 | PASS, WARN or FAIL under the reference policy |
| DrugDev PK | 15 | Within-twofold numeric agreement; endpoint version specified |
| DrugDev dose selection | 20 | Legacy scorer uses 18 non-null labels; structured scorer uses 20 |
| DrugDev ligand ranking | 15 | Spearman correlation with the reference ordering |

Requests and reference labels are author-curated. Per-item reference sources, annotation roles and ambiguity adjudication must be distinguished from the deterministic scoring code. The shared drug-development sources include the BOIN methodological literature, clinical-pharmacology references and structural or affinity data [6–8]. These sources motivate task construction; they do not by themselves validate every derived label.

The direct condition supplies the request without a candidate menu. The documented described-catalog runner builds a sorted set of workflow names from the benchmark's correct labels and appends available workflow descriptions, truncated to 120 characters. This is a fixed, benchmark-derived catalog; it is not a query-specific retrieval test. Correct-label coverage is therefore supplied by construction in this runner. Other stored results include earlier catalog variants, and a full run manifest is required before claiming uniform conditions across all paired rows.

The leaderboard prefers described-catalog predictions and falls back to names-only catalog predictions when necessary. The separate GPT-5.6 row with a names-only condition and Qwen3.8-Max row with problematic direct responses are omitted from the manuscript comparison, as in the source draft. GPT-5.6-luna is a distinct retained row. The Biomni scaffold and retrieval-only system are reported as contextual system results, not matched language-model ablations.

### Deterministic scoring and missing responses

Routing accepts normalized workflow names and specified alternatives. The parameter score counts correct key–value matches as true positives, missing or incorrect expected values as false negatives, and unexpected keys as false positives. An incorrect value on an expected key is not additionally counted as a false positive; this is a benchmark-specific F1 convention. Forbidden-field violations are recorded separately. Value matching includes defined aliases and selected numeric-range rules rather than unrestricted semantic equivalence.

The routing scorer skips absent prediction identifiers, whereas an empty prediction attached to an identifier is scored as incorrect. The described-catalog runner retries empty or failed calls and writes a prediction for each requested item. Coverage, retry counts, failures and effective denominators must therefore accompany the finalized release; the scorer alone does not enforce complete coverage. Deterministic scoring removes a model judge but does not eliminate implementation or reference-label errors.

### Statistical interpretation and model provenance

Results are descriptive point estimates. The benchmark does not provide a basis for inferring population-level equivalence from small score differences. A final statistical analysis should resample paired requests and report task-specific uncertainty, with run variability analysed separately. Model names are retained as recorded in the result artifacts; exact provider identifiers, evaluation dates, revisions, prompts and inference budgets require a frozen run manifest. Locally served results do not include complete per-call token accounting.

### Versioning and historical comparisons

The source protocol identifies an initial freeze on 5 August 2026. Later model additions, semantic-scoring changes and catalog reruns constitute subsequent analyses, rather than extensions of an unchanged preregistered comparison. Historical results are retained in Supplementary Table S1; current workflow comparisons appear in Table 1. The historical Biomni pilot uses 40-item subsets for core tasks and different model engines for computational tasks. Its coverage and serving differences prevent interpreting the scaffold as an isolated model intervention.

The original roster includes eight direct-model systems, a Biomni scaffold and BioMate. Later files add GLM-5.3-prime, multiple Qwen sizes and local base/fine-tuned variants. A model absent from a table has no inferred score. Model names are retained as recorded in the results, and provider variants are not merged. There is no single composite score across routing accuracy, parameter F1, PK agreement and ligand correlation.

## Related benchmarks and scientific-agent systems

The comparison in Table 6 retains the original benchmark families while describing their evaluation targets rather than ranking their openness as a single binary property. A public subset may serve contamination control; deterministic grading may suit a bounded task but omit scientifically meaningful process quality. These choices need to be interpreted in relation to each benchmark's objective [1–5].

**Table 6. Complementary benchmark designs.** This is a methodological comparison, not a head-to-head performance table. Versions and evaluation modes matter; release proportions and model-roster counts are not treated as timeless properties.

| Benchmark | Evaluation target | Relation to RealBio |
|---|---|---|
| BixBench | Biological data analysis with open-ended and multiple-choice settings | Broader analytical tasks; RealBio isolates workflow decisions |
| LAB-Bench | Practical biological research skills, including literature, figures and sequences | Capability assessment; complements workflow-specific references |
| ScienceAgentBench | Scientific programs, execution results and costs | Direct execution evidence beyond workflow selection |
| BioAgent Bench | End-to-end bioinformatics tasks with robustness perturbations and an LLM grader | Pipeline robustness complements deterministic decision scoring |
| BiomniBench | Biomedical research process assessed with task-specific rubrics and an LLM judge | Process quality complements reference-answer agreement |
| RealBio | Fixed workflow decisions and component comparisons | Deterministic task metrics with explicit model/system conditions |

The co-scientist systems discussed in the source manuscript—Google's AI co-scientist, FutureHouse's Robin and Edison Scientific's Kosmos—remain relevant system classes. None has a matched result in the experiments reported here. Their absence is not evidence of inability, and current access conditions are not inferred from an older evaluation date. A comparison would require matching the items, permitted resources, output requirements and evaluation budget.

## Data and code availability

The benchmark package contains items, reference answers, prompts, scorer implementations and retained predictions. The source materials specify CC-BY-4.0 for benchmark data. This preprint does not identify a verified public archive; public repository, final code-license and archival details remain subject to author confirmation. Reproducibility requires preserving the dataset, scorer and condition version for each result, including excluded or incomplete runs.

## Competing interests

Y.Z. and A.D. are affiliated with BioMate AI, which develops the BioMate platform evaluated in this study; A.D. is additionally affiliated with BizBildr. The authors declare these competing financial interests.

## Author contributions and acknowledgements

Y.Z. designed and implemented RealBio and its evaluation harness, ran the cross-system sweep and drafted the manuscript. A.D. contributed to benchmark design and manuscript revision. We thank the BioMate AI team for infrastructure and testing support.

## Supplementary information

### S1 Historical cross-system results

Table S1 preserves the original comparison before later endpoint and scorer revisions. Values are historical observations, not a current unified ranking. The PK prompt was endpoint-ambiguous; dose scoring excluded two null labels; the ligand-ranking task is not an executed docking pipeline. Workflow-generation values use the legacy aggregate endpoint. The eight direct-model means are retained for traceability, not generalized to current models or prompts.

**Table S1. Historical model comparison.** Core denominators are routing 200, failure category 100, parameter extraction 170, workflow specification 40 and QC 100, subject to the Biomni pilot qualification. PK uses 15 cases, dose uses 18 scorable cases and ligand ranking uses 15, except for Biomni's four completed ranking cases. A dash means no comparable same-item result.

| Model | Routing | Failure | Param. F1 | Workflow | QC | PK | Dose | Ranking |
|---|---|---|---|---|---|---|---|---|
| **BioMate** (engine-free curated retrieval) | **0.965** [0.930, 0.983] | — | — | — | — | 0.200 | — | — |
| Claude Opus 5 | 0.615 | 0.870 | **0.757** | 0.500 | 0.330 | 0.133 | 0.444 | 0.700 |
| Gemini 3.1 Pro | 0.580 | **0.880** | 0.693 | 0.500 | **0.630** | 0.000 | 0.278 | 0.700 |
| GPT-5.6 | 0.530 | 0.860 | 0.671 | 0.500 | 0.460 | **0.200** | **0.500** | 0.700 |
| Kimi K3 | 0.450 | 0.770 | 0.628 | 0.450 | 0.360 | 0.000 | 0.167 | 0.700 |
| DeepSeek V4-pro | 0.415 | 0.800 | 0.621 | 0.500 | 0.420 | 0.067 | 0.167 | 0.667 |
| GLM-5.2 | 0.400 | 0.830 | 0.641 | 0.500 | 0.440 | 0.000 | 0.111 | 0.700 |
| GPT-5.6-luna | 0.355 | 0.830 | 0.624 | 0.500 | 0.340 | **0.200** | 0.389 | 0.700 |
| Qwen3.8-Max | 0.345 | 0.860 | 0.692 | 0.500 | 0.460 | 0.000 | 0.111 | 0.700 |
| Biomni (Stanford A1) | 0.950 | 0.950 | 0.708 | 0.500 | 0.500 | 0.000  | 0.500 | 1.0 (n=4)  |

The BioMate retrieval row is a separate system condition; its 0.965 value is not obtained by holding a frontier model fixed. The historical parameter scores differ from the later normalized scoring results in Table 1. No cross-version difference is attributed solely to model improvement.

### S2 Worked examples and prompt excerpts

Table S2 gives original examples, including incorrect answers. Ellipses in the examples and prompt excerpts indicate abbreviated source text; these excerpts are not complete reproducibility specifications.

**Table S2. Illustrative scored core items.** These examples retain the source predictions and reference labels. A single example does not estimate a system's task-level performance.

| Task | Item (input)| Ground truth | Example prediction | Scored |
|---|---|---|---|---|
| cross_domain_routing | "Run standard RNA-seq analysis on my paired-end FASTQ files from a mouse experiment" | `nf-core/rnaseq` | **BioMate:** `nf-core/rnaseq` | Correct |
| autofix_benchmark | "hg19 genome specified but annotations require hg38 … ERROR LOG: …" | `genome_mismatch` | Claude Opus 5: `genome_mismatch` | Correct |
| protocol_thresholds | "Protocol: 10x_genomics_flex_low_input · QC situation: …" | `PASS` | Claude Opus 5: `WARN` | Incorrect |
| param_prefill | "RNA-seq differential expression on human lung adenocarcinoma samples" | `{genome: GRCh38}` | Claude Opus 5: `{}` (failed to infer the assembly) | Incorrect |

- **routing (direct use):** *"Bioinformatics workflows come primarily from three sources: Nextflow/nf-core, Galaxy, and Bioconductor. … Respond with ONLY the single canonical workflow name (e.g. 'nf-core/rnaseq') and nothing else. INPUT: {query}"*
- **autofix:** *"Classify this pipeline failure into exactly one fix CATEGORY. INPUT: {description}\nERROR LOG:\n{error_log}"*
- **protocol_thresholds:** *"Given the sequencing protocol and the QC situation, decide the correct action: PASS, FAIL, or WARN. INPUT: Protocol: {protocol}\nQC situation: {problem}"*
- **param_prefill:** *"Extract values for the specified parameters as a flat JSON object {name: value}. Include a parameter ONLY if its value is clearly stated in the request. Use canonical/standard values (e.g. official reference-genome assembly identifiers, not organism common names). Respond with JSON only. … Candidate parameters: {names}\nRequest: {user_query}"*
- **pbpk:** *"Predict the requested pharmacokinetic value. Respond with a single number only (no units)."*


The original PK prompt is retained to document the endpoint ambiguity. New evaluations should specify the requested quantity, units and context; results from that revision belong to a distinct protocol.

### S3 Uncertainty and coverage

For binary task proportions, the original scorer reports Wilson intervals. Historical examples are BioMate retrieval accuracy 0.965 with interval [0.930, 0.983] at 200 items and GPT-5.6 direct routing 0.530 with interval [0.461, 0.598]. These intervals quantify item-level binomial uncertainty under their assumptions; they do not cover run-to-run variance or annotation uncertainty. Parameter F1, mean tool recall and Spearman correlation are not binary proportions and should not inherit binomial intervals without justification. Paired item resampling is appropriate for matched differences, with repeated model runs analyzed separately.

Biomni pilot coverage, missing prediction identifiers and incomplete ligand-ranking runs require cell-specific denominators. A response attached to an item but containing no usable answer is not the same data state as an absent item identifier. Both need an explicit policy before aggregation. The saved scorer's handling of missing identifiers is described in Methods.

### S4 Additional task families and variants

The broader export contains further instantiated task families (Table S3). These are retained as benchmark coverage and robustness resources, without treating file presence as evidence of a completed model evaluation. The original 610-item denominator excludes them. Paired variants and versioned replacements must not be counted as independent new scientific requests.

**Table S3. Additional available task sets.** Counts are JSONL record counts in the reviewed source snapshot. Alternative versions are listed separately and are not summed into a headline benchmark size.

| Task family | Records | Relationship to the core comparison |
|---|---:|---|
| Accession routing | 27; later version 166 | Versioned resource/accession mapping tasks |
| Paraphrased workflow routing | 200 | Paired wording variant of routing requests |
| Intent interpretation | 96 | Additional interpretation probe |
| Findings probe | 50 | Additional output/findings probe |
| Task decomposition | 30 | Additional planning probe |
| Literature QA | 199 | Literature-answering task set |
| Resource routing | 84 | Separate seven-channel comparison in Table 3 |

### S5 Failure-mode definitions and reconciliation

Invalid-target errors name workflows outside the allowed target set. Discrimination errors select an allowed workflow that does not satisfy the request. A no-answer case contains no parseable final response. An endpoint-mismatch candidate is a numeric response close to a different reference quantity, requiring semantic adjudication before attributing intent. Off-scale responses are inconsistent with all relevant recorded reference quantities under the specified comparison.

The saved taxonomy provides useful historical counts but does not share the later semantic scorer's correctness totals. For example, it records BioMate routing as 182 correct, ten discrimination errors and eight invalid targets on 200 items, whereas the later historical leaderboard reports 0.965. Those artifacts therefore cannot be presented as a decomposition of the same score. The taxonomy remains a useful analysis design; its counts require a common scorer version before quantitative comparison with the current table. A quantitative decomposition of current routing performance requires reclassification under the same scorer.

## References

1. Mitchener, L. et al. BixBench: a Comprehensive Benchmark for LLM-based Agents in Computational Biology. Preprint (2025). https://arxiv.org/abs/2503.00096. Dataset and evaluation modes: https://github.com/Future-House/BixBench.
2. Laurent, J. M. et al. LAB-Bench: Measuring Capabilities of Language Models for Biology Research. Preprint (2024). https://arxiv.org/abs/2407.10362.
3. Chen, Z. et al. ScienceAgentBench: Toward Rigorous Assessment of Language Agents for Data-Driven Scientific Discovery. ICLR (2025). https://arxiv.org/abs/2410.05080.
4. Fa, D. et al. BioAgent Bench: An AI Agent Evaluation Suite for Bioinformatics. ICML (2026). https://arxiv.org/abs/2601.21800v4.
5. BiomniBench: Process-level Evaluation of LLM Agents for Real-world Biomedical Research. Preprint (2026). https://www.biorxiv.org/content/10.64898/2026.05.12.724604v1. Evaluation protocol: https://xbench.org/profession/biomnibench.
6. Liu, S. & Yuan, Y. Bayesian optimal interval designs for phase I clinical trials. J. R. Stat. Soc. C 64, 507–523 (2015).
7. Berman, H. M. et al. The Protein Data Bank. Nucleic Acids Res. 28, 235–242 (2000).
8. US Food and Drug Administration. Guidance on pharmacokinetics in patients with impaired renal function and impaired hepatic function. Item-specific source attribution requires the relevant guidance version and clinical reference.
9. Huang, K. et al. Biomni: a general-purpose biomedical AI agent. Science (2025). https://doi.org/10.1126/science.adz4351.
10. Zhang, Y. & Dike, A. BioMate: a curated, executable, governed catalog for trustworthy biomedical workflow automation. Companion systems manuscript, in preparation.
