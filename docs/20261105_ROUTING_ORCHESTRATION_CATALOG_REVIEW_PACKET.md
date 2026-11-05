# Review packet — chat routing, orchestration and workflow-catalog work (2026-11-03 → 2026-11-05)

Branch `cursor/tutorial-live-recording-and-report-editing-4ea7`, PR #295 → `integration/next-phase`. Deployed to dev
(https://dev-public.biomate.ai) at `ddd8dcd7` (code) with workflow DB MD5 `8807d7e1…`.
Running log of the same work, with every intermediate number: `docs/20261103_ALL_LLM_AGENTIC_UNIFICATION_AND_COLDSTART.md`
§5–§13.4. This packet is the self-contained version for reviewers and testers.

---

## 0. For reviewers — what we ask and how

You are reviewing work done by one engineer (an AI agent) over three days. It has not been reviewed. Assume it
contains mistakes: logic errors, unjustified design choices, evaluation flaws, over-claimed results, missed side
effects. We want them found.

For each issue, give: **severity** (critical / major / minor), **location** (file and function, or document
section), **the claim** (what is wrong), **evidence** (quote the code or number you rely on), **suggested fix**,
and **your confidence** (high / medium / low). Say "uncertain" rather than guess — a confident wrong finding costs
more than a missing one. You see a description and the diffs, not the running system: where a finding depends on
code or data you were not shown, say so. Also tell us what is **right** and should not be changed.

The questions we most want answered are in §6.

---

## 1. System primer (enough to judge the changes)

BioMate is a chat front end over a workflow catalog executed on AWS Batch.

1. **Node chat server** (`frontend/server/galaxy-assistant.ts`, ~9k lines). Each user turn:
   - `analyzeIntent` — an LLM classifier (dev: `gemini-3.5-flash`; production prompt ≈80k chars) returns one or more
     intents with `type`, `execution` (pipeline / direct_compute), `task_spec`, `domain`, `dependsOn`, `key_terms`,
     `preferred_domains`, `chain_hint`.
   - Single intent → `generateResponse`; several → `processMultiIntent` (parallel, or `processSequentialPipeline`
     when sequential; fork/join → `_tryDagPlan`, §2.C).
   - The backend returns a workflow **card**; the response LLM writes the reply; then **card-consistency steps**
     run: 6b (LLM re-selects among the search candidates), 6c (reply names an `nf-core/…` workflow ≠ card → swap),
     6c-2 (same for any catalog workflow, candidates only), 6d (the user named a pipeline explicitly).
2. **Galaxy backend (Python)**: `ai_assistant.generate_workflow_unified` → fast paths → `UnifiedWorkflowSearch.search`
   (iterated over several query "trials") → `_llm_verify_routing` (close calls) → card.
3. **Workflow search** (`backend/lib/galaxy/ai/unified_workflow_search.py`): SQLite FTS5 candidates (BM25 over name,
   description, annotation, annotation_v2, tags, domain, tools), re-ranked by `_calculate_score`. Score terms:
   `abs(bm25) × 1.5` (dominant, see §2.F), keyword weights, phrase match, name overlap / exact-name bonuses,
   source priority (nf-core 6.7, Bioconductor 5.0), pipeline-intent ±8/−5, **domain ±4** (only when the workflow's
   tag is one of the router's `preferred_domains`, which come from `domain_registry.CANONICAL_DOMAINS`, 14 values),
   **input-type term** (§2.F), tags, execution-quality bonus ±2; plus Pass-0 LLM rank bonus ≤ +3 and dense (BGE)
   bonus ≤ +0.5.
4. **Workflow DB** `backend/database/galaxy_ai_tools.db` (~325 MB, not in git; canonical copy on dev; 4,223 rows,
   4,168 executable). Synced by `scripts/sync_to_dev.sh` (S3 presigned transfer, dev backup first, embedding
   re-encode, Galaxy restart). **The catalog is not version-controlled** — per-row edits leave no history.
5. **Executor** (`nextflow_executor.py`): resolves a DB path to a `.nf` file, real downloaded nf-core pipeline first
   (`nf-core-workflows/<name>/main.nf`), display stub (`biomni_workflows/nfcore/<name>/main.nf`, params only) last.

---

## 2. Change inventory

Each item: problem → evidence → change → tests → measured effect → known limits. Commit hashes are on the branch.

### A. Ad-hoc analysis of the user's own data, uploads, keys (Nov 3–4; log §5–§8)
- **Problem:** "compute X on my attached table" was forced into a workflow card or answered without running code;
  uploads silently skipped Galaxy; the per-user Galaxy key was revoked on Galaxy restarts and never recovered.
- **Changes:** classifier `execution` mode (`direct_compute`) + an agent-loop guard that nudges once when the model
  shows code without running it (`8ec3fbb1e`, `cfb903f4d`); `run_code` stages the turn's attachments, shows their
  first lines, replays Python cells within a reply, auto-imports `np/pd/plt/sns` (`686a38fba`, `1644f4eec`,
  `1b9f74f81`, `11869f75f`, `97fdd300a`, `7a1bbf7e5`); Galaxy upload restored (`dd82da160`, `1bd0155f7`); key
  recovery on 401/403 incl. uploads (`9503abf5e`, `ed39c9c46`, `df4ff2ec8`); chat `userId` was `Number(uuid)` = NaN,
  silently disabling per-user features (`47dbececa`).
- **Tests:** `run-code-attached-inputs`, `code-runner-alias-imports`, `direct-compute-routing`,
  `galaxy-key-recovery` (vitest); `scripts/verify_galaxy_key_recovery.sh` (revokes the fixture key via Galaxy's
  admin API, checks recovery incl. upload) — PASS on dev.

### B. Research answers and run-failure answers (Nov 4; log §11)
- Literature agent marks whether its papers answer the question (`EVIDENCE: addresses|insufficient`); an off-topic
  bibliography is no longer forced onto non-literature questions (`87ce3ad79`). Run-failure questions are answered
  from the run's recorded error (`9c1596a6c`). Reply language follows the user (`47dbececa`).

### C. Orchestration: fork/join → one DAG plan (Nov 4; log §10, §12)
- **Problem (external user):** "bulk RNA-seq + lysate + secretome proteomics, then integrate" became separate cards;
  the dependency structure was dropped. A DAG builder existed but had no live caller.
- **Change:** `POST /api/ai_assistant/plan_dag` → `decomposed_dag.plan_dag_from_tasks`; Node `_tryDagPlan` calls it
  after per-intent routing, passing each branch's routed workflow and edges (`5b72d8d7d`, `9e7af9cdf`). The classifier
  writes a `task_spec` and `domain` per branch (`2b5d6cda7`); order-only fan-in when output→input types do not match
  (reported as `unwired_dependencies`). Classifier failure → one LLM fallback chain before the keyword heuristic,
  marked `degraded` (`7c3e7256c`, `d222c1b83`).
- **Tests:** `dag-plan-routing.test.ts`, `decompose-openrouter.test.ts`, `backend/tests/test_plan_dag_from_tasks.py`.
  Dev: bulk+proteomics → one 4-step DAG card; two independent analyses → 2-step parallel; sequential unchanged.

### D. Decomposition model and prompt (Nov 4–5; log §12.2–12.3)
- Held-out set: 24 workflow-level rows of `evaluation/datasets/decomposition_real` (23 after excluding
  `decreal_sequential_66`, whose query is the catalog text "Retired workflow. No longer functional…"). Real
  `analyzeIntent` via OpenRouter; Claude Sonnet 5.5 judge aligns predicted ↔ gold nodes; node/edge F1 + structure.
- 12 models, then 3-run stability: GLM-5.2 0.401±0.037, Kimi K3 0.406±0.028, Gemini 3.8 Flash 0.327±0.009 (paired
  Δ GLM +0.074 [−0.026, +0.194]). **Decision:** keep Flash. **Caveat found later:** dev actually runs
  `gemini-3.5-flash` (`BIOMATE_INTENT_MODEL`), not 3.8 — the benchmark did not measure the deployed model.
- Harness defect fixed: the classifier had been given an empty curated-chain list (production passes 64 names).
  Re-measured with names: production prompt 0.355±0.009 vs "split per stage" prompt v2 0.352±0.005, Δ −0.003
  [−0.034, +0.029] → **v2 not shipped**.

### E. Single-intent `chain_hint` — added, then reverted (Nov 5; log §13)
- Added (`eee894a7f`): when the classifier returns ONE intent with `chain_hint`, build the curated chain.
- Dev arm R showed it replacing correct single pipelines (`nf-core/mag`, `nf-core/methylarray`) with chains in 4/4
  runs; one intent means the classifier judged a single workflow sufficient. **Reverted** (`577ea27d8`). Same commit:
  curated-chain cards had reached the client **unnamed** (TIER 2 set `name`; `routes.ts` read `chain_display_name`
  and mapped string `chain_steps` as objects) — fixed.

### F. Workflow-catalog metadata and scoring (Nov 5; log §13–§13.4) — the main work to review
Trigger: processed protein tables (e.g. MaxQuant `proteinGroups.txt`) routed to `nf-core/proteomicslfq`, a pipeline
that starts from raw spectra (OpenMS, mzML).

1. **Domain re-tag** (`a19a3c0f0`, `fcfffdaf4`): LLM re-classifies each executable workflow's domain. Closed list per
   row = the 14 `CANONICAL_DOMAINS` + `general` + the row's current tag (a first pass over all 42 tags in use was
   discarded: it moved rows into routing-only tags that never receive the domain match). Gemini 3.8 Flash proposed
   1,164 changes; moves into `general` not applied; Claude Sonnet 5.5 re-classified each remaining ≥0.8-confidence
   change independently: **938 / 1,056 agreed → applied** as `UPDATE … WHERE name=? AND domain=<old>`.
2. **Stale FTS index**: `workflows_fts` (external-content FTS5) failed `integrity-check`; the `workflows_au` trigger
   errored ("database disk image is malformed") on the first UPDATE (partial write restored from backup). Fixed with
   `INSERT INTO workflows_fts(workflows_fts) VALUES('rebuild')` before the updates. `MATCH 'dep'`: 2 docs → 8.
3. **`input_kinds`** (`339ef76b9`): new column, closed vocabulary (raw: fastq, bam, raw_spectra, idat, bcl,
   nanopore_signal, raw_images; processed: counts_matrix, h5ad, cellranger_output, protein_table, peptide_table,
   metabolite_table, beta_values; other: vcf, peaks, gene_list, fasta, annotation, structure, molecules, tabular).
   LLM-labelled by `chain_composer/input_kinds_classifier.py` (Flash; 4,167/4,168; Sonnet agreed on the raw-vs-
   processed class for 144/150 random rows). Read only by score step 8a; `input_types` (free-form, used by chain
   wiring / composer) untouched. Query side: regex detection of the user's data kind (`_detect_query_data_types`,
   extended for proteomics tables/spectra, IDAT, beta values, metabolite tables).
