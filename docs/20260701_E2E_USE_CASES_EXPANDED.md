# BioMate E2E Use Cases — Expanded Test Suite
**Date:** 2026-07-01  
**Branch:** integration/next-phase  
**Audience:** QA tester implementing Playwright tests against the live dev stack

---

## Infrastructure Requirements

All tests run against `http://localhost:5000` (Node.js frontend) which proxies
to `http://localhost:8081` (Galaxy Python backend).

**Galaxy backend must be started with:**
```bash
source /Users/kky/biomate/frontend/.env
cd /Users/kky/biomate/backend
export BILLING_DEV_MODE=true
export ANTHROPIC_API_KEY        # from frontend/.env
export GOOGLE_API_KEY           # from frontend/.env
unset BILLING_INTERNAL_KEY      # CRITICAL — must be unset; "dev-insecure-key" fallback
nohup .venv/bin/gunicorn 'galaxy.webapps.galaxy.fast_factory:factory()' \
  --timeout 300 --pythonpath lib \
  -k uvicorn.workers.UvicornWorker \
  -b 127.0.0.1:8081 --workers 1 --log-level warning \
  > /tmp/galaxy-backend.log 2>&1 &
```

**Verify before running any test:**
```bash
# Node.js app responds
curl -s http://localhost:5000/api/version | jq .version

# Galaxy backend responds and accepts provisioning with dev key
curl -s -X POST http://localhost:8081/internal/users/provision \
  -H "X-Internal-Key: dev-insecure-key" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"smoke","email":"smoke@test.com"}' | jq .ok
# expect: true
```

**Fixture account (single account for all tests):**
```
Email:    lifeifei163361@163.com
Password: WpmFixture!2026  (from E2E_FIXTURE_PASSWORD env var)
Token:    biomate-e2e-bypass-token-dev-only  (X-E2E-Test-Token header)
```

**Base imports for every test file:**
```typescript
import { test, expect, type Page } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
import { waitForResponseComplete } from "./helpers.js";

const LLM_TIMEOUT = 90_000;   // 90 s — workflow LLM calls take 30–90 s
test.setTimeout(20 * 60_000); // 20 min per test file
```

---

## Part A — Chat SSE Stream Protocol

### A.1 Complete SSE event sequence

Every call to `POST /api/chat/stream` emits events in this order:

```
event: ready
data: {"ok":true}

event: delta           ← 0..N occurrences; streaming text chunks
data: {"text":"..."}

event: tool_event      ← optional; emitted when Claude calls a tool
data: {"type":"tool_call_start"|"tool_call_complete"|"tool_result", ...}

event: workflow_ready  ← only when a workflow was successfully generated
data: { <workflow_ready payload> }

event: needs_input     ← only when prereqs are missing
data: {"missing": ["param_name", ...]}

event: final           ← always present; authoritative terminal payload
data: { <final payload> }

event: done            ← always last
data: {"ok":true|false}
```

On error:
```
event: error
data: {"message":"..."}

event: done
data: {"ok":false}
```

On safety block:
```
event: delta
data: {"text":"<safety message to display>"}

event: complete
data: {"blocked":true,"category":"<safety category>"}
```

**Rule:** A test must read events until `done` is received. Do NOT rely on
the TCP connection closing — the server closes it only after `done`.

---

### A.2 `workflow_ready` event payload schema

```typescript
interface WorkflowReadyPayload {
  workflow_name:  string;   // e.g. "nf-core/differentialabundance" or ""
  workflow_id:    string;   // draft id; used in /api/workflow-draft/:id
  workflow_type:  string;   // "nextflow" | "chain" | "galaxy" | ""
  nextflow_path:  string;   // e.g. "nfcore/differentialabundance/main.nf" or ""
  source:         string;   // "catalog" | "generated" | "chain" | ""
  confidence:     number | null;  // 0..100 routing confidence score
  chain_name:     string;   // populated only for chain workflows
  chain_steps:    string[]; // constituent workflow names in a chain
  view_url:       string;   // absolute URL: "http://localhost:5000/..."
}
```

**Assertions a tester should always make on `workflow_ready`:**
```typescript
expect(payload.workflow_name).toBeTruthy();          // non-empty name
expect(payload.workflow_type).toMatch(/nextflow|chain|galaxy/);
expect(payload.view_url).toMatch(/^https?:\/\//);   // valid URL
// At least one of:
expect(payload.nextflow_path || payload.chain_name).toBeTruthy();
```

---

### A.3 `final` event payload schema

```typescript
interface FinalPayload {
  state:        "workflow_ready" | "needs_input" | "workflow_failed" | "chat_only";
  response:     string;   // the assistant's text (what the user sees in the chat)
  workflow?:    {
    workflow_ga?:   { name: string; domain: string; required_params: any[]; optional_params: any[] };
    nextflow_path?: string;
    chain_name?:    string;
    workflow_type?: string;
  };
  metadata: {
    llm_usage: {
      input_tokens:  number;
      output_tokens: number;
    };
    intentType?:       string;  // e.g. "workflow_generation" | "literature_synthesis" | ...
    shouldGenerate?:   boolean;
    workflowGenerated?: boolean;
  };
  error?:   string;  // present when state=workflow_failed
}
```

**State meanings:**
| `state` | Meaning | Panel opens? |
|---------|---------|-------------|
| `workflow_ready` | Workflow found and ready to run | Yes — auto-opens |
| `needs_input` | Missing required params (prereq blocked) | Yes — opens to param editor |
| `workflow_failed` | Galaxy returned error or no match | No |
| `chat_only` | Pure research/text answer | No |

---

### A.4 How to parse the SSE stream in a test

Use `page.evaluate()` (NOT `apiRequestContext.post()`).  
`apiRequestContext` buffers the full body — SSE streams stay open for minutes after the last event. `page.evaluate` runs inside the browser and cancels the reader on `final`:

```typescript
async function parseChatStream(page: Page, message: string, sessionId?: string) {
  if (!page.url().startsWith(BASE_URL)) {
    await page.goto(BASE_URL, { waitUntil: "domcontentloaded" });
  }
  return page.evaluate(
    async ({ baseUrl, message, sessionId }) => {
      const resp = await fetch(`${baseUrl}/api/chat/stream`, {
        method: "POST",
        headers: { Accept: "text/event-stream", "Content-Type": "application/json" },
        body: JSON.stringify({ message, stream: true, sessionId }),
      });
      if (!resp.ok || !resp.body) throw new Error(`chat/stream ${resp.status}`);

      const reader = resp.body.getReader();
      const decoder = new TextDecoder();
      let buf = "", lastEvent = "", deltaText = "";
      const events: string[] = [];
      let finalPayload: any = null, workflowReadyPayload: any = null;
      let hasDelta = false, hasFinal = false, hasWorkflowReady = false;

      const processLine = (line: string) => {
        if (line.startsWith("event: ")) {
          lastEvent = line.slice(7).trim();
          if (!events.includes(lastEvent)) events.push(lastEvent);
          if (lastEvent === "delta")          hasDelta = true;
          if (lastEvent === "final")          hasFinal = true;
          if (lastEvent === "workflow_ready") hasWorkflowReady = true;
        } else if (line.startsWith("data: ")) {
          try {
            const d = JSON.parse(line.slice(6));
            if (lastEvent === "delta" && typeof d.text === "string") deltaText += d.text;
            if (lastEvent === "final")          finalPayload = d;
            if (lastEvent === "workflow_ready") workflowReadyPayload = d;
          } catch {}
        }
      };

      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          buf += decoder.decode(value, { stream: true });
          const lines = buf.split("\n"); buf = lines.pop() ?? "";
          for (const line of lines) processLine(line);
          if (hasFinal) { reader.cancel(); break; }
        }
      } catch { /* cancelled */ }

      return { events, hasDelta, hasFinal, hasWorkflowReady,
               finalPayload, workflowReadyPayload, deltaText };
    },
    { baseUrl: BASE_URL, message, sessionId: sessionId ?? `e2e-${Date.now()}` },
  );
}
```

