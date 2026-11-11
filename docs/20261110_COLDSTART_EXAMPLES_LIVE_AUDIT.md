# Cold-start examples — live audit (Search & evidence, Data analysis)

**Date:** 2026-11-10 (UTC 2026-11-11)
**Branches / PRs:** #357 (`fix/coldstart-search-examples` → `integration/next-phase`),
#365 (`fix/coldstart-search-examples-dev` → `integration/unmerged-20261110`, the line dev runs)
**Dev at time of writing:** `401e23e8` (`build-info.json`), synced 2026-11-10 22:07 local, health gate + smoke passed.

---

## 1. Summary

The founder reported three problems on the cold-start dashboard:

1. **Search & evidence:** Literature, Databases and Patents attached identical input datasets.
2. **Repeated testing:** the same example data was exercised repeatedly.
3. **Project ID:** the seeded query still contained the project ID after a "fix".

All three are fixed and deployed. A new live harness that sends each Data analysis example on dev found four further classes of defect. These are documented below and are **not fixed yet**.

---

## 2. Fixed and deployed

### 2.1 Search & evidence tracks shared one dataset

- **Symptom:** every Literature, Databases and Patents example attached the same four ABL1/imatinib files (`pilot_compounds.csv`, `pilot_target_info.json`, `pilot_reference_actives.smi`, `pilot_README.md`).
- **Root cause:** in `cold-start-demo-catalog.ts`, all nine example texts were grouped under one `evidence` bundle. This dates from `394bc9fabb` (2026-10-09), the commit that first introduced cold-start bundles. **It was never correct; no earlier work was lost.**
- **Why tests passed:** the same commit added `cold-start-demo-catalog.test.ts`, which required *every* example to have *some* bundle (≥1 file, context >100 chars). Vague questions ("this target", "this chemotype") were satisfied by the shared bundle nine times. No test checked that bundles were distinct or appropriate, and no test ever sent an example.
- **Fix (`22fbf0c0df` / `419dd9bdc4`):**
  - Search questions now name their own subject and attach nothing: LRRK2 and Parkinson's disease, imatinib-like SAR on ABL1, JAK2 selectivity, KRAS G12C structures, celecoxib off-targets, PD-1/PD-L1 NSCLC trials, sotorasib claims.
  - Only the two patent questions about the user's own compounds attach data, each its own set:
    - "Freedom-to-operate picture for this series" → `ftoSeries`: 15 BCR-ABL1 inhibitors.
    - "Are my generated candidates inside anyone's claims?" → `claimCandidates`: 500-compound library.
  - New tests:
    - an example that refers to the user's data (`this/my/these/our`) must have a bundle;
    - Search tracks, and questions within a track, must not share inputs.

### 2.2 Project ID in the query

- **Symptom:** Internal and hospital examples seeded `… (Project <uuid>; use the attached files — these are inputs, not results.)`.
- **Root cause:** `prepareColdStartSelection` in `cold-start-examples.ts` appended it. The earlier commit `7bff3c2e56` only reworded labels and left the suffix. Its test asserted the prompt *contained* certain words, never that the ID was *absent*.
- **Fix:** the suffix is removed. Project scope already travels structurally (active project ID → `context.projectId`, `chat-interface.tsx` ~805/880).
- **New test:** the seeded prompt must not contain the project ID or `(Project `.

### 2.3 Verification

| Check | Result |
|---|---|
| `tsc --noEmit` | Clean on both trees |
| Full `vitest` on the deploy tree | 260 files, 2656 passed, 0 failed (one earlier run timed out under load average 29 on 8 cores; it passed on rerun) |
| Dev sync | Frontend-only; ancestry guard passed; health gate and smoke passed; `build-info.json` = `401e23e8` |

**Deploy note:** dev runs `integration/unmerged-20261110`, not the session branch (`ui/contrast-tokens-gemini`). Syncing the session branch would have removed 24 integration commits from dev, so the fix was cherry-picked onto dev's line (#365).

A stale remote deploy lock (`/opt/biomate/.dev-deploy.lock`) was held for about 45 minutes with no deploy running anywhere. It was cleared with the founder's approval, only after verifying the owner ID was unchanged.

---

## 3. New live harness

