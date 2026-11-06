# BioMate LLM task and process catalog

This catalog groups the inspected implementation by **training/evaluation responsibility**, not by number of classes or provider calls. A user turn can invoke several tasks. Domain labels such as RNA-seq, cryo-EM, drug discovery and clinical genomics usually reuse these task types with different evidence, workflows and schemas.

The [exact source appendix](/Users/kky/biomate-review/docs/20260912_onprem_llm/PROMPT_APPENDIX.md) contains full extracted prompt expressions/builders. Quotations below are short orientation excerpts from BioMate source, not replacement prompts. Follow the source links for the whole call context. Runtime prompts also include retrieved content, user/project/session state, active skills, tool schemas and provider-specific serialization; those values cannot be reconstructed from a static template alone.

**Reachability labels:** Core = inspected main chat path; Route = API handler or helper used from routes; Conditional = feature/configuration/branch dependent; Secondary = implemented alternative/older module, current production use unproven; Offline = maintenance or evaluation rather than normal user inference. No label asserts measured production frequency.

## User request understanding and context

### T01 — Unified intent analysis and multi-intent decomposition · Core · P0

- **LLM responsibility:** identify information need(s), task/domain hints, subqueries and agent/action requirements; recognize execution, research, clarification, data provision and follow-up intent.
- **Prompt:** “You are a bioinformatics intent analyzer. Classify user messages by their information need and declare which system agents should handle the request.” The large [system prompt](/Users/kky/biomate-review/frontend/server/galaxy-assistant.ts:5850) contains schema examples, boundary cases and routing rules. Input includes session memory, conversation history and the current user message.
- **Process:** deterministic early checks/overrides → assembled intent prompt → model JSON → parsing/defaults and mandatory action corrections → single-intent dispatch or per-intent processing → final response. LLM flags are not the sole authority; `_parseIntentResult` restores mandatory research/workflow actions for certain types.
- **Target/data/evaluation:** structured intent object and subqueries; label multi-turn transitions, negation, execution-vs-discussion, data-only follow-ups and cross-domain requests. Score macro-F1, per-intent recall, decomposition completeness, inappropriate execution and downstream success.
- **Secondary counterparts:** backend [intent parser](/Users/kky/biomate-review/backend/lib/galaxy/ai/intent_parser.py) and [task decomposer](/Users/kky/biomate-review/backend/lib/galaxy/ai/task_decomposer.py:206) use prompt/schema-based extraction and decomposition behind older backend flows. Do not combine all implementations as independent user tasks.

### T02 — Literal scientific data extraction · Core · P0

- **LLM responsibility:** extract directly supplied SMILES, sequences, accessions, coordinates, units, file references and inline tables.
- **Prompt:** “You are a scientific data extractor.” Rules require literal values, no inferred data, no tool/workflow names and a JSON object. [Full prompt and call](/Users/kky/biomate-review/frontend/server/galaxy-assistant.ts:2348).
- **Process:** message hash/cache → model sees currently only the first 1,200 characters → parse JSON and normalize string/list values → cache result; failure uses regex fallback → extracted data injected into response/parameter context. This truncation is a pipeline limitation, not necessarily a model failure.
- **Target/data/evaluation:** exact source spans and typed values. Score literal preservation, list completeness, hallucinated values and extraction beyond the current truncation boundary. Preserve scientific strings during data redaction.

### T03 — Domain inference and tailored clarification · Core, conditional · P0

- **LLM responsibility:** select a domain from the technical registry and generate one useful clarification for ambiguity such as bulk/single-cell or germline/somatic.
- **Prompts:** domain classifier must “Respond with ONLY one of these exact strings”; clarification must be specific and under 70 words. [Domain](/Users/kky/biomate-review/frontend/server/galaxy-assistant.ts:3685), [clarification](/Users/kky/biomate-review/frontend/server/galaxy-assistant.ts:3647).
- **Process:** ambiguity/domain gate → query plus active workflow context → model label or question → whitelist validation; invalid/failed domain response gives no restriction; failed clarification uses a static fallback. Labels influence workflow search rather than execute anything.
- **Target/data/evaluation:** valid labels and minimal questions that change the next decision. Score unnecessary clarification, wrong branch and missing clarification, not only text similarity.

