# Routing: the intent classifier is the single authority for workflow-vs-not

Date: 2026-11-10 · Branch `track/c-routing` · Track C (chat routing)

## 1. Problem

The founder asked two questions: "which LLM can't understand multilingual?" and "will it break next
time in a new case?" Dev logs from 2026-11-10 show where the failure came from. For `先做第一步`,
`第2-5步，并提供结果文件下载链接` and `你可以直接编程统计吗 不用工作流`, the intent classifier
(gemini-3.8-flash) returned `execution=direct_compute, needsWorkflowGeneration=false` on 3 of 3
turns. Code that ran after the classifier then changed `actions.needsWorkflowGeneration` back to
true. There were about 20 such rules, mostly English regexes, plus a pre-classifier short-circuit.
Each one replaced the LLM's decision with a phrase list. Any phrasing the list did not anticipate
went wrong, and Chinese follow-ups were a common case.

**Fix:** the classifier's decision is final. The knowledge each override carried now lives in two
places:
- classifier-prompt examples (`frontend/server/routing-examples.ts`);
- retrieval hints (key terms, preferred domains, subQuery) in `frontend/server/routing-authority.ts`.
  Hints steer *which* workflow the catalog search finds. They never change *whether* a workflow is
  generated.

Two gates can still change the decision, and neither is an intent decision:
- an explicit user prohibition;
- the BOIN dose-level prerequisite.

The prohibition gate now reads the classifier's new structured field `user_constraint`
(`no_workflow` | `no_launch` | null). The EN/ZH regex in `execution-intent-guard.ts` is kept only
as a secondary safety net.

## 2. Override inventory

Commit IDs are where each rule was introduced (`git log -S`). "Examples added" are one-line
classifier-prompt examples. Each states type · execution · needsWorkflowGeneration and includes at
least one boundary case. The ml_training group is only included when `ML_TRAINING_ROUTING=1`.