---

### A.5 Pipeline-run SSE events (separate stream)

After a workflow is launched via the Run button, the frontend opens a second
SSE connection to `/api/sse/:runId` or `/api/sse/invocation/:invocationId`.
These pipeline events are injected by Galaxy Python via
`POST /internal/sse-inject` and are NOT part of the chat stream.

**Pipeline SSE event types** (received on the run SSE connection):

| Event type | When emitted | Payload fields |
|------------|-------------|----------------|
| `chat_progress` | At every workflow lifecycle transition | `kind`, `friendly_message`, `ts`, `technical` |
| `autoloop_gate_results` | After QC gate evaluation | `gateResults`, `suggestions`, `failures`, `phase` |
| `autoloop_update` | When autoloop re-runs with new params | `changes` (param diffs), `iteration` |
| `autoloop_phase_complete` | After an autoloop iteration finishes | `phase`, `passed` |
| `autoloop_escalation` | When autoloop exhausts retries | `reason` |
| `chain_suggestion` | When a follow-on workflow is suggested | `suggestions[]` |
| `cryosparc_progress` | CryoSPARC job progress | `percent`, `message` |

**`chat_progress` kind values** (the `kind` field inside the payload):

| `kind` | Human-readable text shown in chat |
|--------|------------------------------------|
| `workflow.submitted` | "Got it — starting your workflow now." |
| `workflow.uploading_inputs` | "Uploading inputs to S3…" |
| `workflow.queued` | "Your workflow is in the AWS Batch queue." |
| `workflow.running` | "Workflow is running." |
| `workflow.phase_started` | "Step N/M: {name}…" |
| `workflow.phase_completed` | "{name} done." |
| `workflow.phase_failed` | "{name} failed — {reason}." |
| `workflow.qc_gate_warning` | "QC flagged {metric} = {val} (threshold {th})." |
| `workflow.qc_gate_blocked` | "QC blocked on {metric} — adjusting parameters." |
| `workflow.autoloop_started` | "Trying again with {param}={value}." |
| `workflow.completed` | "Workflow finished. N/M steps succeeded." |
| `workflow.failed` | "Workflow stopped — {reason}. Looking into why…" |
| `workflow.cancelled` | "Workflow cancelled by you." |
| `deepagent.start` | "Looking into why your workflow failed…" |
| `deepagent.suggestion` | (from `friendly_message` field) |

**How to listen to pipeline SSE in a test:**
```typescript
// After clicking Run, capture the runId from the panel's data-run-id attribute
// or from the URL, then open the SSE endpoint:
const pipelineEvents: string[] = [];
const sseUrl = `${BASE_URL}/api/sse/${runId}`;
// Use page.evaluate to open and read the pipeline SSE in the browser context
await page.evaluate(async (url) => {
  const es = new EventSource(url, { withCredentials: true });
  es.addEventListener("chat_progress", (e) => {
    const d = JSON.parse(e.data);
    window._pipelineKinds = window._pipelineKinds || [];
    (window as any)._pipelineKinds.push(d.kind);
  });
}, sseUrl);
```

---

## Part B — Workflow Panel: States and DOM Contract

### B.1 Panel anatomy — static `data-testid` map

```
[data-testid="workflow-artifact-panel"]        ← root; invisible until opened
  [data-testid="workflow-overall-status-badge"]   ← top-right; data-status attribute
  [data-testid="button-cancel-workflow-panel"]    ← visible when running
  [data-testid="button-restart-workflow-panel"]   ← visible when completed/failed

  [data-testid="panel-tabs"]
    [data-testid="panel-tab-settings"]    aria-selected="true|false"
    [data-testid="panel-tab-phases"]      aria-selected="true|false"
    [data-testid="panel-tab-after-run"]   aria-selected="true|false"

  ── Settings tab body ──────────────────────────────────────────────
  [data-testid="panel-settings"]
    [data-testid="button-toggle-workflow-settings"]   ← expands param editor
    [data-testid="format-mismatch-warning"]           ← conditional; warn variant
    [data-testid="output-location-section"]
      [data-testid="output-location-default"]         ← radio (default)
      [data-testid="output-location-project"]         ← radio (project)
      [data-testid="output-location-user-s3"]         ← radio (custom S3)
      [data-testid="output-location-user-s3-uri"]     ← text input; visible when S3 selected

    ── QC gate inline alert (before run, when a prior gate fired) ──
    [data-testid="qc-gate-inline"]                    ← alert.warn
      [data-testid="qc-gate-measured"]                ← measured value (red)
      [data-testid="qc-gate-threshold"]               ← threshold value (green)
      [data-testid="qc-gate-countdown"]               ← countdown timer
      [data-testid="qc-gate-apply"]                   ← "Apply fixes" button
      [data-testid="qc-gate-keep"]                    ← "Keep current" button
      [data-testid="qc-gate-cancel-run"]              ← "Cancel run" button

    ── Prereq checklist (when prereqs missing) ──
    [data-testid="workflow-prereq-checklist"]          ← alert.err
      [data-testid="workflow-prereq-item-{id}"]        ← one per missing item
        [data-testid="prereq-chat-link-{id}"]          ← "Fix in chat" link

    [data-testid="autofix-active-banner"]              ← info alert when autofix running
    [data-testid="execution-triage-panel"]             ← err alert when failed + diagnosis
      [data-testid="button-error-fix-chat"]            ← "Fix in chat" CTA
    [data-testid="workflow-step-controls-hint"]        ← hint bar

    ── Run button (settings tab footer) ──────────────────────────────
    [data-testid="button-run-workflow-panel"]
      data-required-unfilled="N"    ← N=0 means enabled; N>0 means blocked

  ── Phases tab body ────────────────────────────────────────────────
  [data-testid="panel-phases"]
    [data-testid="phase-group-{key}"]   data-status="pending|running|completed|failed"
      [data-testid="button-run-phase-{key}"]
      [data-testid="phase-params-toggle-{key}"]

      [data-testid="phase-card-{step.id}"]   data-status="pending|running|completed|failed"
        [data-testid="phase-step-advisory-{step.id}"]
        [data-testid="button-run-step-{step.id}"]
        [data-testid="phase-card-preview-btn-{filename}"]   ← per output file
        [data-testid="phase-card-download-btn-{filename}"]  ← per output file

      ── QC Gate block (below phase steps) ──
      [data-testid="qc-edit-toggle-{key}"]              ← opens threshold editor
      [data-testid="autoloop-toggle-{key}"]             ← aria-checked="true|false"
      [data-testid="button-stop-phase-{key}"]

  ── After-run tab body ─────────────────────────────────────────────
  [data-testid="panel-after-run"]
    [data-testid="workflow-completion-banner"]          ← alert.ok
    [data-testid="qc-report-panel"]
    [data-testid="run-metrics-strip"]
      [data-testid="run-metric-duration"]
        [data-testid="run-metric-duration-value"]
      [data-testid="run-metric-started-at"]
      [data-testid="run-metric-completed-at"]
      [data-testid="run-metric-per-step-costs"]
    [data-testid="button-view-results-link"]
    [data-testid="button-download-all-workflow-panel"]  ← "Download all outputs"
    [data-testid="button-analyze-results"]
    [data-testid="button-download-methods-report"]
    [data-testid="button-download-qc-audit"]
    [data-testid="ai-analysis-panel"]                   ← findings card
    [data-testid="download-commands-panel"]

  ── Action bar (running state; bottom of panel) ────────────────────
  [data-testid="panel-action-bar"]   data-status="running|paused"
    [data-testid="panel-action-pause"]
    [data-testid="panel-action-stop"]
    [data-testid="panel-action-resume"]  ← only visible when data-status="paused"
```

---

### B.2 Panel state machine

