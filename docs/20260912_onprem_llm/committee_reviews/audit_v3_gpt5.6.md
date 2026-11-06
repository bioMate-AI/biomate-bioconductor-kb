[openai] 18666 chars

## Executive verdict

The models learned **catalog routing better than open-world workflow synthesis**. The 27B result is directionally better, but neither model demonstrates reliable out-of-catalog composition. The dominant risks are:

1. **Missing long-tail knowledge exposure**: skipping the 44.9M-token domain corpus left SFT carrying a job it cannot cover across 4,172 workflows and 7,240 tool-functions.
2. **Objective conflict**: routing-heavy SFT taught “select one known workflow,” while the removal benchmark requires “construct a multi-step substitute.”
3. **Unisolated failure sources**: the evaluation does not separate retrieval failure, missing model knowledge, planning failure, schema failure, and judge noise.
4. **Weak benchmark validity**: coverage is recall-only, the reference plan may not be unique, the sample is transcriptomics-heavy, and statistical uncertainty is not reported.

The most important pre-v3 intervention is a **long-tail-balanced domain-adaptive mid-training pass**, with a sealed workflow-family holdout, before compositional SFT.

---

# 1. DATA audit

## P0: SFT coverage is much thinner than the headline suggests

18,597 examples is adequate for learning the **12 task interfaces**, but not evidence of adequate coverage across:

- 4,172 workflows
- 7,240 tool-functions
- 36 domains
- Rare parameters, datatype transitions, and alternative workflow realizations

Naively, 18,597/4,172 is only **4.46 examples per workflow**, and many examples are clarification, parameter filling, generic routing, or otherwise not unique workflow coverage. The explicitly composition-relevant sets are:

- `decompose`: 1,649
- `interwf_decomp`: 2,340
- `wfgen`: 1,539

Total: 5,528, or only **1.33 examples per workflow** if distributed uniformly—which they certainly are not.

The audit is missing the critical coverage tables:

- Number and percentage of workflows seen in zero, one, two, or more SFT examples
- Tool-function frequency and Gini/long-tail distribution
- Domain × task cross-tabulation
- Workflow-family rather than workflow-ID coverage
- Number of datatype edges and tool-function blocks exercised by compositional examples
- Coverage of rare tools appearing in the zero-coverage cases

“Real artifacts,” paraphrases, and committee validation establish local correctness, not breadth.

## P0: The failure list strongly indicates long-tail underexposure

The repeated zero-coverage workflows—`rgsea`, `oncomix`, `rgadem`, `magrene`, `methylgsa_custom_annotation`, etc.—are not random. They are niche workflows or use rare methods. That is consistent with:

- No or very few SFT examples for the relevant tool-functions
- No domain-adaptive mid-training exposure
- Retrieval failing to surface the needed tool blocks
- Models replacing unknown niche procedures with familiar generic workflows

You need an entity-level audit for each zero case:

| Item | Required evidence |
|---|---|
| Workflow | Present in SFT? Count and task types |
| Tool-functions | Present in SFT or 44.9M corpus? |
| Workflow family | Present in training? |
| Required datatype edges | Represented in WKG/SFT? |
| Retrieval | Relevant block in top-1/top-k? |
| Generation | Used relevant retrieved evidence or ignored it? |

Without this, “data sparsity” is plausible but not proven.

## P1: Routing is overrepresented relative to the desired behavior

`rag_routing + routing` contains 6,779 examples, **36.5% of all SFT**. This is a strong single-selection prior. By contrast, direct decomposition is only 1,649 examples.

`interwf_decomp` and `wfgen` help, but they may not counteract the dominant pattern if their outputs still use known workflow names rather than assembling primitive tool-functions under catalog ablation.

The 27B’s concise single-workflow response is therefore not merely a format accident. It is evidence that the model learned the high-frequency routing policy.

## P1: Transcriptomics dominance distorts aggregate conclusions

Approximately 44/80 evaluation queries are transcriptomics, so the overall score is primarily a transcriptomics score. Consequences:

- Improvements in genomics or metagenomics have limited effect on the aggregate.
- Systems biology and other domain means may be based on very few cases and be unstable.
- The aggregate cannot support a claim of coverage across 36 domains.
- The models may look better than a macro-domain evaluation if transcriptomics is better represented in training.

