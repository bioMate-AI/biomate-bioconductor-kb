# BioMate: turn accumulated knowledge and repairs into a better local model

**Scope correction:** The implementation and training target is the main BioMate assistant, not the IND model. T22/T23 and IND datasets/adapters are excluded. See [BioMate trial scope](BIOMATE_SCOPE.md). This overrides earlier conditional IND references.

12 September 2026. Proposed execution strategy; no teacher calls, training, replay benchmarks or deployment have been performed by this audit. The maximum remains 32B total parameters. This extends the [fast-track plan](FAST_TRACK.md) and uses the [task catalog](TASK_CATALOG.md), [prompt appendix](PROMPT_APPENDIX.md) and [data contract](DATA_CONTRACT.md).

## Decision

Build a verified experience pipeline around BioMate, starting with the official post-trained Qwen3.8-27B candidate and Qwen3.5-27B comparison. Improve the existing harness immediately, then distill successful BioMate decisions and recoveries into the model. Keep frequently changing tool facts in local retrieval. Do not put foundation-model pretraining, a new agent framework or autonomous RL on the urgent release path.

The valuable unit is an episode: the user's objective, information available at each decision, selected tool and arguments, observed result, correction, and independently checked outcome. A pile of documents or successful-looking answers cannot substitute for that sequence. Optimize for successful BioMate tasks per unit of latency and compute, not general biomedical fluency alone.

## What we actually have

Read-only inspection of `backend/database/galaxy_ai_tools.db` found **318,631,936 bytes (318.63 MB)**. This confirms a substantial local knowledge asset; it does not establish the size or meaning of the user's broader “300+ M” knowledge collection. Database size includes embeddings and duplicated representations and is not a token count. Full measured counts and inspection revision are in [RESOURCE_AUDIT.json](RESOURCE_AUDIT.json).

| Resource | Local evidence | Product to build |
|---|---|---|
| Tool catalog | 12,312 tool rows; 7,873 with parameters; 5,674 with inputs; 5,119 with outputs | Versioned retrieval cards, argument validators, tool-choice and parameter-completion cases |
| Tool knowledge | 4,141 entries | Evidence-backed explanations, preconditions and failure-recovery recipes |
| Workflows | 4,200 rows, 4,108 distinct nonempty hashes; 70 chains | Workflow-selection cases, composition constraints and executable fixtures |
| Execution status metadata | 690 `ok`, 402 `ok_warnings`, 797 `exec_error`, 277 `fixture_failed` | Candidate positive and repair pools, after provenance and replay checks |
| Sparse correction/rationale records | 19 workflow user corrections, 24 phase rationales, 67 rationale registry rows | Review seeds; not proof of a large complete trajectory corpus |
| Logs, commits and documents | Relevant fix commits and extraction/recording scripts exist | Incident reconstruction, regression fixtures and verified preference pairs |

The 1,092 stored `ok`/`ok_warnings` statuses are **not freshly verified successes**. The 1,074 error/fixture-failure records may include infrastructure or bad fixtures rather than model mistakes. Another 1,868 workflows have no stored execution status, and 109 are `runnable_assumed`; neither category is positive gold. Workflows are predominantly Nextflow-related, so this database alone cannot establish coverage of all BioMate LLM tasks.

## Six resources, six uses

### 1. Correction logs: learn decisions and recovery

Group related attempts into an incident. Link exact episode, request, run and artifact IDs; retain the before/after context and reviewer evidence. Assign a primary cause: model decision, missing retrieval, prompt ambiguity, tool schema, execution infrastructure, source-data defect or product code. Only model-addressable decisions become model training targets. Fix deterministic defects in code as well.

For each accepted incident, create a successful replay, a short supervised decision example where useful, and a regression case in the incident's assigned split. Create preference pairs only when chosen and rejected answers share the **same information and context**. An answer after a new tool result cannot simply be preferred against an earlier answer that lacked that result.

Keep failed trajectories as diagnostics and recovery contexts; do not teach their mistaken actions as desired assistant completions. Mark unavailable historical context explicitly and exclude unverifiable reconstructions from gold data.

### 2. Commits: convert fixes into executable lessons

A commit is a specification hint, not automatically a training example. Reconstruct the triggering input from its tests/issue, reproduce the defect when practical, run the fix, and record the invariant. The future patch or corrected answer must never appear in the student's earlier decision context.

Three concrete seeds found in this checkout:

| Source | Lesson | Independent check |
|---|---|---|
| `2ecef5f02d01816b44dfa6f1dad5d29b5bab67f2`, no-workflow interpretation requests | Respect explicit requests to explain or calculate without launching a workflow | Assert zero execution calls. Existing unit-conversion fixture can check 20 ng/mL = 0.04 µM and ratio 0.4; retain its fictional research context |
| `f0b134e1d`, explicit GEO accession/platform preservation | Preserve the user's exact dataset and platform constraints | Inspect routing tests, then assert selected identifiers and retrieved provenance; replay remains pending |
| `4927059b208354e55eb687a6fef2b19f0583ef88`, missing artifacts | A completed status alone does not establish usable outputs | Generic completion with zero outputs fails the artifact contract; explicit `stdout_only` contract can pass; a loose boolean is insufficient |

