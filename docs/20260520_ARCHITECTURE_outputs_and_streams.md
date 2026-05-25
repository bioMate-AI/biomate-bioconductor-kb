# BioMate Complex Outputs & Streams — How the frontend surfaces are generated

Date: 2026-05-20
Companion: `20260520_ARCHITECTURE_API_endpoints_and_frontend_consumers.md`
covers **what** endpoints exist; this doc covers **how** the user-visible
surfaces are produced, on what data, by which prompts, with what
limitations.

Four surfaces:

1. **The chat-streamed progress lines** (italic 🔹) — §1
2. **Workflow generation from a chat message** — §2
3. **Per-step output fetching & visualization in the right panel** — §3
4. **The after-run report + findings card** — §4

§5 is the assessment of whether the report meets a professional
scientific bar. §6 collects the defects worth fixing and the
fixes applied in this audit.

---

## 1. Chat-streamed progress lines (the italic 🔹 events)

### 1.1 What appears in the chat

```
🔹 Got it — starting your workflow now.                        · 3:40 PM
🔹 Step 1/5: STAR alignment…                                   · 3:40 PM
🔹 STAR alignment done — 91.4% mapped.                         · 3:41 PM
🔹 QC flagged mapping_rate = 0.948 (threshold 0.95).           · 3:41 PM
🔹 Trying again with logp_max=4.5.                             · 3:42 PM
🔹 Workflow finished. 5/5 steps succeeded.                     · 3:48 PM
```

Each line is generated server-side from one of 18 documented event
"kinds." Render is `fontStyle:italic, fontSize:12, color:dim-gray,
opacity:0.85` (chat-message.tsx:188-211). Currently there is **no
speaker pill** in the production renderer — every prefix renders the
same way. The sandbox derives WF/QC/LOOP/AGENT pills from the kind
prefix (see §6 fix-1).

### 1.2 The 18 event kinds — full taxonomy

Source: `backend/lib/galaxy/ai/workflow_ops/workflow_chat_narrator.py:132-158`

| Kind | Friendly template | Required `technical` fields | Speaker (derived) | Wired in backend? |
|---|---|---|---|---|
| `workflow.submitted` | "Got it — starting your workflow now." | optional `workflow`, `run_id` | wf | ✓ nextflow_executor.py:3080 |
| `workflow.uploading_inputs` | "Uploading inputs to S3…" | — | wf | ✗ **no caller** |
| `workflow.queued` | "Your workflow is in the AWS Batch queue." | — | wf | ✗ **no caller** |
| `workflow.running` | "Workflow is running." | — | wf | ✓ nextflow_executor.py:1599 |
| `workflow.phase_started` | "Step {n}/{of}: {phase_name}…" | `phase_name, n, of` | wf | ✓ :1636 |
| `workflow.phase_completed` | "{phase_name} done — {detail}." | `phase_name, [detail]` | wf | ✓ :1679 |
| `workflow.phase_failed` | "{phase_name} failed — {reason}." | `phase_name, [reason]` | wf | ✓ nextflow_executor.py:1671 (verified during this audit; earlier survey reported as unwired in error) |
| `workflow.qc_gate_warning` | "QC flagged {metric} = {value} (threshold {threshold})." | `metric, value, threshold` | qc | ✓ qc_trace_monitor.py:5559 |
| `workflow.qc_gate_blocked` | "QC blocked on {metric} — adjusting parameters." | `metric` | qc | ✓ same site |
| `workflow.autoloop_started` | "Trying again with {k}={v}…" | `changes:{k:v,…}` | loop | ✓ nextflow_executor.py:3347 |
| `workflow.completed` | "Workflow finished. {succ}/{total} steps succeeded." | `steps_succeeded, steps_total` | wf | ✓ :2161 |
| `workflow.failed` | "Workflow stopped — {reason}. Looking into why…" | `reason` | wf | ✓ :2163 |
| `workflow.cancelled` | "Workflow cancelled — {reason}." | optional `reason` | wf | ✓ :3458 |
| `workflow.paused` | "Workflow paused. Tap Resume…" | — | wf | ✓ :3458 |
| `workflow.resumed` | "Resuming your workflow." | — | wf | ✗ **fixed in this audit** (§6) |
| `workflow.auto_proceeded` | "No response — {decision} automatically." | `decision` | wf | ✗ no caller |
| `deepagent.start` | "Looking into why your workflow failed…" | — | agent | (external — DeepAnalysisAgent) |
| `deepagent.investigating`, `tool_call`, `suggestion` | fallback to `friendly_message` payload field | optional | agent | (external) |