Report both:

- Micro-average across cases
- Macro-average across domains and workflow families

Also publish per-domain sample counts and confidence intervals.

## P2: Sequence length may still constrain complex examples

A sequence length of 2,048 can truncate or force simplification of:

- Long retrieved tool descriptions
- Multi-phase workflow plans
- Full parameter/configuration context
- Multiple candidate workflow descriptions

The statement that request truncation was fixed does not establish that **input plus retrieval plus output** fits. Measure truncation and token-budget allocation by task.

---

# 2. DESIGN audit

## Is SFT-first defensible?

Only for a system where the harness reliably supplies all required domain facts. It is not well matched to the reported out-of-catalog task.

SFT-first is defensible for:

- Output schemas
- Routing conventions
- Clarification behavior
- Tool-call syntax
- Limited transformations over supplied context

It is weak for:

- Rare tool knowledge
- Unseen workflow-family generalization
- Datatype and method relationships not stated in the prompt
- Constructing substitute plans after the canonical workflow is removed

The 44.9M-token corpus exists specifically to teach tools, ontologies, code, and WKG relations. Skipping it likely contributed to niche failures. This is not causally established, because there is no mid-trained ablation, but it is the strongest design-level suspect.

For a 27B model, 44.9M tokens is modest, so expectations should be controlled. It can still be valuable if it is high quality and deliberately balanced toward rare tool-functions rather than replaying frequent transcriptomics material.

## Is routing SFT suppressing composition?

Yes, there is direct behavioral evidence of policy interference:

- The benchmark requests a phase-to-step reconstruction.
- The 27B often emits a concise single pick.
- Routing-related examples are the largest SFT component.
- The larger model has lower training loss and may therefore reproduce the dominant SFT policy more sharply.

This explains part of the 27B bimodality: when it recognizes a familiar solution, it performs well; otherwise it collapses to a single familiar workflow instead of building a partial plan.

However, separate two issues:

1. **Regex/schema artifact:** valid semantic content is not counted as composed.
2. **True behavioral failure:** a single workflow pick cannot cover a genuinely multi-step substitute plan.

The former invalidates `composed_rate=0.05` as currently calculated. The latter can genuinely reduce coverage.

## Other unvalidated design claims

Several design principles are stated but not demonstrated:

- The 0.15 near-tie threshold is not calibrated against outcome quality.
- No DPO result is reported.
- No evidence shows the clarification gate improves task success.
- The proposed 4B→27B cascade is not evaluated end-to-end.
- No escalation confidence metric is reported.
- The 27B’s bimodality means escalation alone will not reliably rescue hard cases.

The cascade should be evaluated as a system, including error correlation: if both models fail on the same niche cases, capacity escalation offers little benefit.

---

# 3. TASK audit

## Missing tasks likely causing low out-of-catalog coverage

### P0: Explicit catalog-ablation composition

Training needs examples where:

1. The obvious/canonical workflow is removed.
2. The model is told not to return it.
3. Primitive tool-functions or neighboring workflows remain available.
4. The required output is a dependency-aware substitute plan.
5. Single-workflow answers are marked incorrect unless sufficient.

Current decomposition data may teach decomposition of an available workflow, not reconstruction after removal.

### P0: Retrieval-grounded multi-block planning

Retriever recall@1 is the wrong primary metric for a task needing multiple steps. Report:

- Recall@k for each required tool-function
- Fraction of cases where **all required evidence** appears in top-k
- Datatype-edge recall
- Family-level retrieval recall
- Recall on the exact niche zero-coverage set

A top-1 family-holdout recall of 0.40 is concerning, but it cannot be mapped directly to generation coverage without these measures.

### P1: Rare-tool and workflow-family generalization

Construct splits where:

- Exact workflow is unseen
- Workflow family is unseen
- Tool-functions are seen but their composition is unseen
- Some required tool-functions are rare
- Only datatype compatibility enables the solution

These conditions distinguish memorization from compositional generalization.

### P1: Schema adherence under conflicting priors

