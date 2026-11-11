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

## Deferred — require `galaxy-assistant.ts` (held until the example-data agent's branch merges, to avoid a conflict-marker merge)

- **Correctness #2** — `isValueOnlyReply` fails on the commonest accession
  phrasings ("SRR… and SRR…", "use SRR…", lowercase, CJK), so the value-only
  bind silently doesn't fire and the reply re-routes. Add a small connector
  stoplist + case-insensitive accession match.
- **Correctness #3** — `workflowNamedInRunRequest` pins on generic tokens
  ("run the whole workflow" → name "whole"; a 2-underscore filename). Add a
  stoplist / tighten the pattern so a bogus name can't skip the clarification
  gate.
- **Correctness #4** — `conversationHasPipelineScaleData` scans the whole
  conversation, so one stale pipeline-scale attachment disables `direct_compute`
  for an unrelated later task. Scope it to the current task's data.
- **Correctness #5** — Step 6r can overwrite a legitimate final reply once any
  run_code in the turn is refused. Guard it to only replace when Step 6 produced
  nothing usable.
- **test-quality gap #3** — backend `_return_nextflow_match` `bound_value`
  (accession vs file) has no Python test. Add one (backend, also held while the
  agent writes backend tests).

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

## Acknowledged, not findings

- Remaining user-facing "S3" strings name the real connector feature ("复制 S3
  路径", URL importer "AWS S3 单个文件/文件夹") — a working feature label, left for
  the founder (docs/20261110 §8), not a leak.