### T04 — Session memory, context compression and session summary · Core/background · P1

- **LLM responsibility:** maintain active task, decisions/confidence, uploaded files, attempted workflows, parameters and open questions; compress older chat; summarize completed/recent work.
- **Prompts:** [memory UPDATE_PROMPT](/Users/kky/biomate-review/frontend/server/galaxy-assistant.ts:1606) says “Update incrementally”; [compression prompt](/Users/kky/biomate-review/frontend/server/context-compressor.ts:213) asks for a concise comprehensive conversation summary. The session-summary call is near [the end of the assistant module](/Users/kky/biomate-review/frontend/server/galaxy-assistant.ts:9672).
- **Process:** debounce memory updates → current JSON plus truncated new turn → model → type guards/merge/persistence → later prompt injection. Compression separately extracts dataset/attachment blocks deterministically and reattaches them so summarization does not lose handles. Cross-session/episode retrieval includes keyword-based scoring, which is not an LLM call.
- **Target/data/evaluation:** before/turn/after states and summaries, including corrections and supersession. Score factual precision/recall, stale-fact removal, exact file/run-ID retention and later-turn task success.

## Retrieval, workflow selection and preparation

### T05 — Search query expansion and candidate ranking · Core/backend conditional · P0

- **LLM responsibility:** expand query terms, identify entities/data types, infer categories, rank retrieved tools and choose workflows/chains from candidates.
- **Prompts:** [backend QUERY_ANALYSIS_PROMPT](/Users/kky/biomate-review/backend/lib/galaxy/ai/query_analyzer.py:61) asks for entities, inferred category, task type, expanded terms and data types; [frontend ranker](/Users/kky/biomate-review/frontend/server/galaxy-assistant.ts:7499) asks to rank supplied tools; [workflow reselection](/Users/kky/biomate-review/frontend/server/galaxy-assistant.ts:7728) compares the generated answer and candidate workflows.
- **Process:** query understanding → FTS/dense/catalog candidate retrieval → optional LLM ranking/browse/chain selection → parse and resolve candidate IDs/names → deterministic overrides and compatibility logic → selected workflow. See [backend workflow search](/Users/kky/biomate-review/backend/lib/galaxy/ai/unified_workflow_search.py:697), including later chain-selection prompts.
- **Target/data/evaluation:** rankings and selections **against the supplied candidate list**. Collect near-neighbor wrong workflows, explicit user choices, exclusion/negation and missing catalog entries. Evaluate retrieval recall separately from ranking accuracy, grounded IDs, top-1 accuracy and execution suitability.

### T06 — Schema-grounded parameter resolution · Core · P0

- **LLM responsibility:** map natural-language parameter values to canonical workflow keys, resolving what deterministic rules did not fill.
- **Prompt:** “Use ONLY the canonical key names listed. Do NOT invent keys.” The [prompt head](/Users/kky/biomate-review/frontend/server/lib/schemaGroundedExtractor.ts:74) and `buildResolverPrompt` include workflow name, rendered schema, already-filled keys and user query.
- **Process:** rule/alias pass → gate on unresolved parameters or parameter signal → LLM JSON → fill gaps without overwriting rule-derived/user-overridden keys → schema validation → drop illegal values and create missing/invalid parameter clarification cards. Confidence is a code heuristic, not calibrated model probability.
- **Target/data/evaluation:** canonical key/value map. Score enum normalization, required omissions, forbidden keys, user override retention and explicit invalid-value handling. Data must contain the actual schema version and rule-pass output.

### T07 — Dataset compatibility and workflow prerequisites · Route/helper · P0

