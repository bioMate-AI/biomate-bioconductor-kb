# Cold-start work — committee review and fixes (2026-11-11)

Four independent review agents audited the recent cold-start / search-example /
attachment-binding / simulation-guard work (base commit `006d1e0345`,
branch `fix/coldstart-search-examples-dev`). This records their findings, what
was fixed, and what is deferred.

## Reviewers

| Agent | Scope | Verdict |
|---|---|---|
| test-quality | test coverage of the changed surface | 2 concrete gaps |
| architecture | structural debt / regex-vs-catalog | 1 actionable (#6), rest = debt |
| honesty | no-S3 / no-count / no-scaffold / simulation-block directives | 5/6 hold; 1 gap (S3 stream) |
| correctness | routing / binding / simulation / data-inputs regressions | 1 Med (synthetic FP), 5 lower |

## Fixed in this batch (commit `4af24ef218`) — files outside the live example-data agent's scope

1. **Cryo S3 leak (honesty Finding 1/2, root).** The cryo bundle *context*
   embedded `s3://biomate-cryo-data/empiar-10028/Micrographs/` and fed it to the
   model via the hidden `[Prepared inputs]` block, priming the echo;
   `redactStoragePaths` only cleaned the **final** message, so the path flashed
   token-by-token during streaming (this is what the live sweep caught).
   - Removed the bucket path from the cryo context (now the public EBI EMPIAR
     reference) — `cold-start-demo-catalog.ts`.
   - Dropped `s3_path` from `cryo_inputs.json` and `historical_s3_prefix` from
     `sysucc_synthetic/provenance.json` (public `source_ftp`/`source_http`
     remain). provenance hash test still green.
   - Added a **streaming backstop** in `routes.ts` `safeSend`: each delta is
     `redactStoragePaths`-cleaned, and an unterminated `s3://…` tail is held
     back until its terminator arrives (flushed at `final`), so no storage URI
     renders mid-stream.

2. **Synthetic-data guard precision (correctness Finding 1 + architecture #6).**
   The old regex false-positived on reproducibility/resampling boilerplate —
   `set.seed`, `np.random.seed`/`permutation`/`shuffle`, `random.seed`, and a
   bare `simulat…` substring (which also matched `simulated_annealing` and prose
   comments). With zero staged inputs that wrongly **refused legitimate
   real-data `run_code`** and told the user they faked data. Simultaneously
   `torch.*`, `scipy …​.rvs(`, and sklearn `make_*` generators were **evading**
   it. Narrowed to genuine input-fabrication *draws* and added the evaders —
   `execution-integrity.ts`. `requestAsksForSimulation` still lets explicit
   simulations through. Tests rewritten to the precise contract + a
   refusal-composition test (test-quality gap #2).

3. **`scoreBinding` typedAsFile (correctness #6).** Strip the `[]` suffix so a
   `file[]` data input scores as a typed file (matching the `isFilePathParam`
   baseType fix); an optional `file[]` input no longer falls below the bind
   threshold — `attachment-binding.ts`.

Verification: `tsc` clean; vitest `execution-integrity` (27), `cold-start-demo-catalog` (102), `attachment-binding` (36) green.

## Fixed in batch 2 (after merging `fix/example-data-default` `cd2aa142be`) — `galaxy-assistant.ts`

- **Correctness #2 — DONE.** `isValueOnlyReply` now strips connective glue
  ("use/and/plus/run…", CJK run verbs 跑/用) before the leftover-letters check and
  matches accessions case-insensitively, so "use SRR… and SRR…", "run SRR… plus
  SRR…", lowercase "srr…", and "跑 SRR…" bind to the open workflow instead of
  re-routing. Two existing test assertions that encoded the old narrow behaviour
  ("use SRR…"/"用 SRR…" = not-value-only) were corrected to the fixed contract;
  reviewer's scenarios added.
- **Correctness #3 — DONE.** `workflowNamedInRunRequest` rejects a generic
  determiner/pronoun captured before workflow|pipeline (whole/this/that/the/my/…)
  so "run the whole workflow" no longer pins "whole" and skips the clarification
  gate. 5 new negative cases.
- **Correctness #4 — DONE.** `conversationHasPipelineScaleData` is scoped to the
  current turn: a stale earlier pipeline-scale file (turn-1 FASTQ) no longer
  suppresses `direct_compute` for this turn's own fresh small data (turn-5 CSV);
  a data-less follow-up still sees the carried-over pipeline file. New test.
- **test-quality gap #3** — backend `_return_nextflow_match` `bound_value` test:
  the merged agent branch already added `test_example_data_detection.py` and
  `test_executor_data_inputs.py` covers the data-input marking; the remaining
  accession-vs-file assertion is a small follow-up (tracked), lower priority now
  that the executor-data-input path has coverage.

### Reviewed and intentionally NOT changed

- **Correctness #5 (Step 6r overwrite)** — the overwrite fires only when a real
  workflow card is successfully built (`recovered.success` + a card). Ending on
  that card with the honest "simulation stopped — here's the real path" note is
  the founder's explicit directive ("end with the real workflow card; simulation
  must not be the ending status") and matches the merged example-data behaviour
  (a workflow that runs on its built-in data should not end on "please provide
  data"). When no card can be built, Step 6's reply stands. Left as-is by design.

## Structural debt — surfaced for a decision, NOT done autonomously (bigger than a fix)

- Two parallel `workflow_ga` builders (search endpoint doesn't emit
  `data_inputs`); unify so binding metadata is single-sourced.
- Format/operation detection is hand-maintained regex lists
  (`biologic_format_conflict`, `_DIFFERENTIAL_TOOLS`) — candidates to derive
  from catalog tags.
- Old name-based binder vs the new schema-driven binder — retire or document the
  ordering contract.
- "Built from your data" over-claim (honesty #3) is prompt-enforced only; no
  structural post-check.
- Nanobody-design catalog gap (routing lands on bispecific).

## Cryo-EM license gate (founder note 2026-11-11) — verified, no change needed

Cryo-EM via CryoSPARC requires each user's own license; BioMate already handles
this in the UI (`components/license-gate.tsx` → `/api/workflows/license-requirements`
→ `credentials_api.py` → `LICENSE_REGISTRY["cryosparc"]`, `user_must_provide:True`,
`open_alternatives:[]`). The cryo cold-start query routes to
`cryosparc_standard_spa/main.nf`, whose path matches `container_patterns:["cryosparc"]`,
so the gate returns `source:'none'`, `has_fallback:False` → **hard-block** with
"Provide credentials" + Register link. The S3-leak edit does not touch this (the
gate keys on `nextflow_path`). **Live-sweep scoring:** cryo stopping at the
CryoSPARC license gate is the CORRECT terminal state, not a failure — same for
other `user_must_provide` tools (alphafold3, schrödinger/FEP+, gastroplus). Tools
with `open_alternatives` + `user_must_provide:False` (Boltz, Simcyp, AMBER) are
advisory (run on the open fallback), not blocking.

## Acknowledged, not findings

- Remaining user-facing "S3" strings name the real connector feature ("复制 S3
  路径", URL importer "AWS S3 单个文件/文件夹") — a working feature label, left for
  the founder (docs/20261110 §8), not a leak.
