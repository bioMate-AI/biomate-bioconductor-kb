# Committee verdict

The plan has the right **overall architecture**—retrieval for volatile knowledge, joint format-matched SFT for skills, and verifier-grounded RL—but it currently **over-invests in speculative mid-training** and **under-invests in scenario coverage, evaluation design, and retrieval-conditioned training**.

The proposed **25% domain / 75% general, 2–4B-token mid-training run is not justified yet**. For a 27B base already competitive on RealBio, it is more likely to consume substantial compute while producing small or unmeasurable downstream gains—and may introduce regressions that broad language-loss monitoring will not reveal.

Recommended ROI order:

1. **Retriever and retrieval-conditioned inference/training**
2. **Expanded, production-format joint SFT**
3. **Targeted grounded RL**
4. **Mid-training only if a controlled ablation demonstrates incremental value**

---

# 1. Domain/general ratio and token budget

## Assessment

A fixed **25% domain / 75% general ratio is not empirically justified**.

The rationale—distributional bridging and anti-forgetting—is reasonable in principle, but three facts argue against this specific setting:

- The base model is already strong on-domain.
- LoRA mid-training limits how much broad catastrophic forgetting should occur.
- At 2–4B tokens, 75% general replay means spending **1.5–3B tokens largely teaching the model material it already knows**.

The ratio also cannot be assessed independently of token budget. At 2B tokens, 25% domain is already 500M domain tokens; at 500M total, it is only 125M. These are very different interventions.

## Recommended starting point

If mid-training is retained:

| Component | Recommended share |
|---|---:|
| Internal/task-proximal bioinformatics material | 30–40% |
| High-quality external biomedical/protocol material | 20–30% |
| General replay, including high-quality prose/code | 30–40% |

Thus, start around **60% domain / 40% general**, not 25/75.

This is not because 60/40 is intrinsically optimal. It is a better **DAPT hypothesis**: enough domain pressure to create measurable adaptation, with sufficient replay to monitor and control regressions.

### Token budget

Recommended final budget:

- **Pilot:** 200–300M tokens per condition
- **Extension of winning condition:** total **500–800M tokens**
- **Hard cap before strong evidence:** approximately **1B tokens**

Do not commit to 2–4B tokens up front. Small downstream gains are likely to saturate early, especially with LoRA.

The 37M-token curated set must not simply be repeated many times. Track **effective epochs per source**:

- Internal high-value material: preferably around **1–3 effective passes**
- Repetitive workflow JSON, ontology edges, and templated KG text: lower caps
- Broad external domain text: used to increase diversity rather than amplify repetitions

## Required sweep

Run a token-matched pilot with at least:

1. **No mid-training**
2. **25% domain / 75% general**
3. **60% domain / 40% general**
4. **80% domain / 20% general**

Use the same:

- LoRA rank and target modules
- Token budget
- Data-quality filters
- SFT set and schedule
- Retrieval configuration
- Evaluation prompts
- At least two seeds if differences are only a few percentage points

Checkpoint early, for example every 50–100M tokens. Stop conditions should be based on downstream utility, not continued-pretraining loss.

## What determines the optimum

The optimum is the mixture producing the best **post-SFT production performance under a regression constraint**. Evaluate both before and after identical SFT, because a DAPT gain may disappear after SFT.

Primary criteria should include:

- Routing accuracy with actual retrieved candidate sets
- Parameter exactness, restraint, and cross-field validity
- Decomposition DAG semantic validity
- Execution success and workflow-generation validity
- Diagnosis and interpretation accuracy
- Abstention/clarification behavior
- Performance on tasks not represented in the SFT set
- General reasoning, instruction following, code, and multilingual regression
- Robustness to unseen tools, workflows, schemas, and domains

Use a Pareto criterion, such as:

> Accept mid-training only if it provides statistically credible production-task gains without material regressions on untuned tasks.

Training loss or ontology recall is not sufficient evidence.

---

# 2. Corpus composition

## Overall assessment

The corpus contains valuable assets, but it currently mixes three very different objectives without enough prioritization:

1. Learning stable bioinformatics concepts and procedures
2. Learning workflow/code patterns
3. Memorizing catalog and graph facts that should remain in retrieval

The third category is overemphasized relative to the design principle of **knowledge in retrieval**.

## Internal tool and workflow text: high value

The 9M tokens of internal tool/workflow text are likely among the most valuable data, provided they include:

- Tool purposes and limitations
- Input/output semantics
- Schema descriptions
- Workflow selection criteria
- Preconditions and incompatibilities
- Failure modes
- Examples with realistic files and biological goals

Prefer semantic documentation over catalog boilerplate. Deduplicate near-identical wrapper descriptions and automatically generated parameter listings.

## Workflow code: valuable but probably overweighted

At 17M of approximately 37M curated tokens, code is nearly half the curated set. That is high unless workflow generation is a primary product workload.

Raw Nextflow, Bioconductor, and workflow JSON can teach:

- Workflow syntax and composition
- Data dependencies
- Common parameter conventions
- Execution structure

However, raw code alone is weak supervision for routing, decomposition, parameter restraint, diagnosis, and interpretation. It may also overrepresent:

- Boilerplate
- Serialization details
- Wrapper-specific conventions
- Long low-information configuration blocks
- Repeated workflow scaffolding

### Recommendation

Keep code around **20–30% of domain tokens**, unless execution-tested workflow generation is a dominant task.

Increase its value by pairing code with:

- Natural-language intent
- Input/output data types
- Dependency/DAG summaries
- Valid parameter examples
- Execution outcomes
- Error logs and repairs
- Explanations of why specific tools or stages were selected

Execution-tested code is much more valuable than scraped code. Weight by quality rather than file count.

## Ontologies: useful selectively

EDAM is directly relevant because it supports:

- Operation normalization
- Data-type compatibility
- Query-to-tool mapping
- Decomposition constraints
- Retrieval expansion

GO, SO, HPO, and ChEBI are useful where they support biological entity normalization or interpretation, but their value for workflow routing is indirect.

Do not serialize complete ontologies indiscriminately. Prefer:

- Definitions
- Synonyms
- Parent/child relations
- Cross-ontology mappings
- Examples of normalization in realistic requests
- Data-type and operation compatibility paths

Ontology IDs and graph topology should generally remain retrieval-accessible. The model should learn **how to use ontological evidence**, not memorize every edge.

## Verbalized KG triples: limited mid-training value

Naively verbalized triples often produce:

- Templated low-entropy text
- Artificial language distributions
- Memorization without graph reasoning
- Excessive exposure to facts that may become stale
- Spurious confidence when retrieval evidence is absent

Use KG data primarily to create:

- Multi-hop reasoning examples
- Tool/data-type compatibility judgments
- Positive and hard-negative retrieval pairs
- “Insufficient evidence” examples
- Graph-path explanations
- Constraint-checking tasks

Raw or mechanically verbalized triples should be a small fraction of the mixture, roughly **5–10% of domain tokens at most**, unless pilot results prove otherwise.

## Hetionet: low direct relevance

Hetionet is primarily a biomedical discovery graph, not a bioinformatics workflow-execution graph. Its relevance is low unless BioMate explicitly handles tasks such as:

- Drug repurposing
- Gene–disease association reasoning
- Mechanistic hypothesis generation
- Biomedical knowledge-graph interpretation

At only 34.7k edges, it is also unlikely to materially affect a 27B model through continued pretraining.

Recommendation:

- **Remove or heavily downweight Hetionet** for the initial run.
- Retain it in retrieval or task-specific examples if those use cases exist.
- Do not treat it as core workflow-domain adaptation data.

## External literature and protocols

PMC and peS2o can provide terminology and scientific style, but broad biomedical literature is not equivalent to workflow-assistant data. Much of it will be low-density for BioMate’s tasks.

Use relevance filtering for:

- Methods sections
- Computational protocols
- Software/tool descriptions
- Data-processing pipelines
- Benchmarking and failure analysis
- Reproducibility and parameter reporting