- **LLM responsibility:** match datasets to required inputs, identify missing inputs/parameters and explain next actions.
- **Prompts:** [prerequisites validator](/Users/kky/biomate-review/frontend/server/workflow-prerequisites-validator.ts:468) supplies requirements, available datasets, tool documentation and user context; a second [response prompt](/Users/kky/biomate-review/frontend/server/workflow-prerequisites-validator.ts:612) turns the result into natural-language guidance. [DatasetValidator](/Users/kky/biomate-review/frontend/server/dataset-validator.ts:75) asks whether uploaded datasets suit the first workflow step.
- **Process:** construct requirements/metadata → LLM matching/JSON → normalize mappings and requirements → user guidance/form → separate execution input gate. The older DatasetValidator catches LLM failure and returns `valid: true` with low-confidence auto-assignment; do not treat that as a validated positive training label.
- **Target/data/evaluation:** input mappings, missing requirements and explanations. Test incompatible formats/sample types, missing mates, invalid enum choices and ambiguous matching. Match correctness and false-ready rate matter more than persuasive prose.

### T08 — Workflow draft, detailed parameter generation and propose/validate refinement · Conditional/secondary · P1

- **LLM responsibility:** propose workflow steps/tools/parameters and revise a rejected proposal.
- **Prompts:** iterative frontend calls “Generate a high-level workflow structure based on the requirements” and “Configure this step,” with detailed system builders in [iterative generator](/Users/kky/biomate-review/frontend/server/iterative-workflow-generator.ts:212). Backend [propose/validate generator](/Users/kky/biomate-review/backend/lib/galaxy/ai/propose_validate_workflow_generator.py:229) generates JSON then uses validator feedback; [LLM parameter generator](/Users/kky/biomate-review/backend/lib/galaxy/ai/llm_parameter_generator.py) supplies tool constraints/context.
- **Process:** requirement clarification/catalog context → draft JSON → real tool/parameter/connection validation → refinement prompt with failures and available alternatives → bounded revised proposal → executable representation/approval flow. Draft generation is not workflow execution.
- **Target/data/evaluation:** paired proposal/validation/refinement transitions and final executable workflow. Use real catalog versions and successful runs. Score tool existence, parameter validity, I/O compatibility, scientific sequence and actual output correctness. Verify which alternative generator the target deployment actually uses before allocating training volume.

### T09 — Multi-workflow chain composition and coverage reasoning · Core conditional/backend composer · P0/P1

- **LLM responsibility:** extract scientific entities, compose a candidate workflow chain and assess whether one workflow covers multiple requested steps.
- **Prompts:** [NER template](/Users/kky/biomate-review/backend/lib/galaxy/ai/chain_composer/ner.py:205); [`_build_prompt`](/Users/kky/biomate-review/backend/lib/galaxy/ai/chain_composer/composer.py:490) uses retrieved patterns/chains/workflows and entities; [coverage question](/Users/kky/biomate-review/frontend/server/galaxy-assistant.ts:4942) asks how many user analysis steps a workflow covers.
- **Process:** entity extraction → retrieve compatible patterns/candidates → LLM compose → ground placeholders/IDs → verifier → optional LLM correction with feedback → proposal. Separately, [chain_planner.py](/Users/kky/biomate-review/backend/lib/galaxy/ai/chain_planner.py:18) explicitly uses BFS without an LLM in its inner loop. Missing credentials can select a deterministic composer stub; record that distinctly.
- **Target/data/evaluation:** typed DAG/steps/bindings, valid identifiers and coverage decisions. Score chain validity, candidate grounding, unresolved input honesty and run-to-run artifact linkage; test both a single comprehensive pipeline and genuinely multi-pipeline requests.

### T10 — Workflow changes in conversation · Backend conditional · P0

- **LLM responsibility:** parse value changes, skipped steps and added workflows.
- **Prompt:** [classifier system/schema](/Users/kky/biomate-review/backend/lib/galaxy/ai/workflow_modification_classifier.py:17) returns `type`, `step_index`, `param_changes`, `skip_flags`, `new_workflow_name` and reasoning.
- **Process:** current workflow plus message → Gemini helper → parse JSON to modification object → session/application logic; errors use regex heuristics. Downstream validation must verify the actual schema and step scope.
- **Target/data/evaluation:** mutation intent only, not invented final execution state. Test “what if,” negation, discussion vs command, references to prior steps and later corrections; score exact mutation and absence of unintended changes.