```
                   ┌─────────────────────────────────────┐
                   ▼                                     │
              ┌─────────┐                                │
  (load)───►  │  idle   │  data-status="idle"            │
              └────┬────┘  Run button enabled            │
                   │                                     │
           [click Run]                                   │
                   │                                     │
                   ▼                                     │
           ┌──────────────┐                             │
           │   running    │  data-status="running"       │
           │              │  action-bar visible           │
           │              │  phases tab auto-selected     │
           └──┬───────┬───┘  cancel button visible       │
              │       │                                  │
       [step  │   [stop/      [all steps done]           │
       fails] │   cancel]           │                    │
              │       │             ▼                    │
              │       │      ┌────────────┐             │
              │       │      │ completed  │ ─────────────┘
              ▼       │      └────────────┘  Run again → idle
        ┌──────────┐  │      data-status="completed"
        │  failed  │  │      after-run tab auto-selected
        └────┬─────┘  │      Download all button visible
             │        │
             │   ┌────┴──────┐
             │   │ cancelled │  data-status="cancelled"
             │   └───────────┘
             │
        [click Restart]
             │
             └──────►  idle
```

**Key data-status values for `[data-testid="workflow-overall-status-badge"]`:**

| Value | Panel state | Footer button text | Tabs active |
|-------|-------------|-------------------|-------------|
| `idle` | Before first run | "Run" | Settings (selected) |
| `running` | Run in progress | "Running…" (disabled) | Phases (auto-selected) |
| `completed` | Run finished OK | "Run again" | After-run (auto-selected) |
| `failed` | Run failed | "Restart" | Phases (stays selected) |
| `cancelled` | User stopped | "Run" | Settings |

---

### B.3 Phase card states

Each `[data-testid="phase-card-{step.id}"]` carries `data-status`:

| `data-status` | Visual | Meaning |
|---------------|--------|---------|
| `pending` | Grey dot | Not yet started |
| `running` | Blue spinner | Currently executing |
| `completed` | Green check | Finished successfully |
| `failed` | Red X | Exited non-zero |

Phase groups (`[data-testid="phase-group-{key}"]`) derive their status from
the worst-case child step: if any step is `running`, group is `running`; if
any is `failed`, group is `failed`; if all are `completed`, group is `completed`.

---

### B.4 Chat message DOM contract

Chat messages are rendered by `chat-message.tsx`. Key selectors:

```typescript
// Latest assistant message (changes as new messages arrive)
page.locator('[data-is-latest-assistant="true"]')

// Specific message by id
page.locator('[data-testid="chat-message-{messageId}"]')

// Workflow card anchor (present when workflow was returned)
page.locator('[data-testid^="workflow-artifact-anchor-"]').first()

// wf-chip (compact card shown when panel is open in same session)
page.locator('.wf-chip')          // the chip container
page.locator('span.chip-ok')      // "In panel" badge — only visible when panel open

// Action buttons after AI message
page.locator('[data-testid="button-copy-response-icon"]')
page.locator('[data-testid="button-regenerate-message-icon"]')
page.locator('[data-testid="button-save-response"]')
page.locator('[data-testid="button-download-outputs-icon"]')

// IND report chip (drug development flows)
page.locator('[data-testid="ind-report-handoff-chip"]')
```

**"In panel" badge logic:** `span.chip-ok` contains "In panel" text ONLY when
`[data-testid="workflow-artifact-panel"]` is currently visible AND the chip's
workflow matches the workflow in the panel. If the panel is closed, the chip
shows a "View" button instead.

---

### B.5 Helper functions every test needs

```typescript
/** Wait until the panel's overall badge reaches a terminal state. */
async function waitForPanelTerminal(page: Page, timeoutMs = 10 * 60_000) {
  await page.waitForFunction(
    () => {
      const s = document.querySelector('[data-testid="workflow-overall-status-badge"]')
                  ?.getAttribute("data-status") ?? "";
      return s === "completed" || s === "failed";
    },
    { timeout: timeoutMs },
  );
}

/** Wait until panel enters running (or skips to terminal). */
async function waitForPanelRunning(page: Page, timeoutMs = 30_000) {
  await page.waitForFunction(
    () => {
      const s = document.querySelector('[data-testid="workflow-overall-status-badge"]')
                  ?.getAttribute("data-status") ?? "";
      return s === "running" || s === "completed" || s === "failed";
    },
    { timeout: timeoutMs },
  );
}

/** Open the panel from a chat message that has a workflow card.
 *  Returns true if panel became visible. */
async function openPanel(page: Page): Promise<boolean> {
  const panel = page.locator('[data-testid="workflow-artifact-panel"]');
  if (await panel.isVisible().catch(() => false)) return true;

  // Try clicking the wf-chip or the workflow anchor card
  const chip = page.locator('[data-testid^="wf-chip-"], .wf-chip').first();
  if (await chip.count() > 0 && await chip.isVisible().catch(() => false)) {
    await chip.click();
  } else {
    const anchor = page.locator('[data-testid^="workflow-artifact-anchor-"]').first();
    if (await anchor.count() > 0) await anchor.click();
  }

  await page.waitForSelector('[data-testid="workflow-artifact-panel"]',
    { state: "visible", timeout: 8_000 }).catch(() => null);
  return panel.isVisible().catch(() => false);
}
```

---

## Part C — Use Cases

Each use case follows this structure:
1. **What it tests** — the system contract being verified
2. **Input** — exact message text or UI actions
3. **Expected SSE sequence** — event names in order, with payload assertions
4. **Expected panel states** — `data-status` values observed in sequence
5. **Screenshots** — checkpoint name + what to capture
6. **Console log assertions** — `console.log` lines the server emits
7. **Pass/fail criteria** — binary assertions that determine the result
8. **Estimated duration**

---

### UC-1 — scRNA-seq 10x count matrix → Seurat/scRNA workflow

**Test ID:** `UC1`  
**File:** `e2e/inline-omics-routing.e2e.ts`

**What it tests:**  
A sparse cell × gene count matrix pasted inline is detected by the
`extractInlineDataWithLLM` regex fallback (≥2 numeric rows → `count_matrix`
populated in `inlineDataMap`), and the Galaxy AI routes to a single-cell
workflow (`nf-core/scrnaseq` or a Seurat-family workflow), NOT a bulk
differential-expression pipeline.

**Input message:**
```
Cluster these single-cell RNA-seq counts from a 10x Chromium run and generate a UMAP:
barcode,CD3D,CD4,CD8A,MS4A1,CD19,GNLY
AAACCTGAGAAGGCCT,45,32,0,0,0,1
AAACCTGAGACAGACC,0,0,38,0,0,0
AAACCTGAGACTTTCG,0,0,0,87,91,0
AAACCTGAGATCACGG,12,8,0,0,0,0
AAACCTGAGCGATAGC,0,0,0,0,0,112
AAACCTGAGCGCTTAT,22,18,0,0,0,0
AAACCTGAGGCTAGCA,0,0,0,74,82,0
AAACCTGAGTCACGAA,1,0,44,0,0,2
```

**Expected SSE sequence:**
```
ready → delta(×N) → workflow_ready → final → done
```

**`workflow_ready` payload assertions:**
```typescript
expect(payload.workflow_name).toBeTruthy();
expect(payload.workflow_type).toBe("nextflow");
// Must NOT be a bulk DE pipeline
const name = payload.workflow_name.toLowerCase();
expect(name).not.toMatch(/differentialabundance|deseq/);
// Should be scRNA-seq family
expect(name).toMatch(/scrna|seurat|scanpy|singlecell|single.cell|sc_rna/);
expect(payload.view_url).toMatch(/^https?:\/\//);
```

**`final` payload assertions:**
```typescript
expect(fp.state).toBe("workflow_ready");
expect(fp.metadata.workflowGenerated).toBe(true);
// Response text mentions clustering or UMAP
expect(fp.response.toLowerCase()).toMatch(/cluster|umap|dimensionality|cell type/);
```

**Screenshots:**
| Name | Content |
|------|---------|
| `UC1_00_new_session.png` | Blank chat composer visible |
| `UC1_01_response_with_card.png` | AI text response + workflow anchor card below |
| `UC1_02_panel_idle.png` | Panel open; `data-status="idle"` on badge |

