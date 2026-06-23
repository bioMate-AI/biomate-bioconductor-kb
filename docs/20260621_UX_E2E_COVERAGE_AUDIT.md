# UX E2E Coverage Audit — 2026-06-21

## Context

This document audits all items in the CLAUDE.md UX E2E Completeness Standard
against the existing test suite, identifies gaps, and tracks the revised test
plan implemented in `frontend/e2e/ux-completeness-audit.e2e.ts`.

---

## Summary of Registration + Auth Fixes (session 2026-06-21)

These bugs were found during user testing and fixed. All items below have code
fixes committed; E2E regression coverage is added in the new comprehensive test.

| # | Issue | Fix | Status |
|---|-------|-----|--------|
| 1 | "Check your email" screen shown after registration even though the app immediately continues to domain setup | Removed `email-sent` step from `register.tsx` | ✅ Fixed |
| 2 | Payment/trial UI shown even when Stripe not configured (devMode) | `handleStartTrial()` now checks `import.meta.env.VITE_STRIPE_PUBLIC_KEY`; skips UI if unset | ✅ Fixed |
| 3 | New users see other users' mock chat history | `getDefaultSessions()` returns `[]`; `storageKey` namespaced by `userId` via `setUserId()` | ✅ Fixed |
| 4 | Pending query from hero textarea lost after cross-domain redirect (biomate.ai → dev-public.biomate.ai) | `?q=<encoded>` URL param chain: hero form → register → `finalRedirectUrl()` → App.tsx reads once | ✅ Fixed |
| 5 | Auto-loop toggle default ON; user can toggle it on before testing complete | Default changed from `!== false` to `=== true`; `autoloopLocked={true}` added | ✅ Fixed |
| 6 | After auto-submitting query from hero textarea, only "BioMate is thinking" shown (user message invisible) | `setCurrentChatSession(null)` in `user?.id` effect removed (was wiping session created by auto-submit) | ✅ Fixed |
| 7 | Hero textarea placeholder disappears on focus | Changed to pre-filled text with `.bm-hero-query-prefilled` class (text stays until user edits) | ✅ Fixed |
| 8 | Logo had white background visible on dark header | Border flood-fill (tolerance=55) + tight crop on original `logo-original.png` | ✅ Fixed |

---

## Workflow Panel (`nextflow-workflow-viewer.tsx`) Coverage

| Checklist Item | Covered By | Gap? |
|----------------|------------|------|
| Pre-run state: param strip, missing params alert + "Fix now" / "Confirm anyway" | `demo-ref-A01-nfcore-idle.demo.ts` (static prototype only) | ❌ Not tested on live app |
| Running state: spinner, "Running…" footer, phase cards `data-status="running"` | `demo-ref-B02-gatk-running.demo.ts` (static); `demo-01` to `demo-05` observe completion but not mid-run phase cards | ❌ No live-app running-state assertion |
| Completed state: phase cards `completed`, "Run again" footer | `demo-ref-B03-gatk-completed.demo.ts` (static); live demos observe completion | ✅ Partial |
| Failed state: phase cards `failed`, "Restart" footer | `demo-ref-A04-nfcore-failed.demo.ts` (static only) | ❌ Not tested on live app |
| QC gate: alert shows with red border; two-number display | `demo-ref-C01-admet.demo.ts` (static); `demo-05-autoloop-qc` (live, fires gate) | ✅ Partial |
| QC Settings section: threshold editor per-metric rows, editable inputs, save updates | None | ❌ MISSING |
| "Edit" button on QC gate row → opens QC settings and scrolls to metric | None | ❌ MISSING |
| Parameter override: "Edit params" → GlobalParamsPanel; all param types (boolean toggle, select dropdown, file textarea, number input) | None | ❌ MISSING |
| "View phase outputs" link → panel opens and scrolls to step outputs | `exploreTutorial()` helper partially | ❌ No explicit assertion |
| Step file preview: image→img, table→HTML table, FASTA/VCF→code block | `exploreTutorial()` helper clicks first preview | ❌ No format-specific assertions |
| Auto-loop panel: remediation card was→now diff; gate table colors | `demo-05-autoloop-qc` (live); `demo-ref-09b-qc-autoloop` (static) | ✅ Partial |
| Skip phase/step buttons DO NOT appear | None | ❌ MISSING (negative test) |
| Watcher bar DOES NOT appear | None | ❌ MISSING (negative test) |
| Real-time SSE: idle→running→terminal `data-status` transitions | None with explicit assertions | ❌ MISSING |

---

## Sidebar (`app-sidebar.tsx`) Coverage