### T11 — Nextflow composition and conversion · Conditional/maintenance · P1/P2

- **LLM responsibility:** generate or repair DSL/code connecting existing processes, and assist conversion between workflow representations.
- **Prompts:** [Nextflow composer](/Users/kky/biomate-review/backend/lib/galaxy/ai/nextflow_composer.py:542) calls its assembled prompt within composition/retry logic; the appendix includes its prompt builder. Alternative conversion paths include [dual converter](/Users/kky/biomate-review/backend/lib/galaxy/ai/dual_llm_converter_system.py) and enhanced/legacy generators.
- **Process:** supplied process/tool signatures and workflow intent → code proposal → parsing/validation/error feedback → correction → execution by Nextflow/container runtime. Catalog conversion scripts are generally a build-time workload, not necessarily customer inference.
- **Target/data/evaluation:** compileable and executable DSL with correct dataflow and output contracts. Validate against pinned Nextflow and containers; successful syntax alone is insufficient. Keep build-time data distinct from user routing data.

## Scientific reasoning, tools, papers and evidence

### T12 — Main scientific answer and iterative tool use · Core · P0

- **LLM responsibility:** reason from available evidence, select tools, generate Python/R/bash tool arguments when needed, interpret observations and write an answer.
- **Prompt:** [research/workflow branches](/Users/kky/biomate-review/frontend/server/galaxy-assistant.ts:8201) plus [user context assembly](/Users/kky/biomate-review/frontend/server/galaxy-assistant.ts:8409). Dynamic inputs include session/long-term/project memory, inline data, dataset handles, domain knowledge, research results, workflow information and active skills. Tool definitions are supplied separately from prose.
- **Process:** T01 → searches/research/workflow preparation as selected → model with context/tools → tool request → application tool dispatcher and sandbox/API → tool observation → repeat → final answer/artifacts. The model proposes code; `code-runner.ts`, scientific libraries and containers compute results. Provider adapters differ: current Ollama path lacks the tool loop.
- **Target/data/evaluation:** complete multi-turn tool trajectories, verified code outputs and grounded final responses. Test multi-tool calls, tool errors, uploaded data and prior-run output reuse. Score both final science and action correctness; never train on claims that a tool ran without an actual observation.

### T13 — Alternative compact tool orchestrator · Secondary · P1

- **LLM responsibility:** select search_workflows, search_literature, run_code, synthesize_papers and benchmark tools and synthesize results.
- **Prompt:** [ORCHESTRATOR_SYSTEM_PROMPT](/Users/kky/biomate-review/frontend/server/orchestrator.ts:398) lists the tools and requires citations, no fabricated outputs and avoidance of duplicate calls.
- **Process:** messages + tool definitions → Claude call → dispatch returned tool calls → feed observations back → final text. This is an alternative implementation; it was not established as the main route used by this checkout's chat handler.
- **Target/data/evaluation:** share the T12 tool-use dataset contract, but preserve tool-schema/version differences and measure which orchestrator is active before treating results as production parity.

### T14 — Evidence-grounded scientific research synthesis · Backend research path · P0

- **LLM responsibility:** answer research/methodology/interpretation questions using gathered scientific evidence, benchmark results, database records, papers and skill guidance.
- **Prompt:** [`_build_synthesis_prompt`](/Users/kky/biomate-review/backend/lib/galaxy/ai/agents/research_agent.py:2214) builds skill, benchmark, database, paper/full-text, figure and literature blocks plus question, analysis and instructions. [LLM invocation](/Users/kky/biomate-review/backend/lib/galaxy/ai/agents/research_agent.py:2568) uses the shared client.
- **Process:** analyze question → gather evidence from database/literature/benchmark/knowledge clients → optionally extract figures → synthesize with LLM → parse/format result/citations → main assistant may use this result for final synthesis. Some classification/evidence collection logic is deterministic; the LLM is not the database.
- **Target/data/evaluation:** evidence packet → supported answer with citations and uncertainty. Include conflicting/absent/stale evidence. Score retrieval availability separately from entailment, completeness and biological validity.

