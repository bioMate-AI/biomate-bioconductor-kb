# QC-on-Dataset Flow — Design Plan

**Date:** 2026-10-19
**Status:** Plan (approved sequencing: clean slice now → backend follow-on)
**Scope:** Make BioMate run *real* QC on user datasets, prompt for it on ingest,
handle large-dataset sampling, track QC status, and keep the data surface honest —
all built *on the platform's existing mechanisms*, not as a parallel system.

> **Guiding principle — platform consistency first.** Every piece below reuses an
> existing BioMate mechanism (the execution engine, the QC gate, data-scoping,
> project files, the chat-as-execution path, the dataset-object provenance). We
> add one new source-of-truth signal (dataset QC status) and wiring — never a
> second QC system.

---

## 1. Context — what already exists (the anchors we build on)

| System | Where | What it gives us |
|---|---|---|
| **Heuristic profiler** | `backend/lib/galaxy/ai/data_perception.py` (`POST /api/perception/profile`) | Instant, zero-dep read of a file: shape, FASTQ read stats, VCF shape, CSV leakage/effective-N/class-balance, a Good/Watch/Blocked verdict. Feeds the dataset **Data profile** section + the per-row quality dot. **NOT real QC.** |
| **Real QC workflows** | `backend/biomni_workflows/.../fastqc`, `_qc_harness`, `fastqcleaner`, `cohort_qc_triage`, `hts_plate_qc_hit_calling`, `rqc`, `cytofqc`, `teqc`, … | The genuine QC capability (FastQC/MultiQC/domain QC). Runs on Batch. |
| **QC gate / auto-loop** | workflow panel + `nextflow_executor` | The platform's **canonical QC mechanism**: thresholds, halt/advisory/pass, auto-remediation. Dataset QC must *align with this*, not reinvent it. |
| **Execution engine** | `POST /api/workflows/execute` (search→execute), `useUnifiedExecution` | Chat→search→execute. **Tunable data scope 1–100% + sampling strategies** (`dataScopeApplied`). Project files staged as inputs (`resolveProjectFileParams`); outputs auto-filed to project Files. |
| **Chat as execution path** | root route `?project=&attachFile=&draft=&q=`, `chat-input` attach resolver | A dataset can be attached + a request pre-filled; the pipeline routes, runs, reports. The just-shipped **Run full QC** button already uses this. |
| **DatasetObject** | `components/datasets/dataset-object.tsx` | Preview (profile) · Lineage (producedBy) · **Consumers** (runs that read it, *lazy-loaded*) · Versions · Origin. |
| **Data kind sniffer** | `data_perception._sniff_kind` | fastq / vcf / bam / table / … — reuse for "does a QC module apply?" |
| **Project model** | `project_files` table, data hub | Datasets are first-class objects scoped to a project. |

