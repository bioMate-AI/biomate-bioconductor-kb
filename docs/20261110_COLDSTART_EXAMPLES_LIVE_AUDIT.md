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

### 4.3 Example ↔ data mismatches (static audit) — MEDIUM (fixed, see §9)

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

---

## 9. Data analysis example catalog reworked (4.3 closed — branch `fix/data-analysis-example-catalog`)

Standard applied: **every clickable example has its own appropriate inputs, and
the text the user sees must be supportable by the data that is attached.** Where
a well-known small public dataset genuinely fits, it was added (option a);
where it did not, the visible text was rewritten to what the existing data
supports (option b). Nothing was fabricated or synthesized.

### 9.1 Per-example decisions

| Example (domain / track) | Before | After | Data + provenance |
|---|---|---|---|
| Genomics — "Compare variant burden between my responder and non-responder cohorts." | `variants`: one normal + one tumour Strelka VCF from a single nf-core test patient — no cohorts, no response | **(a)** text unchanged, data replaced → `cohorts` | `rizvi2015_mutations.csv` (4,079 somatic coding mutations, GRCh37) + `rizvi2015_clinical.csv` (16 samples, `DURABLE_CLINICAL_BENEFIT` DCB=7 / NDB=9, `OVERALL_RESPONSE`, PFS). cBioPortal study `nsclc_mskcc_2015`; Rizvi NA et al., *Science* 2015, PMID 25765070. cBioPortal public-study terms |
| Clinical — "Stratify this cohort by response and test the primary endpoint." | `clinical`: NCCTG lung cohort has **no** response variable; the hidden context told the model to stratify by sex instead | **(a)+(b)** text rewritten to what a real randomised trial supports → `trial`; shape title now "Compare trial arms and test the primary endpoint", seed "Compare the treatment arms in this trial cohort and test the primary endpoint." | `pbc_cohort.csv` + `pbc_dictionary.json` — Mayo Clinic PBC trial, R `survival::pbc` (418 rows; `trt` 1=D-penicillamine / 2=placebo for the randomised 312; OS with transplant as a competing event). Rdatasets mirror; LGPL (>=2) |
| Functional genomics — "QC my CRISPR screen — guide representation, replicate correlation, and control separation" | `crispr`: MAGeCK demo has one column per line/time → **no replicates**, so replicate correlation was impossible | **(a)** → `crisprQc` | `ht29_brunello_counts.tsv` (plasmid + `Brunello_HT29-rep1/2/3`, three true replicates) + `essential_genes_CEGv2.txt` / `nonessential_genes_NEGv1.txt` for control separation. CRISPRcleanR `inst/extdata` (MIT; Iorio et al., *BMC Genomics* 2018; Brunello library Doench et al. 2016) and hart-lab/bagel CEGv2/NEGv1 (MIT) |
| Functional genomics — "Call hits from a pooled CRISPR screen" | shared `crispr` | **(a)** → `crisprHits` | `ht29_minlibcas9_counts.tsv` (plasmid `MHG_library_v1` + `HT29_c9M1R4/R5/R6`) + the same two reference gene sets. CRISPRcleanR example (MIT); MiniLibCas9 library Gonçalves et al., *Genome Biol* 2021 |
| Functional genomics — "Compare screen hits across two conditions" | shared `crispr`; the MAGeCK demo's two arms are two **cell lines**, not two conditions | **(b)** → `crisprLines`, title "Compare screen hits across two cell lines", seed "…between the two cell lines and flag line-specific dependencies." | `crispr_counts.tsv` + `crispr_design.csv` (MAGeCK demo, HL60 and KBM7 initial/final) — unchanged data, honest text |
| Proteomics — "Assess run-to-run quality across this proteomics batch." | shared `proteomics` (the DE bundle) | **(a)** → `proteomicsQc` | `proteinGroups_batch.txt` + `proteomics_batch_design.txt` — LFQ-Analyst 12-run example (4 replicates each of CD34High/Low/Neg), GPL-3.0; Shah AD et al., *J Proteome Res* 2020. The DE example keeps the 15-run `proteinGroups.txt` |
| Drug discovery — "Why might this hit series be failing on hERG? Cite the evidence." | shared `admet` (the ABL1 pilot compound set, whose hERG values are curated single drugs, not one series) | **(a)** → `hergSeries` | `herg_series.csv` — one published chromone-2-carboxamide MCHR1 series with measured MCHR1 IC50 (CHEMBL344) and hERG IC50 (CHEMBL240, [³H]dofetilide) in nM. ChEMBL document CHEMBL1137327 (*J Med Chem* 2006, doi:10.1021/jm060683e); ChEMBL data CC BY-SA 3.0. 109 measured activities over 46 compounds (25 with a measured hERG IC50); the 24 records with no numeric value were dropped |
| Genomics — "Check these samples for contamination and relatedness before I analyse them." | shared `reads` (two tiny nf-core FASTQ pairs — a single tumour/normal pair cannot support relatedness) | **(a)+(b)** → `relatedness`; needs now "multi-sample genotypes + a pedigree", seed "Check these **genotypes** for contamination and relatedness…" | `ceph1463_genotypes.vcf.gz` (17 samples, 19,991 sites, GRCh37) + `ceph1463.ped` — Illumina Platinum Genomes CEPH 1463 pedigree from brentp/peddy (MIT; Pedersen & Quinlan, *AJHG* 2017). INFO dropped and FORMAT reduced to `GT:DP:RO:AO` for size; genotypes and allele counts unchanged |
| Genomics — "Call variants on these samples…" | `reads` | unchanged (`reads` is now exclusive to it) | nf-core/sarek tiny fixtures, GRCh37 |
| Clinical — "From this cohort, discover a biomarker panel…" | `clinical` | unchanged bundle, context corrected to drop the "stratify by sex" instruction (that instruction only existed to paper over the response-stratification example) | NCCTG lung cohort, R `survival::cancer` |