These are source-derived seeds, not newly replayed results. Existing tests used to generate training examples must be marked exposed and cannot simultaneously serve as independent evaluation. “Not explicitly prohibited” also does not mean “authorized to execute.” Preserve execution-intent controls in code.

### 3. Knowledge: retrieve facts; train their correct use

Canonicalize tool/version and workflow/hash records. Build compact cards containing purpose, input/output types, parameter schema, prerequisites, environment availability, example invocation, expected artifacts, known failures and evidence sources. Preserve version and provenance. Validate schemas against installed tools rather than trusting prose.

Use cards in three different products:

- **Local retrieval:** serve current facts and available capabilities at inference time.
- **Training generation:** construct tool contrasts, missing-parameter questions, compatibility failures, workflow repairs and evidence-grounded explanations.
- **Evaluation fixtures:** independently authored cases with withheld task/data/workflow families where feasible.

Generate difficult cases by changing one constraint: unavailable tool, wrong input type, different accession, missing covariate, changed units or incompatible version. Validate that the change actually alters the correct action. A knowledge card used to create both training and test variants creates leakage; track ancestry and split before generation.

Do not start by continuing pretraining on the entire database. Consider a small continued-pretraining experiment only if later controlled results show a knowledge deficit that retrieval and supervised tuning do not fix. It would require another instruction-retention check and is outside the initial critical path.

### 4. Frontier APIs: an offline teaching service inside BioMate's real flows

OpenAI, Claude and Gemini are potential hosted teachers; they are not open-weight models. Use approved development data under each provider's applicable terms and the data owner's permissions. Record model/version, date, data permission and permitted training destination for each batch. Platform fine-tuning documentation alone does not establish permission to train an external Qwen checkpoint. No production on-premise request should require a teacher.

Calibrate available teachers on the same development tasks using outcome verifiers. Choose by verified-example yield, latency and cost per accepted episode rather than vendor reputation. Use one teacher for ordinary cases; request a second attempt or another teacher for failed, difficult or disputed cases. Reserve human review for scientific ambiguity and consequential judgment. Agreement between teachers is not a correctness oracle.

Capture actual tool-call sequences and observations using BioMate's interface. Validate the final artifacts and scientific claims before accepting a trajectory. Distill decisions, tool arguments, recoveries and concise evidence-grounded explanations; hidden chain-of-thought and cross-tokenizer logits are unnecessary.

After the first SFT model, collect **student-induced failures**: let the student reach a difficult state, ask the teacher for the correct next step using the same state, and continue in a sandbox. This targets weaknesses the student actually has. If the teacher chooses a different tool or arguments, execute that action; do not attach observations from the student's different action. Reuse cached observations only for matching tool/version, arguments, data and environment fingerprints.

A teacher may research more broadly while authoring a case, but every student target must be answerable from the information the student will receive. Include required evidence in the context or teach an appropriate retrieval action.

### 5. Open-source harnesses: borrow one capability at a time