The model needs targeted examples where routing and composition prompts are lexically similar but require different schemas. Add explicit contrastive negatives:

- Incorrect: one workflow ID
- Correct: ordered multi-step JSON
- Incorrect: valid tools with incompatible datatypes
- Incorrect: unordered or dependency-breaking steps

Constrained decoding or a harness renderer should enforce JSON. Do not spend model capacity relearning deterministic syntax if the harness can guarantee it.

### P1: Plan precision and executability

Step coverage alone rewards verbosity. Add:

- Step precision
- Hallucinated-tool rate
- Dependency/order correctness
- Input/output datatype compatibility
- Executability or compilation success
- Required versus optional step coverage
- Redundant-step rate

## Is the removal evaluation well designed?

It is useful as a stress test, but not sufficient as currently specified.

### What it measures well

- Robustness when a familiar catalog answer is unavailable
- Whether the model can reconstruct a substitute plan
- Tendency to route versus compose
- Long-tail brittleness

### Major construct-validity issues

1. **“Removed from candidates” is not necessarily unseen.**  
   If the workflow appeared in SFT, base pretraining, or retrieved WKG text, the task can be memorized reconstruction rather than true out-of-catalog generalization.

2. **A single reference plan may not be unique.**  
   Bioinformatics workflows often have several valid tool choices and optional QC steps. Penalizing alternatives as missing “true steps” can understate performance.

3. **Some tasks may be underdetermined.**  
   If the query lacks assay details, genome build, platform, or desired output, clarification may be the correct behavior.

4. **The domain distribution is heavily skewed.**

5. **The benchmark mixes failure modes.**  
   Retrieval, planning, formatting, and tool knowledge are not separately controlled.

Use four matched conditions:

- No retrieval
- Current retrieval
- Oracle retrieval containing all necessary tool blocks
- Oracle plan primitives with only ordering/composition left to generate

That factorial design will localize the bottleneck.

---

# 4. OUTPUT audit

## Is 0.30/0.40 versus 0.54 a fair verdict?

It is a fair verdict only for this specific benchmark and scoring pipeline:

- 27B is directionally better than 4B on semantic step recall.
- Both trail the GPT-5-mini baseline.
- Neither has demonstrated robust out-of-catalog composition.

It is not yet a fair general verdict on BioMate quality or broad bioinformatics competence.

## Statistical uncertainty is missing

With only 80 bounded observations, differences of 0.10 and 0.14 should not be treated as definitive without paired analysis. In the worst case, a bounded mean at \(n=80\) can have an approximate 95% half-width around 0.11. The actual uncertainty may be lower because systems were presumably evaluated on identical cases, but that requires:

- Paired bootstrap confidence intervals
- Per-case score differences
- Sign or permutation tests
- Domain/family-stratified intervals

“27B > 4B” is directionally supported but not statistically established from the supplied aggregates.

## `composed_rate` is invalid as implemented

A metric reporting 0.05 composition despite 0.40 semantic coverage is not measuring composition; it is measuring exact schema/regex compliance.

Re-score all outputs with:

1. A real JSON parser
2. Schema normalization
3. A semantic classifier for single-pick versus multi-step plan
4. Separate metrics for:
   - Interface compliance
   - Semantic composition
   - Step coverage

Still, do not dismiss the output mismatch entirely. In a production API, failure to return the required schema is a real integration failure. The appropriate remedy is usually constrained generation or harness-side normalization.

## Coverage itself has important confounds

### Judge noise

An LLM judge may:

- Merge or split steps differently
- Favor wording similar to the reference
- Fail to recognize equivalent tool substitutions
- Over-credit vague steps
- Penalize concise but correct abstractions

Audit with blinded human review on a stratified subset, multiple judges, and agreement statistics.

### Recall-only scoring

Coverage can be increased by emitting many plausible steps. It must be paired with precision, hallucination, compatibility, and executability.

### Baseline comparability

The GPT-5-mini comparison is fair only if all models received identical:

- Prompts
- Candidate sets
- Retrieval context
- Token budgets
- Schema instructions
- Retry/repair opportunities

Calling 0.54 “frontier” is too strong based on one baseline.

## Training loss is overinterpreted

The losses are not a clean capacity comparison because the runs differ in:

- Model size
- LoRA rank
- Training steps
- Potential optimization dynamics

A lower 27B training loss is compatible with greater capacity, but it does not prove that capacity caused the improvement or that the model generalizes better. Validation loss and per-task held-out metrics are needed.

---

# 5. ERROR ANALYSIS

## Most likely root cause of niche zero-coverage

The evidence points to a **knowledge-access failure followed by routing-policy collapse**, not one isolated cause.

Likely chain:

1. The niche workflow/tool family is sparse or absent in SFT.
2. Mid-training that could have exposed the model to rare tools was skipped.
3. The retriever may fail to surface the relevant blocks; family-holdout recall@1 is only 0.40.
4. The model falls back to the heavily trained single-workflow routing behavior.
5. The answer contains no reference-aligned steps, producing zero coverage.

The supplied data cannot determine how much is retriever versus generator because retrieval traces on the 80 cases are absent.

## Explanation for the 27B bimodality

The bimodality is consistent with thresholded recognition:

- When the 27B recognizes the workflow family or retrieves useful evidence, its extra capacity yields a substantially better plan: 22 cases at ≥0.67 versus 11 for 4B.
- When it does not recognize the family, it confidently emits a familiar single workflow or an irrelevant plan, producing zero coverage.
- The larger model reduces zero cases from 26 to 20 but does not eliminate the missing-knowledge tail.

This is not a simple “27B generates worse” story. It is a **high-confidence known/unknown split** amplified by the routing-heavy SFT policy.

The domain changes support this interpretation: 27B improves strongly in genomics, metagenomics, variant calling, and systems biology, but single-cell remains weak. However, domain counts are needed before interpreting those means.

## Required root-cause experiment

For every zero-coverage case, run:

| Condition | Interpretation if successful |
|---|---|
| Current prompt, no retrieval | Tests model-parametric knowledge |
| Current retrieval | Current system performance |
| Oracle relevant WKG/tool blocks | Improvement means retrieval is the bottleneck |
| Oracle blocks + forced plan schema | Additional improvement means formatting/policy is a bottleneck |
| Gold primitive steps, model only orders/connects | Failure means planning/dependency learning is the bottleneck |

Also inspect attention/citation or explicit evidence use: retrieving the correct block is not enough if the model ignores it.

## What single change is most likely to raise coverage?

Given the evidence, the best single training change is:

> **Run domain-adaptive mid-training on the 44.9M-token corpus, rebalanced toward rare tool-functions, workflow families, and datatype relations, before compositional SFT.**

This targets the sharpest observed weakness: niche tools that SFT cannot economically enumerate.

It should not simply replay the corpus at its natural frequency. Use rarity-aware sampling and ensure that long-tail tools receive meaningful exposure. Preserve a sealed family-level holdout so that the next evaluation measures generalization rather than exact workflow memorization.

If the oracle-retrieval experiment shows that most zero cases are solved merely by supplying the right blocks, retriever improvement would supersede this recommendation. Current recall@1 is concerning, but there is not enough per-case evidence to make retrieval the primary diagnosis yet.

---

# 6. SINGLE highest-priority fix before v3 compositional training

## Run a long-tail-balanced domain-adaptive mid-training stage

Concrete requirements:

1. **Use the skipped 44.9M tokens**, emphasizing tool-function descriptions, code semantics, ontology relations, and WKG datatype edges.
2. **Oversample rare tool families and underrepresented domains**, rather than preserving transcriptomics dominance.
3. **Do not train on exact plans for the sealed evaluation workflows/families.** Expose constituent tools and general relations, but prevent benchmark recipe leakage.
4. Evaluate before SFT on:
   - Rare-tool recognition
   - Tool input/output compatibility
   - Family-held-out retrieval/use
   - Workflow-step completion from partial plans
5. Then run v3 compositional SFT with explicit catalog-ablation examples and a lower routing-to-composition imbalance.

Why this is the top fix: v3 compositional SFT can teach the model **how to compose**, but it cannot reliably compose niche tools whose semantics were never learned or retrieved. More routing examples, more paraphrases, or simply more 27B steps will reinforce the current failure mode rather than fix it.