Bio-protocol and GTN tutorials are more task-proximal than generic biomedical papers and should receive higher weights, subject to deduplication and benchmark-contamination checks.

## Important missing or underweighted data

The corpus should contain substantially more of the following:

1. **Real execution traces**
   - Commands, environments, runtime states, outputs, failures, retries

2. **Error-to-cause-to-fix trajectories**
   - Dependency failures, malformed inputs, resource failures, incompatible formats, version conflicts

3. **Schema and parameter semantics**
   - Required versus optional, defaults, units, arrays, enums, file types, cross-field constraints

4. **Workflow decision boundaries**
   - Why workflow A is preferable to B
   - When no workflow is suitable
   - When clarification is required

5. **Results and QC interpretation**
   - Tables, logs, plots, reports, warning signs, biologically implausible outputs

6. **Cross-workflow composition**
   - Data-type handoffs, branching, merging, conditional stages, incompatible interfaces

7. **Coverage across all 36 domains**
   - Prevent high-resource genomics workflows from dominating less common domains

8. **Retrieval-conditioned examples**
   - Realistic top-k candidates, distractors, stale entries, conflicting descriptions, missing correct candidates

Because Qwen3.8-27B is multimodal, include plot/report/image examples if results interpretation is expected to use that capability. Otherwise, explicitly scope interpretation to text and structured outputs and test that text adaptation does not degrade multimodal ability.

## Data governance concern

“Commercial-safe” should be documented at the item/source level. Maintain:

- License manifests
- Required attribution
- Source URLs and versions
- Article-specific PMC license checks
- The Stack file-level license handling
- Removal and provenance procedures

Private deployment does not eliminate license obligations.

---

# 3. Is mid-training worth doing?

## ROI ranking

### 1. Retriever: highest ROI

The reported hybrid recall@20 of 0.95 already shows that retrieval is the dominant routing lever.

Next work should focus on:

- Recall on underrepresented domains
- Hard-negative ranking
- Candidate ordering and calibration
- Entity and synonym normalization
- Data-type compatibility retrieval
- Query decomposition before retrieval
- Missing-candidate detection
- End-to-end routing accuracy conditioned on the top-k list

Recall@20 alone is not enough. Measure:

- Recall@1/5/10/20
- MRR or nDCG
- End-to-end selection accuracy
- Accuracy when the correct workflow is absent
- Performance under stale or contradictory catalog entries

The remaining 5% retrieval misses impose a hard ceiling that weight tuning cannot remove.

### 2. Joint production-format SFT: high ROI

This has already demonstrated real gains without negative transfer. Expand it before undertaking large-scale DAPT.

SFT should teach:

- How to use retrieved evidence
- Structured output discipline
- Parameter restraint
- Clarification and abstention
- Cross-workflow planning
- Verification and repair behavior

Keep all relevant tasks in one joint mixture, including preservation examples for tasks that previously showed negative transfer.

### 3. Grounded RL: medium-to-high conditional ROI

RL is promising where rewards are objective:

- JSON/schema validity
- Execution success
- Data-type compatibility
- Correct parameter omission
- Correct citations to retrieved evidence
- Successful repair after errors
- Appropriate abstention

However, execution success is not equivalent to semantic correctness. A workflow can run and still answer the wrong biological question.

Use composite rewards and adversarial reward validation. Otherwise the model may learn to:

- Prefer trivial executable workflows
- Omit useful parameters excessively
- Exploit verifier blind spots
- Produce superficially valid but semantically poor DAGs

RL should follow a sufficiently broad SFT baseline and should be evaluated for reward hacking.

### 4. Mid-training: lowest current ROI

Mid-training may help with:

- Stable domain terminology
- Workflow/code priors
- Tool-schema comprehension
- Error-log familiarity
- Long-form procedural reasoning

But it is unlikely to be the best mechanism for:

- Catalog facts
- Current workflow availability
- Exact tool versions
- Routing among retrieved candidates
- Production serialization behavior

Those are better addressed through retrieval and task training.

## Recommendation