The two Strelka VCFs and `variant_samples.csv` are no longer selected by any
example. They were left in place (not deleted) and remain listed in
`checksums.json`.

### 9.2 Provenance recording

Every new asset has an entry in `frontend/client/public/demo/cold-start/checksums.json`
carrying `bytes`, `sha256`, **`source` (URL), `licence`, `citation` and
`derivation`** — the derivation line states exactly what was changed (column
flattening, line endings, FORMAT reduction) so no file can be mistaken for an
untouched upstream download or for new measurements. `sources.json` and
`demo_notes.md` were updated in the same pass. 13 new files, 7.3 MB total,
largest 2.7 MB.

### 9.3 Uniqueness regression test

`cold-start-demo-catalog.test.ts` now has three new assertions:

1. **`never shows two examples that silently resolve to the same inputs`** —
   within every module track and within every validated-workflow domain, no two
   printed examples may map to the same bundle key unless the pair is in
   `SHARING_ALLOWLIST` with a written reason. This generalises the
   Search-track-only check from §2.1 to all four modules and all seven domains.
2. **`allowlists only sharing that actually happens`** — an allowlist entry that
   no longer corresponds to real sharing fails the suite, so the allowlist cannot
   rot into a blanket exemption.
3. **`every bundle in the catalog is reachable from a printed example`** — a
   bundle that no example selects is dead weight and fails.

Allowlist (2 entries, both the design chain working on one candidate set by
design):

| Entry | Reason |
|---|---|
| `design:molecules` | the small-molecule design chain deliberately carries ONE candidate library through Generate → Predict → Optimise → Rank |
| `design:biologics` | same chain, biologic modality: one nanobody/antibody design set end to end |

The earlier tests are kept unchanged: deictic examples must have a bundle, no
storage paths or demo scaffolding in visible text, every selected asset exists
and is not an HTML SPA fallback, no default dataset for a custom goal.

### 9.4 Verification

- `npx vitest run client/src/components/cold-start` → **3 files, 202 tests passed**.
- `npx tsc --noEmit -p .` → clean.
- One existing dashboard assertion was widened: the Drug discovery domain now
  shows two sample badges (ADMET example SMILES and the hERG series), so the test
  asserts one badge per shape that names a dataset, in shape order.

---

## 10. Integration, deploy and live verification (2026-11-11)

### 10.1 What was merged (PR #365, now based on `integration/tracks-20261111`)

