# Committee verdict

**The corrected eval no longer supports the v3 claim that mid-training was critical.** It supports only this narrower conclusion:

> Under one light-dose mid-training recipe and a query-derived, LLM-judged goal-coverage metric, mid-training did not produce a detectable improvement over SFT-only.

It does **not** show that mid-training is intrinsically useless, that the models have ~0.5 real out-of-catalog composition ability, or that the on-prem models approach frontier performance.

The central remaining problem is **construct validity**: the current task can be passed by restating analytical goals from the query without selecting, grounding, connecting, parameterizing, or executing substitute components. It therefore measures **retrieval-conditioned analytical-plan paraphrase** more than operational workflow composition.

---

# 1. Task definition

## 1.1 Is the current removal task valid?

**Partially, but only as a diagnostic subtask.**

Removing a known workflow and asking for an alternative plan is a reasonable stress test for:

- robustness when the preferred workflow is unavailable;
- recognition of the analytical phases implied by a request;
- recovery through alternative workflows or code;
- graceful fallback from catalog retrieval.

It is **not by itself a valid end-to-end measure of out-of-catalog composition**, because:

1. **“Out-of-catalog” is not clearly established.**  
   The workflow is removed from one retrieved candidate list, but it or close paraphrases may have appeared in:
   - mid-training;
   - SFT;
   - tool documentation;
   - workflow-order data;
   - other catalog workflows;
   - the model’s original pretraining.

   This is closer to **leave-one-retrieved-workflow-out** than true out-of-catalog generalization.

2. **Retrieval and planning are confounded.**  
   Retriever recall is only 0.40 on unseen workflows. If viable substitutes are absent from the top 10, a planner failure cannot be distinguished from a retrieval failure.

3. **Candidate feasibility is unknown.**  
   Removing the original workflow does not guarantee that the remaining candidates can satisfy the request. Allowing `GENERATE/RUN_CODE` avoids literal impossibility, but then the task mixes:
   - catalog substitution;
   - workflow synthesis;
   - arbitrary code generation;
   - impossibility recognition.

4. **The output need not be operational.**  
   A phase→step plan may omit:
   - specific tool/component choice;
   - input/output data types;
   - dataflow edges;
   - parameter bindings;
   - reference genome/build or annotation constraints;
   - statistical design and contrasts;
   - output schema;
   - executable code.

5. **Artificial deletion may not reflect deployment.**  
   In deployment, the difficulty may be that no workflow exists, requirements are incomplete, candidates conflict, or components have incompatible interfaces—not that one known-good workflow was manually hidden.

6. **Single-workflow ancestry still biases the task.**  
   Even with tool-agnostic steps, cases originate from workflows that encode one author’s decomposition. Other scientifically valid decompositions may remain under-credited.

## 1.2 Recommended formulation

Define the primary task as:

> **Given a user request, available data/environment, and a constrained catalog, produce a grounded, executable workflow DAG—or correctly request clarification/declare infeasibility—that satisfies explicit and hidden scientific requirements.**

The output should include:

- normalized analytical requirements;
- selected catalog components, with citations;
- generated code only where catalog components are insufficient;
- typed inputs and outputs for every node;
- dataflow edges and format conversions;
- key parameters and statistical design;
- expected deliverables;
- validation/QC checks;
- uncertainty, clarification, or infeasibility when appropriate.

### Separate four task classes

Do not collapse these into one score:

1. **Substitution:** viable alternatives are present.
2. **Composition:** no single workflow suffices, but available components can be combined.
3. **Code fallback:** catalog is insufficient, but bounded code can solve the gap.
4. **Clarification/infeasibility:** the request cannot safely be completed from the supplied information/resources.

For planner evaluation, provide an **expert-verified oracle candidate set**. Evaluate retrieval separately, then run an end-to-end condition using retrieved candidates.

---

# 2. Metric audit

## 2.1 Fraction of LLM-judged steps covered is not an adequate primary metric

It can remain a secondary semantic-recall diagnostic, but it has major confounds.

### A. Step granularity is arbitrary

“Normalize and estimate dispersion” may be one gold step or two. Micro-averaging then gives different weights based on annotation style rather than scientific importance.

The disagreement between the reported summaries is already informative:

- micro favors `full_mix` by 0.010;
- macro favors `SFT-only` by 0.014;
- nonzero fraction is identical.

There is no stable conclusion without a preregistered primary unit and metric.

### B. Recall-only scoring rewards verbosity

A model can enumerate generic analytical phrases until the judge finds matches. There is no penalty for:

- irrelevant steps;
- mutually incompatible methods;
- invented tools;
- missing bindings;
- unsupported parameters;
- invalid dataflow;
- redundant boilerplate.

