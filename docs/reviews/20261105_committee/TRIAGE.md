# Committee review triage — 2026-11-05

Packet: `docs/20261105_ROUTING_ORCHESTRATION_CATALOG_REVIEW_PACKET.md`; code given: `input_code_diffs.txt` (15 commits).
Reviewers (OpenRouter, same input, independent): Claude Opus 5.5, GPT-5.6 Terra, Gemini 4 Argon, Kimi K3, DeepSeek V4 Pro.
Raw outputs: `*.json` in this folder (Opus, Kimi, DeepSeek re-run at 48k max tokens; truncated first attempts kept as `*_truncated.json`).
Cost: $2.31 total.

**Rule applied:** no finding was acted on before it was checked against the code or data. Verdicts:
ADOPTED (verified, fixed), PARTIAL (part verified/fixed, part wrong or deferred), REJECTED (contradicted by code/data — evidence given),
DEFERRED (valid or plausible, needs design or measurement first).

Totals: ADOPTED 29, DEFERRED 13, PARTIAL 9, REJECTED 7 of 58.

## 1. What the review changed (commit `ffe84a8d3`)
- **Data bug on dev, confirmed and repaired:** the claim-audit cleaner removed phrases as raw substrings — "sam" was cut from "samtools" in
  `nf-core/bam_dedup_stats_samtools_umicollapse` and `…_umitools` annotations. Token-bounded cleaner + a guarded `repair` step (rows still
  holding exactly what v1 wrote); 2 rows repaired; the other 17 audited rows verified undamaged. (Opus F12, Gemini F2, Kimi F6)
- **Lost answers:** a DAG plan discarded the non-workflow parts of a request (interpretation, literature) already answered — now kept. (Kimi F1)
- **Dropped dependencies:** a combining step emitted before its branches lost its edges and was shown as parallel — intents are now numbered in
  dependency order; cycles are refused. (GPT F2, Gemini F1 second half)
- **Fabricated pre-execution text** kept in the final message by the unexecuted-code guard — removed. (Opus F17, GPT F4, Kimi F2, Gemini F7)
- Catalog tools: writes by row id; the Bioconductor exclusion and integrity checks encoded in the tools; sync refuses to upload a DB whose FTS
  index is inconsistent. Routing robustness: env parse, cache errors/WAL, POST lookup, branch-domain canonicalisation, refused-swap note.
  Orchestration: catalog-validated paths, no exception text, order-only wording, parallel naming.

## 2. Rejected findings — why
Five rejections rest on code the reviewers were not shown (call sites outside the diff, a later commit): Opus F5, F10, F13; DeepSeek F2, F5;
Kimi F10 (first half), F19; Gemini F1 (self-loop half). Each is answered with the file:line in the table. These are not reviewer errors so much as
packet gaps: the next packet should include call sites of changed functions.

## 3. Deferred — proposed next work (needs a decision or a measurement)
- **T-LLMKINDS** (Opus F1/F3/F11, Gemini F3/F5, Kimi F9): the user's data kind is regex-detected from text; it confuses mentions with possession,
  ignores negation, and is unknown for multi-intent branches. Proposal: the intent classifier (already an LLM, already emitting `facts` with
  category `data_type`) outputs the user's input kinds per intent from the closed vocabulary; the backend uses them instead of the regex, the regex
  only as fallback. Measure on the offline harness + a v2 dev set before switching.
- **T-REGIMES** (Opus F6, Gemini F4, Kimi F8, DeepSeek F3): vcf / peaks / gene_list are in neither regime, so "has a VCF → FASTQ-only pipeline"
  is not penalised. Offline A/B of treating them as processed, before any change.
- **T-EVALV2** (Opus F4, Kimi F3): by the pre-registered criteria the deployed arm is not better than baseline on loose/controls; the improvement
  rests on reading the cards, on n = 2 reps. A v2 set with criteria written as "input-compatible workflow that performs the task" (lists of
  acceptable workflows fixed in advance, not regexes), more queries, ≥ 3 reps.
- **T-DECOMP** (Kimi F4, Opus F18): re-run the decomposition model comparison with the fixed harness and include the deployed `gemini-3.5-flash`
  (≈ 4 models × 3 runs × $0.6 ≈ $7).

## 4. Correction to the packet
Packet §3.1 says the improvement holds "by substance". Stated precisely: on the pre-registered criteria, arm G vs before is target 10/12 vs 12/12,
strict 5/8 vs 4/8, controls 25/28 vs 27/28 (n = 2 reps). The substantive reading (MaxQuant / label-free protein tables now on table methods in all
runs since P/G; scdownstream and coMethDMR uncredited) is post-hoc and must be confirmed by T-EVALV2.