| Branch | Fixes | Key root cause |
|---|---|---|
| `fix/research-answer-clutter` | 7.1 | Research answer rendered Boundary banner, Save to project and Plan-analysis button |
| `fix/known-workflow-routing` | 7.2, 7.4 | The library run seeded plain text (identity dropped); `context.currentWorkflow` was used only for domain inference |
| `fix/prerun-state-clarity` | 7.3 | The response format had no "identified, needs input" state; the panel listed only `type:'file'` params |
| `fix/lost-workflow-card` | 4.1 | Card arrives ~60 s after the text; the UI looked done; a disconnect partial save blocked the final save; reload ignored the server copy |
| `fix/example-routing-failures` | 4.2 | `direct_compute` trusted with no data (EBV); the agentic loop ended on its tool budget with no final answer; 502 retries fell inside the deploy gap; operation-phrase synonyms were missed in ranking |
| `fix/data-analysis-example-catalog` | 4.3 | Shared bundles and labels the attached data could not support |

**Merge with the line dev runs.** Dev had moved to `integration/tracks-20261111` (47, then 52 commits ahead), so syncing the fix branch alone would have removed other sessions' work. That line was merged in and 9 conflicts were resolved:

- **Research answers:** took the tracks redesign and also removed its Boundary banner.
- **Message building:** kept the extracted `buildAssistantMessageFromFinal`, with tracks' `toolBlocks` ported into it.
- **Bubble stripping:** `[Prepared inputs]` was added to the shared `stripSystemBlocks`.
- **Routing:** took `routing-authority.ts`; the direct_compute-needs-data guard was ported into `reconcileExecutionMode(intent, conversationHasData)`.
- **Locales:** both sides kept; added en/zh copy for the reworked examples.

Also added: `.ped` uploads are now allowed (relatedness example).

**Additional founder directive:** the search progress line reads just "Searching…" / "正在检索…", with no workflow count.

**Deploys** (ancestry guard passed; health gate and smoke passed each time):
- `a1c53df0`: full sync, frontend and backend.
- `e04ec5f2`: frontend-only sync for the progress label.

A stale remote deploy lock was cleared earlier with the founder's approval.

### 10.2 Founder rnaseq flow — live on dev (`e04ec5f2`), real chat API

| Turn | Check | Result |
|---|---|---|
| 1. Library pick, "运行 nf-core/rnaseq 工作流。" with `selectedWorkflow` | No search stage | **PASS**. Stages were intent → matched → plan. Log: `Step 1: workflow pinned → "nf-core/rnaseq" (user selection)`, `source: user_selected` |
| | Card | **PASS**: nf-core/rnaseq, `workflow_ready` |
| | Reply | No "无法生成" and no S3, **but** it led with "缺少输入数据" and suggested "airway (Bioconductor dataset)" as an input (wrong for a FASTQ pipeline). See 10.3 |
| 2. "SRR1039508" with rnaseq open | Card stays rnaseq | **PASS** (not differentialabundance) |
| | Mechanism | **Not via binding.** The classifier attached an `analysis_goal` carried over from history at confidence 0.95, so the binding rule refused and the turn searched (Step 4 took 55 s). See 10.3 |

### 10.3 Root-cause fixes from the live check

- **Follow-up binding.** The classifier's confidence does not separate "stated by the user" from "carried over from history".
  - Added `isValueOnlyReply(message)`, a deterministic and language-neutral check: after removing public data identifiers, attached-file blocks, file names and numbers, no letter or CJK character is left.
  - A value-only reply cannot state a new analysis, so it binds to the open workflow. Replies with any words still use the classifier rule.
  - Tests cover the dev case ("SRR1039508" with goal@0.95 binds) and counter-cases ("run variant calling on SRR1039508", "用 DESeq2 分析 SRR1039508" do not bind).