Already shipped (2026-10-19): honest relabel **Quality → Data profile / 数据概况**
(+ sub-line stating it's a heuristic), and the **Run full QC / 运行完整质量检查**
button routing through the real engine.

---

## 2. Design principles

1. **One QC path.** Dataset QC dispatches through the *same* chat→search→execute
   engine and lands in the *same* QC gate as workflow QC. No bespoke dispatcher.
2. **One source of truth.** A server-side **dataset QC status** (per dataset
   *version*) drives every UI decision (button visibility, prompt, verdict). The
   frontend never name-matches workflow strings to guess QC state.
3. **Honest surfaces.** "Data profile" = instant heuristic; "QC" = real workflow.
   The real QC verdict, once present, augments/supersedes the heuristic verdict.
4. **Reuse the sniffer + search.** QC-module availability = `_sniff_kind` → real
   workflow search, never a hardcoded map.
5. **Proactive, not intrusive.** The on-ingest prompt uses the existing chat
   suggestion/card surface (how BioMate already proposes workflows), one-time,
   dismissible.
6. **Bounded cost.** Default QC runs on a **random sample**; full is an explicit
   upgrade. Auto-run (when the user doesn't choose) is always the *sampled* scope.

---

## 3. Scenario matrix (all cases the flow must handle)

Dimensions: **ingest source** (file-panel upload / chat attach / workflow output) ×
**data type** (QC module exists?) × **size** (sampling needed?) × **project**
(in-project / ad-hoc) × **prior QC** (none / running / sample-done / full-done) ×
**freshness** (current version / updated since QC).

| # | Scenario | Expected behavior |
|---|---|---|
| A | Upload (file panel), in project, QC module exists, small, no prior QC | Chat offers QC; small ⇒ no sample/full choice (sample = full). If user doesn't choose ⇒ auto-run. |
| B | Same as A but **large** | Offer **random sample** (default) vs **full**; auto-run the *sample* if unanswered. |
| C | **Provide via chat** (attach), QC module exists | Same as A/B; ingest detected on attach. |
| D | Data type with **no QC module** (arbitrary CSV, PDF, image w/o pipeline) | **No prompt, no button.** Data profile only. |
| E | **Full QC already done**, dataset unchanged | **No button, no prompt.** Show QC verdict + link to the QC run. |
| F | QC done, then dataset **updated / re-uploaded** (new version) | QC status is per-version ⇒ **button + prompt return**. |
| G | Dataset is a **workflow output** (auto-filed) | Auto-filing notice; QC prompt only if it's a new user-analyzable input, **not** a QC report output (avoid loops). |
| H | **Ad-hoc** (no project) | QC still runnable via chat; **no** project-files auto-filing notice (nothing to file into). |
| I | **Sample QC done**, user wants more | Offer **Run full QC** (upgrade sample → full). Sample verdict shown as provisional. |
| J | QC **running** | Button shows "QC running…" (disabled) + link to the live run; no duplicate dispatch. |
| K | QC **failed** | Show failure + "Retry QC"; treat as not-done for button/prompt. |

---

## 4. Architecture — components

### 4.1 Dataset QC status (new source of truth)
- **Endpoint:** `GET /api/datasets/:ref/qc-status`
  → `{ version, state: none|running|done|failed, scope: sample|full|null, runId, verdict, at }`.
- **Derivation (no new table required for v1):** compute from existing provenance —
  the dataset's **consumers** filtered to QC-workflow runs for the *current version*,
  with run status + timestamps. Backend owns the "is this a QC run" classification
  (by the catalog's QC tag / workflow identity), so the frontend gets a clean flag.
- **Consistency:** sits beside the existing `datasets_object.py` endpoints
  (lineage/consumers/versions). Keyed by dataset **version** so re-upload (F) resets it.

### 4.2 QC-module availability
- **Endpoint (or field on qc-status):** given `_sniff_kind(ref)`, resolve via the
  real workflow search whether a QC workflow exists + which + whether the dataset is
  "large" (sampling applies). Returns `{ hasQC, workflowHint, sampleRecommended }`.
- **Consistency:** reuses `_sniff_kind` + `UnifiedWorkflowSearch` — no hardcoded map.

### 4.3 Sampling (R3) — **reuses the existing `DataScopeConfig`**
- Workflow execution **already has** a data-scope control: `components/data-scope-config.tsx`
  — a fraction slider (1–100%) + sampling strategies (random / first-N / diverse-
  representative) + strata selection. QC sampling **reuses this verbatim**; it is not
  a new control (platform consistency).
- **Default random sample = 30%** (decision 2026-10-19): the QC default is
  `fraction = 0.30, strategy = random`. "Full" sets `fraction = 1.0`.
- Small datasets (below a documented threshold — FASTQ reads / table rows / bytes,
  pinned in Phase 1 from `data_perception` shape) ⇒ `sample == full`, choice hidden.
- The chat request text names the scope so the router/panel applies it; the
  `DataScopeConfig` control remains the visible/manual override (consistency).

### 4.4 Proactive on-ingest prompt (R1)
- **Trigger:** a new dataset enters a session — file-panel upload, chat attach, or a
  provided dataset — where `hasQC && state==none` for the current version.
- **Surface:** an assistant chat suggestion/card (the existing workflow-suggestion
  surface), e.g. *"I can run QC on `<name>`."* → **[Random sample]** · **[Full]** ·
  **[Skip]** (sample/full shown only when large).
- **Default / auto-run:** if the user proceeds without choosing (the spec's "did not
  respond"), **auto-start QC on a 30% random sample**. Bounded cost by construction.
  Realized through the platform-wide Confirm & Run auto-start (§4.7) — no QC-specific
  timer.
- **Suppression:** respects `state != none` (E/I/J) and type-without-QC (D); one prompt
  per dataset version; dismiss = don't re-ask this version.

### 4.7 Confirm & Run auto-start (platform-wide — decision 2026-10-19)
> Not QC-specific. A general workflow-panel behavior that QC (and R1's auto-run) ride on.
- When a workflow is **ready to run** — i.e. **all required parameters are filled** —
  and the user has not interacted for **10 seconds**, Confirm & Run **auto-starts**.
- **Gate:** if any *important/required* parameter is still unfilled, the timer does
  **not** run — the panel waits for the user (never auto-run an underspecified workflow).
- Any user interaction (focus, edit, hover on the control, explicit cancel) **resets/
  cancels** the countdown; a visible countdown affordance makes it non-surprising.
- Applies uniformly to every workflow run, so dataset QC inherits the auto-run with no
  special-casing. This is what satisfies R1's "auto-start if the user didn't respond."

### 4.5 Conditional QC button (R4)
- DatasetObject **eagerly** fetches `qc-status` (cheap) when it opens.
- Visibility:
  - `state==none` **or** version newer than last QC ⇒ show **Run full QC**.
  - `state==done(sample)` ⇒ show **Run full QC** (upgrade, I).
  - `state==done(full)` & unchanged ⇒ **hide**; show verdict + "View QC run" (E).
  - `state==running` ⇒ disabled "QC running…" + link (J).
  - `state==failed` ⇒ "Retry QC" (K).
  - `hasQC==false` ⇒ never show (D).

### 4.6 Auto-filing notice (R2)
- When a dataset is attached in a **project** (chat) or on upload, a concise,
  one-time notice: *"This dataset and any workflow outputs are saved under this
  project's Files."* (中文 parity.)
- Placed near the attached-dataset chip in the composer (consistent with the
  data-centric "dataset is a project object" model); suppressed when ad-hoc (H).

---

## 5. Phasing (per approved sequencing)

### Phase 0 — Clean slice (now, no backend)
- **R3-lite:** enrich the `Run full QC` request so it offers **random sample
  (default) vs full**, driving the engine's existing data-scoping via the real chat
  path. (EN + 中文.)
- **R2:** auto-filing chat notice when a project dataset is attached. (EN + 中文.)
- Ships value immediately; zero fake heuristics.

### Phase 1 — Backend QC-status + availability
- `GET /api/datasets/:ref/qc-status` (§4.1) + QC-module availability (§4.2).
- Server classifies QC runs; frontend consumes a clean flag.

### Phase 2 — Conditional button (R4)
- DatasetObject consumes qc-status (§4.5); verdict + "View QC run" when done.

### Phase 3 — Proactive on-ingest prompt (R1) + full sampling (R3)
- Ingest hook → assistant QC suggestion with sample/full (§4.4); auto-run-sample
  default; sampled scope wired to the engine.

Each phase is independently shippable and testable (tsc + vitest + dev sync +
中文/EN capture-audit), consistent with the repo's pre-sync discipline.

---

## 6. Decisions (resolved 2026-10-19) + remaining edge cases

**Resolved with the user:**
1. **Default random sample = 30%** (`DataScopeConfig` fraction 0.30, strategy random).
   The "large" threshold (when the sample/full choice is *offered* vs `sample==full`)
   is pinned in Phase 1 from `data_perception` shape.
2. **Auto-run via a 10 s timer, gated on required params (§4.7).** Confirm & Run
   auto-starts 10 s after the last interaction **only when all required params are
   filled**; otherwise it waits. Platform-wide, not QC-specific — QC inherits it.
3. **QC verdict supersedes the heuristic.** Once a real QC run completes, its verdict
   drives the dataset header pill (Good/Watch/Blocked), overriding the `data_perception`
   heuristic verdict; the heuristic remains the instant placeholder until QC lands.
   *(Confirmed: workflow execution already ships the sample control `DataScopeConfig`;
   QC reuses it — §4.3.)*
4. **Only user-provided/uploaded datasets get the QC prompt** (G) — QC report outputs
   and intermediate outputs never trigger a prompt (no loops).

**Still to pin during build:**
5. **Ad-hoc QC (H)** — allowed; the auto-filing notice is project-only.
6. **Persistence** — v1 derives qc-status from provenance (no new table). If that's
   too slow or lossy, add a `dataset_qc` record keyed by (ref, version).
7. **Large-dataset threshold numbers** — concrete reads/rows/bytes cutoffs (Phase 1).

---

## 7. Non-goals (explicitly out of scope here)
- A new QC engine, thresholds UI, or report renderer — QC reuses the existing QC
  gate + after-run report.
- Replacing the heuristic profiler — it stays as the instant "Data profile" + dot.
- QC of non-analyzable artifacts (PDFs, images without a pipeline) — no module ⇒ no QC.