### 1.3 What's there and not there

**In the chat:**
- Phase-level granularity (start, complete, fail).
- QC events (gate warning, gate block, autoloop attempts).
- Submission + completion summary.
- DeepAnalysisAgent investigation when a run fails.

**Not in the chat (but the data exists):**
- Process-level output file completions ("BAM produced, 12 GB on S3").
- AWS Batch job submission/start (queue wait visibility is zero).
- Intermediate findings before final analysis.
- Cost milestones (e.g., "You've burned 60% of pilot budget").
- The "uploading_inputs" and "queued" kinds are designed but unwired.

### 1.4 Generation mechanism — single source of truth

```python
# workflow_chat_narrator.emit(invocation_id, kind, technical, sse_callback=...)
payload = {
  "kind": kind,
  "invocation_id": invocation_id,
  "friendly_message": render_friendly(kind, technical),
  "ts": time.time(),
  "technical": technical or {},
}
log.info("[WORKFLOW][inv=%s][%s] %s | technical=%s", ...)
if sse_callback is not None:
    sse_callback("chat_progress", payload)
return payload
```

The `friendly_message` is a static template applied to `technical`.
There is **no LLM in this pipeline**. Wire path: §3 of the companion
endpoints doc.

### 1.5 Persistence & history

**Progress messages are NOT persisted.** They live in the React local
state of the active `ChatMessage` component. Refreshing the browser
mid-run wipes prior progress lines from view (the rest of the chat
history reloads from DB; the 🔹 events do not). This is intentional
per the narrator design comment ("backend stays stateless w.r.t. chat
history"), but it does mean users see a chat that "jumps" from
`submitted` to `phase 3` after refresh.

### 1.6 Ordering, dedup, reconnection

None of the above are handled. SSE events are appended in arrival
order; the `ts` field is on the payload but not used. EventSource
auto-reconnects on transient drops, but there's no resume cursor
(`Last-Event-ID`), so events emitted during the disconnect are lost.

### 1.7 Test coverage

- Unit: `test_workflow_chat_narrator.py` — 14 tests on template
  rendering + `emit()` callback invocation.
- E2E (mocked): `frontend/research_agent_v2/audit.cjs`,
  `frontend/e2e/research_agent_v2_sandbox.e2e.ts` — 25 tests over 4
  scenarios, all using injected events via `sse-adapter` mock.
- E2E (real): `frontend/research_agent_v2/real_sse_smoke.cjs` — 8
  events round-tripped through dev EC2 `/internal/sse-inject` → SSE
  → translator (proven 2026-05-19).
- **Gap:** no test that fires a real Nextflow workflow on dev,
  triggers a real QC gate, and verifies the chat DOM renders the
  resulting 🔹 line. The injection step is mocked.

---

## 2. Workflow generation — chat message → executable workflow

### 2.1 The pipeline

```
User chat message
  ↓
frontend/server/galaxy-assistant.ts:1150-1225
  extractInlineDataWithLLM()    — pull paths/SMILES/accessions
  ↓
galaxy-assistant.ts:804-940
  inferActionsFromType()         — intent classification → routing
  ↓
galaxy-assistant.ts:751-763
  buildWorkflowRoutingBlock()    — domain catalog → LLM system prompt
  ↓
POST /api/ai_assistant/generate_workflow
  ↓
backend/lib/galaxy/ai/ai_assistant.py:3069
  generate_workflow_unified()
    ├── unified_workflow_search.py:577    — FTS + LLM-rerank + BGE
    ├── _classify_match() vs 12.0 / 6.0 thresholds
    ├── _extract_explicit_params_from_query()  — rule-based
    ├── _apply_llm_suggestions()                — LLM-inferred params
    └── _build_prereq_validation()              — guardrail
  ↓
Returns workflow_ga = {
  name, description, domain, format, nextflow_path,
  required_params, optional_params,
  steps: {},        // lazy — filled by /api/nextflow/steps later
}
```

### 2.2 Workflow database

- `backend/database/galaxy_ai_tools.db` (SQLite)
- **2,449 workflows** across 34 biological domains (transcriptomics
  865, genomics 369, epigenomics 133, proteomics 113, drug discovery
  61, cryo_em 10+, general 464 Bioconductor utilities).
- Tables: `workflows`, `workflows_fts` (FTS virtual), `tools` (~12k),
  `chains` (multi-step research pipelines).

### 2.3 Search architecture (unified_workflow_search.py:577-770)

Hybrid retrieval combining three signals:

1. **FTS5 keyword** with weighted query construction:
   - Keyword weights e.g. `rnaseq → 3.0, sarek → 4.0, differential → 2.5`
   - **Named-tool anchoring**: "using X" / "run X" extracts X and
     forces an AND-clause so the named workflow ranks #1.
2. **Pass-0 LLM catalog browse**: Claude Haiku gets 60 broad FTS
   candidates, returns top 10 ranked IDs. Bonus: rank-0 +3.0, rank-9
   +0.3. Degrades gracefully to FTS-only.
3. **BGE dense retrieval**: `BAAI/bge-small-en-v1.5`, 384-dim
   embeddings (`database/galaxy_ai_workflow_embeddings.npz`). Min
   cosine 0.55, bonus `cosine_sim * 0.5` (cap +4.0). Tiebreaker only.

Source priority bonus: nfcore 100 > nfcore_subwf 95 > biomni_nextflow
85 > bioconductor 75 > galaxy_biomni 35.

Match classification thresholds:
- `_MATCH_SCORE_HIGH = 12.0` → high_confidence (use as-is)
- `_MATCH_SCORE_MED = 6.0` → medium_confidence (adapt template)
- `< 6.0` → low_confidence → compose from scratch

**IR baseline** (per memory): MRR=0.847, P@1=0.742, NDCG@3=0.920,
Hit@5=0.967.

### 2.4 Disambiguation gate (ai_assistant.py:2941)

Fires only for **genuine ambiguity**:
- `match_type != 'high_confidence'`, AND
- ≥2 candidates with score ≥ 6.0, AND
- gap between top two < 3.0

Returns `workflow_type='disambiguation'` with up to 4 candidates.
Frontend renders `WorkflowDisambiguationCard`
(`frontend/client/src/components/workflow-disambiguation-card.tsx`)
wired in `chat-message.tsx` via `workflow_type === 'disambiguation'`.

### 2.5 Param prefill — hybrid rule + LLM

Rule-based first (ai_assistant.py:2700-2800):

| Rule | Example |
|---|---|
| Explicit `key=value` | `pixel_size=0.83, cryosparc_license=…` |
| File extension → param | `.mrc/.mrcs/.tif → movies_path`, `.fastq → reads`, `.vcf → vcf`, `.fasta → genome`, `.pdb → receptor_pdb` |
| SRA/GEO/PRIDE accession | `SRR12345678` → `reads`, `input`, `reads1`, `reads2` |
| Genome alias | `human → GRCh38`, `dUTP → reverse`, `GRCh37 → hg19` |
| `max_spots` | regex from `\bmax_spots\s*[=:]\s*(\d+)` |

LLM second (ai_assistant.py:2800-2840): `_apply_llm_suggestions()`
overlays inferred params, marks `autoFilled=True` with `rationale`.
User-explicit values always win.

Validation guardrail (ai_assistant.py:2472-2500):
`_build_prereq_validation()` checks for params with neither a default
nor a value; returns a `prerequisitesValidation` JSON the frontend's
prereq-normalizer uses to block the Run button.

### 2.6 Defects

- **D-WG-1** (low): extension-to-param map covers 20 unambiguous
  extensions; many domain formats (`.sdf`, `.nwk`, `.h5ad`) unmapped.
- **D-WG-2** (medium): no check that `nextflow_path` exists on disk
  before returning workflow_ga (`ai_assistant.py:3380-3400`). 500 at
  execution time instead of clarification.
- **D-WG-3** (low): disambiguation gate returns HTTP 200 with
  `success=False` (`ai_assistant.py:3328`) — frontend cannot reliably
  distinguish from a real error.
- **D-WG-4** (low): count-matrix → differentialabundance routing
  hint is fragile, depends on exact filename patterns; synonym
  queries ("abundance analysis") not boosted.

---

## 3. Step output fetching & visualization

### 3.1 Endpoint trio

| Endpoint | Purpose | File:Line |
|---|---|---|
| `GET /api/workflows/runs/:id/output_files` | List with metadata + presigned URLs | routes.ts:9217-9361 |
| `GET /api/workflows/runs/:id/step-file?path=…` | Single file stream | routes.ts:9389-9490 |
| `GET /api/workflows/runs/:id/outputs` | Thin wrapper around output_files | routes.ts:9375-9387 |
| `GET /api/nextflow/steps?nextflow_path=…` | Lazy step schema | routes.ts:6728-6740 |

### 3.2 Output discovery — fallback chain (routes.ts:9217-9361)

1. In-memory `nextflowStatus.s3_output_files / .output_files`
   (live cloud runs).
2. Galaxy backend `/api/nextflow/status/:id` (server restart, DB-loaded).
3. Local disk scan of `outdir` (dev only, recursive walk depth ≤4).
4. S3 ListObjectsV2 + presigned URLs (1-hour TTL) for AWS Batch
   where Galaxy callback was dropped.

### 3.3 Viewer registry — extension → React component

Source: `step-output-preview.tsx:46-86`

| Extension | Viewer | Implementation |
|---|---|---|
| `.png .jpg .jpeg .gif .svg .pdf` | image | `<img>` + zoom lightbox |
| `.csv .tsv .json .tabular .star` | table | InlineTableViewer (delimiter detect, STAR/RELION parser) |
| `.fasta .fa .fastq .fq` | sequence | SequenceViewer (record list) |
| `.vcf .bcf` | vcf | VcfViewer (variant table) |
| `.bed .gff .gtf .gff3` | annotation | AnnotationViewer |
| `.pdb .mmcif .cif` | structure | StructureViewer (text fallback; NGL 3D planned) |
| `.mrc .map .mrcs .rec` | density | DensityMapViewer (3-axis slice, ArrayBuffer fetch) |
| `.cs .csg` | download | Download link only (CryoSPARC binary) |
| `.html .htm` | html | Sandboxed iframe |
| `.log .txt .sh .py .out .err` | text | `<pre>` with tail toggle |
| (unknown/binary) | download | Download link |

### 3.4 Special viewers

- **STAR/RELION parser** (step-output-preview.tsx:99-127): detects
  `loop_` block header, extracts column names + data rows.
- **DensityMapViewer** (`viewers/density-map-viewer.tsx`): full
  3-axis orthogonal slicer for `.mrc` cryo-EM maps; streams the file
  via `/api/workflows/runs/:id/step-file` as ArrayBuffer.
- **Table** (step-output-preview.tsx:176-174): auto delimiter
  detection, up to 200 rows with truncation warning.

### 3.5 Defects

- **D-OV-1** (medium): chain runs return 200 with empty outputs
  instead of 404 (routes.ts:9225-9227) — hides "run never registered"
  errors.
- **D-OV-2** (low): local recursive walk has no depth/size guards
  beyond depth ≤ 4 (routes.ts:9254-9261).
- **D-OV-3** (medium): S3 listing fallback only triggers if Galaxy
  callback dropped; cloud runs can appear to have zero outputs for an
  extended window before the fallback fires.
- **D-OV-4** (low): step-file S3 security relies on bucket whitelist
  only — no scope check against the run's actual outdir.

---

## 4. After-run report + findings

Three distinct artifacts produced from a finished run:

| Artifact | Endpoint | Format | Generator |
|---|---|---|---|
| **Methods report** | `GET /api/invocations/:id/methods-report` (?format=docx) | Plain text / DOCX (via pandoc) | Claude Sonnet 4.5, single call, domain-adaptive prompt |
| **Findings JSON** | `GET /api/workflows/runs/:id/findings` | JSON | Claude Sonnet 4.6 inline analysis, structured schema |
| **Findings report (markdown)** | `GET /api/workflows/runs/:id/findings/report` | Markdown | Renderer over the findings JSON / cache |

Trigger pathway for the **AI analysis**:

```
button-analyze-results → POST /api/workflows/runs/:id/ai/analyze (routes.ts:9883)
  ↓
fetch up to 6 text output files (.txt/.log/.csv/.tsv/.json/.vcf/...) — 8KB each
  ↓
Claude Sonnet 4.6 with structured prompt (routes.ts:9962-9989)
  ↓
JSON-only response:
  { summary, key_findings:[{finding, significance}], quality_assessment,
    next_steps[], citations[], limitations }
  ↓
Inject proactive follow-ups (ADMET → REINVENT4; rare-disease → TxGNN)
  ↓
Cache in-memory (_findingsCache) + populate /api/workflows/runs/:id/findings
```

### 4.1 Methods report — what's in it

CryoEM example (6 sections per the prompt):

```
BioMate AI — Report
============================================================
Generated: 2026-05-20T12:34:56 UTC
Workflow:  CryoSPARC Standard Single-Particle Analysis
Invocation ID: ...
Nextflow Run ID: ...
Wall Time: 52m 07s
============================================================

1. ABSTRACT.
2. STUDY OVERVIEW.
3. COMPUTATIONAL ENVIRONMENT.
4. DATA ACQUISITION AND PREPROCESSING.
5. METHODS.
   5.1. MOTION CORRECTION.
   5.2. CTF ESTIMATION.
   5.3. PARTICLE PICKING.
   5.4. 2D CLASSIFICATION.
   5.5. AB-INITIO + 3D REFINEMENT.
6. FINDINGS.
N. REFERENCES.
```

Domain-adaptive prompt selection (routes.ts:4375-4385) chooses one of:

| Domain | Sections | Key citations baked in |
|---|---|---|
| CryoEM | ABSTRACT, METHODS, DATA, OUTPUT, FINDINGS, SUMMARY | (extracted from outputs) |
| ADMET | ABSTRACT (120w), STUDY OVERVIEW, METHODS×5, RESULTS, SAFETY INTERPRETATION, PIPELINE EXECUTION, REFERENCES | RDKit PMID 19997329, Kazius-Bursi PMID 15832503, Lipinski PMID 11259830, ICH E14, DILI PMID 31134006 |
| RNA-seq | ABSTRACT, COMPUTATIONAL ENVIRONMENT, DATA, DE, RESULTS, PIPELINE, REFERENCES | nf-core PMID 32055031, STAR PMID 23104886, DESeq2 PMID 25516281 |
| Variant calling | ABSTRACT, COMPUTATIONAL ENVIRONMENT, METHODS, RESULTS, PIPELINE, REFERENCES | GATK PMID 20644199, BWA-MEM2 PMID 31006120, nf-core/sarek PMID 34044496 |
| Generic | ABSTRACT, COMPUTATIONAL ENVIRONMENT, INPUT, METHODS, RESULTS, PIPELINE, REFERENCES | (none) |

LLM = Claude Sonnet 4.5, single call. **Input context** stuffed into
the user prompt:
- Extracted metrics from JSON output files (workflow_summary.json,
  fsc_validation.json, etc.)
- Actual parameter values (from `workflowDefinition.parameters` or
  `parameters.toolParameters`)
- Step definitions + descriptions from the workflow DB
- Up to 15 text files from S3 (priority list applied)
- Wall time, start/end timestamps
- Cloud platform (hardcoded — see §4.4 defects)

Conversion to DOCX (routes.ts:4794-4810): pandoc subprocess. Falls
back to plain text if pandoc absent.

### 4.2 Findings JSON — what the frontend gets

```json
{
  "status": "ready",
  "runId": "...",
  "summary": "<2-3 sentences from LLM>",
  "key_results": [
    { "metric": "string", "value": "string", "interpretation": "string" }
  ],
  "citations": [
    { "pmid": "12345678", "title": "...", "year": "2024", "relevance": "..." }
  ],
  "caveats": ["string"],
  "next_steps": ["string"],
  "reportUrl": "/api/workflows/runs/:id/findings/report"
}
```

LLM system prompt (routes.ts:9997-10017): "You are a senior
bioinformatics scientist interpreting results…" Schema enforced via
JSON-only response, with regex fence stripping
(routes.ts:10041 — see D-AR-5).

### 4.3 Findings markdown — what the user can download

Rendered by `finding_reporter.py:181-241` (preferred) or the in-memory
cache fallback in `routes.ts:10474-10510`. Structure:

```markdown
# Findings Report
**Run ID:** ...
**Output type:** ...

## Findings Summary
[prose]

## Key Results
| Metric | Value | Interpretation |
| ------ | ----- | -------------- |
| ...    | ...   | ...            |

## Supporting Literature
1. **Title** (Year) — PMID:xxx
   *Relevance excerpt*

## Caveats
- ...

## Recommended Next Steps
1. ...
```

### 4.4 Defects in the report generators

| ID | Severity | Where | Issue | Fixed here |
|---|---|---|---|---|
| D-AR-1 | high | routes.ts:4739 / 4744 / 4754 | CryoSPARC version hardcoded as **"v5.0.2"** in the prompt regardless of actual version. Regulatory submissions require true software version. | **yes — §6 fix-3** |
| D-AR-2 | medium | routes.ts:~4500-4530 (ADMET) | `Math.min()` over empty compound list → emits `"herg_ic50_min_uM: Infinity"` in findings. | **yes — §6 fix-4** |
| D-AR-3 | medium | routes.ts:4408 | NU refinement particle-count fallback chain emits the string `"not captured"` into the metric block; LLM reads it as plain text and may write "completed with zero particles". | tracked, not surgical |
| D-AR-4 | medium | routes.ts:4270-4275 | If `workflowDefinition.parameters` is `null` (not `{}`), `Object.keys(null)` throws and falls through to wrong parameter source. | tracked |
| D-AR-5 | medium | routes.ts:10041 | Markdown fence stripping regex assumes trailing `\`\`\`` is at the end; trailing newlines after the fence cause JSON.parse to fail and the entire structured analysis is replaced with a 500-char raw-text fallback. | **yes — §6 fix-5** |
| D-AR-6 | medium | routes.ts:10017-10035 | Proactive follow-up suggestions use regex `/ic50.*<.*1\s*µm/i` — matches "not < 1 µM" because negation isn't handled. Misleading suggestions surface for safe compounds. | **yes — §6 fix-6** |
| D-AR-7 | medium | routes.ts:10164-10195 | Findings cache is in-memory; server restart wipes the report; no fallback to disk for AWS Batch runs. | tracked, requires DB schema |
| D-AR-8 | medium | routes.ts:4330-4350 | S3 path parsing assumes `s3://`. If `s3OutputBase` starts with `http://` (misconfig), bucket name becomes the hostname and list silently returns nothing. | tracked |
| D-AR-9 | low | routes.ts:9883-10001 | No audit-trail logging of LLM tokens, model version, prompt hash on findings/report generation. 21 CFR Part 11 gap. | tracked |

---

## 5. Is the report "professionally scientific"?

### 5.1 Strengths

- **Domain-aware structure** (6-section CryoEM, ICH-referenced ADMET,
  nf-core RNA-seq with PMID citations). Methods section follows
  conventional ordering.
- **Quantitative metrics from real outputs** — the LLM gets actual
  JSON values (particle counts, FSC resolution, mapping rate)
  rather than fabricating. Prompt explicitly requires "specific and
  quantitative" findings.
- **References baked into the prompt** for the major tools (GATK,
  STAR, DESeq2, RDKit, ICH E14). Findings JSON adds PMIDs when the
  LLM can extract them from context.
- **Real execution metadata** (wall time, start/end UTC timestamps,
  S3 output path). Traceability is reasonable.

### 5.2 Gaps for IND-filing / journal-submission grade

1. **No confidence intervals, p-values, or FDR.** Single point
   estimates throughout. ADMET hERG IC50 reported as scalar with no
   SD/CI. RNA-seq "1,847 DEGs" with no adjusted-p cutoff stated.
2. **Reference format isn't APA/IEEE/Nature.** Bare PMIDs and
   author-year strings; no journal name, pagination, or DOI in many.
3. **No figures or supplementary materials.** CryoEM report should
   embed density map, class averages, FSC curve.
4. **No formal QC pass/fail gates surfaced in the report** (just
   metric values; no "PASS / FAIL / FLAG FOR REVIEW" verdict).
5. **Software versions hardcoded** (D-AR-1) — fraud risk for
   regulatory filings.
6. **Audit trail absent** (D-AR-9) — 21 CFR Part 11 requires who/
   when/with-what-version-and-prompt. Nothing logged.
7. **PBPK/PK narrative missing for drug discovery** despite the IND
   §2.6.1 LLM narrative work (memory entry from 4 weeks ago). The
   route fires the narrative but doesn't bundle it into the
   methods-report by default.
8. **Hardcoded fallbacks mask failures** — "not captured", "MISSING",
   `Infinity` strings flow into the prompt and the LLM treats them
   as content rather than flagging as data gaps.
9. **No reproducibility bundle** — workflow definition + parameters +
   conda env / Docker SHA / input file hashes are not attached.

### 5.3 Verdict

**Publication-adjacent.** Suitable as a methods-section starter and
for internal QC review. NOT IND-filing-ready without:

- CI computation (post-hoc bootstrap or model-derived)
- Full reference section generation
- Software version extraction (not hardcoding)
- Audit trail with prompt + model + token-usage logged
- PBPK/PK narrative bundled into the §2.6 sections for drug runs
- QC gate verdict embedded in the report
- Reproducibility appendix (workflow def + container digests)

---

## 6. Fixes applied in this audit

Five surgical fixes covering the most actionable issues. All keep the
existing call-site signature and behavior — only the missing wiring or
incorrect logic is patched.

1. **`workflow.resumed` now fires.** After a successful upstream
   resume, `routes.ts:/api/workflows/runs/:id/resume` invokes
   `sseManager.injectRawEvent` directly (in-process, same effect as
   the Python `/internal/sse-inject` POST) so the chat thread shows
   the resume. Closes D-WS-3. (`workflow.phase_failed` was reported
   as a gap by the survey but is actually wired at
   `nextflow_executor.py:1671` — no fix needed; doc corrected.)

2. **CryoSPARC version unhardcoded.** Report generator reads the
   actual version from the workflow definition / execution metadata;
   falls back to the legacy string only if nothing is provided.
   Closes D-AR-1.

3. **Empty-compound ADMET no longer emits `Infinity`.** Defensive
   guard converts `Math.min(...empty)` and `Math.max(...empty)` to
   `null` and the prompt now receives `"no compounds assessed"`
   instead of `Infinity`. Closes D-AR-2.

4. **JSON fence stripping made tolerant of trailing whitespace.**
   Regex updated to match `^\`\`\`json\s*` and `\s*\`\`\`\s*$` so
   trailing newlines after the closing fence no longer break
   JSON.parse and discard the entire structured analysis. Closes
   D-AR-5.

5. **Negation-aware ADMET follow-up suggestion.** The proactive
   hERG-liability suggestion now checks that the trigger phrase is
   not negated ("not < 1 µM" no longer triggers). Closes D-AR-6.

See companion commit for the diffs.

---

## 7. Quick map — surface to file

| User-visible surface | Frontend component | Backend file | Producer |
|---|---|---|---|
| 🔹 italic progress line | `chat-message.tsx:188-211` | `workflow_chat_narrator.py:177` | static templates |
| Plan checklist (sandbox only) | `research_agent_v2/src/PlanChecklist.jsx` | — | mock SSE |
| Right-panel phase cards | `nextflow-workflow-viewer.tsx` | `nextflow_executor.py:1636+` | trace parser |
| Step output file list | `output-panel.tsx`, `step-output-preview.tsx` | `routes.ts:9217` | fallback chain (S3/disk/proxy) |
| Density-map viewer | `viewers/density-map-viewer.tsx` | `routes.ts:9389` | streamed ArrayBuffer |
| Findings card | `findings-card.tsx` | `routes.ts:10080` | Claude Sonnet 4.6 |
| Methods report download | export dialog | `routes.ts:4207` | Claude Sonnet 4.5 + pandoc |
| AI Analyze button | `ai-analysis-panel.tsx` | `routes.ts:9883` | Claude Sonnet 4.6 |
| Disambiguation card | `workflow-disambiguation-card.tsx` | `ai_assistant.py:2941` | search ranker |
| AutoLoop param diff | `auto-loop-panel.tsx` | `nextflow_executor.py:3347` + qc monitor | rule engine |
