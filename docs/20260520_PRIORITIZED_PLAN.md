# BioMate report + chat-stream — prioritized implementation plan

Date: 2026-05-20
Source: synthesis of the four agent audits. Replaces the long defect
catalogues in the architecture docs with a punch-list ordered by
**user impact × shipping risk**. Each item has scope, effort, and the
file:line to edit.

## Priority axis

```
P0  Ship-blocker for what we already advertise (regulatory, billing).
P1  Visible UX gap; cheap to close.
P2  Architectural debt that will bite later.
P3  Nice-to-have polish.
```

We do NOT touch the workflows themselves, nor production env vars, nor
billing math. Everything below is bounded to:
- `frontend/server/routes.ts` (report + analyze endpoints, SSE wiring)
- `frontend/server/workflow-sse.ts`
- `backend/lib/galaxy/ai/workflow_ops/workflow_chat_narrator.py`
- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`
- `frontend/client/src/components/chat-message.tsx` (one component)

---

## P0 — Ship this week (regulatory + reliability)

### P0.1 Report audit trail
**Why** — Today the methods report is generated with zero metadata.
21 CFR Part 11 + journal reproducibility require who/when/with-what-
model-and-prompt. Currently impossible to defend a report under audit.

**What** — On every successful call to `/api/invocations/:id/methods-
report` and `/api/workflows/runs/:id/ai/analyze`, write one row:
```
report_id, run_id, generated_at, model_id, prompt_sha256,
input_token_count, output_token_count, generator_version,
generated_by (user_id), output_bytes_sha256, ms_elapsed
```

**Where** — `routes.ts:~4761` (Anthropic call site), `:~10090` (analyze
call site). Add a `await storage.insertReportAudit({...})` after each
LLM call. Schema: new table `report_audit` migration in
`frontend/migrations/` (Drizzle).

**Effort** — half a day.

### P0.2 Persist findings cache to disk
**Why** — `_findingsCache` is in-memory only. Server restart =
finding/report blank. Already documented (D-AR-7).

**What** — Write `findings_data.json` to `<work_dir>/findings/<run_id>.json`
on first generation, and prefer disk-read over in-memory cache. Existing
`finding_reporter.py:181-241` markdown builder already works against the
on-disk file; just need the disk write on the generation path.

**Where** — `routes.ts:~10100` (after `analysis` is assembled). One
`fs.writeFileSync()` call, gated on a config flag for AWS Batch runs
(S3 → use S3 PutObject instead).

**Effort** — half a day.

### P0.3 Report Confidence Intervals on the metrics the user already pays for
**Why** — Today findings JSON has `key_results: [{metric, value,
interpretation}]` with point estimates only. For ADMET/RNA-seq runs
where the underlying tool emits CI/SD (DESeq2, scanpy, RDKit ensemble
methods), we **already have the data** but throw it away.

**What** — In the metric extractor (`routes.ts:~4500-4560`), pull the
`stderr` / `confidence_interval` / `padj` fields when present in the
output JSON and pass them into the LLM prompt as paired columns. Update
the prompt: "Report each metric with its 95% CI or adjusted p-value
when available; if not available, state 'no CI computed by upstream
tool'." (Do NOT fabricate CI — only surface what's there.)

**Where** — `routes.ts:~4500-4560` + the 5 domain prompts at
`:~4565-4750`.

**Effort** — 1 day. Pair with a `findings.confidence_intervals` E2E
test that drives a DESeq2 run and asserts the report has `padj`.

### P0.4 No more "Infinity" / "MISSING" / "not captured" in LLM input
**Why** — These sentinels flow into the prompt as plain text and the
LLM treats them as content. Already partially fixed (ADMET hERG), but
the same pattern is in CryoEM NU refinement (D-AR-3), parameter
extraction (D-AR-4), and the report's `compactMeta` block.

**What** — Introduce a `safeMetric(value, label)` helper that returns
either a real number/string, or formats as `«${label}: not reported by
pipeline»` (visually distinct in the prompt). Replace every
`String(... ?? 'MISSING')` and `?? 'not captured'` in the report
generator with `safeMetric(...)`.

**Where** — `routes.ts:~4500-4560`, `~4655-4675`, `~4775-4795`.

**Effort** — 1 day.

### P0.5 SSE endpoint ownership check
**Why** — `/api/workflows/:invocationId/events` is `optionalAuth` with
NO ownership check (D-4). Anyone who guesses an invocation_id can
subscribe to that user's QC events, chat progress, and deep-diagnose
output. Security incident waiting to happen.

**What** — In `workflow-sse.ts:391` `handleConnectionByInvocationId`,
after token validation, look up the run by invocationId and reject
if `run.user_id !== req.user?.id` (except for anonymous runs which
have `user_id=null`).

**Where** — `workflow-sse.ts:391-438`, with a storage lookup helper.

**Effort** — half a day. Plus a Playwright test that another user's
EventSource subscribe gets 403.

---

## P1 — Ship next week (visible UX gaps)

### P1.1 Speaker pills in production chat
**Why** — Today every chat-progress line gets the same italic 🔹.
The sandbox proved that prefix-derived pills (WF / QC / LOOP / AGENT)
materially improve scan-ability. This is the most-visible single
upgrade and the lowest-risk surface to promote per the integration
plan.

**What** — Cherry-pick `deriveSpeakerFallback(kind)` from
`research_agent_v2/src/ResearchApp.jsx:translateBiomateEvent` into a
new helper used by `chat-message.tsx:188-211`. Render a 4-char pill
("WF " / "QC " / "LOOP" / "AGENT") in front of the friendly_message
with per-pill background colors matching the sandbox's
`research-tokens.css`.

**Where** — `frontend/client/src/components/chat-message.tsx:188-211`
+ a tiny CSS block in `workflow-panel.css` or a new
`speaker-pills.css`.

**Effort** — 1 day including a snapshot test on the existing E2E.

### P1.2 Progress-line replay on refresh
**Why** — Chat progress is React local state only — refresh = lose
the 🔹 lines. Users see chat that "jumps" from `submitted` to `phase 3`.

**What** — Add `GET /api/workflows/:invocationId/chat-progress` that
returns the events emitted so far for this run. Source: the existing
`[WORKFLOW][inv=…][kind]` engineer-channel log line in
`workflow_chat_narrator.py:206` — parse on demand, or (cleaner) write
a sidecar `chat_progress.jsonl` next to the workflow's `findings/`
dir on every emit and read it on this endpoint. Frontend hydrates on
mount before the EventSource subscribes.

**Where** — new endpoint in `routes.ts`; sidecar write in
`workflow_chat_narrator.py:emit()` (one extra line after the log).

**Effort** — 1 day (including the file rotation: cap at 1 MB / 1000
lines per invocation).

### P1.3 Add QC pass/fail verdict to the methods report
**Why** — Report contains metric values but no PASS/FAIL/FLAG
verdict, so a reviewer has to look up each threshold themselves.

**What** — `qc_trace_monitor` already knows what the gates were and
what they evaluated to. Persist the gate outcomes per run (one JSON
sidecar `qc_verdict.json`) and inject into the methods-report user
prompt as a dedicated `## QC Gates` section with PASS / FAIL /
ADVISORY rows.

