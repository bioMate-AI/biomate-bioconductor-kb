# Work + Test Manual — 2026-11-04/05 session (for the review committee)

This documents everything shipped in this session and exactly how to verify each piece. It is the
brief for a multi-model review committee. **Reviewers: your findings are LEADS, not verdicts — this
session already produced several false positives (see §7). Trace the ACTUAL current code (file:line),
mark each finding CONFIRMED (you reproduced the wrong behavior) vs PLAUSIBLE, give a concrete
failure scenario, and never fabricate. Do NOT re-raise the §7 items.**

Branch: `cursor/tutorial-live-recording-and-report-editing-4ea7` (PR #295). All changes below are
committed + pushed; the frontend/Node ones are deployed to dev. Full suite baseline: `cd frontend &&
npx tsc --noEmit -p . && npx vitest run` → tsc clean, ~2179 passed / 0 failed.

## 0. How to verify (shared)
- **Static:** `cd frontend && npx tsc --noEmit -p .` (types), `npx vitest run <suite>` (tests).
- **Live (read-only):** dev is `https://dev-public.biomate.ai`. Login: POST `/api/auth/login`
  `{email:"lifeifei163361@163.com", password:<~/.config/biomate/e2e_fixture_password>}` → JWT; reuse
  it; **never register**; GET only. Dev frontend logs: `docker logs biomate-dev-frontend` (read-only).
- **Scrutinize for:** (a) did a "fix" introduce a NEW bug or regress a working path? (b) is a test
  update legitimate or does it just paper over a real failure? (c) is any capability/claim overstated?
  (d) edge cases the fix misses.

---

## 1. #5a — long-tail findings pipeline (findings never appeared for non-parser workflows)
`frontend/server/routes.ts`, `GET /api/workflows/runs/:id/findings` + `runAsync`. Five layered bugs,
each masked by the prior; see `docs/20261105_FINDINGS_5A_APPROACH_DECISION.md`.
- **A — sidecar/cache shape validation** (`c3096f51a`): added `isFindingsShaped(o)` (summary:string OR
  key_results:array OR findings_document OR reportMd) and gated all 3 "ready" returns (local sidecar,
  S3 sidecar, in-memory cache). A `findings_data.json` holding raw output samples was being served as
  `ready`. **Loop-safe:** accepts a well-formed-but-EMPTY result (so a low-signal run isn't
  regenerated forever); rejects only non-findings shapes. *Verify:* reopen CAR-T `dc9f3235` findings —
  must not return the filename-keyed samples map as ready.
- **B — 90s bound** (`3995fc1b2`): the generic `llmGenerate` findings call had no AbortSignal and
  `llm-client.ts` has no timeout → hang → stuck `pending`. Wrapped in `Promise.race` vs 90s. *Verify:*
  a stalled provider resolves within ~90s to the Claude fallback / "unavailable" note.
- **D — response-contract gate** (`80c85aa62`): the LLM echoes the input files as a JSON ARRAY; it was
  cached as "findings". Added `isFindingsShaped(parsed)` gate on the primary parse AND the Claude
  fallback → non-findings JSON throws to the fallback; persist the "unavailable" note so cross-worker
  reads converge. Prompt hardened (object not array, don't echo). *Verify (live-done):* fresh CAR-T
  `e10a5e6a` returned 7 real key_results.
- **E — Claude fallback key** (`f8b8cfaf9`): fallback built its Anthropic client from the gate cascade
  `GEMINI||...||ANTHROPIC` → on dev got a Gemini key → `401 invalid x-api-key`. Use
  `process.env.ANTHROPIC_API_KEY` specifically; skip cleanly when absent. *Scrutinize:* is skipping to
  the note correct when no Anthropic key? (dev HAS one — verified Claude-fallback-succeeded live.)

## 2. #8 — per-step run-record finalization
`frontend/server/run-record-metrics.ts`, `routes.ts`, `storage.ts`.
- **Finalization** (`8555353ce`): `finalizeRunSteps(run, nextflowStatus)` sets terminal step status +
  attaches outputs; wired at the Nextflow terminal transition, the late-output refresh, and the
  read-time backfill in `GET /:id`. Honest: never fabricates a `failed` status; leaves inputs/logs/
  duration omitted (not in the status payload). *Verify:* `GET /api/workflows/runs/82c1245a` steps are
  `completed` (not `pending`).
- **Output attribution via S3 path** (`f0c8dcb8b`): `/output_files` returns null `step_name`, but the
  S3 key encodes the process (`…/02_predict_admet_properties/x.json`). Added `stepKeyFromUri` to derive
  the step from the `NN_<process>/` dir (strip numeric prefix, normalize); aggregate `output/` dir
  stays unattributed. *Verify (live-done):* `82c1245a` "Predict Admet Properties" shows 6 outputs.
  *Scrutinize:* could the trailing-segment match mis-attribute when two processes share a tail?

## 3. #9 — failed-run UX
`frontend/client/src/v2/AfterRunReport.tsx`, `step-output-preview.tsx`.
- `isRunMetadataFile` splits Nextflow `pipeline_info`/dag/report/timeline/trace out of the scientific
  Outputs list; failed run shows "No report"; HTML reports open in a new tab (NOT a sandboxed
  same-origin iframe — security rationale in `docs/20261104_ISSUE9_AFTERRUN_FAILED_RUN_UX.md`).
  (`8a8426b0e`, `5ff9b2b8a`, merge fixup `67fecf426`.) *Verify (live-done):* failed `d72b67af` → 3/3
  metadata, 0 scientific, findings `status=error`.

## 4. Audit sweep — 18 frontend/Node fixes (`docs/20261105_ADHOC_ERROR_AUDIT_SWEEP.md`)
- **S4 chat** (`fd1925ea7`): `chat-interface.tsx` — a generated-but-never-executed card inherited the
  GLOBAL `currentExecutionRun` (guard short-circuited on falsy invocationId) → wrong run's status +
  FindingsCard. Fixed with a positive id/galaxyInvocationId match (`scopedRun`), used for the prop AND
  the FindingsCard gate. In-panel badge no longer mis-fires on all cards. *Scrutinize:* does a
  just-launched card briefly lack invocationId and so show no live status? (acceptable vs wrong run.)
- **S3 parsers** (`613201fed`): DESeq2 parser was comma-only → EMPTY findings on BioMate's own TSV
  (now autodelim); gene IDs in the unlabeled first column → fake `gene_N` (now col-0 fallback);
  rare-disease `/moderate|mod/` matched MODIFIER → inflated MODERATE (now exact-match + MODIFIER
  bucket); variant top-200 no sort → dropped pathogenic HIGH (now count over all rows). *Scrutinize:*
  the col-0 gene fallback — could col 0 ever be a numeric column, not the gene id?
- **S5 billing/run-record** (`9f40c77e1`): `billing.tsx` read `tokens_in/mem_usd/size_gb/...` which the
  API never emits (it emits `input_tokens/memory_usd/total_seconds/puts`) → usage quantities all 0.
  Renamed to the real fields (verified vs `realtime_cost_service.py:501-525`); compute hrs =
  total_seconds/3600; storage shows puts (no GB field). `storage.ts` INSERT+UPDATE now persist
  totalSteps/currentStepIndex/percentComplete (were 0 from DB under multi-worker).
  `reproducibility-record.ts` completedAt fallback reads `execution.status` (was `run.status`, always
  undefined). *Scrutinize:* did the billing field rename miss any read site? grep `tokens_in|mem_usd|size_gb`.
- **S2 QC display** (`ae59978be`): `AfterRunReport.tsx` — surface degraded QC (unavailable/unknown/
  not_evaluated) that the backend writes but the UI hid (showed only fail/advisory → read as
  all-clear); color fail/halt red, advisory amber, pass green, degraded gray (was fail==advisory amber).
- **S3#1 reconcile** (`656972259`): `findings-extract.ts` `reconcileFindingsDocument` — `flatLiabilities`
  only recognizes the deterministic "potential liability" marker, so an LLM flat → empty flatSet →
  treated as "disagreement" → overwrote the CORRECT document summary with the LLM's "no liabilities".
  Fix: empty flatSet → document is primary (return unchanged); defer to flat only on a DETERMINISTIC
  disagreement. Test updated (the old test asserted the buggy behavior). *Scrutinize this test change
  carefully.*
- **S4#3 + S3#7 + S6** (`dcd0fed35`): `galaxy-assistant.ts` drops inline params with no schema to
  validate (was: guard skipped when schema empty → phantom param rows); `findings-descriptors.ts`
  VARIANT dropped the generic `annotated|filtered` tokens (cross-fired on scRNA files); removed dead
  `ConnectorsDialog` + unused `recentProjects`/`projectService` import. Test `c2e182ac9` updated the
  source-contract assertion.
- **S4#4 SSE** (`638103857`): `nextflow-workflow-viewer.tsx` — index each nf process by its trailing
  segment so nf-core FQ names (`NFCORE_RNASEQ:RNASEQ:FASTQC`) match a phase keyed `fastqc` (additive,
  non-clobbering). *Scrutinize:* two processes sharing a trailing segment.

## 5. Simplification — shadow instrumentation (`3f40e7cf7`)
`routes.ts` deterministic findings branch: computes `documentToLegacy(_findingsDoc)` alongside the
parser flat and LOGS key-set divergence (`[Findings][shadow] … cutover-ready / parser-only=[…]`).
**No behavior change** — returned flat unchanged. Design + live evidence (ADMET projection missed 9
metrics) in `docs/20261105_FINDINGS_QC_SIMPLIFICATION_DESIGN.md`. *Scrutinize:* is the shadow truly
side-effect-free?

## 6. Review patches (NOT applied — human-applied; review the DIAGNOSIS, not shipped code)
`docs/20261105_{ADMET_DILI,BOIN_PHASE2_DOSE,GEO_PSEUDOBULK_CONTRAST,NF_WORKFLOW_SAFETY,BACKEND_PYTHON}_*.md`.
Patient-safety `.nf` (BOIN dose>MTD, DILI asymmetric override, phase2 highest-when-unsafe,
repeated_dose_tox `(x or 999)` PASS, docking fake-receptor, stability degenerate ranking) + backend QC
gate / billing fixes. *Reviewers: check the diagnosed root cause + proposed fix are correct and the
fix doesn't break the workflow.*

## 7. KNOWN FALSE POSITIVES — do NOT re-raise (already verified against code/live)
- **S2#8** manual-remediation input key — the RemediationCard prop is already re-keyed to bare keys
  (`auto-loop-panel.tsx:561-562`); the bare read is correct. A "fix" would BREAK it.
- **S3#6** "dead" `_parseAdmetOutput` — verified live (`deterministic parse succeeded`, 9 key_results);
  not dead. The shadow later confirmed the parser is the MORE complete ADMET source.
- Parameter-adjustment "suggestion" capability — code exists (`ParameterSuggester.suggest`), but the
  product owner judged it not claimable; treat as out of scope for review.

## Reviewer output
Return a ranked list (most severe first), each: title · file:line · bug class · failure scenario
(inputs→wrong output) · CONFIRMED|PLAUSIBLE · recommended fix · frontend-safe vs backend/.nf. Prefer
few high-confidence findings over many speculative ones. If a change is correct, say so briefly.