## 5. All findings
| Finding | Sev. | Claim (abridged) | Verdict | Evidence / action |
|---|---|---|---|---|
| claude-opus-5.5 F1 | major | The mismatch penalty is computed from the per-trial `query` text, not from the user's data. The backend runs several query trials and logs 'Selected t… | **PARTIAL** | Trials always include the full intent (`_build_intent_trials`: trial 1 = intent, trial 2 = intent + key_terms), so single-intent turns see the data words. Valid for multi-intent branches routed on `task_spec`, which may omit the data kind — deferred with T-LLMKINDS (§3). |
| claude-opus-5.5 F2 | major | Up to 4000 characters of the message are sent URL-encoded in a GET query string. Non-ASCII and punctuation expand roughly 3×. Gunicorn's default `limi… | **ADOPTED** | Request text moved to a POST body (`POST /api/ai_assistant/workflow_by_name`); Node uses POST. |
| claude-opus-5.5 F3 | major | The regexes detect any mention of a data kind, not only data the user has. Mentions of desired outputs, negations, or other people's data count. Examp… | **DEFERRED** | Valid limitation (mentions vs data the user has, negation). Fix belongs in the classifier, not more regex: T-LLMKINDS. |
| claude-opus-5.5 F4 | major | On the pre-registered criteria, the final arm G is worse than baseline: target 10/12 vs 12/12 and controls 25/28 vs 27/28. Strict proteomics moved 4/8… | **ADOPTED** | Correct: by the registered criteria arm G is not better than baseline on loose/controls. Packet §3.1 wording corrected in this triage; a v2 evaluation is planned (T-EVALV2). |
| claude-opus-5.5 F5 | major | The docstring says the function falls back to `_find_nf_file` when the executor cannot resolve the path. The code only falls back on an exception. If … | **REJECTED** | `_resolve_nextflow_path` never returns None — it raises FileNotFoundError (nextflow_executor.py:2017), caught → `_find_nf_file` fallback. |
| claude-opus-5.5 F6 | major | Several downstream kinds belong to neither regime: vcf, peaks, gene_list, annotation, tabular, structure, molecules. A user holding a VCF or gene list… | **DEFERRED** | Valid: vcf/peaks/gene_list are in neither regime. Needs an offline A/B before changing which kinds count as processed (T-REGIMES). |
| claude-opus-5.5 F7 | major | input_kinds were labelled (339ef76b9) from prompts containing ANNOTATION, before the audit removed the false claims. The audit then treats INPUT KINDS… | **PARTIAL** | Re-labelled the 19 audited rows from cleaned text: 4 changed, none changed raw/processed class (proteomicslfq: [fasta, raw_spectra] → [raw_spectra]). No effect on scoring; not applied. |
| claude-opus-5.5 F8 | minor | Acceptance rules described in the packet are not encoded in the code. (a) verify_domain_retag does not exclude moves into 'general'. (b) The audit's '… | **PARTIAL** | (a) wrong: the 'general' filter is in verify_domain_retag.py:22-23 (fcfffdaf4; reviewers saw an earlier diff). (b) adopted: Bioconductor exclusion now in `apply`. (c) adopted: writes by id. |
| claude-opus-5.5 F9 | major | The stale external-content FTS index was rebuilt, but its root cause is not identified. Possible causes include writes bypassing triggers, a rowid cha… | **PARTIAL** | Root cause still unknown (adopted guard instead): catalog tools and sync_to_dev.sh now refuse to write/upload a DB whose FTS fails integrity-check. Caveat accepted: earlier benchmarks ran on the stale index. |
| claude-opus-5.5 F10 | minor | The packet says Steps 6b/6c/6c-2 refuse incompatible targets. The diff only shows Step 6c and the shared regenerate helper gaining `message`. Whether … | **REJECTED** | Step 6b calls `_cardForNamedWorkflow(reselectedName, message, …)` (galaxy-assistant.ts:5349), which is guarded; the call site was outside the diff. |
| claude-opus-5.5 F11 | minor | A constant −25 is set against `abs(bm25)×1.5`, which scales with query length and with appended key_terms. The margin came from a single 17–24-point g… | **DEFERRED** | Accepted as a limitation (one measured gap). Superseded if T-LLMKINDS makes the data kind reliable enough for a filter or a learned weight. |
| claude-opus-5.5 F12 | minor | `str.replace` removes every occurrence of the phrase as a raw substring, including inside true phrases or longer tokens. A confirmed short phrase like… | **ADOPTED** | CONFIRMED DATA BUG: 'sam' was cut out of 'samtools' in 2 nf-core annotations on dev. Token-bounded `cleaned` + guarded `repair` step; 2 rows repaired. |
| claude-opus-5.5 F13 | minor | Routed paths are matched to intents by array index (`subIntentResults[k]`). If `subIntentResults` is filtered, reordered, or omits non-workflow intent… | **REJECTED** | `Promise.all` preserves order; `subIntentResults[k]` aligns with `decomposition.intents[k]`. |
| claude-opus-5.5 F14 | minor | The classifier's `domain` is not validated against CANONICAL_DOMAINS. The prompt lists 16 values while the registry has 14, so some hints may never ea… | **ADOPTED** | Prompt lists 16 branch domains, router accepts 14 canonical. `canonicalBranchDomain` maps aliases (variant_calling→genomics, pharmacology→drug_discovery, imaging→bioimaging, registry subdomains) and drops the rest; prompt unchanged (no untested prompt change). |
| claude-opus-5.5 F15 | minor | The cache is invalidated by the main DB file's mtime. In WAL mode, committed writes sit in the -wal file until a checkpoint, so updates to `input_kind… | **ADOPTED** | DB is in WAL mode (verified). Cache now keys on DB + -wal mtimes. |
| claude-opus-5.5 F16 | minor | The client-supplied `nextflow_path` is accepted verbatim into an executable plan without checking that it is a catalog workflow.… | **ADOPTED** | plan_dag uses a caller path only if it is an executable catalog workflow; otherwise resolves from the task. |
| claude-opus-5.5 F17 | minor | In streaming mode, the first reply ('Running analysis…' plus code, possibly with fabricated numbers) stays visible and persisted above the real result… | **ADOPTED** | Final message no longer prepends the pre-nudge text; the UI replaces the streamed preview with `data.response` (chat-interface.tsx:1112,1205). |
| claude-opus-5.5 F18 | minor | 'Keep Flash' was decided on 3.8 Flash while dev runs 3.5 Flash, so there is no measurement of the deployed model. The task_spec and domain prompt addi… | **PARTIAL** | True: the deployed model (gemini-3.5-flash) was never benchmarked; task_spec/domain shipped without a routing measurement. Re-benchmark proposed with cost (T-DECOMP). |
| deepseek-v4-pro F1 | major | The documented decision to apply the false-claim audit only to BioMate-authored annotations is not enforced by the tool; a future run of verify+apply … | **ADOPTED** | Bioconductor exclusion encoded in annotation_claim_audit.apply (UPSTREAM_AUTHORED_SOURCES). |
| deepseek-v4-pro F2 | major | The verifier emits SQL for every two-model-agreed change, including moves into `general`, despite the packet stating those were not applied; the exclu… | **REJECTED** | Filter exists: verify_domain_retag.py:22-23 (fcfffdaf4). |
| deepseek-v4-pro F3 | minor | The +3 'exactly the right input kind' branch is actually an any-overlap bonus; for workflows that accept multiple required primary inputs, a user with… | **DEFERRED** | Design choice; an any-overlap +3 can credit a workflow needing a second input the user lacks. Covered by T-REGIMES. |
| deepseek-v4-pro F4 | minor | The task-to-index map uses Python's built-in `id(t)` on task dicts instead of the task's explicit `id` field; if `build_dag_plan` ever passes copied/r… | **ADOPTED** | DAG task map now keyed by task id, not object identity. |
| deepseek-v4-pro F5 | minor | The classifier-driven `direct_compute` override does not exclude requests where the user asks for code itself, while the codebase already has `wantsCo… | **REJECTED** | The unexecuted-code guard already requires `!wantsCodeItself(message)` (galaxy-assistant.ts `_shouldNudgeUnexecutedCode`); the classifier's direct_compute only changes routing, not 'write code' requests' replies. |
| deepseek-v4-pro F6 | minor | `--canonical` without `--all-domains` still only audits `domain='general'`, which makes the flag easy to misuse and inconsistent with its closed-list … | **ADOPTED** | `--canonical` without `--all-domains` is now a CLI error. |
| deepseek-v4-pro F7 | minor | The annotation-audit row query assumes the `input_kinds` column already exists; if run on an older DB or before the input-kinds pass, it fails at SQL … | **ADOPTED** | Audit row query checks for the input_kinds column. |
| gemini-4-argon F1 | critical | Off-by-one error in `depends_on` filtering allows self-loops (`n === k + 1`) and silently drops valid dependencies if the LLM emits the fan-in integra… | **PARTIAL** | Self-loop claim wrong: filter keeps `n <= k` (1-based n, 0-based k) → excludes self and later steps. Second half right (fan-in emitted first lost its edges): adopted, intents now numbered in topological order; cycles refused. |
| gemini-4-argon F2 | major | `cleaned()` uses unanchored `str.replace(ph, ' ')` which can corrupt substrings inside longer words or leave dangling punctuation/conjunctions, and `a… | **PARTIAL** | Substring removal: adopted (see Opus F12). FTS after apply: the triggers maintain it once consistent; apply now refuses an inconsistent index. |
| gemini-4-argon F3 | major | Query regexes in `_detect_query_data_types` do not distinguish between data the user *has* vs. output they *want* or negative mentions, and `_kinds_mi… | **DEFERRED** | Same as Opus F3 (T-LLMKINDS). |
| gemini-4-argon F4 | major | Eight of the 22 `INPUT_KINDS` (`vcf`, `peaks`, `gene_list`, `fasta`, `annotation`, `structure`, `molecules`, `tabular`) are in neither `_RAW_KINDS` no… | **DEFERRED** | Same as Opus F6 (T-REGIMES). |
| gemini-4-argon F5 | major | In Step 6c and `_rebuildCardForNamedWorkflow`, `message` (the raw user message) is passed to `_lookupWorkflowByName` for `input_compatible`, whereas i… | **PARTIAL** | True for multi-intent: the full message can contain both regimes → guard returns None (unknown) → fail-open, no wrong swap. Better per-branch data kinds: T-LLMKINDS. |
| gemini-4-argon F6 | major | `hasComputableData` matches any prose message containing 3 lines with two commas per line, which can falsely flip `needsWorkflowGeneration = false` wh… | **DEFERRED** | Regex heuristics for computable data; real but low impact and untested to change. Logged for the ad-hoc-compute workstream. |
| gemini-4-argon F7 | minor | When the streaming loop triggers `_shouldNudgeUnexecutedCode(rawResponse)`, the unexecuted code block has already been streamed to the client via `onR… | **ADOPTED** | Same fix as Opus F17. |
| gemini-4-argon F8 | minor | Both `input_kinds_classifier.py` and `domain_reclassifier.py` key and `UPDATE` workflows by `name` rather than `id`, overwriting or conflating rows th… | **ADOPTED** | Writes by id in all three catalog tools (27 duplicated names; copies of the same tool, no observed harm). |
| gemini-4-argon F9 | minor | When `orModel` (`openrouter:...`) is configured and fails, `analyzeIntent` falls back to `this.gemini` (Flash), and if that also fails or fails JSON p… | **DEFERRED** | True: up to 3 sequential LLM calls on a classifier failure. Latency budget not addressed now. |
| kimi-k3 F1 | major | When a DAG plan is assembled, the results of all non-workflow sub-intents (interpretation, literature, benchmark) that were already computed in Steps … | **ADOPTED** | CONFIRMED: non-workflow sub-intent answers were discarded when a DAG plan returned; now appended. |
| kimi-k3 F2 | major | The guard keeps the pre-nudge reply text — which may contain fabricated results stated before any code ran — in the final persisted and displayed mess… | **ADOPTED** | Same fix as Opus F17. |
| kimi-k3 F3 | major | By the packet's own pre-registered criteria the cumulative change is neutral-to-negative, and the improvement story is post-hoc. The deployed arm G is… | **ADOPTED** | Same as Opus F4. |
| kimi-k3 F4 | major | The 12-model comparison that underpins 'Decision: keep Flash' was measured with the defective harness (empty curated-chain list); only the prompt A/B … | **ADOPTED** | Correct: the 12-model comparison predates the harness fix. Re-run with real chain names + the deployed 3.5 Flash proposed (T-DECOMP). |
| kimi-k3 F5 | major | The FTS index was corrupt ('database disk image is malformed'; MATCH 'dep': 2 docs instead of 8) for an unknown period. All historical per-query routi… | **PARTIAL** | Same as Opus F9. |
| kimi-k3 F6 | minor | cleaned() removes phrases with plain str.replace (all occurrences, no word boundaries), so a short confirmed phrase can corrupt adjacent text (e.g. re… | **ADOPTED** | Token-bounded cleaner; writes by id with executable filter in kinds; repair. |
| kimi-k3 F7 | minor | A transient sqlite error is cached as an empty kinds map keyed to the current mtime, so all searches silently lose the input-kind signal until the DB … | **ADOPTED** | Load errors are no longer cached. |
| kimi-k3 F8 | minor | The mismatch penalty only covers the raw↔processed axis. The 'other' kinds (vcf, peaks, gene_list, fasta, annotation, structure, molecules, tabular) a… | **DEFERRED** | Same as Opus F6 (T-REGIMES). |
| kimi-k3 F9 | minor | Any query that mentions both regimes — including negations — disables the penalty entirely, because both penalty branches require the user to be in ex… | **DEFERRED** | Same as Opus F3 (T-LLMKINDS). |
| kimi-k3 F10 | minor | The packet says 'moves into general not applied', but the shown script has no such filter — cand excludes only same-domain and sub-0.8-confidence prop… | **REJECTED** | Filter exists (fcfffdaf4). KeyError on missing rows: adopted (rows looked up by id/name, missing → never edited). |
| kimi-k3 F11 | minor | The pipeline-vocabulary veto matches ordinary English words, so the ad-hoc path is silently disabled for benign requests: '\bstar\b' ('the star datase… | **DEFERRED** | PIPELINE_REQUEST_RE ordinary-word matches; fails safe to the old behaviour. Logged. |
| kimi-k3 F12 | minor | When 6c refuses the swap, the card is kept but the reply text still recommends the wrong workflow — the user sees 'use nf-core/proteomicslfq for your … | **ADOPTED** | Refused 6c swap adds a note to the reply naming the card actually used. |
| kimi-k3 F13 | minor | Up to 4000 characters of the user's message are placed in a GET URL query parameter. This leaks request content into access logs, and percent-encoded … | **ADOPTED** | Same as Opus F2. |
| kimi-k3 F14 | minor | (a) _INPUT_KIND_MISMATCH_PENALTY is parsed with float() at module import — a malformed BIOMATE_INPUT_KIND_MISMATCH_PENALTY value raises ValueError at … | **ADOPTED** | (a) malformed env no longer crashes import; (b) warning when the openrouter key is missing. |
| kimi-k3 F15 | minor | Routing tests open the real local galaxy_ai_tools.db and _migrate_schema may ALTER it (adds columns). The local DB is the source of the dev sync and i… | **DEFERRED** | True (observed: tests ALTER the local DB). Mitigation today: md5 check before sync; making tests use a copy is a test-infra change. |
| kimi-k3 F16 | minor | In an order_only plan (no typed handoff), the per-step line still says 'uses the results of step N' even though nothing is wired; only the trailing no… | **ADOPTED** | Order-only plans now say 'runs after step N'. |
| kimi-k3 F17 | minor | For pure-parallel plans (no fan-in) the plan is named after the last branch's task, which is arbitrary and misleading ('call variants on WGS and, sepa… | **ADOPTED** | Purely parallel plans are named 'N parallel analyses'. |
| kimi-k3 F18 | minor | (a) The endpoint returns internal exception text to clients (`reason: f"error: {exc}"`). (b) A caller-supplied nextflow_path bypasses resolution entir… | **ADOPTED** | (a) no exception text in plan_dag responses; (b) caller paths validated against the catalog. |
| kimi-k3 F19 | minor | The packet claims 'Steps 6b/6c/6c-2 refuse an incompatible target', but the diffs show the guard only for 6c and for _swapToNamedWorkflow (which appea… | **REJECTED** | Same as Opus F10: 6b is guarded. |
| gpt-5.6-terra F1 | major | Catalog edits are keyed by workflow name rather than a stable row ID, so duplicate workflow names cannot be independently classified or safely updated… | **ADOPTED** | Writes by id. |
| gpt-5.6-terra F2 | major | Malformed or forward dependency edges are silently removed rather than rejected, which can turn a requested dependent/fan-in analysis into independent… | **ADOPTED** | Topological numbering; cycles refused instead of silently dropped. |
| gpt-5.6-terra F3 | major | The new DAG API trusts a client-supplied `nextflow_path` as if it were the result of catalog routing, bypassing backend workflow resolution and valida… | **ADOPTED** | Same as Opus F16. |
| gpt-5.6-terra F4 | major | The guard detects an unexecuted code answer but deliberately preserves it in the final response, so fabricated statements or invented numerical conclu… | **ADOPTED** | Same as Opus F17. |
| gpt-5.6-terra F5 | major | The fallback creates and offers a runnable DAG even when no workflow outputs are connected to dependent workflow inputs. Ordering alone does not make … | **DEFERRED** | Order-only plans already tell the user to select the results as inputs; executing one without wiring is the executor's behaviour — not changed. |