### T15 — Claim entity extraction and evidence reranking · Route · P1

- **LLM responsibility:** identify genes/pathways/compounds/traits and score whether each retrieved item supports or refutes a claim.
- **Prompts:** [entity parser](/Users/kky/biomate-review/frontend/server/evidence-routes.ts:145) requests JSON entity arrays; [reranker](/Users/kky/biomate-review/frontend/server/evidence-routes.ts:297) requests index, relevance score, confidence and summary for every input item.
- **Process:** user claim or provided entities → optional model extraction → PubMed/OpenTargets/STRING queries → model rerank → merge source URLs/DOIs with summaries → sort/cache. The source registry includes more possible datasets than are necessarily implemented in this dispatcher.
- **Target/data/evaluation:** entity golds, evidence ordering and faithful summaries; assess source preservation and polarity (support vs contradiction). Self-reported confidence requires calibration.

### T16 — Multi-paper PDF synthesis through PaperQA · Route, dependency gated · P1

- **LLM responsibility:** summarize retrieved paper passages and synthesize a cited cross-paper answer.
- **Prompt:** BioMate supplies the user question and configures model, summary model, embeddings and retrieval counts in the [PaperQA route](/Users/kky/biomate-review/backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py:6049). **Internal evidence-summary and answer templates belong to the installed PaperQA version and were not extracted by this repository audit.** Capture them at runtime and pin the package; do not invent a supposedly exact template.
- **Process:** uploaded/local PDF paths → parse/index documents → embeddings → evidence retrieval/summarization → answer → returned contexts/citations. The inspected route requires an Anthropic key and configures embedding access separately, so local generation alone does not make it offline.
- **Target/data/evaluation:** permissioned paper sets, questions and supported answers with page/passage references; score cross-paper synthesis, contradictions, citation precision and evidence recall, plus offline indexing/query execution.

### T17 — Uploaded images and scientific figure reading · Core/research conditional · P1

- **LLM responsibility:** interpret supplied images and extract figure labels, numbers and relationships relevant to a research question.
- **Prompt:** [figure question](/Users/kky/biomate-review/backend/lib/galaxy/ai/agents/research_agent.py:1433) feeds base64 image and question to a vision helper; uploaded images also become image blocks alongside the T12 prompt in the frontend.
- **Process:** locate/download/read image within permitted storage → format/size filtering → image-content block or figure-specific vision call → textual evidence → research/final answer. A text model cannot replace the image encoder by seeing base64 as text.
- **Target/data/evaluation:** original images/crops, panel IDs, labels/units, gold values and evidence-linked interpretation. Assess unreadable axes and ambiguous panels; either provide a validated local vision model or explicitly leave this capability unavailable for the first release.

## Execution outcomes, repair and reporting

### T18 — Log diagnosis and root-cause analysis · Route/workflow-ops conditional · P0/P1

- **LLM responsibility:** classify failures, infer likely root cause from logs and recommend corrective actions.
- **Prompts:** [frontend ERROR_ANALYSIS_SYSTEM_PROMPT](/Users/kky/biomate-review/frontend/server/routes.ts:11593); backend [log analyzer](/Users/kky/biomate-review/backend/lib/galaxy/ai/workflow_ops/log_analyzer.py:324) includes Chinese instructions for Nextflow log analysis; root-cause and error-search agents have separate prompts in the appendix.
- **Process:** collect stderr/logs → fast regex/progress scanning → conditional LLM for unresolved/new issues → structured diagnosis/severity/suggestions → display or repair planner. Frontend model failure uses a regex result. Log tails are truncated, so missing causal context is possible.
- **Target/data/evaluation:** log + actual environment/configuration → adjudicated cause, evidence line and safe action. Use real failure episodes and distinguish infrastructure, input, software and scientific-parameter faults. Evaluate diagnosis accuracy and unhelpful/wrong repair rate.

### T19 — Autofix planning, parameter mapping and code/command repair · Workflow-ops conditional · P1