Do not remove mid-training entirely, but make it a **stage-gated experiment**, not the default centerpiece:

> Proceed beyond 300M pilot tokens only if DAPT improves the same production-format, retrieval-conditioned tasks after identical SFT, with no meaningful regression.

---

# 4. SFT quality, generalization, and gaps

## Overall assessment

The existing 1,834-example set is a credible pilot and its exact production formatting is a strength. It is not yet sufficient evidence of broad generalization across:

- 4,200 workflows
- 12,312 tools
- 36 domains
- Approximately 28 LLM-backed tasks
- Unseen schemas and cross-workflow scenarios

The principal danger is not merely “format overfitting.” It is **template, tool-family, verifier, and scenario overfitting inside the correct format**.

## Production-format matching

Given the empirical evidence, preserving the exact production envelope is correct.

Do not introduce arbitrary prompt paraphrases that will never appear in production. Instead, vary the contents that can genuinely vary:

- User wording and ambiguity
- Candidate count and order
- Irrelevant retrieved candidates
- Missing or conflicting metadata
- Schema size and field order
- Optional context sections
- Tool and workflow families
- Domain terminology

Version prompts and adapters together. If production prompt formats change, train and evaluate that version explicitly rather than assuming transfer.

## Routing: 529 examples

529 examples may improve candidate selection but cannot cover 4,200 workflows directly. Generalization must come from learning selection criteria.

Add:

- Retrieval-conditioned hard negatives
- Near-equivalent workflows
- Correct candidate absent from top-k
- Multiple valid workflows with trade-offs
- No-suitable-workflow cases
- Ambiguous requests requiring clarification
- Unseen workflow-family and domain holdouts
- Candidate metadata corruption or staleness

Split by workflow family, not randomly by example. Otherwise near-duplicate workflow descriptions will inflate results.

## Parameter extraction: 384 examples and 16% yield

A 16% generation yield is a warning sign. The accepted set may be biased toward:

- Easy schemas
- Short outputs
- Common tools
- Cases the verifier can readily validate
- Generator-specific templates

Stratify coverage by schema feature:

- Required versus optional parameters
- Defaults that should not be restated
- Units and numeric ranges
- Enums and booleans
- Arrays and nested objects
- File types and paired inputs
- Conditional and mutually exclusive fields
- Cross-field constraints
- Unknown values requiring clarification
- Explicitly irrelevant user details
- Requests where most fields should remain unset

Include negative supervision for overfilling. Rejected generated examples can be useful for preference or repair training after labeling, but should not be admitted to SFT merely by automatic cleanup.

## Decomposition: 341 examples, intra-workflow only

This is a major mismatch with the stated task of producing an ordered sub-task DAG.

Intra-workflow decomposition teaches stage summarization, not general agentic workflow planning. Add:

- Cross-workflow chains
- Branching and merging DAGs
- Conditional branches
- Parallelizable stages
- Iterative QC and retry loops
- Data-type conversion stages
- Incompatible tool interfaces
- Missing prerequisites
- Partial plans requiring clarification
- No-valid-plan cases
- Alternative valid DAGs with trade-offs

Evaluation should check semantic dependencies and data compatibility, not only topological or JSON validity.

## Workflow generation: 320 examples

Prioritize execution-tested diversity over raw count. Hold out:

- Workflow families
- DSL features
- Tool combinations
- Domain categories
- Complex schema patterns

Test both execution and semantic alignment with the user request.

## Autofix: 211 examples

Ensure these are based on realistic failures, not synthetic syntax errors alone.

Needed error families include:

- Environment/container failures
- Missing dependencies
- Version mismatches
- Permissions and paths
- Resource exhaustion
- Invalid or corrupted input
- Data-type mismatches
- Empty outputs
- Tool-specific exit codes
- Biological QC failures despite successful execution

Separate diagnosis from repair in evaluation: a patch that happens to execute is not necessarily based on the correct diagnosis.

## Protocol: 49 examples

Forty-nine examples are insufficient to claim a protocol skill unless the task is extremely narrow.

Either:

- Expand to at least several hundred diverse, audited examples, or
- Remove it from the trained-skill claims and keep it retrieval-driven until more data exists

Include protocol-to-workflow mapping, deviations, prerequisites, timing, materials, ambiguity, and infeasible protocol requests.

## Missing core tasks

The SFT set does not clearly cover several stated core capabilities:

- Results interpretation
- Standalone error diagnosis
- Retrieval evidence use and citation
- Abstention/clarification
- Tool-KG querying or graph-path reasoning
- Recovery when retrieval misses the correct workflow
- Multimodal QC/plot interpretation, if in scope

Most importantly, only six tasks are represented while the system has about 28 LLM-backed tasks. Given the observed negative transfer, the remaining tasks require:

- Preservation/replay examples during joint SFT, or
- Explicit regression evaluation with a hard release gate

## Verifier quality

Schema and execution checks are necessary but insufficient:

- Schema-valid can be semantically wrong.
- Executable can answer the wrong question.
- An “independent auditor” may share the same model biases.
- Exact overlap detection does not catch template or workflow-family leakage.

Add stratified human expert review, especially for:

- Complex decomposition
- Parameter omission
- Workflow equivalence
- Biological interpretation
- Error root-cause diagnosis

Use source-, time-, tool-family-, and workflow-family-level holdouts. Scrub held-out benchmark material from **all stages**, including mid-training corpora.

---

# 5. Biggest risk and top three changes

## Single biggest risk

The largest risk is **false evidence of improvement caused by narrow, verifier-friendly, production-template data that does not cover real deployment scenarios**.

This can produce excellent structured-validity and held-out-example scores while failing on:

- Unseen workflow families
- Cross-workflow DAGs
- Hard parameter constraints
- Retrieval misses
- Ambiguous requests
- Semantic execution errors
- Untuned tasks

The 2–4B-token mid-training run compounds this risk because it is expensive and may cause subtle regressions without addressing those scenario gaps.

## Top three changes

### 1. Make mid-training conditional on a controlled no-mid ablation

- Reduce the pilot to 200–300M tokens per mixture.
- Compare no-mid, 25/75, 60/40, and 80/20.
- Apply identical joint SFT afterward.
- Evaluate production tasks, untuned tasks, and general regressions.
- Extend only a clearly winning condition to 500–800M tokens.

This prevents a large compute commitment based on an unvalidated analogy to other projects.

### 2. Rebuild SFT and evaluation around scenario and family generalization

Prioritize:

- Cross-workflow decomposition
- Parameter edge cases and restraint
- Retrieval-conditioned hard negatives
- Protocol expansion
- Results interpretation
- Real diagnosis/error traces
- Clarification and abstention
- Preservation examples for the other LLM-backed tasks

Use workflow-family, tool-family, domain, source, and temporal splits rather than random splits. Add blinded human review for semantically complex cases.

### 3. Recompose the corpus around task-proximal evidence and retrieval use

- Downweight raw KG verbalization and Hetionet.
- Cap repetitive code/JSON exposure.
- Increase execution traces, errors, schema semantics, QC outputs, and workflow decision rationales.
- Use ontology/KG data to generate reasoning paths, hard negatives, and compatibility examples rather than memorized facts.
- Spend the saved compute on retriever improvement, retrieval-conditioned SFT, and grounded RL.

---

# Final go/no-go recommendation

| Component | Recommendation |
|---|---|
| 2–4B-token mid-training as proposed | **No-go without pilot evidence** |
| 25% domain / 75% general | **Do not adopt as default** |
| 60% domain / 40% general, 200–300M pilot | **Recommended experimental starting point** |
| Expanded joint production-format SFT | **High priority** |
| Retrieval and reranking improvements | **Highest priority** |
| Grounded RL after broader SFT | **Proceed cautiously** |
| Raw KG/Hetionet-heavy adaptation | **Downweight or remove** |

The strategic direction is sound, but the training plan should shift from “large domain adaptation followed by tasks” to **“retrieval-first, scenario-complete joint task training, then narrowly justified adaptation and RL.”**