### C. The judge may over-credit generic language

Statements such as “perform normalization,” “fit a statistical model,” and “correct for multiple testing” can match many gold steps without demonstrating that the model can instantiate a valid workflow.

### D. The query may directly expose the scoring targets

If gold goals are derived from the same query and the output is judged for semantic overlap with those goals, the test can reduce to **reading comprehension plus paraphrase**.

That is not inherently “leakage”—the user query should state requirements—but it is circular if the intended construct is composition and the metric only checks whether those requirements were repeated.

### E. No grounding or execution requirement

A plan may receive full coverage despite selecting no viable substitute, using incompatible components, or being impossible to execute.

### F. Judge instability and bias

A single `gpt-5-mini` judge introduces:

- stochastic variance;
- positional and verbosity biases;
- model-family style preferences;
- possible tool-name familiarity bias;
- threshold instability for partial coverage.

Judge validity must be demonstrated, not assumed.

## 2.2 Recommended scoring system

Use a **multi-axis scorecard with hard gates**, not one unqualified scalar.

### Primary endpoint

**End-to-end pass@1 task success**, defined by:

1. valid parse into the workflow schema;
2. all mandatory scientific constraints satisfied;
3. every non-code operation grounded in an available component;
4. typed dataflow compatibility;
5. successful dry run or execution on a fixture;
6. expected output files/tables produced;
7. output-level assertions passed.

For expensive workflows, use progressively stronger validation:

- schema/type checking;
- static tool-interface validation;
- containerized dry run;
- reduced synthetic dataset;
- full execution for a representative subset.

### Secondary diagnostic dimensions

Report separately:

- **Requirement recall:** mandatory goals satisfied.
- **Requirement precision:** proposed operations that are necessary and valid.
- **Grounding precision:** fraction of steps correctly supported by cited candidates.
- **Dataflow correctness:** compatible input/output types and valid ordering.
- **Parameter correctness:** required parameters, design formulas, contrasts, references.
- **Scientific validity:** method appropriate for data and question.
- **Execution success.**
- **Output correctness:** schema and numerical/property-based assertions.
- **Calibration/abstention:** clarification or infeasibility when required.

Avoid hiding failures in a weighted composite. If a summary is needed, apply hard gates: for example, semantic coverage cannot compensate for an ungrounded or non-executable workflow.

## 2.3 Required metric validation

Run these before treating the score as a model capability estimate:

1. **Human agreement study**
   - At least two independent bioinformatics reviewers.
   - Stratify by domain and difficulty.
   - Measure per-dimension agreement using Krippendorff’s alpha or an appropriate ordinal/continuous reliability statistic.
   - Adjudicate disagreements.

2. **Judge calibration**
   - Compare the LLM judge with adjudicated human labels.
   - Report correlation, absolute error, false-credit and false-rejection rates.
   - Re-test under multiple seeds and orderings.

3. **Boilerplate adversary**
   - Submit long generic plans covering common phrases.
   - A robust metric should score them poorly on grounding, specificity, and execution.

4. **Query-only baseline**
   - Hide all candidates and ask for a plan.
   - If performance remains near the candidate-conditioned score, the benchmark is primarily measuring query interpretation.

5. **Candidate-shuffle and wrong-candidate ablations**
   - Replace candidates with irrelevant but plausible workflows.
   - A grounded composer should either degrade or reject them, not preserve its score.

6. **Oracle-candidate versus retrieved-candidate comparison**
   - This decomposes retrieval loss from planning loss.

7. **Gold granularity perturbation**
   - Split and merge equivalent gold steps.
   - The primary result should remain stable.

---

# 3. Evaluation data setting

## 3.1 Does deriving gold from the query create leakage?

**Not automatically, but the current use creates circularity risk.**

The query is naturally the source of user requirements. It is valid to annotate those requirements from the query. The problem arises when:

- gold is merely a paraphrase of the query;
- the model is scored only for paraphrasing those requirements;
- hidden implementation constraints are absent;
- the same evaluator helped revise gold after observing failures.

The fixed gold is a substantial improvement over copied workflow metadata, but it should be treated as a **post hoc diagnostic repair**, not a final confirmatory benchmark.

### Better gold construction

Gold should combine:

1. user-visible requirements;
2. independent expert interpretation;
3. data- and environment-specific constraints;
4. one or more acceptable executable reference implementations;
5. output-level assertions;
6. an ontology of acceptable operation equivalences.

Annotators should not simply rewrite the removed workflow, and ideally should be blinded to the model outputs. The regenerated 80 cases should not be the sole basis for final claims because the benchmark was modified after failure inspection.

## 3.2 Transcriptomics dominance