- **LLM responsibility:** propose changes and tool actions to fix an observed workflow failure; map mismatched parameters; revise ineffective fixes.
- **Prompts:** [auto healer](/Users/kky/biomate-review/backend/lib/galaxy/ai/workflow_ops/auto_healer.py:486), [parameter analyzer](/Users/kky/biomate-review/backend/lib/galaxy/ai/workflow_ops/parameter_analyzer.py:118), and [autofix package](/Users/kky/biomate-review/backend/lib/galaxy/ai/workflow_ops/autofix/agent.py). Exact task/error/context prompts and fix schemas are in the appendix.
- **Process:** issue classification and deterministic fixers → LLM analysis/plan if appropriate → confidence/eligibility gates → constrained fix application → restart/re-run → observe success/failure → bounded refinement. Several alternative generations of autofix coexist; audit configured registration instead of assuming all are active.
- **Target/data/evaluation:** full repair trajectory with diffs, commands, validator decisions and post-fix artifacts. A patch that merely suppresses an error is not a successful fix. Preserve execution permissions, prohibit unrelated changes and report human escalation frequency.

### T20 — Post-run findings and numerical interpretation · Route · P0

- **LLM responsibility:** turn workflow output samples/metrics into concise findings, explanations, caveats and next steps.
- **Prompts:** [analysis prompt](/Users/kky/biomate-review/frontend/server/routes.ts:13176) requests quantitative findings/citations; the separate [file-grounded findings prompt](/Users/kky/biomate-review/frontend/server/routes.ts:13829) requires exact source-file values and explicitly forbids invented numbers and literature citations. These are different prompt contracts.
- **Process:** completed-run artifacts → format-specific parsers/output sampling → LLM JSON → parsing/grounding checks/figures/cache → UI. The file-grounded path uses Gemini and has a direct Claude fallback for malformed/truncated JSON.
- **Target/data/evaluation:** actual output files and expected metrics, source filenames, explanation and caveats. Score exact numerical fidelity and source attribution; detect fake success after failed/partial execution. Evaluate the grounded path's fallback separately because it shortens the evidence context.

### T21 — Downloadable scientific/methods/run reports · Route · P1

- **LLM responsibility:** write structured narrative sections from run context, parameters, workflow steps, metrics and findings.
- **Prompt:** report system/template branches and generation are in [routes.ts](/Users/kky/biomate-review/frontend/server/routes.ts:5567); multiple section requests use the shared `llmGenerate` helper. The appendix captures assigned system prompts as well as template builders.
- **Process:** load execution/results context → build domain/report-specific prompts → one or more narrative generations → assemble text/document output → download. Formatting/conversion and numerical computation are not language-model tasks.
- **Target/data/evaluation:** complete context plus accepted report with source mapping; assess omitted methods/parameters, invented references, mismatched environment/version statements, cross-section consistency and downloadable artifact integrity.

## Regulatory writing and support features

### T22 — Regulatory narrative drafting and revision · IND route/backend · P0 if IND is in scope

- **LLM responsibility:** draft regional/section-specific narrative grounded in provided study/computational evidence and revise it after audit feedback.
- **Prompts:** [_NARRATIVE_SYSTEM_BY_REGION](/Users/kky/biomate-review/backend/lib/galaxy/ai/drug_discovery/ind_assembly.py:643); [section prompt dictionary](/Users/kky/biomate-review/backend/lib/galaxy/ai/drug_discovery/ind_assembly.py:740); special longer overview prompt near line 1500. Inputs can include regional guidance, computed anchors, organization rules, retrieved few-shot examples and audit constraints.
- **Process:** validated/assembled study data and deterministic calculations → section prompt + RAG/org context → configurable model route → quick audit/length checks → possible Gemini fallback → guardrails → document assembly → further audit/revision. The current longer-overview request and per-call output budgets must be reviewed for truncation; model quality cannot repair an insufficient output allowance.
- **Target/data/evaluation:** section-level and whole-document examples, evidence, region, omitted data, computations and reviewed revisions. Evaluate numerical/citation fidelity, jurisdiction applicability, no invented study results and cross-section consistency. This catalog describes software behavior, not validation of its regulatory interpretations.