- **Required data input missing from the definition.** The live rnaseq `workflow_ga` had **no `input` param**: `input` is in `_NEXTFLOW_INTERNAL_PARAMS` (`backend/lib/galaxy/ai/ai_assistant.py` ~2439), which is correct because the executor builds it (fetchngs samplesheet for accessions, upload wiring for files). As a result, chat could not say what the workflow needs, and the panel showed only reference overrides.
  - **Fix:** the schema parser now records required executor-owned data inputs as `workflow_ga.data_inputs` (label "Samplesheet (sequencing reads)", schema description). They are never editable params, so the run path is unchanged.
  - `_return_nextflow_match` marks an input `bound` (and sets `bound_value` to the accession) when the request carries an accession or attached files.
  - `unboundRequiredDataInputs` reads `data_inputs`, which drives the "identified, needs input" reply state.
  - The panel lists the input as the one required row, with no file picker, because the executor fills it.
  - Tests:
    - backend pytest with an nf-core-shaped schema: `input` is described, `outdir` is not, reference overrides stay optional;
    - shared unit tests;
    - viewer render tests with the live payload shape (unbound shows "1 required, not set"; with SRR1039508 the row shows the accession).
- **Follow-up (not changed):** the browse/search endpoints (`/api/ai_assistant/search_nextflow_workflow`, `webapps/.../ai_assistant.py` ~2799) build `workflow_ga` from DB parameter metadata and do not emit `data_inputs`. Chat cards, including library picks, go through `_return_nextflow_match` and are covered.

### 10.4 Founder notes (not acted on)

- **Security:** Galaxy dev logs print the Gemini API key in request URLs (httpx INFO). Recommend rotating the key and setting httpx logging to WARNING.
- **Deploys drop live chats:** the frontend container is replaced mid-request with no drain (the source of the structure-prediction "Bad Gateway"). The client now retries 502/503/504 at 1, 2, 4 and 8 s.
- **Disambiguation card never renders:** `awaitsWorkflowInput` returns true for `workflow_type === 'disambiguation'`, and `onAdjustViaChat` is never passed in.
- **Slow follow-up turn:** the ~55–60 s between text and card is parameter grounding (`param_ground_*` status events). Worth a separate look.
- **Agent loop cannot create a workflow card:** on the compute path, the agent can find a pipeline with `search_workflows` but has no tool that produces a card, so it narrates ("pipeline configured"). The routing rules below keep pipeline-scale requests off that path. A card-producing agent tool (via the `selectedWorkflow` mechanism) is the remaining structural fix; it touches response plumbing and was not done unreviewed.
- **Proteomics differential abundance** still routed live to Chemoproteomics Pulldown, with a clarification question, despite the operation-phrase ranking fix (Pass-0 LLM ranking or dense retrieval can outweigh it, as predicted). Open.

### 10.5 Full live pass on dev `e04ec5f2` (2026-11-11 07:16–07:55Z, 39 rows, 3 workers)

- **Attachments:** 36/36 recorded rows attached exactly their own bundle.
- **Lost cards fixed:** Try-sample-data rows ending in a stored workflow card went from **1/12 to 10/11** recorded.
- **Workflow cards now produced for:**
  - ADMET ×2, docking
  - MAGeCK ×2, seqvartools (relatedness)
  - mixOmics ×2, MOFA2
  - CryoSPARC ×2, AlphaFold
  - scdownstream, DE chain ×3, sarek
  - differentialabundance (MG), metaboanalystr, flow cytometry, CAR-T, ChIP MACS, WSI nuclei segmentation, ATAC, chemoproteomics QC