| Checklist Item | Covered By | Gap? |
|----------------|------------|------|
| "New Chat" → starts new session | `demo-helpers.ts:setupDemoUser` clicks it (but no assertion) | ❌ No assertion |
| "Workflows" → opens StarredWorkflowsDialog | None | ❌ MISSING |
| "Runs" → navigates to /dashboard | None | ❌ MISSING |
| "CRO Library" → navigates to /drug-discovery-cro | None | ❌ MISSING |
| Chat history dots: blue=running, red=failed, green=completed | None | ❌ MISSING |
| "Starred Workflows" → StarredWorkflowsDialog | None | ❌ MISSING |
| "Recent Tools" → RecentToolsDialog | None | ❌ MISSING |
| "Billing" → /billing | None | ❌ MISSING |
| "Settings" → SettingsDialog | None | ❌ MISSING |
| Collapse toggle: hides sidebar → icon rail; expand restores | None | ❌ MISSING |

---

## Chat Message (`chat-message.tsx`) Coverage

| Checklist Item | Covered By | Gap? |
|----------------|------------|------|
| AI text-only message renders (markdown, code blocks) | `demo-01` to `demo-T05` implicitly | ❌ No explicit assertion |
| Workflow card appears AFTER AI text message | `sendAndWait()` in demo-helpers implicitly | ❌ No explicit assertion |
| wf-chip shows "In panel" badge when workflow is open | None | ❌ MISSING |
| DisambiguationCard renders when `workflow_type === 'disambiguation'` | `demo-ref-09e-disambiguation.demo.ts` (static) | ❌ Not tested on live app |
| Alert banners: warn/error/info with correct icon+color | None | ❌ MISSING |

---

## Use-Case Scenario Coverage

| Scenario | Demo File | Gap? |
|----------|-----------|------|
| ADMET screening → QC gate → autoloop → final report | `demo-01` + `demo-05` | ✅ Covered |
| RNA-seq (nf-core/rnaseq) → AWS Batch → SSE → findings → methods report | None | ❌ MISSING |
| WGS / variant calling → sarek → GATK → VCF preview | `demo-02` | ✅ Covered |
| CryoEM → cryosparc_standard_spa → 3D reconstruction | `demo-03` | ✅ Covered |
| CRO compliance → campaign → ADMET results → export package | `demo-06` + `demo-07` | ✅ Covered |
| Drug discovery IND → PBPK + clinical trial → §2.6.1 narrative → DOCX | `demo-11-ind-assembly` | ✅ Partial |
| Bioconductor routing (DESeq2 chain) | `demo-bioc-01` (static prototype) | ⚠ Static only |
| scRNA-seq → pseudobulk DE | `demo-bioc-02` (static prototype) | ⚠ Static only |
| 450k methylation → DMRs | `demo-bioc-03` (static prototype) | ⚠ Static only |
| Bispecific format triage | `demo-T01` | ✅ Covered |
| In-vivo CAR-T | `demo-T02` | ✅ Covered |
| Verve base editing | `demo-T03` | ✅ Covered |
| GLP-1 bakeoff | `demo-T04` | ✅ Covered |
| Modality triage | `demo-T05` | ✅ Covered |

---

## Implementation: New Test File

All MISSING items above are addressed in:

```
frontend/e2e/ux-completeness-audit.e2e.ts
```

This file uses the canonical fixture account, logs in once, runs one shared
project, and covers all checklist items in sequence. It is structured as:

- **Block A: Chat + Routing** — text rendering, workflow card order, wf-chip badge, disambiguation
- **Block B: Workflow Panel States** — pre-run, running (SSE), completed, failed (negative: skip/watcher)
- **Block C: Param Override Panel** — all 4 param types
- **Block D: QC Gate + Settings** — threshold edit, "Edit" button → scroll, two-number display
- **Block E: File Preview Formats** — image, table, FASTA/VCF
- **Block F: Auto-Loop Panel** — was→now diff, gate table colors
- **Block G: Sidebar Navigation** — all 10 items
- **Block H: RNA-seq Live Run** — nf-core/rnaseq end-to-end with SSE assertions

---

## Dataset Upload — Supported Formats, Folder Upload, File Count

### Accepted file extensions (server-enforced, `routes.ts:1114`)

| Category | Extensions |
|----------|-----------|
| Sequencing reads | `.fastq` `.fastq.gz` `.fq` `.fq.gz` |
| Alignment | `.bam` `.sam` `.cram` |
| Mass spec | `.mzml` `.mzxml` `.mgf` |
| Tabular | `.csv` `.tsv` `.txt` `.tab` `.xlsx` `.xls` |
| Sequence | `.fasta` `.fa` `.fna` `.fas` `.faa` `.fap` |
| Variant / annotation | `.vcf` `.vcf.gz` `.bed` `.gff` `.gtf` |
| Single-cell | `.h5ad` `.h5` `.hdf5` `.loom` |
| Cryo-EM / EM | `.mrc` `.mrcs` `.tif` `.tiff` `.eer` `.spi` `.dm4` `.map` |
| Archives (bulk) | `.zip` `.tar` `.tar.gz` `.tgz` `.gz` |
| Notebook / R | `.ipynb` `.rds` `.rda` |
| Phylogenomics | `.nwk` `.newick` `.treefile` `.phy` `.phylip` `.aln` `.nxs` `.nexus` |
| Other | `.json` `.xml` `.log` `.model` `.mldist` |