### T23 — Semantic regulatory audit · IND conditional · P0 if IND is in scope

- **LLM responsibility:** judge semantic consistency and unsupported claims that rule checks alone may miss.
- **Prompt:** [_JUDGE_SYSTEM and template](/Users/kky/biomate-review/backend/lib/galaxy/ai/drug_discovery/regulatory_auditor.py:151) combine selected document sections and context; [_call_llm_judge](/Users/kky/biomate-review/backend/lib/galaxy/ai/drug_discovery/regulatory_auditor.py:377) uses Claude with Gemini fallback.
- **Process:** deterministic structure/content/citation/threshold checks + optional semantic LLM judgment → normalized findings/severity → document revision or user review. The semantic check supplements the deterministic checks and must report when unavailable.
- **Target/data/evaluation:** clean and deliberately flawed documents with reviewer-labeled defects and evidence. Score sensitivity for critical defects, false positives and localization; use independent experts, not agreement with the generator as the gold standard.

### T24 — Project notebook synthesis · Route · P1

- **LLM responsibility:** synthesize project progress from recent workflows and episodes into an updated research note.
- **Prompt:** [buildSynthesisPrompt](/Users/kky/biomate-review/frontend/server/notes-routes.ts:92) supplies project name/description and recent work.
- **Process:** ownership check → load scoped project context → model Markdown → reject empty/error output → save note. The model does not determine project ownership or database authorization.
- **Target/data/evaluation:** project context and reviewed note; score factual consistency, linkage to actual runs, unresolved questions and separation of proposed vs completed work.

### T25 — Titles and semantic yes/no classification · Routes · P2

- **LLM responsibility:** short task naming and binary semantic classification for UI/test helper use.
- **Prompts:** title asks for a concise 4–6 word scientific task title at [title route](/Users/kky/biomate-review/frontend/server/routes.ts:11707); [classify prompt](/Users/kky/biomate-review/frontend/server/routes.ts:15872) asks a supplied question about text with only yes/no output.
- **Process:** capped input → model → normalize short text/boolean → simple fallback when unavailable. These do not justify a large specialist model and may use small local models or deterministic formatting where appropriate.
- **Target/data/evaluation:** task relevance and binary correctness, with cheap latency budgets; keep semantic classifier outputs out of scientific gold labels unless independently verified.

## Secondary and non-runtime workloads

### T26 — Tool/resource recommendation and domain specialization · Secondary/conditional

[Tool recommender](/Users/kky/biomate-review/backend/lib/galaxy/ai/tool_recommender.py), [resource resolver](/Users/kky/biomate-review/backend/lib/galaxy/ai/resource_resolver.py), [domain specialist](/Users/kky/biomate-review/backend/lib/galaxy/ai/agents/domain_specialist.py), [workflow assembler](/Users/kky/biomate-review/backend/lib/galaxy/ai/agents/workflow_assembler.py), biological logic detection and enhanced domain routing contain further LLM-assisted analysis or recommendation. Their prompt expressions are in the appendix. Typically the process is structured request/context → model proposal → parse/validate against catalog → recommendation. Confirm activation before collecting a separate corpus; map them to T01/T05/T08/T14 where contracts match. Include actual retrieved knowledge and candidate constraints when they differ.

### T27 — Catalog enrichment, tool installation analysis and conversion · Offline/conditional

[Backend scripts](/Users/kky/biomate-review/backend/scripts) include scientific-context extraction, tool compatibility mapping, workflow conversion and documentation analysis; [tool_discovery.py](/Users/kky/biomate-review/backend/lib/galaxy/ai/tool_discovery.py) includes classification and extraction calls. These consume tool documentation/schema and produce metadata/code used later by retrieval or execution. Their output needs schema checks and tool-level verification before being indexed. Precompute and ship approved catalogs for an air-gapped installation, or explicitly support local maintenance inference. Do not confuse these with every live customer turn.

### T28 — Model evaluation/judging and training data generation · Offline