- **Computed inline with real numbers** (valid direct compute on the attached data; the harness's "must be a card" expectation was too strict here):
  - variant burden on the Rizvi cohort (DCB vs NDB, Mann-Whitney)
  - PBC trial arms (log-rank p = 0.75, HR 0.944)
  - Cox flare model
  - CRISPR QC (Gini 0.297)
  - hERG series
  - biomarker panel
  - subtype classifier
  - proteomics batch QC
- **Defects found, and fixed in `7026189dfb`:**
  - **EBV simulated data:** EBV ran `run_code` that **simulated ELISA readings** and reported them as results.
    - Fix 1: `workflowNamedInRunRequest` pins a workflow the user names to run.
    - Fix 2: `generatesSyntheticData` detects run_code with no inputs that draws random values, and the reply gets an explicit "simulated, not a real analysis" note.
    - Fix 3: the `run_code` tool now forbids inventing input data.
    - A single-row rerun in the browser on `27e93b96` produced the EBV card, so the failure is classifier-nondeterministic, which is exactly what the pin removes.
  - **Call variants with FASTQ attached:** went to run_code and claimed "pipeline configured" with no card. Raw instrument data is now pipeline-scale: `direct_compute` is not honoured.
  - **Cryo-EM reply echoed `s3://…/Micrographs/`:** reply prose now passes through `redactStoragePaths`.

### 10.6 Deploy status at hand-off

- Dev runs `276e4e79` (`integration/tracks-20261111`; another session merged this branch up to `e04ec5f2` and deployed it). Healthy (HTTP 200).
- Branch head `c794bd6c` (adds `16b106a9ef` and `7026189dfb` on top of dev's line) is pushed to PR #365 but **not yet deployed**.
- **The full sync at 02:13 CST failed:** the SSH transport dropped during the nf-core check ("Bad packet length … Connection corrupted") before any files changed, and the script hung until its 90-minute limit.
  - The script's own remote lease (created 08:13:26Z, owner `fd6dfc01…`) was left behind and blocks every dev deploy.
  - It must be released (guarded on that owner id), then re-run `scripts/sync_to_dev.sh` from `/Users/kky/biomate-coldstart-dev`.

### 10.7 Deploy of `78aeb642` and the Galaxy outage it exposed (2026-11-11 13:26–13:44Z)

- **What happened:** after the sync restarted Galaxy, the new supervisor-managed gunicorn could not bind port 8080 (`Errno 98 Address already in use`). The health probes failed, and Galaxy-backed features (workflow generation, runs, `/api/health`) were down for about 18 minutes. The home page and login stayed up.
- **Root cause:** an **orphaned gunicorn master** (PID 152212, parent PID 1, about 6 h old, from an earlier restart around 07:38Z) still held the listening socket. It no longer served requests: no workers, about 194 connections queued, requests hung. The new code loaded cleanly.
- **Recovery (founder-approved):** SIGTERM had no effect (graceful shutdown never completed), so it was SIGKILLed. The supervisor's gunicorn then bound with 4 workers, `/api/version` returned 200, and the sync's health gate and smoke tests passed.
- **Follow-up:** the restart path in `scripts/sync_to_dev.sh` / gravity can leave an orphaned gunicorn master that survives later restarts and silently holds the port.
  - Before starting gunicorn, the deploy should check that nothing outside the supervisor tree holds 8080, and fail loudly if something does.
  - Also: an earlier full sync at 08:13Z died on an SSH transport error and left its own remote lease; it was released at about 11:10Z.

**Founder rnaseq flow on `78aeb642` (real chat API):**

| Turn | Result |
|---|---|
| 1. Library pick | PASS. No search stage; nf-core/rnaseq card. The reply leads with "**nf-core/rnaseq** — …", names the one input it needs (a sample sheet) and how to give it (📎 or an SRR/GSE accession). No "无法生成" / "缺少输入数据", no airway, no S3 |
| 2. "SRR1039508" | PASS. No search stage (value-only binding pinned the open workflow); the card stays rnaseq with SRR1039508 as the input |

### 10.8 Simulation is blocked, never disclosed as an ending (`baf85d3d05`, live on `a856c613`)

- **Founder direction:** telling the user a simulation was detected is fine, but it must not be the ending, and simulated numbers lower confidence even when disclosed.
- **Prevention:** `run_code` that would generate its own input values (no staged inputs, random draws or assumed distributions) is **refused before it runs**, unless the user explicitly asked for a simulation (power analysis, Monte Carlo, bootstrap, "simulate…", 模拟/蒙特卡洛…). The model receives a refusal that tells it to use real data, so no simulated number can reach a reply.
- **Recovery (Step 6r):** if that refusal happened and no workflow card exists, the real workflow is built: the one the user named, otherwise normal routing.
  - The turn ends on that **workflow card**, with one line: "A simulated-data attempt was detected and stopped."
  - If no workflow fits, the reply asks for the data.
  - `run_code` itself never has a card; it answers inline with real numbers, code and output files.
- **Deploy note:** the first frontend-only sync (`5744952d`) auto-rolled back. The smoke test's 25 s limit on Galaxy workflow generation was shorter than measured generation times (9.5 s, 11 s, 40 s). Raised to 90 s per CLAUDE.md rule 6 (`a856c613`); the re-sync passed.

**Live check on `a856c613`: EBV example × 5 (real chat API)**

| Run | Card | Search stage | run_code | Simulated numbers | S3 |
|---|---|---|---|---|---|
| 1–5 | Analyze Ebv Antibody Titers (`workflow_ready`) | no (pinned by name) | none | none | none |

### 10.9 Full live pass, 39 rows (dev `a856c613` → `d303eca6`, redeployed mid-run by another session; both contain all fixes through `a856c613`)

- **All 39 rows recorded.**
  - Attachments correct: 39/39.
  - Storage-path leaks: 0.
  - Simulated results or clarification bounce-backs: none.
- **Try sample data:** 11/12 end on a workflow card. EBV and Cox are now pinned by name. The classifier-training row computes inline.
- **Call variants with FASTQ attached:** nf-core/sarek card (the raw-reads rule); no "configured" claim without a card.
- **Remaining real defects** (in progress on agent branches):
  - Proteomics differential abundance still routes to Chemoproteomics Pulldown.
  - Hospital SNF multi-omics: a MOFA2 card was chosen although SNF was requested, and a "Which omics?" clarify card appeared although rna/protein/methyl CSVs were attached (the multi-file input was not bound).
- **Harness false positives (fixed in the harness):** "still in progress" matched words like "Analyzing" anywhere in a finished answer, so it now checks only the reply's ending. For proteomics batch QC, the stored session and screenshot show a complete answer (5 run_code calls + full QC table); the text capture was taken before the final text replaced the narration.

### 10.10 Dev ↔ git alignment (founder rule 2026-11-11)

- PR #365 was merged at `e04ec5f2`. Commits pushed to the branch afterwards were deployed while no open PR contained them; they are all on `integration/tracks-20261111` now, which dev runs.
- **Follow-up PR #374** (into `integration/tracks-20261111`) holds everything not yet on dev: the Gemini key-in-header fix, phase lettering, and the in-progress binding and routing fixes.
- **Rule from now on:**
  1. Sync only the pushed head of a branch in an **open** PR, after confirming dev's commit is an ancestor.
  2. After the sync, verify `build-info.json` equals that commit.

### 10.11 Founder UI_refinement screenshots — fixed and verified live (dev `0525045c`, 2026-11-11)

| Screenshot | Fix | Live result |
|---|---|---|
| whyPhaseBAsFirstPhase | phase letters by display position | single phase shows "Phase A" (unit-verified; frontend derivation) |
| not_aligned_workflowpanel_input / still_noInputWithAttachment | schema-driven attachment binding + reword | scFv example routes to `scfv_antibody_design`, uploaded PDB **bound** to `antibody_pdb` |
| parameterFillNotWorking | clarify-card resolves an attachment answer; auto-binding withdraws the card | binding fires at generation; fails safe otherwise |
| (potency) | model-training no longer routed to scaffold hopping | trains real models on the attached CSV (inline; see note) |

**Bonus issues found while verifying, also fixed + live:**
- Multi-omics "Integrate … with SNF" now routes to the **SNF** card (was MOFA2).
- Its `omics` input (`type: file[]`) now binds **all three** modality CSVs and the "Which omics?" clarification is gone. Two fixes: `isFilePathParam` accepts `file[]`; a multi-file param pre-bound to one file is topped up with the rest.

**Open / notes:**
- Potency training computes inline rather than opening the Models/ml_training card. Correct results on the attached data, and no longer a wrong design workflow; whether it should be a formal training card is a routing preference, not a bug.
- `prerequisitesValidation.fulfilled` is computed before the frontend binding runs, so it can read stale; the panel gates Run on the (now bound) param values, and the clarification card is correctly withdrawn.
- Clarify-card attachment interpretation is keyword-based (fails safe); an LLM-interpreted version via a server turn is a possible follow-up for broader phrasing.
- Catalog input metadata: 396/4227 workflows still have empty `input_types` and 32 use the `["input"]` placeholder — a routing-quality follow-up (separate from binding).

**Dev↔git:** each sync verified dev's commit was an ancestor of HEAD and that `build-info.json` equalled the pushed commit afterward. PRs #374/#375/#376 into `integration/tracks-20261111`.