4. **FTS dominance found; normalisation rejected** (`86b0c8951`): for the MaxQuant request the FTS term was 62 of
   proteomicslfq's 74 points. Bounding it fixed the target rows but cost −0.15 routing / −0.18 bioc offline → not
   shipped.
5. **False-claim audit** (`7aee147d2`, `ec1784045`): root cause of the lexical lead — a 2026-07-19 per-query fix
   (`docs/20260719_ROUTING_BENCHMARK_R9_197_FIXES.md`, benchmark row prot_004) appended "MaxQuant output processing
   proteinGroups isobaric labeling TMT iTRAQ" to proteomicslfq's `annotation`. Audit is removal-only: Flash lists
   VERBATIM annotation phrases claiming something the workflow does not do; Sonnet confirms each, judging against the
   real tool because our descriptions are incomplete (pilot: it correctly kept "RSEM" for nf-core/rnaseq and "UMI
   consensus calling" for sarek). 2,628 rows → 98 with proposals → 30 confirmed. **Applied only to BioMate-authored
   annotations (19 rows)**: on Bioconductor rows the annotation is the upstream package description and the spot
   check found wrong confirmations (e.g. DSS's own DML/DMR sentence). Verified against real nf-core sources on dev:
   methylseq (no DMR), methylarray (no epigenetic clock).
6. **Input-kind mismatch made disqualifying** (`76ac575c2`): production adds the intent model's `key_terms` to the
   FTS query; the term `LFQ` (truthfully in proteomicslfq's description) lifted it from 82.6 to 106.6. The step-8a
   penalty for "user data in one regime, workflow accepts only the other" raised **4 → 25**
   (`_INPUT_KIND_MISMATCH_PENALTY`). A penalty, not a filter, because the kind labels carry ~4% disagreement.
7. **Executability check uses the executor's resolver** (`f008ecc19`): routing judged the display stub (no
   `workflow {}`), so every nf-core pipeline was "non-executable" while the executor runs the real copy (128/131
   catalog nf-core entries have one on dev).
8. **Card-swap guard** (`ddd8dcd7c`): after 7, Galaxy chose `dep` (verified) but Node Step 6c moved the card to
   proteomicslfq because the chat reply recommended it (wrongly) "for MaxQuant proteinGroups.txt"; 6c followed the
   first `nf-core/` name in the reply, unconstrained. Now one predicate `_kinds_mismatch` serves the score and
   `workflow_by_name?query=` → `input_compatible`; Steps 6b/6c/6c-2 refuse an incompatible target; 6c follows only
   search candidates (as 6c-2 already did).

### G. Deploy tooling (Nov 4; log §8–§9)
- `sync_to_dev.sh`: restores the 230 real nf-core pipelines + nf-core library into the Galaxy container on every sync
  (they were missing: 0 of 137 real pipelines present); never replaces dev's live `universe.sqlite` without opt-in;
  kills orphan gunicorn outside supervisord; an unreachable host is "UNVERIFIED", not a rollback trigger.

---

## 3. Measured results

### 3.1 Dev routing A/B (`evaluation/routing_eval/domain_retag/`, 20 queries × 2 reps)
6 target queries (4 processed-table proteomics, 2 methylation) + 14 controls across domains. Criteria (regex on the
card name, `score.py`) fixed before the after-arms; the **strict** proteomics criterion (card must take processed
tables) was added after the before-arm, before any after-arm. Every arm records container + gunicorn start times
before/after; a restart mid-run invalidates it.

| Arm (cumulative) | target loose | strict proteomics | controls |
|---|---|---|---|
| before | 12/12 | 4/8 | 27/28 |
| R: FTS rebuild (+ single-intent chain hook, reverted) | 10/12 | 4/8 | 25/28 |
| RT: + domain re-tag, hook removed | 12/12 | 4/8 | 27/28 |
| C: + false-claim audit (6 client-side http −1 rows re-run) | 12/12 | 4/8 | 28/28 |
| P: + mismatch penalty 25 | 12/12 | 4/8 | 25/28 |
| E: + executor-resolver executability | 11/12 | 4/8 | 26/28 |
| G: + card-swap guard (current) | 10/12 | 5/8 | 25/28 |

Substance vs the pre-registered regexes (scores kept as registered): from P on, all processed-table proteomics runs
land on table methods except E rep 1 (fixed by G); the strict regex is anchored (`^deqms$`) and does not credit
`deqms_maxquant_lfq`; the control regexes do not credit `nf-core/scdownstream` (correct for Cell Ranger output) or
`coMethDMR`. Remaining real misses: row 4 (MWAS on EPIC **beta values**, continuous phenotype) — G rep 1 asked for
data without a card, G rep 2 → a CYP2C19-specific MWAS workflow (input-compatible, over-specific); row 19 shotgun
"taxonomic profiling and genome binning" → nf-core/taxprofiler once (no binning).

### 3.2 Offline search-only (`scripts/routing_eval/search_offline_eval.py`, local DB = dev DB, no Pass-0 / dense / key_terms)
| | cross_domain_routing (200) | bioc_method_selection (24) | retag loose (20) | strict (4) |
|---|---|---|---|---|
| input_kinds off | 0.877 | 0.475 | 0.85 | 1/4 |
| input_kinds on | 0.882 | 0.500 | 0.85 | 1/4 |
| FTS normalised (rejected) | 0.735 | 0.325 | 0.80 | 3/4 |
| + claim audit | 0.873 | 0.500 | 0.85 | 2/4 |
| + mismatch 25 | 0.873 | 0.500 | 0.75 | 2/4 |
The −0.009 after the audit is two rows whose gold depends on the removed false claims (epi_011: DMR → methylseq;
epi_012: epigenetic clock → methylarray). That set feeds the RealBio manuscript and was not edited. The 0.85 → 0.75
"drop" for mismatch 25 is two rows moving to the input-compatible workflow (beta values → coMethDMR; Cell Ranger
output → scdownstream) that the loose regex does not credit.

---

## 4. Test manual

All commands from the repo root unless noted. Nothing below runs workflows on Batch.

### 4.1 Unit tests (≈1 min)
```
cd frontend && npx tsc --noEmit -p . && npx vitest run            # expect 2181 passed, 42 skipped
cd backend && PYTHONPATH=lib python3 -m pytest tests/test_input_kinds_scoring.py \
  tests/test_annotation_claim_audit.py tests/test_executability_uses_executor_resolver.py \
  tests/test_named_workflow_routing.py tests/test_nextflow_routing_runnable.py tests/test_plan_dag_from_tasks.py -q
python3.9 -m py_compile backend/lib/galaxy/ai/unified_workflow_search.py backend/lib/galaxy/ai/ai_assistant.py \
  backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py                # Galaxy runs Python 3.9
```
Note: some routing tests open the real local DB and `_migrate_schema` may ALTER it (adds missing columns). Check
`md5 -q backend/database/galaxy_ai_tools.db` before a sync.

### 4.2 Offline search-only A/B (≈3 min, free)
```
SEARCH_DB=<candidate copy of galaxy_ai_tools.db> python3 scripts/routing_eval/search_offline_eval.py out.json
```
Compare `summary` and per-row `pred` against `evaluation/routing_eval/domain_retag/offline_kinds_on.json`.
`BIOMATE_INPUT_KIND_MISMATCH_PENALTY=<n>` overrides the penalty for an A/B. Limits: no Pass-0, dense, key_terms,
`_llm_verify_routing` or Node card steps — it measures the scorer only.

### 4.3 Dev routing A/B (≈20 min; chat LLM calls only)
```
scripts/routing_eval/route_eval.py evaluation/routing_eval/domain_retag/payloads.json <out.jsonl> 3 "" 2
python3 evaluation/routing_eval/domain_retag/score.py <baseline.jsonl> <out.jsonl>
```
Fixture password from `~/.config/biomate/e2e_fixture_password` (never committed). Record before/after
`docker inspect … StartedAt` for `biomate-dev-frontend`, `biomate-galaxy-dev` and the gunicorn start time; any change
→ the run is invalid (other sessions sync from the same worktree). Rows with `http -1` after 0 s never reached the
server — re-run them and mark `rerun_reason`. Diagnose a changed row from dev logs: Galaxy `/app/galaxy.log`
("Selected trial … best=", "_llm_verify_routing"), Node `docker logs biomate-dev-frontend` ("Step 6b/6c/6c-2").

### 4.4 Decomposition benchmark (≈$0.6 per model-run)
```
cd frontend && DECOMP_CHAIN_NAMES_FILE=<64 names json> npx tsx ../scripts/routing_eval/decomp_model_bench.ts out.jsonl google/gemini-3.8-flash
python3 scripts/routing_eval/decomp_judge.py out.jsonl judged.jsonl
```
Three runs minimum; compare with paired bootstrap on row means. Rows without real usage are failures (the classifier
silently falls back to a heuristic on provider errors).

### 4.5 Catalog passes (LLM, ≈$3–6 each; never on the live file)
```
cd backend
PYTHONPATH=lib python3 -m galaxy.ai.chain_composer.domain_reclassifier --all-domains --canonical --openrouter-model google/gemini-3.8-flash --workers 16 --output p.jsonl
python3 ../scripts/routing_eval/verify_domain_retag.py p.jsonl v.jsonl updates.sql
PYTHONPATH=lib python3 -m galaxy.ai.chain_composer.input_kinds_classifier --workers 16 --output k.jsonl [--apply <db>]
PYTHONPATH=lib python3 -m galaxy.ai.chain_composer.annotation_claim_audit propose|verify|apply …
```
Before any write: back up the DB, run `INSERT INTO workflows_fts(workflows_fts, rank) VALUES('integrity-check', 1)`;
after: integrity-check + `pragma quick_check`, then the offline A/B (4.2) before syncing.

### 4.6 Deploy
Commit → push → `scripts/sync_to_dev.sh` (pre-sync: tsc + vitest + py3.9 compile). A DB change triggers a ~8-min
embedding re-encode and a Galaxy restart. Verify with `md5sum /opt/biomate/galaxy_db/galaxy_ai_tools.db` on dev and a
grep for the new code inside the containers, then 4.3.

---

## 5. Known limitations and evaluation caveats (stated before review)
1. **Small dev A/B** (20 queries × 2 reps, LLM-stochastic): single-row flips are within noise; the regexes are
   flawed (§3.1). A v2 query set with corrected criteria should be built before reuse.
2. **Offline harness ≠ production** (no Pass-0 / dense / key_terms / verify / Node steps). The MaxQuant row passed
   offline long before it passed on dev.
3. **The penalty value 25** was chosen from one measured lexical gap (17–24 points); it is a constant, not learned.
4. **Query-side data-kind detection is regex** over the user's text; misses unusual phrasings; can misfire on
   mentions of data the user does not have.
5. **input_kinds labels** are LLM-produced (≈4% raw/processed disagreement between models); duplicate workflow names
   share one label.
6. **Audit scope**: Bioconductor annotations excluded; 3 rows failed the audit; only `annotation` audited, not
   `description` / `annotation_v2`; the number of earlier per-row catalog patches is unknown.
7. **Decomposition benchmark measured Gemini 3.8 Flash**; dev runs 3.5 Flash.
8. **cross_domain_routing gold errors** (epi_011, epi_012) reported, not fixed (RealBio-owned).
9. **Executability**: 3 stub-only nf-core entries; the webapps copy of the check does not read files.
10. **Concurrency**: another session commits and syncs from the same worktree; three dev arms needed re-runs.

## 6. Questions for the committee
1. Is the step-8a design sound — a regex-detected user data kind against LLM-labelled workflow kinds, with a fixed
   −25 for a raw/processed mismatch? What failure modes do you foresee (false mismatch, users with both data kinds,
   misleading mentions)? Would a hard filter, a learned weight, or asking the user be better?
2. Step 6c/6c-2 follow the reply text to change the card ("the text is the more authoritative signal"). After this
   work they are limited to search candidates and input-compatible targets. Should text ever override the backend's
   card at all? What is the right precedence between backend ranking, `_llm_verify_routing`, and the reply?
3. The two-model catalog passes (propose with Flash, confirm with Sonnet, closed vocabulary, guarded SQL): are the
   prompts / acceptance rules sound? Is "two LLMs agree" adequate evidence to edit a production catalog with no
   version control? What validation would you add?
4. Evaluation: is the evidence (20×2 dev A/B with flawed regexes; offline harness without production components)
   enough to keep each change deployed? Which conclusions are over-claimed?
5. The FTS term dominates scoring (~85% of a typical score). Normalising it hurt. Is there a better way to let
   semantic signals (domain, input kinds) count without losing lexical precision?
6. Anything in the diffs that is a bug: wrong condition, missed path, Python 3.9 incompatibility, a TypeScript path
   that bypasses the guard, a test that does not test what it claims.