Approximately 44 of 80 cases being transcriptomics makes the aggregate score largely a transcriptomics score.

Consequences:

- It cannot support catalog-wide or 36-domain claims.
- Sparse per-domain samples cannot support domain comparisons.
- Common transcriptomics recipes may be unusually easy to recover from the query.
- Mid-training effects in less familiar domains could be diluted.
- Correlated cases from similar differential-expression families reduce effective sample size.

Report at minimum:

- transcriptomics and non-transcriptomics separately;
- domain-stratified results;
- workflow-family-stratified results;
- macro-domain and deployment-weighted aggregates;
- confidence intervals for all summaries.

A deployment-weighted aggregate is useful, but it must be accompanied by a balanced capability view.

## 3.3 Is n=80 or n=150 adequate?

It is adequate for exploratory diagnosis, not for the claimed 0.010 difference.

The comparison is paired, so uncertainty should be estimated by **paired bootstrap over independent cases or workflow families**, not over individual steps. Step-level resampling would create pseudo-replication.

For intuition, if the standard deviation of paired case differences is 0.20, detecting a 0.01 effect with conventional 80% power would require roughly 3,000 paired cases. The actual requirement depends on the observed paired variance, but **n=80 cannot generally establish equivalence within ±0.01 or ±0.02**.

Also:

- domain/family clustering lowers the effective sample size;
- multiple checkpoints or seeds add another variance source;
- the macro reversal indicates heterogeneous effects;
- “no significant difference” is not evidence of equivalence.

Required analyses:

- paired case-level confidence interval for the delta;
- family-clustered bootstrap;
- equivalence test with a preregistered smallest meaningful effect;
- seed-to-seed variation;
- domain interaction estimates.

## 3.4 Defensible held-out evaluation design

Construct the split **before training corpus assembly** and freeze it.

### Leakage controls

Hold out by:

- workflow identity;
- workflow family and near-duplicate cluster;
- tool family where relevant;
- query template/paraphrase cluster;
- source repository or organization;
- time, for a temporal generalization set.

Audit exact and semantic overlap across mid-training, SFT, retrieval corpus, and evaluation.

### Domain design

Use two reporting tracks:

1. **Balanced capability set:** enough cases in selected major domains for domain-level intervals.
2. **Deployment-weighted set:** sampled according to real BioMate traffic.

A practical initial confirmatory set would contain several hundred cases across 8–12 adequately represented domains, plus a separately reported long-tail challenge set. Do not claim coverage of 36 domains from a handful of cases per domain.

### Difficulty strata

Annotate and balance:

- number of required operations;
- single-tool versus multi-tool composition;
- cross-format conversions;
- statistical-design complexity;
- ambiguity/clarification need;
- candidate sufficiency;
- code-generation need;
- tool-family novelty;
- operation-combination novelty;
- domain novelty.

Include negative and impossible cases. Otherwise, always producing a plausible pipeline is rewarded and abstention cannot be evaluated.

---

# 4. What the mid-training wash proves

## 4.1 Supported conclusion

The experiment shows:

> The specific 800-step, sequence-1024, effective-batch-16 mid-training treatment, with the stated mixture and subsequent SFT LoRA, did not cause a measurable gain on this benchmark.

That is the strongest justified statement.

## 4.2 It does not distinguish among four explanations

1. **Wrong corpus**  
   The corpus may contain tool descriptions and code but insufficient examples of:
   - component substitution;
   - interface alignment;
   - workflow DAG construction;
   - failure recovery;
   - scientific constraint satisfaction.

2. **Insufficient or poorly allocated dose**  
   At roughly 13.1M total token presentations before replay accounting, the model saw only a fraction of the 46.4M domain corpus. With heavy FineWeb-Edu replay, effective domain exposure may be around the stated ~14%. Sequence length 1024 may also fragment long workflow and tool relationships.

3. **Wrong training lever**  
   Next-token domain adaptation may improve vocabulary or factual recall without teaching grounded planning. The target behavior may require supervised composition examples or execution/verifier feedback.

4. **Benchmark insensitivity**  
   Query-derived analytical-goal recall may not require detailed domain knowledge. A model can name “normalization,” “dispersion,” and “adjusted p-values” from general knowledge.

A fifth possibility is that later SFT and LoRA compress or overwrite small mid-training gains.

## 4.3 Experiment needed to decide

Use a controlled factorial design.

### A. Dose sweep

Train at matched checkpoints such as:

- 0 domain tokens;
- 0.25 effective domain epoch;
- 1 epoch;
- 2–3 epochs.

Match total compute with a FineWeb-only control. Use multiple seeds and evaluate intermediate checkpoints.

### B. Corpus-content ablation

Compare matched-token mixtures:

- tool/documentation text;
- code;
- ontology/KG text;
- executable workflow traces;
- substitution/composition examples;
- error-repair traces.

This identifies whether composition-oriented data matters more than general domain text.

### C. Pre-SFT and post-SFT evaluation

Measure each checkpoint:

- immediately after mid-training;
- after identical SFT;
- after identical LoRA settings.

This reveals whether knowledge was never learned or was masked by downstream training.

### D. Positive-control probes

Create held-out probes whose answers genuinely require facts present in the domain corpus but absent from the base model’s likely knowledge, such as:

- tool-specific input/output contracts;
- uncommon parameter semantics;
- ontology relations;
- rare format conversions;
- niche domain procedures.

If mid-training cannot improve these, the dose/optimization is suspect. If it improves these but not composition, the lever or benchmark is wrong.

### E. Composition-specific held-out probes

Test novel combinations of known components while holding out the exact combination. This separates:

- factual tool knowledge;
- interface reasoning;
- compositional planning;
- execution correctness.

---

# 5. Correct task and data setting to move out-of-catalog composition

## 5.1 Define novelty explicitly

“Out-of-catalog” should be decomposed into novelty axes:

- unseen workflow identity;
- unseen workflow family;
- unseen combination of known operations;
- unseen tool family;
- unseen domain;
- unavailable preferred component;
- unseen data schema or interface combination.

Report each separately. Removing one workflow from top-10 retrieval is not enough.

## 5.2 Build training data aligned with the target behavior

The current SFT is broad, but the counts do not establish sufficient coverage of **grounded substitution and composition**.

Create training examples where the model must:

- choose among viable and non-viable candidates;
- map requirements to component capabilities;
- bind typed inputs and outputs;
- insert required format conversions;
- preserve statistical design and covariates;
- replace unavailable tools with equivalent operations;
- generate bounded adapter/code steps;
- detect impossible or underspecified requests;
- repair workflows from execution feedback.

Generate examples from real executable workflows by controlled perturbations, but split by workflow/tool family before generation to prevent evaluation leakage.

## 5.3 Use a two-stage benchmark

### Stage 1: Planner-only

Provide an expert-verified candidate set containing:

- sufficient components;
- plausible distractors;
- incompatible candidates;
- optionally no valid solution.

This measures composition without retrieval noise.

### Stage 2: End-to-end

Use the production retriever and measure:

- retrieval sufficiency;
- planner success conditional on sufficiency;
- total end-to-end success.

This makes failures attributable.

## 5.4 Prefer executable references over one textual gold

For each case, store:

- requirement graph;
- acceptable operation alternatives;
- one or more executable reference DAGs;
- tool-interface specifications;
- fixture data;
- expected output schemas;
- property-based or numerical tests.

A model need not reproduce the removed workflow; it must satisfy the scientific contract.

---

# 6. Priority findings and actions

## Single biggest validity threat

> **The benchmark currently conflates restating analytical goals with composing a grounded, executable substitute workflow.**

Because gold is derived from the query and scoring is semantic step recall, a model can score well without using the remaining candidates or solving tool selection, interface compatibility, parameterization, and execution. Therefore, **“~0.5” should not be described as real out-of-catalog composition performance.**

## Top three changes

### P0 — Replace the primary endpoint

Make the primary task an executable, candidate-grounded workflow DAG with:

- component citations;
- typed dataflow;
- parameters;
- scientific constraints;
- execution/output checks;
- clarification/infeasibility behavior.

Retain LLM-judged goal coverage only as a secondary diagnostic.

### P0 — Build a new frozen, leakage-controlled confirmatory set

- Split by workflow family, tool family, paraphrase cluster, source, and time before training-data assembly.
- Balance major domains and report deployment-weighted results separately.
- Include substitution, composition, code-fallback, and impossible cases.
- Use independent expert annotation and executable fixtures.
- Do not use the post hoc repaired 80 as the sole confirmatory benchmark.

### P1 — Separate retrieval, planning, and knowledge

Evaluate:

1. query-only;
2. oracle candidates;
3. retrieved candidates;
4. shuffled/wrong candidates;
5. execution.

Then run a matched-compute dose/content sweep with pre- and post-SFT knowledge and composition probes.

---

# Bottom line

- **v3’s causal diagnosis is invalidated:** mid-training was not shown to be the missing ingredient.
- **The corrected benchmark is better but still not a composition benchmark in the strong sense.**
- **The 0.483 versus 0.493 result is a null under one recipe, not evidence of equivalence.**
- **No frontier comparison should be made until the fixed frontier baseline is complete.**
- **The next investment should be benchmark reconstruction and failure attribution—not simply more mid-training tokens.**