**Where** — `qc_trace_monitor.py` writes the sidecar at run end;
`routes.ts` methods-report path includes it in the user prompt.

**Effort** — 2 days.

### P1.4 Wire the dead templates (`uploading_inputs`, `queued`,
`auto_proceeded`)
**Why** — Three friendly-message templates exist but nothing emits
them, so the chat gets a 30-minute silence between "Got it" and
"Step 1/5".

**What** — Fire them from the existing emit points:
- `workflow.uploading_inputs` — at the start of S3 sync in
  `nextflow_executor.py` `_stage_inputs_to_s3`.
- `workflow.queued` — in `nextflow_monitor.py` when Batch submits.
- `workflow.auto_proceeded` — in the 10-s decision auto-proceed
  branch (already in `nextflow_executor.py`).

**Where** — three single-line `_narrate_chat(...)` insertions.

**Effort** — half a day.

### P1.5 Software-version extraction (extends P0)
**Why** — `cryoSparcVersion` defaults to "version not recorded" too
often. We already capture software versions in `multiqc_data.json`
for most pipelines but never read it.

**What** — Parse `multiqc_data/software_versions.yaml` (or the JSON
equivalent) in the metric extractor and inject the actual tool
versions into the prompt's PIPELINE CONTEXT block.

**Where** — `routes.ts:~4500-4560`.