**File:** `frontend/e2e/coldstart-data-analysis-live.e2e.ts` (committed on #365).

It drives the real user path for every Data analysis row: Ad-hoc compute (3), Validated workflows (3), Try sample data (12), and 7 domains × 3 shapes = 39 rows. For each row it clicks the card, lets the composer seed and attach files, sends, then reads the real response. Nothing is mocked; requests are only observed. It stops before Confirm & Run, so there is no Batch spend.

| Assertion | Checks |
|---|---|
| A | Attached files equal the row's own bundle (catalog or `PREPARED_EXAMPLES`) |
| B | No project ID, scaffolding, or `s3://…/uploads/<uuid>` path in the query or answer |
| C | The AI does not bounce back with "which target / please upload" |
| D | Non-empty answer, not stuck in progress, workflow name never `undefined` |
| E | Run-type rows end in a workflow card. Ground truth is the stored session (`GET /api/sessions/:id` → assistant `metadata.workflow`); the in-chat anchor is an empty div, so DOM text cannot be used |

Diagnostics written per row: the raw SSE the browser received (`*.sse.txt`) and the client's chat console log (`*.console.txt`).

**Run:**

```bash
cd frontend && BIOMATE_URL=https://dev-public.biomate.ai \
  npx playwright test e2e/coldstart-data-analysis-live.e2e.ts \
  --project=chromium --retries=0 --workers=3
```

**Harness bugs found and fixed during the session** (none were product issues):
- The answer was captured while the UI still showed "Preparing the plan…" or "Understanding your goal…".
- Curly quotes on card labels broke the prepared-example lookup.
- The layout check ended on the wrong track tab.
- The session ID is at `body.context.sessionId`.
- Playwright's ESM loader rejects the JSON import inside `cold-start-examples.ts`, so the harness reads that file's source text instead.

---

## 4. Open issues found by the live test (not fixed yet)

### 4.1 Workflow card intermittently lost in the browser — HIGH

- **Symptom:** for run-type examples (seen on ADMET, proteomics DE, CRISPR compare, chemoproteomics QC, EBV), the chat shows the full pre-execution summary ("Workflow — Input / Key steps / Expected output") but **no card, no panel and no Confirm & Run button**. The stored assistant message has text but no `metadata`.
- **Evidence:**
  - Dev logs for the failing ADMET turn show `Step 4 complete - workflowGenerated: true`.
  - Replaying the exact stored user message (attachment block included) against `/api/chat/stream` returns a final SSE event with `state: workflow_ready` and a runnable workflow (`predict_admet_properties/main.nf`, `success: true`). Without attachments it returns the same.
  - So **the server generates and sends a valid card; the browser fails to keep it.**
  - A later browser run of the same ADMET row worked: the console shows `SSE final event received, workflow: true` → card created.
- **Status:** intermittent; root cause not yet identified.
  - Leading hypothesis: the browser does not receive or process the final SSE event, because the stream is cut or the client aborts. The server's own persistence then saves text only.
  - Candidates in `chat-interface.tsx`: the per-attempt `ATTEMPT_TIMEOUT_MS = 120_000` with retry; the user-abort path that returns a partial payload; session-update races (`App: Updating chat session … workflows: []`).
- **Next step:** reproduce a failure with SSE and console capture on, under the same 3-worker concurrency. **Do not patch before the cause is identified.**

**Root cause identified (2026-11-11, branch `fix/lost-workflow-card`):**
- Timing (curl, dev `3b329654`, metaboanalystr): full summary text at 10 s, then about 62 s of server-side parameter grounding, then `workflow_ready` + `final` with the card at 72 s.
- The client decided a turn was over once the reply had text. The typing cue was off, Stop was hidden, and the soft-queue was off for the whole ~60 s (`chat-interface.tsx` `displayTyping`; the progress line stayed in metadata and blocked the indicator even though it was no longer rendered). Users, and the 401e23e8 harness (not busy + 20 s stable), left before the card arrived.
- Server: closing the socket wrote a text-only `partial: true` row and set the single `persisted` flag. The generation kept running and finished with `workflowGenerated: true`, but its final write was skipped (`routes.ts` `persistAssistantMessage`). 7 of the 9 failing sessions are stored `partial: true`.
- The 2 failing sessions stored `partial: false` held only `workflowMetadata`. The reload path (`chat-history.ts` `fetchSessionDetail`) restores only `metadata`, so no card came back.
- The current harness (polls the session for 90 s, so the page stays open) got 6 of 6 cards on dev `3b329654`. This is consistent with the above.
- **Fix:**
  - The turn state now follows the stream (`lib/chat-turn-state.ts`); `progress: matched` shows the workflow cue.
  - The server persister never lets a partial write block or overwrite the final write (`server/chat-stream-persistence.ts`), and it stores `finalPayload`.
  - The reload rebuilds the card from `finalPayload` with the same builder as the live stream (`lib/assistant-message-from-final.ts`).
- **Still open:** the ~60 s parameter-grounding latency itself.

### 4.2 Wrong routing or no result — MEDIUM–HIGH

| Example | Observed |
|---|---|
| Quantify EBV antibody titers (Try sample data) | Refuses: "launch it from the Workflows panel … search for Analyze Ebv Antibody Titers". No card. |
| QC a CRISPR screen before hit-calling | "I'll run a comprehensive QC analysis…", then nothing |
| Integrate multi-omics across phenotypes | "I'll first check the demo notes… then route you…", then stops |
| Predict and assess a structure for a sequence | "Chat API error: Bad Gateway" |
| Compare variant burden; Stratify cohort by response | Answered inline (computed) instead of a workflow. Acceptable only if intended. |
| Quantify differential protein abundance | Routed to *Chemoproteomics Pulldown* (H/L enrichment), not a DE workflow |

### 4.3 Example ↔ data mismatches (static audit) — MEDIUM

- **"Compare variant burden between my responder and non-responder cohorts"** attaches one normal and one tumour Strelka VCF from the same patient. There are no responder cohorts.
- **"Stratify this cohort by response and test the primary endpoint"** uses the NCCTG lung cohort, which has no response variable. The bundle context tells the model to stratify by sex instead; the label promises something the data cannot deliver.
- **CRISPR "QC … replicate correlation"** uses data with one column per line and time point, i.e. no replicates.
- **Shared bundles inside a domain** (the same class of problem as the Search bug):
  - Functional genomics: all 3 shapes use the same `crispr` bundle.
  - Proteomics: 2 of 3 shapes share a bundle.
  - Clinical: 2 of 3 shapes share a bundle.
  - Drug discovery: "Screen these SMILES" and "Why might this hit series be failing on hERG" share `admet`.
  - Genomics: "Call variants" and "Check contamination/relatedness" share `reads`.

### 4.4 Internal scaffolding shown to the user — MEDIUM (fixed in `6ad8247755`, not yet deployed)

- **User bubble:** every catalog-backed example sends and displays `Prepared demo context: These are prepared public tutorial inputs, not new experimental results. Use demo_notes.md…`, followed by the bundle's internal instructions. This is the same class of problem as the project ID: context meant for the model is shown as the user's own words. A `demo_notes.md` attachment is also added to every row.
- **Assistant answers:** raw storage paths sometimes appear, e.g. `s3://biomate-nextflow-work/uploads/<uuid>/pilot_compounds.csv`. They come from the `[Uploaded datasets: … s3_uri=…]` block the client appends to the message (`chat-interface.tsx` ~1773–1792), which the model then quotes.

---

## 5. Live results so far (Data analysis)

- **Attachments:** 36 of 36 rows from the first full pass attached exactly their own bundle. No wrong or shared-default datasets.
- **Ad-hoc compute:** real, numerically correct answers (BACE1 potency vs logP, r = 0.117; predicted vs measured IC50, Pearson 0.383 on 1,310 compounds; 8×12 plate → 96-row long table).
- **Workflow cards observed** (any pass): DESeq2 chain, sarek, scdownstream, MAGeCK, CryoSPARC, AutoDock Vina, Predict ADMET, cart_construct_design. The per-row pass/fail table will be appended when the current pass (stored-session ground truth) completes.


### 5.1 Stored-session ground truth (partial pass, dev `401e23e8`, 2026-11-11 04:49–05:00Z, 3 workers)

| Track | Rows | Workflow card stored | Notes |
|---|---|---|---|
| Ad-hoc compute | 3 | n/a (Instant by design) | Correct computed answers |
| Validated workflows | 3 | 2 | sarek reply in workflow format but no card |
| Try sample data | 12 | **1** (wsi nuclei seg) | 9 replies use the "**Workflow** — Input / Key steps / Expected output" format (used only when a workflow *was* generated) but have no card. This includes metaboanalystr, which has no attachments, so 4.1 is **not attachment-specific** and is frequent, not rare. The Cox row ran inline R; the two hospital rows started with file reads. |

All 18 rows attached exactly their own files. One reply mentioned storage (flow cytometry).

---

## 6. Next steps

1. Reproduce 4.1 with SSE and console capture. Find where the final event is lost; fix at the root.
2. Fix 4.4 at the source:
   - Carry bundle context and upload references as structured request context, not as text appended to the user's message.
   - Never echo storage URIs to the user.
3. Rework the Data analysis catalog (4.3):
   - one distinct, appropriate bundle per shape;
   - labels that the attached data can actually support;
   - extend the uniqueness test from Search to every module.
4. Investigate the routing failures in 4.2: EBV refusal, stalled "I'll run…" turns, the Bad Gateway, and proteomics DE → pull-down.
5. Re-run the live harness after each fix. A pass means every row green on dev, not unit tests.

---

## 7. Founder-reported issues (2026-11-10, screenshots `UI_refinement/`)

### 7.1 Research answer clutter — `remove_squared_content.png`

Remove the "**Boundary:** Synthesizes retrieved literature only — not validated against your project's data…" banner, the **Save to project** button and the **规划我的数据分析 / Plan my data analysis** button from research answers.

### 7.2 Running a known workflow re-searches the catalogue — `overcomplicating_process.png`

- **Symptom:** clicking run on nf-core/rnaseq in the Workflows panel sends "运行 nf-core/rnaseq 工作流。"; chat then shows "正在检索 4,000+ 个工作流…".
- **Root cause:** `workflow-history-dialog.tsx` `handleRunCatalog` discards the selected workflow's identity (`name` / `source` / path) and seeds plain text (`workflows_library.seed_prompt`). The server must rediscover the workflow through intent → search → generate.
- **System-wide:** there is no structured "user selected this exact workflow" path; even the disambiguation card re-sends text ("Use X").

### 7.3 Contradictory pre-run state — `Confusing_optional_parameters.png`

- **Chat:** says "无法生成工作流 / 缺少必要的输入数据" while showing the nf-core/rnaseq card.
  - **Root cause:** the response-format rules in `galaxy-assistant.ts` (~10020) have only "generated" and "not generated" cases. There is no case for "workflow identified, required input not yet provided", so the model writes "cannot generate".
- **Panel:** "输入已映射 (9 个输入)" lists 8 optional reference overrides (Fasta, Gtf, Gff, Gene Bed, …) as "未设置 · 可选——留空", plus a ribo manifest default. The real required input (samplesheet / reads) is absent. There are also 86 optional parameters.
  - **Root cause:** the inputs card in `nextflow-workflow-viewer.tsx` (~3700) lists every `type: 'file'` parameter. For rnaseq those are the reference overrides; the samplesheet is not typed `file`. The header says "mapped" even when nothing is mapped.

### 7.4 Follow-up input re-routes to the wrong workflow — `wrong_routing.png`

- **Symptom:** after 7.3 the user replies "SRR1039508". The reply text describes nf-core/rnaseq, but the card is **nf-core/differentialabundance**.
- **Dev log of this exact turn:**
  - `User intent: SRR1039508 … Inline parameters: {"accession":"SRR1039508","domain_hint":"rna_seq"}` → `source: template_reuse` → `Found workflow: nf-core/differentialabundance` (confidence 54);
  - then `Step 6c: text mentions "nf-core/rnaseq", not a search candidate for this request — keeping "nf-core/differentialabundance"`.
- **Root cause:** a turn that supplies the missing input for the workflow open in the panel is routed as a brand-new request. `context.currentWorkflow` is sent by the client but used only for domain inference (`galaxy-assistant.ts` ~9429) and panel parameter edits (`routes.ts` ~7630), never to bind the follow-up to the open workflow. The Step 6c guard then keeps the wrong card over the text that names the right one.

---

## 8. Fixes in progress (2026-11-10 late)

- **`6ad8247755` (S3 and scaffolding, 4.4):**
  - Examples seed only the goal; bundle notes travel as a hidden `[Prepared inputs: …]` block, stripped from the bubble.
  - `demo_notes.md` is no longer attached.
  - The LLM prompt no longer offers "S3 URIs" and forbids storage paths in replies.
  - The panel hint is fixed (en/zh).
  - Regression tests added.
  - Founder directive recorded: no S3 anywhere in user-facing text.
- **Parallel branches** (each from `6ad8247755`):
  - `fix/research-answer-clutter` (7.1)
  - `fix/known-workflow-routing` (7.2 + 7.4)
  - `fix/prerun-state-clarity` (7.3)
  - `fix/lost-workflow-card` (4.1)
  - `fix/example-routing-failures` (4.2)
  - `fix/data-analysis-example-catalog` (4.3)

  They will be merged into #365, then pre-sync checks, dev sync and a full re-run of the live harness.
- **Left for the founder to decide:** UI that belongs to the real S3 connector feature still says "S3": "复制 S3 路径" (copy path), "我的 S3 存储桶" (output destination), and the URL importer's "AWS S3 单个文件 / S3 文件夹". These name a working feature rather than leak storage.