[Evaluation](/Users/kky/biomate-review/evaluation) contains external-model judges and prompt-driven harnesses. Regulatory generation scripts create synthetic SFT/DPO examples. These are part of the replacement project’s tooling, not user-facing BioMate tasks. Keep evaluator/training traffic inside the permitted boundary, version the judge/rubric and validate against human labels. The audit appendix includes selected evaluation prompts so cloud dependencies are not overlooked; it is not a complete inventory of every research/marketing script in the monorepo.

## Work BioMate does without an LLM

| Responsibility | Implementation/evidence | Keep deterministic or tool-based |
|---|---|---|
| Workflow execution, scheduling and state | Nextflow/Galaxy executors, containers, job monitors | Model proposes; executor performs and records the computation. |
| Scientific computation | Bioinformatics tools, Python/R libraries, docking/prediction pipelines | Train selection and interpretation, not imitation of computed values. |
| Typed parameter/rule validation | [paramRules.ts](/Users/kky/biomate-review/frontend/server/lib/paramRules.ts), schema/input gates | Enums, required inputs, user overrides and executable arguments remain enforced by code. |
| Workflow graph search | [chain_planner.py](/Users/kky/biomate-review/backend/lib/galaxy/ai/chain_planner.py) | BFS, graph edges and compatibility checks do not require LLM training. |
| Output parsing and templated reports | [output_analyzer.py](/Users/kky/biomate-review/backend/lib/galaxy/ai/output_analyzer.py), [finding_reporter.py](/Users/kky/biomate-review/backend/lib/galaxy/ai/finding_reporter.py), [methods_generator.py](/Users/kky/biomate-review/backend/lib/galaxy/ai/methods_generator.py) | These inspected paths parse/format results without a generation call; their names alone are not evidence of LLM use. |
| Regulatory arithmetic and structural checks | MRSD calculator/verifier, phase gates, table/consistency/structural validators | Validate assumptions and arithmetic in code; prose must reflect computed evidence. |
| Retrieval and embeddings | FTS/catalog matching, shared embedding service, local BGE option | Embeddings are a separate model/deployment task; rebuilding an index may be required when the encoder changes. |
| Authorization, storage and audit state | Auth middleware, repositories, execution policies | The model must not determine access rights or certify its own execution success. |

## Representative end-to-end training episodes

1. **“Run differential expression on these files.”** T04 context → T01 execution intent → T02 literal/file extraction → T05 workflow choice → T06 parameters + T07 input matching → validated execution → T20 grounded findings → T21 report. Train both component transitions and the full episode; a correct intent does not establish a successful analysis.
2. **“Which target is best supported for this disease?”** T01 research routing → T14 database/literature evidence or T15 claim evidence → T12 synthesis/tool use → cited answer. If data sources are unavailable on premise, supply an approved local corpus or state the limitation; do not label memorized unsourced answers as equivalent.
3. **“Why did this run fail, and fix it?”** actual failed-run state → T18 diagnosis → T19 candidate fix → application permission/validation → actual rerun → verified outputs → T20 explanation. A fabricated successful rerun is a critical error even if the explanation sounds correct.
4. **“Draft the nonclinical section from these studies.”** deterministic ingestion/calculation → T22 generation with regional evidence → structural/numeric validators + T23 semantic review → revision → rendered document. Train section dependencies and missing-evidence handling, not only isolated polished paragraphs.
5. **“Use the prior run’s output; change the threshold to 0.01.”** T04 memory/history → T01 follow-up → T10 modification → T12 history/output tools → T06 exact parameter binding → input gate → execution. Preserve full identifiers and the distinction between a user-proposed value and an already-applied change.

## Coverage completion before deployment

Instrument task IDs at the selected call boundaries, then exercise each enabled route with success, invalid input and local-service failure. Reconcile observed calls with the static inventory. Mark every unmatched candidate as active, optional, build-time, obsolete or unreachable with evidence. Export **rendered** message/tool/schema payloads and third-party prompt versions for the enabled subset. This closes the known static-audit limits and establishes the actual corpus and release scope.