UI label in `file-upload.tsx:407` shows only a short subset (FASTQ, BAM, SAM, mzML, mzXML, CSV, TSV, FASTA) — **the actual server list is much larger**. This is a documentation gap: the UI undersells what is accepted.

### Folder upload

**No native folder upload.** The file `<input>` has no `webkitdirectory` attribute. However:

- `.zip` and `.tar.gz` are accepted → users must archive the folder first
- The DB schema (`shared/schema.ts:424`) has `source: 'folder'` in the enum — this is used for **Galaxy collection paths** (server-side reference to a Galaxy history collection), not a browser folder picker
- URL import (HTTP/FTP/S3) can point to a remote path prefix; Galaxy fetches all files under it in deferred mode — effectively a "folder" import without a browser upload

**Gap to fix:** Add a "Folder / archive" hint to the upload UI explaining that folder uploads should be zipped. Consider adding `webkitdirectory` support for local folder → auto-zip on client side.

### Maximum file count

| Limit | Value | Where enforced |
|-------|-------|---------------|
| Per-file size | **5 GB** | `multer limits.fileSize` (`routes.ts:1110`) |
| Files per HTTP request | **1** | `upload.single('file')` (`routes.ts:3258`) — one request per file |
| Concurrent uploads | **3** | Client batches (`file-upload.tsx:121`) |
| Dataset refs visible to LLM | **32** (FIFO, oldest dropped) | `dataset-cap.ts:29`, enforced at `routes.ts:13122` |
| Galaxy/S3 storage per account | **50 GB default** | `availableStorageGB` prop default in `file-upload.tsx:48` |
| URL import file size | **No limit** | Galaxy fetches server-side; bypasses the 5 GB client cap |

**What happens with 100 small files:**
1. All 100 upload successfully to Galaxy/S3 (no file-count cap on storage)
2. Only the **most recent 32** references are written into the conversation's `datasets` column
3. The LLM prompt block (`galaxy-assistant.ts`) renders at most 32 dataset entries — files 1–68 become invisible to the AI
4. The files still exist in Galaxy/S3 and can be re-referenced by telling the AI the file name

**Recommendation for many small files:** zip them into a single archive, or use an S3 URL pointing to the folder prefix with deferred import mode.

### Coverage gaps added to test plan

| Gap | New Test |
|-----|---------|
| Upload UI shows short format list (UI undersells accepted types) | I1 |
| No folder picker; zip workaround not documented in UI | I2 |
| 32-ref cap: counter badge shows X/32, overflow drops oldest | I3 |
| Drag-and-drop + multi-file parallel upload (3 concurrent) | I4 |
| URL import (deferred vs immediate mode) | I5 |
| Compression dialog auto-trigger at 70% token limit | I6 |
| Storage indicator updates as files are added | I7 |

---

## Dataset Upload + Context Management Coverage

| Checklist Item | Covered By | Gap? |
|----------------|------------|------|
| Drag-and-drop upload zone renders; accepts files | None | ❌ MISSING |
| Multi-file upload: batched 3 at a time, progress bars | None | ❌ MISSING |
| 5 GB per-file limit enforced with clear error message | None | ❌ MISSING |
| URL import tab: deferred vs immediate mode selection | None | ❌ MISSING |
| Dataset browser: "This session" / "BioMate history" / "From URL" tabs | None | ❌ MISSING |
| Dataset counter badge X/32 in chat-input | None | ❌ MISSING |
| 32-ref cap: overflow silently drops oldest (FIFO) | None | ❌ MISSING |
| Format list in UI matches actual server-accepted extensions | None | ❌ DOC GAP |
| Folder upload: no picker — zip workaround explained in UI | None | ❌ DOC GAP |
| Compression dialog: auto-triggers at 70%, "Compress Now" + "New chat" | None | ❌ MISSING |
| S3 credential setup in Settings → Data tab | None | ❌ MISSING |

---

## Test Group Map

| Group | Use cases | Demo files |
|-------|-----------|-----------|
| Bioconductor 3 | DESeq2 chain, scRNA-seq pseudobulk DE, 450k methylation DMRs | demo-bioc-01, 02, 03 |
| Integration 5 | Bispecific format, CAR-T, base editing, GLP-1, modality triage | demo-T01–T05 |
| Major domain 7 | Drug discovery, WGS, CryoEM, PKPD, autoloop QC, CRO compliance, IND | demo-01–07 |