| Resource | Useful role | Decision for BioMate |
|---|---|---|
| [DeepSeek-R1](https://github.com/deepseek-ai/DeepSeek-R1) | Research and released distillation examples/checkpoints | Borrow the verified-outcome approach; the repository is not the full original turnkey training system |
| [Hugging Face Open-R1](https://github.com/huggingface/open-r1) | Open reproduction with SFT/GRPO recipes | Reference recipes; this is a separate reproduction, not DeepSeek's original harness |
| [verl](https://github.com/verl-project/verl) | Multi-turn tool RL and verifiable rewards | First framework to evaluate if outcome-based RL later earns its complexity |
| [slime](https://github.com/THUDM/slime) | Scalable rollout/training infrastructure | Consider only if cluster throughput becomes the bottleneck |
| [Agent Lightning](https://github.com/microsoft/agent-lightning) | Agent instrumentation and separation of execution from training | Optional adapter concept; preserve BioMate's existing execution system |
| [GEPA](https://github.com/gepa-ai/gepa) | Feedback-driven optimization of prompts and other text parameters | Early candidate for improving bounded harness components before weight training |

Do not adopt all frameworks. Start with the existing supervised training path, repair its gaps, and add one tool only for a measured need. Verify exact checkpoint, architecture, tokenizer, chat template and training/serving support before committing to a framework; support for another Qwen version is insufficient evidence for 3.8 compatibility.

### 6. Self-improvement: controlled experiments with immutable evaluation

Version model **M**, harness **H**, knowledge **K**, execution environment **E** and evaluator **V** independently. Initially allow optimization of task prompts, retrieval query construction, evidence packing and retry budgets. Keep access controls, execution authorization, provenance checks, evaluators, gold answers and held-out data outside the optimizer's writable scope.

The loop is: collect failures → diagnose → propose one bounded change → sandbox replay → development evaluation → independent release gates → versioned candidate → local canary → promote or roll back. Code changes go through reviewed changes and tests, not unrestricted production self-editing.

Compare M0/H0, M0/H1, M1/H0 and M1/H1 with K/E/V fixed. Otherwise a retrieval or prompt improvement can be falsely credited to weight training. Optimize repeatedly on development data, reserve release tests, and replenish independent holdouts as testing itself exposes information.

## Data pipeline repairs before training

Source inspection found concrete quality risks:

1. [Episode extractor](../../evaluation/training_data_extractor.py) associates a session with its latest run, which can attach the wrong outcome to an earlier episode. It also focuses on generated-workflow episodes and exports simplified user/assistant text. Require exact run linkage and full decision context, and deliberately include non-workflow tasks.
2. [DPO collector](../../scripts/collect_dpo_training_data.py) defaults to the test split as a source. Replace this with a separate training-mining pool; never harvest the frozen release test. Citation substrings and length checks are insufficient scientific verifiers.
3. [Pair recorder](../../backend/lib/galaxy/ai/drug_discovery/regulatory_pair_recorder.py) allows incomplete pairs and truncates context/responses. Treat its rows as candidates requiring context recovery, completeness and deduplication checks.
4. [Training-pair builder](../../scripts/build_training_pairs.py) reconstructs plausible inputs from regulatory prose. Label these as synthetic reconstruction, not observed input/output ground truth.
5. Existing regulatory splits have exact repeated examples across train/dev/test; see [dataset profile](data_profile.json). Regroup and split by case/source lineage before generating new examples. Also check semantic duplicates and related revisions.
6. The per-organization LoRA worker is a stub, and generic training's QLoRA flag does not itself establish actual four-bit loading. Validate a real load/train/save/reload cycle before scheduling capacity or promising adapters.

Store an immutable source manifest, split assignment, context/tool/environment hashes, transformations, verifier results, reviewer decisions and teacher permissions. Keep raw logs restricted; redact secrets and identifiers before approved external teaching. Export only accepted, traceable examples. Track task coverage rather than merely total row counts.

## Training and evaluation sequence

**Baseline:** measure the official post-trained checkpoint with working local tool use, retrieval and constraints. Generic text-only Ollama streaming is not equivalent to the existing cloud agent loop. Remove direct cloud fallbacks from the release dependency path and verify offline behavior before calling the pilot on-premise.

**SFT:** begin with the fast-track target of 2,000 accepted training episodes, 300 development cases and 500 locked test cases, subject to available independently sourced data. These are planning targets, not existing verified counts. Split source families before deriving examples. Oversample high-cost failures and underrepresented tasks; do not let numerous easy knowledge questions dominate tool execution, recovery and evidence handling. Mask tool observations and prompts from the assistant-target loss; retain complete tool context and the checkpoint's template.

**Second iteration:** mine student failures, obtain verified corrections, and rerun SFT. Add preference optimization only for complete, reviewed same-context pairs where SFT still leaves a material gap. Use fresh or held-out cases to detect generic instruction-following regressions.

**Optional RL:** begin only after reliable resets and rewards exist. Reward verified completion under hard validity gates, then optimize cost/latency. Do not reward mere length, keyword inclusion, citations that only look plausible, or a process exit code without usable outputs. Scientific QC, identity preservation and artifact contracts must remain independent of the policy. Use small executable fixtures first and expensive workflows for selected end-to-end verification.

Report by task family: tool/argument validity, correct workflow and constraints, artifact availability, scientific correctness, citation support, recovery success, unauthorized-execution rate, abstention/clarification quality, end-to-end success, p50/p95 latency and memory at intended concurrency. Aggregate scores cannot hide a failing critical task. Treat hard-gate failures as release blockers; choose numerical quality/latency thresholds against the measured baseline and customer requirements before evaluating the candidate.

## Immediate work order and ownership

| Window, after hardware and access are ready | Owner | Reviewable output |
|---|---|---|
| First 24 hours | Application + data engineers | Local tool-loop baseline; source/split manifests; inventory of trace linkage gaps; representative incident and knowledge-card sample |
| 24–72 hours | Application + evaluation engineers, scientist | Limited pilot only for passing tasks; 200-case smoke suite from the fast-track plan; verified teacher calibration on development cases; first replayed repairs |
| Days 3–5 | Data engineer + scientist | Accepted episode batch, rejected-example reasons, coverage report, frozen independent evaluation pool |
| Days 5–10 | Training + evaluation engineers | First SFT candidate if the data/hardware gates pass; baseline comparison, quantized-serving checks and rollback artifact |
| Subsequent iterations | Same owners | Student-failure corrections; controlled harness/model comparisons; DPO or RL only if justified |

The smoke suite is a quick diagnostic, not an additional claim of 200 independent gold training cases. Actual dates depend on GPU memory/count, intended concurrency, data access and execution reliability; no throughput or quality guarantee is implied.

Measure accepted unique episodes per engineering hour and cost per accepted episode: (teacher inference + execution + review cost) / accepted episodes. Also track marginal held-out task improvement per GPU-hour. Stop generating repeated easy cases when acceptance volume rises without coverage or evaluation gains.

The fastest useful asset is a small, replayable set of real BioMate failures and repairs. Build that first, make the local agent reliable, and let each subsequent training batch address observed weaknesses.