| # | Site (galaxy-assistant.ts @2faa9a9a) | Origin | Case it protected | Status | Where its knowledge went | Examples added (count, zh/en) |
|---|---|---|---|---|---|---|
| 1 | `parseActions` mustGenerateWorkflow (~8800) | aadd820910 (2026-07-02) | A no-workflow reply came back EMPTY from Gemini, leading to "having trouble…" | **Removed** | Root cause fixed: `requireNonEmptyResponse` makes an empty provider reply fail over to the next provider; `_generateWithGemini` retries an empty no-tool turn once. `execution=direct_compute` now forces nwg=false (the classifier is consistent with itself). | covered by direct_compute group |
| 2 | Direct-code overrides (5127): `_isDirectCodeExecutionQuery`, `isAdhocAnalysisOfAttachedData`, `isSimpleSequencePropertyRequest` | cdab019e1d (08-19), cfb903f4d5 (11-04), 11c5a500da (11-07) | Explicit run_code requests, ad-hoc analysis of attached data, and sequence properties must not get a card (a card disables run_code) | **Removed** (detectors deleted; the sequence detector is still used for its prompt hint) | Prompt "direct_compute" group; `reconcileExecutionMode` | 9 (3 zh / 6 en) |
| 3 | Inline-table + tool-name short-circuit in `analyzeIntent` (pre-classifier) | 801d52bf48 (06-26) | Pasted CSV + "DESeq2" was classified tool_search | **Removed** | Prompt example: tiny pasted table + DESeq2 → direct_compute | (in #2 group) |
| 4 | ml_training (5143) | 2d512aaf93 (07-26) | "train/fine-tune a model" was bucketed as tool_search | **Removed** | Prompt group (flag-gated) | 4 (2/2) |
| 5 | Target evidence (5158) | 5422fcf3c9 (07-19) | Target-evidence lookups were routed to research_question | **Removed** | Prompt group + research-agent suppression hint | 4 (2/2) |
| 6 | Trial feasibility (5175) | 5422fcf3c9 | Recruitment/power requests were routed to experiment_design | **Removed** | Prompt group | 4 (1/3) |
| 7 | Pathway enrichment (5193) | 5422fcf3c9 / 92e7c2b615 (BC-04) | Enrichment must get a clusterProfiler card, not run_code, and not differentialabundance | **Flip removed; hints kept** | Prompt group; `applyRetrievalHints` (clusterProfiler key terms, transcriptomics penalty, subQuery reset) | 4 (2/2) |
| 8 | GWAS→eQTL chain (5253) | 41d8b17fe0 (07-19) | Chain queries were routed to research | **Removed** | Prompt group + drug_discovery domain hint | 4 (1/3) |
| 9 | Multi-omics (5272) | 41d8b17fe0 | Multi-layer integration was routed to research | **Removed** | Prompt group + multi_omics domain hint | 4 (2/2) |
| 10 | Macrophage metabolic (5300) | 41d8b17fe0 | Macrophage scRNA states were routed to research | **Removed** | Prompt group + single_cell domain hint | 4 (2/2) |
| 11 | Canonical fixture (5338) | f32b141c00 (06-10) | "airway/pasilla/pbmc3k" was routed to chat_only | **Removed** (the fixture suppression in the clarification gate is kept; it is not a routing decision) | Prompt group | 4 (2/2) |
| 12 | Named AutoDock Vina (5349 + processSubIntent 7009) | a0e289bc78 (05-26) | ANDV step 4 must produce a Vina card | **Removed** | Prompt group | 4 (2/2) |
| 13 | Plan A epitope / Plan B codon / pocket (5362 + processSubIntent 7022) | a0e289bc78, d15f94ffaa | ANDV stepwise named cards | **Removed** (the detectors remain only to pick the empty-reply fallback text) | Prompt group | 5 (2/3) |
| 14 | `_applyNamedWorkflowOverridesToDecomposition` (4984) | b88e18bc87 (05-26) | Named ANDV workflow forced on all intents | **Removed** | Groups 7, 12, 13 | (in 7/12/13) |
| 15 | ADMET screening (5387 + processSubIntent 7040) | eba06595ff (07-21) | SMILES + ADMET was routed to research when the project context described the goal | **Flip removed; hint kept** | Prompt group (incl. the SMILES-only follow-up); `applyRetrievalHints` (subQuery = original text, drug_discovery domain) | 4 (2/2) |
| 16 | HPO+ENSG force-false (5421) | 1cbb616901 (04-17) | Causal-gene benchmark tasks must not get a pipeline | **Removed** | Prompt group (adds to the existing clinical_genomics rules) | 3 (1/2) |
| 17 | Paper-question guard (5470) | 9694a382d8 (07-02) | "Summarize this PDF" must not produce a workflow | **Removed** | Prompt group | 3 (1/2) |
| 18 | Data-attach guard (5492) | 0a1b80b736 (11-09) | "also add the other two files" produced a card | **Removed** | Prompt group | 3 (1/2) |
| 19 | Execution-prohibition guard (5439) | be5468d979 (09-11) | "interpret only / do not run" | **Kept as a gate** (explicit user control) | Reads `user_constraint` first, then the EN/ZH regex; `no_workflow` + direct_compute keeps run_code instead of switching to research | 3 (2/1) |
| 20 | BOIN prerequisite (5522) | cc585c191d (04-29) | BOIN design without dose levels | **Kept as a gate** (prerequisite, not intent) | Also detects via the classifier subQuery and `inlineParameters.dose*`, plus ZH dose patterns | existing table rows |
| — | `_maybeCollapseNamedWorkflowCardRequest` | b88e18bc87 | User explicitly asked to "show the … workflow card" | Kept (shapes the decomposition after an explicit card request) | — | — |
| — | `_detectCrossIntentAmbiguity` | — | Asks the user; flips nothing | Kept | — | — |
| — | `run_diagnostics` and `KNOWLEDGE QUESTION` short-circuits | — | Run-failure questions; eval-harness prefix | Kept (not workflow-vs-not) | — | — |

**Prompt size:** the examples block adds 10,087 chars (10,624 with ML_TRAINING_ROUTING=1). The
`user_constraint` field definition adds about 600 chars. Total is about +2.7k tokens per
classification.

## 3. Replay measurement (the real classifier)

- **Harness:** `scripts/routing_replay/run.ts`. It calls the production `analyzeIntent` prompt
  through OpenRouter `google/gemini-3.8-flash`, which is the deployed intent model. It then applies
  the post-classifier policy in the same order as `_generateResponse`.
- **Case set:** `scripts/routing_replay/cases.json` has 67 held-out cases.
  - 2–5 paraphrases per override, with zh/en mixed and boundary cases.
  - The founder's 3 Chinese prompts and their English equivalents, with the dataset block in an
    earlier turn.
- **Held-out check:** a vitest test asserts that no replay case reuses any prompt-example wording.
- **Degraded results:** a result where the classifier itself failed (network outage, keyword
  fallback) is excluded and re-run with `--only`.

| Group | Before (HEAD + overrides), 2 reps | After run 1, 2 reps | After run 2 (fresh), 1 rep |
|---|---|---|---|
| founder (3 zh + 3 en) | 12/12 | 12/12 | 6/6 |
| direct_code | 16/16 | 16/16 | 8/8 |
| ml_training | 8/8 | 8/8 | 4/4 |
| target_evidence | **4/8** (TE2 zh, TE3 missed) | 8/8 | 4/4 |
| trial_feasibility | **6/8** (TF1 missed) | 8/8 | 4/4 |
| pathway_enrichment | **4/8** (PE1 forced to direct_compute; PE4 knowledge question forced into a workflow) | 8/8 | 4/4 |
| gwas_chain | 6/6 | 6/6 | 3/3 |
| multi_omics | **5/6** (MO2 zh) | 6/6 | 3/3 |
| macrophage | 6/6 | 6/6 | 3/3 |
| canonical_fixture | 6/6 | 6/6 | 3/3 |
| named_docking | **4/6** (DK3 "how does Vina score?" forced into a workflow) | 6/6 | 3/3 |
| plan_ab_pocket | **8/10** (PA5 knowledge question forced into a workflow) | 10/10 | 5/5 |
| admet | 8/8 | 8/8 | 4/4 |
| hpo_ensg | 4/4 | 4/4 | 2/2 |
| execution_prohibition | 6/6 | 6/6 | 3/3 |
| paper_question | **4/6** (PQ3 "reproduce this paper" forced to no-exec) | 6/6 | 3/3 |
| data_attach | 6/6 | 6/6 | 3/3 |
| boin | 4/4 | 4/4 | 2/2 |
| **Total** | **117/134 (87%)** | **134/134** | **67/67** |

Before the change, the raw classifier output (after the old `parseActions`, before the overrides)
scored 95/134. The `mustGenerateWorkflow` guard turned every direct_compute answer, including all 12
founder turns, into "workflow". The other overrides then partly undid that.

Confusion matrix, rows = expected (primary label), columns = final:

| | workflow | direct_compute | no_exec |
|---|---|---|---|
| before: workflow | 53 | 8 | 9 |
| before: direct_compute | 2 | 24 | 0 |
| before: no_exec | 6 | 4 | 28 |
| after: workflow | 70 | 0 | 0 |
| after: direct_compute | 0 | 26 | 0 |
| after: no_exec | 0 | 0 | 38 |

Some cases accept more than one label, e.g. a power calculation with numbers may be a workflow or
direct_compute. Their misses were counted against the acceptable set.

**Parity:** every removed override reached parity or better after one prompt iteration. No case
needed escalation. The overrides themselves *caused* 10 of the 17 "before" misses: 6 knowledge
questions forced into workflows, PE1 forced to direct_compute, and PQ3 forced to no-exec.

## 4. Relevance floor (W2) — calibration

- `_classify_match` labels anything ≥12 as high_confidence. The current score scale puts junk hits
  at 18–41, so they were labelled high_confidence and could be attached. Examples: mmuphin and
  "Estimate Alpha Particle Radiotherapy Dosimetry" both declare `input_kinds ["tabular"]`, so
  input-kind compatibility alone cannot reject them.
- **Calibration method:** for each replay case, take the classifier's real subQuery, key_terms,
  domains and input_kinds (run 2). Search the canonical catalog
  (`UnifiedWorkflowSearch`, `galaxy_ai_tools.db`) with them. Results are in
  `scripts/routing_replay/out/calib_scores.jsonl`.
- **Dense term:** the dense bonus is ≤0.5 by design (`_WF_DENSE_BONUS_WEIGHT`), so local lexical
  scores ≈ production.
- **Results:**
  - Intended workflow for real workflow requests: top-1 = 51.4–147.6. The minimum was
    nf-core/scdownstream for a macrophage scRNA request.
  - Best catalog hit for requests no workflow serves (founder follow-ups, ad-hoc table stats,
    explicit "no workflow"): 18.6–40.7. Max = xeva for a dose/response correlation.
  - Synthetic EPAR-table queries: 23.6–29.8.
- **Floor = 45** (`BIOMATE_WORKFLOW_RELEVANCE_FLOOR`). It sits in the gap 40.7 → 51.4.
- **Rule** (`backend/lib/galaxy/ai/workflow_relevance.py`, wired after the iterative search in
  `generate_workflow_unified`):
  - attach only a hit with score ≥ floor that is not input-incompatible
    (`input_compatible(...) is False`);
  - if the top hit is incompatible but a lower one qualifies, promote the lower one;
  - otherwise return `success: false, error: no_relevant_workflow` with an honest message and the
    top-3 candidates.
- **Caveats:**
  - The margin is about 10 points on 67 cases.
  - Knowledge questions about a domain (DK3, PA5, TF4) do score high. They are excluded by the
    classifier, not by the floor.

## 5. Other fixes in this branch

- **W4 dataset UUID leak.** `stripDatasetReferenceParams`:
  - drops dataset-reference keys (`dataset_id`, `galaxy_dataset_id`, `s3_uri`, "Dataset Id", …)
    unless the chosen workflow declares them;
  - rebinds an upload-id value to that file's `s3_uri`, which the viewer already shows by file name;
  - is applied in `groundInlineParameters`, which every path uses, and to every pre-generation merge
    (single, Tier-1, multi-intent, sub-intent).

  Files are bound by `extractUploadedFileParams`.
- **Structural fabrication guard** (`execution-integrity.ts`):
  - When the classifier said `direct_compute`, run_code was offered and no run_code call ran, the
    model is re-prompted once to execute. This is wired into both the Claude loop and the Gemini
    loop; Gemini previously had no guard.
  - The prose regex (`presentsUnexecutedCode`) is now only a secondary signal.
  - Files the reply presents as produced must be this turn's run_code `$OUTPUT_DIR` artifacts, which
    `_toolRunCode` now records in `context.runCodeOutputFiles`. Any other claimed file gets an
    explicit "not produced" note in the user's language.
- **Empty-reply root cause:** `requireNonEmptyResponse` in the provider chain, and one Gemini retry
  for an empty no-tool turn.

## 6. Tests

- `frontend/server/routing-authority.test.ts`:
  - no flips on 18 former trigger phrases (EN/ZH, both directions), on both the hint layer and
    `_applyPostClassifierRouting`;
  - `parseIntentResult` honours `execution` and the run_code branch;
  - `user_constraint` gate and BOIN gate;
  - every example group has ≥3 examples mixing zh+en with consistent flags;
  - the held-out set does not reuse prompt wording.
- `frontend/server/execution-integrity.test.ts`: structural guard, unbacked-file claims, empty-reply
  failover, W4 stripping, and `groundInlineParameters` never emitting the upload UUID.
- `backend/tests/test_workflow_relevance_floor.py` (loaded by file path): floor and promotion
  behaviour, and the floor separating the recorded calibration set.
- Characterization test updated: the deleted detectors are removed; the router table snapshot is
  unchanged.
- Deleted `direct-code-execution-20261022.test.ts` and `adhoc-analysis-routing.test.ts`. They tested
  the deleted detectors, and the second depended on `evaluation/` data that is not present in sparse
  checkouts.

## 7. Residual risks / next steps

- The classifier is now load-bearing for every phrasing. Re-run the replay after any prompt or model
  change:
  `BIOMATE_DECOMP_OPENROUTER_KEY=… npx tsx ../scripts/routing_replay/run.ts --label X --reps 2`.
- 67 cases × 2 reps is small. Grow it from dev logs: every misroute becomes a held-out case, never a
  regex.
- The relevance floor is calibrated on lexical scores of 67 queries with a margin of about 10. Watch
  `no_relevant_workflow` rates on dev, and tune via env, not code.
- The text-guardrail card swap (Step 6c, `workflow_by_name`) is a separate path. It is not covered by
  the floor.
- Not verified live on dev. The CLAUDE.md dev loop is pending: no sync was done, per the track
  instructions.