**Effort** — half a day.

---

## P2 — Within the month (architectural debt)

### P2.1 Unify the two output-list endpoints
- Deprecate `/api/invocations/:id/outputs` (legacy shape).
- Migrate the 3 callers in `output-panel.tsx` to the new shape from
  `/api/workflows/runs/:id/outputs`.
- Remove the conditional shape detection in `output-panel.tsx`.
- Effort: 2 days, mostly type changes + Playwright runs.

### P2.2 SSE per-user connection cap + reconnect cursor
- Add per-user max connections in `workflow-sse.ts` (default 8).
- Emit `id: <ts>-<seq>` on every event; honor `Last-Event-ID` header on
  reconnect to replay missed events from sidecar (P1.2 enables this).
- Effort: 2 days.

### P2.3 Findings citation provenance
- LLM-generated citations are at risk of hallucinated PMIDs.
- Cross-check every returned PMID against a small static
  whitelist of tools-actually-used-by-this-workflow (we already
  have `tools_used` column in the workflow DB).
- Drop citations not in the whitelist before sending to client.
- Effort: 1 day.

### P2.4 Reproducibility appendix in the methods report
- Append a "Reproducibility" section listing: workflow path + git
  SHA, Nextflow config profile, Docker image digests (from
  `.nextflow.log`), input file SHA256s, conda env if applicable.
- We already log this engineer-side; just need to scrape and
  format.
- Effort: 2 days.

---

## P3 — Quality polish (when there's slack)

- Negation-aware regex for the rare-disease proactive suggestion
  (same pattern as the ADMET fix already landed).
- DOCX report: bullet-pointed Methods → numbered Section, add page
  breaks before each major section so pandoc output looks like a
  paper.
- Figure embedding for cryo-EM (FSC plot, class averages) using
  pre-generated PNGs already in outputs/.
- Reference formatting (APA/IEEE/Nature toggle) — needs a citations
  service; out of scope for now.

---

## Execution sequencing

Week of May 25:
- Mon: P0.5 SSE ownership + P0.2 findings cache persist (½+½ day)
- Tue: P0.4 sentinel cleanup (1 day)
- Wed: P0.1 audit trail (½ day) + P0.3 confidence intervals start (½ day)
- Thu–Fri: P0.3 finish + tests + dev sync

Week of Jun 1:
- Mon: P1.1 speaker pills + snapshot test
- Tue–Wed: P1.2 progress-line replay
- Thu–Fri: P1.3 QC verdict in report

Week of Jun 8:
- Mon: P1.4 dead templates + P1.5 versions
- Tue–Fri: P2 items in order

**Out of scope, explicitly:**
- ADMET PBPK / IND §2.6.1 narrative bundling — needs product decision.
- Stripe billing logic changes.
- Replacing routes.ts god-file with a service split — too large.
- LLM model swap.

---

## Definition of done per item

Each P0/P1 item ships only when:
1. Code change in the file:line listed above.
2. One Playwright test asserting the new behavior (`e2e/report-*.e2e.ts`
   or `e2e/chat-progress-*.e2e.ts`).
3. Sync to dev EC2 (`scripts/sync_to_dev.sh`) — verified there.
4. Session doc under `docs/20260???_<TOPIC>.md` capturing what
   landed and what's open.

No item is "done" with only a local pass.