**Console log assertions** (from Node.js server stdout):
```
[chat] hasInlineData=true      ← must appear
[Routing] workflow_ready       ← must appear; nextflow_path contains scrna/seurat
```

**Pass/fail criteria:**
- `hasWorkflowReady === true`
- `finalPayload.state === "workflow_ready"`
- `workflow_name` does not match `differentialabundance` or `deseq2`
- Panel visible after clicking chip

**Estimated duration:** 2–3 min

---

### UC-2 — Pasted VCF snippet → variant annotation workflow

**Test ID:** `UC2`  
**File:** `e2e/inline-omics-routing.e2e.ts`

**What it tests:**  
VCF-format lines pasted inline (tab-separated, with numeric QUAL/AF columns)
are detected by the tabular fallback → `count_matrix` in `inlineDataMap` →
`hasInlineData = true` → Galaxy routes to a variant annotation or GWAS workflow.
The `file_path` regex must NOT fire (no file:// or s3:// URL present).

**Input message:**
```
Annotate and filter these germline variants for a population study:
#CHROM	POS	ID	REF	ALT	QUAL	AF
1	752566	rs3094315	G	A	60	0.42
1	776546	rs12124819	A	G	55	0.31
1	798959	rs11240777	G	A	71	0.18
1	800007	rs6681049	C	T	80	0.09
1	838555	rs4970383	C	T	63	0.24
1	846808	rs4475691	C	T	58	0.37
1	854250	rs7537756	A	G	74	0.11
```

**Expected SSE sequence:**
```
ready → delta(×N) → workflow_ready → final → done
```

**`workflow_ready` payload assertions:**
```typescript
expect(payload.workflow_type).toBe("nextflow");
const path = payload.nextflow_path.toLowerCase();
expect(path).toMatch(/sarek|gatk|plink|regenie|variant|annotate|gwas/);
```

**`final` payload assertions:**
```typescript
expect(fp.state).toBe("workflow_ready");
// Response must not ask for data already provided
expect(fp.response).not.toMatch(/please provide|can you share|need.*file|upload.*vcf/i);
```

**Screenshots:**
| Name | Content |
|------|---------|
| `UC2_00_new_session.png` | Blank chat |
| `UC2_01_response_card.png` | Card with variant workflow name visible |
| `UC2_02_panel_params.png` | Panel open; genome_build or input param pre-filled |

**Panel param assertion:**
```typescript
// At least one param in the params strip references genome or VCF
const panelSettings = page.locator('[data-testid="panel-settings"]');
await expect(panelSettings).toBeVisible();
const text = await panelSettings.textContent();
expect(text).toMatch(/genome|build|grch|hg38|input|vcf/i);
```

**Pass/fail criteria:**
- `hasWorkflowReady === true`
- `nextflow_path` matches a variant/GWAS pipeline
- Response does not re-ask for the VCF data

**Estimated duration:** 2–3 min

---

### UC-3 — Multi-compound SMILES → ADMET screen

**Test ID:** `UC3`  
**File:** `e2e/inline-omics-routing.e2e.ts`

**What it tests:**  
Multiple SMILES strings on separate lines are detected by the LLM extractor
(Gemini returns `{"smiles": "..."}` in the `inlineDataMap` JSON) — not by the
tabular regex fallback (SMILES lines don't have ≥2 numeric columns).
`hasInlineData = true` because `Object.keys(inlineDataMap).length > 0`.
The workflow routes to an ADMET or drug-property pipeline.

**Input message:**
```
Run full ADMET profiling on these five drug candidates and flag any hERG or CYP3A4 liabilities:
CC(=O)Oc1ccccc1C(=O)O
CN1CCC[C@H]1c2cccnc2
CC12CCC3C(C1CCC2O)CCC4=CC(=O)CCC34C
c1ccc2c(c1)cc1ccccc1n2
COc1cc2c(cc1OC)C(=O)c1ccccc1C2=O
```

**Expected SSE sequence:**
```
ready → delta(×N) → workflow_ready → final → done
```

**`workflow_ready` payload assertions:**
```typescript
expect(payload.workflow_type).toBe("nextflow");
const name = (payload.workflow_name + " " + payload.nextflow_path).toLowerCase();
expect(name).toMatch(/admet|drug|pkpd|tox|property|screening/);
```

**`final` payload assertions:**
```typescript
expect(fp.state).toBe("workflow_ready");
// Must mention ADMET, hERG, or CYP
expect(fp.response.toLowerCase()).toMatch(/admet|herg|cyp|absorption|toxicit/);
```

**Panel SMILES param assertion:**
```typescript
// After opening panel, SMILES value visible in params strip
const settingsText = await page.locator('[data-testid="panel-settings"]').textContent();
// One of the SMILES strings should appear
expect(settingsText).toContain("CC(=O)Oc1ccccc1");
```

**Screenshots:**
| Name | Content |
|------|---------|
| `UC3_00_new_session.png` | Blank chat |
| `UC3_01_card.png` | ADMET workflow card below AI text |
| `UC3_02_panel_smiles_param.png` | Panel open; SMILES visible in params strip |

**Pass/fail criteria:**
- LLM extractor detected `smiles` key (not the tabular regex)
- Workflow routes to ADMET family
- SMILES value visible in params strip without user having to re-enter it

**Estimated duration:** 2–3 min

---

### UC-4 — Literature synthesis with citations (PaperQA)

**Test ID:** `UC4`  
**File:** `e2e/research-paperqa-flows.e2e.ts`

**What it tests:**  
A multi-paper literature-synthesis question triggers the research agent
(PaperQA), which returns a response with numbered citation markers
(`[1]`, `[2]`, etc.). The `final.state` must be `chat_only` (no
`workflow_ready`). The rendered DOM contains `<sup>` or inline citation
elements.

**Input message:**
```
Summarise the current evidence on KRAS G12C inhibitors in non-small cell 
lung cancer: mechanism of action, clinical trial outcomes (overall response 
rate, PFS), and known resistance mechanisms. Cite at least 3 primary papers.
```

**Expected SSE sequence:**
```
ready → delta(×N) → final → done
```
`workflow_ready` must NOT appear.

**`final` payload assertions:**
```typescript
expect(fp.state).toBe("chat_only");
expect(fp.response.length).toBeGreaterThan(500);
// Must mention KRAS and resistance
expect(fp.response.toLowerCase()).toMatch(/kras|sotorasib|adagrasib/);
expect(fp.response.toLowerCase()).toMatch(/resist|bypass|feedback/);
// Citation markers in text
expect(fp.response).toMatch(/\[\d+\]/);
```

**DOM assertions:**
```typescript
// Response text in the page
const responseText = await page.locator('[data-is-latest-assistant="true"]').textContent({ timeout: LLM_TIMEOUT });
expect(responseText?.length ?? 0).toBeGreaterThan(500);

// At least 2 citation references rendered
// (either <sup> tags or [N] patterns in text)
const supCount = await page.locator('[data-is-latest-assistant="true"] sup').count();
const textCitations = (responseText?.match(/\[\d+\]/g) ?? []).length;
expect(supCount + textCitations, "at least 2 citation markers").toBeGreaterThanOrEqual(2);

// No workflow card below the message
expect(await page.locator('[data-testid^="workflow-artifact-anchor-"]').count()).toBe(0);
```

**Screenshots:**
| Name | Content |
|------|---------|
| `UC4_00_new_session.png` | Blank chat |
| `UC4_01_response.png` | Full response with paragraphs + citation markers |
| `UC4_02_citations_closeup.png` | Cropped bottom showing `[1] Author...` block |

**Pass/fail criteria:**
- `finalPayload.state === "chat_only"`
- Response > 500 chars
- At least 2 citation markers (`[N]` or `<sup>`) in rendered DOM
- No workflow card present

**Estimated duration:** 2–3 min

---

### UC-5 — Two-turn protocol guidance (context maintained)

**Test ID:** `UC5`  
**File:** `e2e/research-paperqa-flows.e2e.ts`

**What it tests:**  
Two-turn conversation in the same session. Turn 1 asks for a protocol;
turn 2 asks a follow-up about a specific step. The follow-up response must
reference context from turn 1 (proving session context is maintained).
Both turns must be `chat_only`.

**Turn 1 message:**
```
What is the recommended protocol for preparing a stranded total RNA-seq 
library from FFPE tissue samples?
```

**Turn 2 message (same session, after turn 1 response appears):**
```
In step 3 of that protocol, what is the purpose of the rRNA depletion step 
and what reagents are typically used?
```

**Expected SSE sequence per turn:**
```
Turn 1: ready → delta(×N) → final → done   (no workflow_ready)
Turn 2: ready → delta(×N) → final → done   (no workflow_ready)
```

**Turn 2 response assertions:**
```typescript
const turn2Text = await page.locator('[data-is-latest-assistant="true"]')
  .textContent({ timeout: LLM_TIMEOUT });
// Must mention rRNA or ribosomal (from context of turn 1)
expect(turn2Text?.toLowerCase()).toMatch(/rrna|ribosomal/);
// Must mention a reagent (RNase H, RiboCop, RiboZero, etc.)
expect(turn2Text?.toLowerCase()).toMatch(/ribocop|ribozero|rnase h|probe|hybridiz/i);
```

**DOM assertions:**
```typescript
// After both turns, 2 assistant messages present
const assistantMsgs = await page.locator('[data-is-latest-assistant]').count();
expect(assistantMsgs).toBeGreaterThanOrEqual(2);

// No workflow cards in either turn
expect(await page.locator('[data-testid^="workflow-artifact-anchor-"]').count()).toBe(0);
```

**Screenshots:**
| Name | Content |
|------|---------|
| `UC5_00_session_start.png` | Blank chat |
| `UC5_01_turn1_response.png` | First AI response (protocol text) |
| `UC5_02_turn2_submitted.png` | Second message visible in composer |
| `UC5_03_turn2_response.png` | Both messages + both responses in thread |

**Pass/fail criteria:**
- Both turns return `chat_only`
- Turn 2 response contains rRNA/ribosomal (context from turn 1)
- Exactly 0 workflow cards

**Estimated duration:** 3–4 min (2 LLM calls)

---

### UC-6 — Full panel lifecycle: idle → running → completed

**Test ID:** `UC6`  
**File:** `e2e/panel-state-machine.e2e.ts`

**What it tests:**  
The entire workflow panel state machine in sequence, verified via
`data-status` attribute polling. A real Nextflow run is triggered and the
test observes `pending` → `running` → `completed` transitions in real time
via SSE (not mocked).

**Setup:** Send the DESeq2 inline message to get `nf-core/differentialabundance`.

**Step-by-step verification:**

**Step 1 — Idle state:**
```typescript
const badge = page.locator('[data-testid="workflow-overall-status-badge"]');
// Before Run: badge is idle (may be hidden, but attribute is "idle")
const idleStatus = await badge.getAttribute("data-status");
expect(idleStatus).toBe("idle");

// Settings tab selected
await expect(page.locator('[data-testid="panel-tab-settings"]'))
  .toHaveAttribute("aria-selected", "true");

// Run button enabled (no required params missing)
const runBtn = page.locator('[data-testid="button-run-workflow-panel"]');
await expect(runBtn).toBeEnabled();
expect(await runBtn.getAttribute("data-required-unfilled")).toBe("0");
```

**Step 2 — Click Run:**
```typescript
await runBtn.click();
await ss(page, "UC6_01_run_clicked");
```

**Step 3 — Running state (within 30 s):**
```typescript
await waitForPanelRunning(page, 30_000);
const runStatus = await badge.getAttribute("data-status");
// Accept "running" or quick transition to "completed"
expect(["running", "completed"]).toContain(runStatus);

if (runStatus === "running") {
  // Phases tab auto-selected
  await expect(page.locator('[data-testid="panel-tab-phases"]'))
    .toHaveAttribute("aria-selected", "true");

  // Action bar visible
  await expect(page.locator('[data-testid="panel-action-bar"]')).toBeVisible();
  await expect(page.locator('[data-testid="panel-action-stop"]')).toBeVisible();

  // Cancel button in header visible
  await expect(page.locator('[data-testid="button-cancel-workflow-panel"]')).toBeVisible();

  // At least one phase card exists
  const phaseCards = page.locator('[data-testid^="phase-card-"]');
  expect(await phaseCards.count()).toBeGreaterThan(0);

  // Wait for at least one phase card to reach "running"
  await page.waitForFunction(
    () => [...document.querySelectorAll('[data-testid^="phase-card-"]')]
           .some(c => c.getAttribute("data-status") === "running"),
    { timeout: 60_000 }
  );
  await ss(page, "UC6_02_phase_running");
}
```

**Step 4 — Terminal state (up to 10 min):**
```typescript
await waitForPanelTerminal(page, 10 * 60_000);
const terminal = await badge.getAttribute("data-status");
expect(["completed", "failed"]).toContain(terminal);
await ss(page, "UC6_03_terminal");

if (terminal === "completed") {
  // After-run tab auto-selected
  await expect(page.locator('[data-testid="panel-tab-after-run"]'))
    .toHaveAttribute("aria-selected", "true");

  // Download button visible
  await expect(page.locator('[data-testid="button-download-all-workflow-panel"]')).toBeVisible();

  // Metrics strip visible
  await expect(page.locator('[data-testid="run-metrics-strip"]')).toBeVisible();
  const durationVal = await page.locator('[data-testid="run-metric-duration-value"]').textContent();
  expect(durationVal?.trim()).toBeTruthy();

  // AI findings panel visible
  await expect(page.locator('[data-testid="ai-analysis-panel"]')).toBeVisible();
}
```

**Screenshots:**
| Name | Content |
|------|---------|
| `UC6_00_panel_idle.png` | Badge `data-status="idle"`, Run button enabled |
| `UC6_01_run_clicked.png` | Immediately after clicking Run |
| `UC6_02_phase_running.png` | At least one phase-card `data-status="running"` |
| `UC6_03_terminal.png` | `completed` or `failed` state |
| `UC6_04_after_run_tab.png` | After-run tab; metrics + download button visible |

**Pass/fail criteria:**
- `badge.data-status` transitions: `idle` → `running` → `completed|failed`
- At least one phase card observed in `running` state
- After-run tab visible on completion with download button

**Estimated duration:** 8–12 min (AWS Batch dependent)

---

### UC-7 — Failed run → "Restart" → panel resets to idle

**Test ID:** `UC7`  
**File:** `e2e/panel-state-machine.e2e.ts`

**What it tests:**  
The `failed` state renders correctly (badge, phase cards, triage panel) and
the "Restart" button in the header resets the panel to `idle` so the user
can re-run with corrected params.

**Setup:** Open panel, set `input` param to `s3://nonexistent-bucket/invalid.csv`
to force CHECK_SAMPLESHEET to fail within seconds.

**Verification sequence:**

```typescript
// Set invalid param via the param editor
const toggleBtn = page.locator('[data-testid="button-toggle-workflow-settings"]');
await toggleBtn.click();
// Find and fill input_paths or samplesheet param
const inputParam = page.locator('[data-param-name="input"] input, [data-param-name="samplesheet"] input').first();
await inputParam.fill("s3://nonexistent-bucket/invalid.csv");

// Run
const runBtn = page.locator('[data-testid="button-run-workflow-panel"]');
await runBtn.click();
await ss(page, "UC7_01_invalid_run_clicked");

// Wait for failure (samplesheet check fails fast, usually < 2 min)
await waitForPanelTerminal(page, 3 * 60_000);
const terminal = await badge.getAttribute("data-status");
expect(terminal).toBe("failed");
await ss(page, "UC7_02_panel_failed");

// Triage panel visible
await expect(page.locator('[data-testid="execution-triage-panel"]')).toBeVisible();
await expect(page.locator('[data-testid="button-error-fix-chat"]')).toBeVisible();

// Restart button (header, not footer) visible
const restartBtn = page.locator('[data-testid="button-restart-workflow-panel"]');
await expect(restartBtn).toBeVisible();

// Phase card in failed state
const failedCard = page.locator('[data-testid^="phase-card-"][data-status="failed"]');
expect(await failedCard.count()).toBeGreaterThan(0);

// Click Restart
await restartBtn.click();
await ss(page, "UC7_03_after_restart");

// Panel resets to idle within 5 s
await page.waitForFunction(
  () => document.querySelector('[data-testid="workflow-overall-status-badge"]')
          ?.getAttribute("data-status") === "idle",
  { timeout: 5_000 }
);

// Settings tab re-selected
await expect(page.locator('[data-testid="panel-tab-settings"]'))
  .toHaveAttribute("aria-selected", "true");
```

**Screenshots:**
| Name | Content |
|------|---------|
| `UC7_00_panel_idle_invalid_param.png` | Params editor showing invalid S3 path |
| `UC7_01_invalid_run_clicked.png` | After click; running state begins |
| `UC7_02_panel_failed.png` | `data-status="failed"` badge; triage panel |
| `UC7_03_after_restart.png` | Panel reset to `idle` |

**Pass/fail criteria:**
- Badge reaches `failed` (not `completed`)
- `[data-testid="execution-triage-panel"]` visible
- `[data-testid="button-restart-workflow-panel"]` visible when failed
- Badge returns to `idle` after Restart click

**Estimated duration:** 3–5 min

---

### UC-8 — QC gate fires → displays measured vs threshold → auto-loop card

**Test ID:** `UC8`  
**File:** `e2e/panel-state-machine.e2e.ts`

**What it tests:**  
After a completed ADMET run that produces a hERG-active compound,
the `qc-gate-inline` alert appears in the settings tab with correct color
coding (red measured, green threshold) and the autoloop panel renders
the remediation card.

**What triggers the QC gate:**  
- Run ADMET pipeline with astemizole SMILES (known hERG liability)
- Set hERG IC50 threshold to 10 µM via the QC settings
- The measured value will exceed the threshold → gate fires

**Input SMILES:**
```
O=C(Nc1ccc(N2CCC(Cc3ccc(OC)cc3)CC2)cc1)c1ccc(F)cc1
```
(Astemizole — known hERG blocker, IC50 ≈ 0.9 nM)

**Verification sequence:**

```typescript
// After completed run, navigate to Settings tab
await page.locator('[data-testid="panel-tab-settings"]').click();

// QC gate inline alert must appear
const qcAlert = page.locator('[data-testid="qc-gate-inline"]');
await expect(qcAlert).toBeVisible({ timeout: 10_000 });
await ss(page, "UC8_01_qc_gate_visible");

// Two numeric values present
const measured = page.locator('[data-testid="qc-gate-measured"]');
const threshold = page.locator('[data-testid="qc-gate-threshold"]');
await expect(measured).toBeVisible();
await expect(threshold).toBeVisible();

// Measured value is red-colored, threshold is green
const measuredColor = await measured.evaluate(
  el => getComputedStyle(el).color
);
// Red: rgb(220, 38, 38) = var(--red)
expect(measuredColor).toMatch(/220|38/);

const measuredText = await measured.textContent();
const thresholdText = await threshold.textContent();
console.log(`[UC8] Measured: ${measuredText}, Threshold: ${thresholdText}`);
expect(Number(measuredText?.trim())).toBeGreaterThan(
  Number(thresholdText?.trim())
); // measured > threshold = gate fires

// Countdown timer present
await expect(page.locator('[data-testid="qc-gate-countdown"]')).toBeVisible();

// Action buttons
await expect(page.locator('[data-testid="qc-gate-apply"]')).toBeVisible();
await expect(page.locator('[data-testid="qc-gate-keep"]')).toBeVisible();
await expect(page.locator('[data-testid="qc-gate-cancel-run"]')).toBeVisible();
await ss(page, "UC8_02_qc_gate_detail");

// Autoloop toggle for this phase
const autoloopToggle = page.locator('[data-testid^="autoloop-toggle-"]').first();
await expect(autoloopToggle).toBeVisible();
const autoloopOn = await autoloopToggle.getAttribute("aria-checked");
console.log(`[UC8] Autoloop enabled: ${autoloopOn}`);
```

**Screenshots:**
| Name | Content |
|------|---------|
| `UC8_00_panel_idle.png` | ADMET panel before run |
| `UC8_01_qc_gate_visible.png` | After run; QC gate alert visible in settings tab |
| `UC8_02_qc_gate_detail.png` | Closeup: measured (red) vs threshold (green) + buttons |
| `UC8_03_autoloop_toggle.png` | Autoloop toggle for this phase |

**Pass/fail criteria:**
- `[data-testid="qc-gate-inline"]` visible after ADMET run
- `[data-testid="qc-gate-measured"]` and `[data-testid="qc-gate-threshold"]` both present
- Measured numeric value > threshold numeric value
- "Apply fixes", "Keep current", "Cancel run" buttons all visible

**Estimated duration:** 10–15 min (ADMET pipeline)

---

### UC-9 — Informational tangent does not destroy workflow context

**Test ID:** `UC9`  
**File:** `e2e/multiturn-workflow-context.e2e.ts`

**What it tests:**  
The `isLikelyInformationalTangent` gate in galaxy-assistant.ts detects
a short research question when an active workflow card exists, pushes the
context stack, and returns `chat_only`. When the user returns to the
workflow, only 1 workflow card exists (not 2).

**Step sequence:**

```typescript
// Turn 1: send DESeq2 message → get workflow card
await sendMessage(page, "Run DESeq2 on this count matrix — 3 ctrl vs 3 treated:\n" +
  "gene,ctrl1,ctrl2,ctrl3,treat1,treat2,treat3\n" +
  "GENE1,100,120,110,200,210,195\n" +
  "GENE2,50,55,48,52,49,51\n" +
  "GENE3,30,28,32,90,88,95");
await waitForResponseComplete(page, LLM_TIMEOUT);
await ss(page, "UC9_00_workflow_card_present");

// Confirm workflow card present
await expect(page.locator('[data-testid^="workflow-artifact-anchor-"]').first())
  .toBeVisible();
const cardCountAfterT1 = await page.locator('[data-testid^="workflow-artifact-anchor-"]').count();
expect(cardCountAfterT1).toBe(1);

// Turn 2: informational tangent (short question, no data)
await sendMessage(page, "What statistical test does DESeq2 use internally?");
await waitForResponseComplete(page, LLM_TIMEOUT);
await ss(page, "UC9_01_tangent_response");

// After tangent: still exactly 1 workflow card
const cardCountAfterT2 = await page.locator('[data-testid^="workflow-artifact-anchor-"]').count();
expect(cardCountAfterT2).toBe(1);

// wf-chip still present (workflow context intact)
await expect(page.locator('.wf-chip').first()).toBeVisible();

// Turn 3: return to workflow
await sendMessage(page, "OK, run the DESeq2 analysis now.");
await waitForResponseComplete(page, LLM_TIMEOUT);
await ss(page, "UC9_02_return_to_workflow");

// Panel Run button still active (or panel auto-opens)
const panel = page.locator('[data-testid="workflow-artifact-panel"]');
const panelVisible = await panel.isVisible().catch(() => false);
if (!panelVisible) await openPanel(page);
const runBtn = page.locator('[data-testid="button-run-workflow-panel"]');
await expect(runBtn).toBeVisible();
```

**Screenshots:**
| Name | Content |
|------|---------|
| `UC9_00_workflow_card_present.png` | Turn 1 response with workflow card |
| `UC9_01_tangent_response.png` | Turn 2 chat-only response; still 1 card in thread |
| `UC9_02_return_to_workflow.png` | After turn 3; panel accessible |

**Pass/fail criteria:**
- After turn 2: exactly 1 workflow card (not 2)
- `.wf-chip` visible after the tangent
- Panel Run button accessible after turn 3

**Estimated duration:** 4–5 min (3 LLM calls)

---

### UC-10 — Parameter override round-trip

**Test ID:** `UC10`  
**File:** `e2e/multiturn-workflow-context.e2e.ts`

**What it tests:**  
Opening the params editor, changing `study_type` from default to `atacseq`,
and applying the change causes the params strip outside the editor to reflect
the updated value.

```typescript
// Open panel (after DESeq2/differentialabundance workflow card)
await openPanel(page);
await ss(page, "UC10_00_panel_params_default");

// Open param editor
const toggleBtn = page.locator('[data-testid="button-toggle-workflow-settings"]');
await expect(toggleBtn).toBeVisible();
await toggleBtn.click();
await ss(page, "UC10_01_params_editor_open");

// Find study_type select
const studyTypeSelect = page.locator(
  '[data-param-name="study_type"] select, ' +
  '[data-param-name="study_type"] [role="combobox"]'
).first();
await expect(studyTypeSelect).toBeVisible();

// Change value to atacseq
await studyTypeSelect.selectOption("atacseq");
// If it's a custom combobox: await studyTypeSelect.click(); then click option
await ss(page, "UC10_02_study_type_changed");

// Apply / Save (look for an Apply button or the change may auto-save)
const applyBtn = page.locator('button:has-text("Apply"), button:has-text("Save")').first();
if (await applyBtn.count() > 0) await applyBtn.click();

// Params strip outside editor should reflect the new value
const settingsBody = page.locator('[data-testid="panel-settings"]');
await expect(settingsBody).toContainText("atacseq", { timeout: 5_000 });
await ss(page, "UC10_03_params_strip_updated");
```

**Screenshots:**
| Name | Content |
|------|---------|
| `UC10_00_panel_params_default.png` | Panel with default params |
| `UC10_01_params_editor_open.png` | Editor expanded after toggle click |
| `UC10_02_study_type_changed.png` | `atacseq` selected in dropdown |
| `UC10_03_params_strip_updated.png` | Params strip shows `atacseq` |

**Pass/fail criteria:**
- Editor visible after toggle click
- Select accepts `atacseq`
- Settings panel text contains `atacseq` after apply

**Estimated duration:** 2–3 min

---

### UC-11 — Page reload preserves messages and workflow card

**Test ID:** `UC11`  
**File:** `e2e/session-auth-recovery.e2e.ts`

**What it tests:**  
After sending a DESeq2 message and opening the workflow panel, `page.reload()`
restores the session — messages and workflow card re-render from DB persistence,
and the panel is re-openable with the same workflow.

```typescript
// Send message, open panel, confirm "In panel" badge
await sendMessage(page, DESeq2_MESSAGE);
await waitForResponseComplete(page, LLM_TIMEOUT);
await openPanel(page);
await expect(page.locator('span.chip-ok')).toHaveText(/In panel/i);
await ss(page, "UC11_00_panel_open_before_reload");

// Note current URL (contains sessionId)
const urlBefore = page.url();

// Full page reload
await page.reload({ waitUntil: "networkidle" });
await ss(page, "UC11_01_after_reload");

// Messages still present
const assistantMsgs = await page.locator('[data-is-latest-assistant]').count();
expect(assistantMsgs).toBeGreaterThanOrEqual(1);

// Workflow card still present
await expect(page.locator('[data-testid^="workflow-artifact-anchor-"]').first())
  .toBeVisible({ timeout: 10_000 });

// Panel re-openable
const reopened = await openPanel(page);
expect(reopened).toBe(true);

// Same workflow (panel-settings content doesn't change)
const panelText = await page.locator('[data-testid="panel-settings"]').textContent();
expect(panelText).toMatch(/differentialabundance|deseq/i);
await ss(page, "UC11_02_panel_reopened");
```

**Screenshots:**
| Name | Content |
|------|---------|
| `UC11_00_panel_open_before_reload.png` | "In panel" badge visible |
| `UC11_01_after_reload.png` | Page after reload; messages visible |
| `UC11_02_panel_reopened.png` | Panel reopened; same workflow |

**Pass/fail criteria:**
- Messages visible after reload without re-sending
- Workflow card clickable after reload
- Panel opens to same workflow (same `nextflow_path`)

**Estimated duration:** 2–3 min

---

### UC-12 — Expired token redirects to login; re-login restores session

**Test ID:** `UC12`  
**File:** `e2e/session-auth-recovery.e2e.ts`

```typescript
// Send one message to establish session
await sendMessage(page, "What is the p-value threshold in RNA-seq?");
await waitForResponseComplete(page, LLM_TIMEOUT);
const sessionUrl = page.url(); // e.g. http://localhost:5000/chat/abc123

// Clear auth cookie to simulate expiry
await page.context().clearCookies();
await ss(page, "UC12_00_before_cookie_clear");

// Reload — should redirect to login
await page.reload({ waitUntil: "networkidle" });
await ss(page, "UC12_01_after_cookie_clear");

// Should be on login page or unauthenticated home
const currentUrl = page.url();
expect(currentUrl).toMatch(/login|\/$/);

// Re-authenticate
await loginAsFixture(page);

// Navigate back to session
await page.goto(sessionUrl, { waitUntil: "networkidle" });
await ss(page, "UC12_02_after_relogin");

// Prior message still visible
const msgs = await page.locator('[data-is-latest-assistant]').count();
expect(msgs).toBeGreaterThanOrEqual(1);
```

**Screenshots:**
| Name | Content |
|------|---------|
| `UC12_00_before_cookie_clear.png` | Authenticated session with messages |
| `UC12_01_after_cookie_clear.png` | Login/home page after cookie clear |
| `UC12_02_after_relogin.png` | Session restored with prior messages |

**Pass/fail criteria:**
- Cookie clear triggers unauthenticated redirect
- Re-login with fixture credentials succeeds
- Prior session messages visible

**Estimated duration:** 2 min

---

### UC-13 — "Download all outputs" produces a valid zip

**Test ID:** `UC13`  
**File:** `e2e/output-download-preview.e2e.ts`

**Requires:** A completed run (invoke UC-6 first, or use a pre-existing `invocationId`).

```typescript
// Ensure we are on the after-run tab
await page.locator('[data-testid="panel-tab-after-run"]').click();

// Locate Download all button
const downloadBtn = page.locator('[data-testid="button-download-all-workflow-panel"]');
await expect(downloadBtn).toBeVisible({ timeout: 5_000 });
await ss(page, "UC13_00_panel_completed");

// Set up download handler
const downloadPromise = page.waitForEvent("download", { timeout: 30_000 });
await downloadBtn.click();
const download = await downloadPromise;

const suggestedName = download.suggestedFilename();
console.log(`[UC13] Download filename: ${suggestedName}`);
expect(suggestedName).toMatch(/\.zip$/i);

// Save and inspect
const zipPath = "/tmp/uc13-outputs.zip";
await download.saveAs(zipPath);
const { execSync } = require("child_process");

// File is non-empty
const stat = require("fs").statSync(zipPath);
console.log(`[UC13] Zip size: ${stat.size} bytes`);
expect(stat.size).toBeGreaterThan(1000); // > 1 KB

// At least 3 biological output files
const listing = execSync(`unzip -l ${zipPath}`).toString();
console.log(`[UC13] Zip contents:\n${listing}`);
const bioFiles = (listing.match(/\.(csv|tsv|html|png|pdf|rds|txt|json)\b/gi) ?? []).length;
expect(bioFiles).toBeGreaterThanOrEqual(3);
```

**Screenshots:**
| Name | Content |
|------|---------|
| `UC13_00_panel_completed.png` | After-run tab; "Download all outputs" button visible |

**Pass/fail criteria:**
- Download triggers within 30 s
- File is `.zip` with > 1 KB
- At least 3 biological output files listed

**Estimated duration:** 1 min (if run already complete)

---

### UC-14 — Step file preview: image, CSV table, text code block

**Test ID:** `UC14`  
**File:** `e2e/output-download-preview.e2e.ts`

**Requires:** Completed run with output files of various types.

```typescript
// Navigate to Phases tab
await page.locator('[data-testid="panel-tab-phases"]').click();

// Expand first phase group
const firstPhaseGroup = page.locator('[data-testid^="phase-group-"]').first();
await expect(firstPhaseGroup).toBeVisible();
if (!(await firstPhaseGroup.getAttribute("class"))?.includes("open")) {
  await firstPhaseGroup.click(); // expand
}
await ss(page, "UC14_00_phase_outputs_section");

// ── Image file preview ──────────────────────────────────────────────
const imgPreviewBtn = page.locator('[data-testid^="phase-card-preview-btn-"][data-testid$=".png"],' +
  '[data-testid^="phase-card-preview-btn-"][data-testid$=".jpg"]').first();

if (await imgPreviewBtn.count() > 0) {
  await imgPreviewBtn.click();
  // Image renders inside the preview pane
  const previewImg = page.locator('[data-testid*="step-preview"] img').first();
  await expect(previewImg).toBeVisible({ timeout: 10_000 });
  const src = await previewImg.getAttribute("src");
  expect(src).toBeTruthy(); // has a real src (not empty)
  await ss(page, "UC14_01_image_preview");
}

// ── CSV / TSV table preview ─────────────────────────────────────────
const csvPreviewBtn = page.locator('[data-testid^="phase-card-preview-btn-"][data-testid$=".csv"],' +
  '[data-testid^="phase-card-preview-btn-"][data-testid$=".tsv"]').first();

if (await csvPreviewBtn.count() > 0) {
  await csvPreviewBtn.click();
  const table = page.locator('[data-testid*="step-preview"] table').first();
  await expect(table).toBeVisible({ timeout: 10_000 });
  const rowCount = await table.locator("tr").count();
  console.log(`[UC14] CSV table rows: ${rowCount}`);
  expect(rowCount).toBeGreaterThanOrEqual(2); // header + at least 1 data row
  await ss(page, "UC14_02_csv_table_preview");
}

// ── Text / FASTA / log code block ──────────────────────────────────
const textPreviewBtn = page.locator('[data-testid^="phase-card-preview-btn-"]')
  .filter({ hasNotText: ".png" }).filter({ hasNotText: ".csv" }).first();

if (await textPreviewBtn.count() > 0) {
  await textPreviewBtn.click();
  const codeBlock = page.locator('[data-testid*="step-preview"] code,' +
    '[data-testid*="step-preview"] pre').first();
  await expect(codeBlock).toBeVisible({ timeout: 10_000 });
  const codeText = await codeBlock.textContent();
  expect(codeText?.length ?? 0).toBeGreaterThan(0);
  await ss(page, "UC14_03_text_preview");
}
```

**Screenshots:**
| Name | Content |
|------|---------|
| `UC14_00_phase_outputs_section.png` | Expanded phase showing output file list |
| `UC14_01_image_preview.png` | `<img>` rendered in preview pane |
| `UC14_02_csv_table_preview.png` | `<table>` with header + data rows |
| `UC14_03_text_preview.png` | `<code>` or `<pre>` with file content |

**Pass/fail criteria:**
- Image preview: `<img src="...">` with non-empty `src`
- Table preview: `<table>` with ≥ 2 rows
- Text preview: `<code>` or `<pre>` with non-empty content
- No loading spinner stuck after 10 s

**Estimated duration:** 2 min (assuming completed run)

---

## Part D — Report Format

Each test file writes a JSON report to `/tmp/<suite>/report.json` in `afterAll`:

```typescript
const testResults: any[] = [];

// In each test, push a result entry:
testResults.push({
  id: "UC1",
  name: "scRNA-seq 10x count matrix → Seurat workflow",
  status: "passed" | "failed" | "skipped",
  duration_ms: Date.now() - testStart,
  screenshots: ["/tmp/inline-omics-e2e/UC1_00_new_session.png", ...],
  sse: {
    events: stream.events,              // ["ready","delta","workflow_ready","final","done"]
    hasWorkflowReady: stream.hasWorkflowReady,
    finalState: stream.finalPayload?.state,
    workflowName: stream.workflowReadyPayload?.workflow_name,
    nextflowPath: stream.workflowReadyPayload?.nextflow_path,
    deltaChars: stream.deltaText.length,
    llmUsage: stream.finalPayload?.metadata?.llm_usage,
  },
  panel: {
    opened: true,
    idleConfirmed: true,
    runningConfirmed: true,
    terminalStatus: "completed",
    phaseCardsObserved: 3,
  },
  assertions: { passed: 8, failed: 0 },
  error: null,
});

// In afterAll:
test.afterAll(async () => {
  const report = {
    suite: "inline-omics-routing",
    timestamp: new Date().toISOString(),
    durationMs: Date.now() - suiteStart,
    tests: testResults,
    summary: {
      passed: testResults.filter(t => t.status === "passed").length,
      failed: testResults.filter(t => t.status === "failed").length,
      skipped: testResults.filter(t => t.status === "skipped").length,
    },
  };
  fs.writeFileSync(path.join(SS_DIR, "report.json"), JSON.stringify(report, null, 2));
  console.log(`[Report] ${SS_DIR}/report.json`);
  await sharedPage?.close();
});
```

**Sample report output:**
```json
{
  "suite": "inline-omics-routing",
  "timestamp": "2026-07-01T11:00:00Z",
  "durationMs": 187432,
  "tests": [
    {
      "id": "UC1",
      "name": "scRNA-seq 10x count matrix → Seurat workflow",
      "status": "passed",
      "duration_ms": 98212,
      "screenshots": [
        "/tmp/inline-omics-e2e/UC1_00_new_session.png",
        "/tmp/inline-omics-e2e/UC1_01_response_with_card.png",
        "/tmp/inline-omics-e2e/UC1_02_panel_idle.png"
      ],
      "sse": {
        "events": ["ready","delta","workflow_ready","final","done"],
        "hasWorkflowReady": true,
        "finalState": "workflow_ready",
        "workflowName": "nf-core/scrnaseq",
        "nextflowPath": "nfcore/scrnaseq/main.nf",
        "deltaChars": 847,
        "llmUsage": { "input_tokens": 2341, "output_tokens": 312 }
      },
      "panel": {
        "opened": true,
        "idleConfirmed": true,
        "runningConfirmed": false,
        "terminalStatus": null
      },
      "assertions": { "passed": 9, "failed": 0 },
      "error": null
    }
  ],
  "summary": { "passed": 3, "failed": 0, "skipped": 0 }
}
```

---

## Part E — Execution

**Group A — Fast (routing + research + auth; no pipeline runs):**
```bash
cd /Users/kky/biomate/frontend
npx playwright test \
  e2e/inline-omics-routing.e2e.ts \
  e2e/research-paperqa-flows.e2e.ts \
  e2e/multiturn-workflow-context.e2e.ts \
  e2e/session-auth-recovery.e2e.ts \
  --project chromium --reporter=line --workers 1
# Estimated: 20–25 min
```

**Group B — Slow (panel state machine + downloads; real pipeline runs):**
```bash
npx playwright test \
  e2e/panel-state-machine.e2e.ts \
  e2e/output-download-preview.e2e.ts \
  --project chromium --reporter=line --workers 1
# Estimated: 30–50 min (AWS Batch dependent)
```

**Run a single use case:**
```bash
npx playwright test e2e/inline-omics-routing.e2e.ts \
  --grep "UC1" --project chromium --reporter=line
```

**View screenshots after run:**
```bash
ls /tmp/inline-omics-e2e/
ls /tmp/research-paperqa-e2e/
ls /tmp/panel-state-machine-e2e/
```
