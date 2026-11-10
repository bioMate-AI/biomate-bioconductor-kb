# EPAR dataset test — chat + dataset-panel failures: root causes and fix plan (2026-11-10)

**Test input:** `data/glp_study_data/epar_study_tables.jsonl` — 2,281 valid JSON lines, every line the same
5 keys (`source, drug, page, headers[], rows[][]`), 227 drugs (EMA EPAR clinical-study tables).
**Surface:** dev (`https://dev-public.biomate.ai`), Chinese UI, project "test".
**Evidence:** 19 founder screenshots in `~/Desktop/business/bioconductor_screenshot/UI_refinement/` (2026-11-10).
**Code of record:** all file:line references are at **`99655a1a91`** — the commit actually deployed on dev
(sync worktree HEAD), read with `git show`. Not `integration/next-phase` (see §1).

---

## 0. The three questions, answered directly

### Q1. Why is a workflow always generated?

Not the LLM's choice — a hard-coded override, and the escape hatches that should prevent it don't understand Chinese.

1. **Classifier override (main cause).** `frontend/server/galaxy-assistant.ts:8776-8784` (`parseActions`):
   if the intent type is any of `workflow_generation, data_format_conversion, external_db_retrieval,
   visualization, multi_step_procedure`, `needsWorkflowGeneration` is **forced to `true`**
   (`mustGenerateWorkflow`), overwriting the classifier's own answer. The classifier prompt itself
   (GA:7248, 7508-7509) tells it to return `workflow_generation` + `needsWorkflowGeneration:false` for
   run_code work on uploaded files — and the override then throws that `false` away. "Extract/structure
   this data" (先做第一步) is `data_format_conversion` → always a workflow.
2. **The escape hatches are English-only or current-message-only** (GA:5103-5109):
   - `_isDirectCodeExecutionQuery` (GA:4446): Chinese only matches 运行/执行…代码; the "no workflow"
     directive only matches English ("do not launch … workflow").
   - `isAdhocAnalysisOfAttachedData` (GA:2466-2471): English verbs only — 统计/编程/解析/整理 miss.
   - `_directCompute` requires `hasComputableData(message)` (GA:2628), i.e. an `[Uploaded datasets: …]`
     block **in the current message**. The client only adds that block on the upload turn
     (`chat-interface.tsx:1789-1794`); on later turns it exists only in history. So on turns 2 and 3 every
     direct-compute check is false.
3. **"不用工作流" is not recognized as a refusal.** `frontend/server/execution-intent-guard.ts:21`
   `CHINESE_NO_EXECUTION` requires 不要/别/无需/不需要 **+ a verb** (运行/执行/生成…). "你可以直接编程统计吗
   不用工作流" contains 不用 and no verb → no match. The guard is also only consulted inside
   `prohibitsWorkflowExecution(...)` (GA:5415).
4. **The status line "正在检索 4,000+ 个工作流…" is a symptom, not a decision.** GA:5547 emits
   `onProgress('search')` whenever the (forced) flag is true → `routes.ts:7414/7421` SSE → `chat-interface.tsx:997`.

### Q2. Why can't run_code be used?

1. **Tools are switched off whenever a workflow card exists.** GA:10256
   `toolsEnabledThisTurn = (!useThinking && onToolEvent && !hasRunnableWorkflow)`; `hasRunnableWorkflow`
   (GA:9876-9880) is true for any successful `workflow_ga` — **including an empty one** (Q1 guarantees a card on
   every data turn). Same gate on the OpenAI-compatible (GA:10357) and OpenAI (GA:10412) paths.
   So run_code is never offered to the model on these turns.
2. **With tools off the reply goes through the text-only provider chain** (GA:10323-10440). Dev's chat model is
   `gpt-5.6-luna` (`scripts/sync_to_dev.sh:285`). A text-only model can *say* "我直接用 Python 代码在沙箱环境中
   统计分析……让我立即执行" and "已生成 clinical_studies_structured.csv" with nothing behind it.
3. **The guard against exactly this only runs in the agentic loop.** The "unexecuted code" nudge (GA:10477-10485)
   requires `_runCodeOffered`; the integrity disclaimer (GA:10467-10474) only matches English "query/search …
   database" phrasing. Neither covers the text-only chain or Chinese claims.
4. **The run_code retry fix (`aef0198c78`) was never deployed** — it is not an ancestor of `99655a1a91`
   (verified), despite `docs/20261110_ORGANIC_USER_COMPLETE_ISSUE_COLLECTION.md` stating "FIXED + deployed".

### Q3. Why is the BioMate answer locked in the progress box?

`frontend/client/src/components/chat-message.tsx:611-612`:
```tsx
{(progressMessages.length > 0 || (isWorkflowMessage && message.content?.trim())) && (
  <ProgressStreamBox messages={progressMessages} inline plan={isWorkflowMessage ? responseContent : undefined} />
```
and line 681: `{!isWorkflowMessage && responseContent}`.
When a reply carries a workflow card (= every data turn, Q1), the **entire final answer** is passed into the
progress box as `plan` and the normal body render is suppressed. The box (`chat-progress-fold.tsx:156`) is
`maxHeight: 132` (line 191), `overflowY:auto`, with a follow-tail auto-scroll (159-170) — so the answer is
clipped top and bottom and pinned to the end. `isWorkflowMessage` (chat-message.tsx:284) does not look at
streaming state, so it stays boxed after completion. Narration ("让我先预览文件内容……") and the final
answer are also not separated — both are in `message.content`; only `workflow_progress` messages are split off
(`chat-progress-fold.tsx:36`).

**The three questions share one root:** the forced workflow flag (Q1) produces a card on every data turn; the
card switches off run_code (Q2) and pushes the answer into the 132-px box (Q3).

---

## 1. "Already pointed out — not resolved, or lost again?"

Verified with `git merge-base --is-ancestor` and `gh pr view`:

- **Nothing was fixed and then reverted on dev.** The dev-deployed fixes are still present in `99655a1a91`.
- **What matters is what is on dev.** Two fixes were committed but never synced, so they are not live:
  the run_code retry (`aef0198c78`) and refresh-keeps-chat (`a7ade23c52`, PR #349).

| Issue | Earlier report | Fix commit | On dev? | In next-phase? | Verdict |
|---|---|---|---|---|---|
| Always / wrong workflow | 20261108 cluster 5 | `0a1b80b736` (attach-intent guard) | yes | no | **Partially fixed** — guard covers only "attach files" turns; the type override (Q1.1) was never touched |
| run_code not used | 20261106 §F; 20261110 I2 | `8ec3fbb1ef`, `d55de9be8a`; retry `aef0198c78` | first two yes; **retry no** | first two yes | **Partially fixed; retry never deployed**; the tool-gate (Q2.1) never addressed |
| Answer in progress box | 20261023 design problems; 20261107 lifecycle trace | none (`2b41d859c0` *introduced* the 132-px box) | — | — | **Never fixed** |
| JSONL as CSV / 8-row preview | 20261020 tracker + audit | none | — | — | **Never fixed** (`MAX_PREVIEW_ROWS = 8` unchanged since 2026-09-10) |
| QC card footer / "Watch" | 20261020 audit; 20261106 conformance | none | — | — | **Never fixed** |
| Folder upload / drag-drop | 20261109 organic | `3751a263f4` | yes | no | **Partially fixed** — chat input + upload dialog got folders; the **project Files tree** (the surface used) did not |
| English in zh UI | 20261108 cluster 2 | `8b2d54798f`, `89fb8358de`, `f6d4a580ae`, `e3e7f4d3bc` | yes | no | **Partially fixed** — screenshotted strings only; whole components (QC card) are still hard-coded English |
| Raw IDs shown | 20261108 cluster 1 | `3823ee6aa8`, `aebf2f5b4c` (prompt rule) | yes | no | **Partially fixed** — prompt rule only; the inline-param path (W4) still injects the UUID |
| Citations / "Read" | 20261107 trace | `6c5a7eddd4` | yes | yes | **Partially fixed** — folded, but no full-text fetch exists, so Read can never show text |
| Refresh → new chat | today | `a7ade23c52` | **no** | no | **Fixed, not deployed** (PR #349 open) |

**Why this keeps happening:** fixes were (a) scoped to the exact screenshot instead of the class, and
(b) declared "deployed" in docs without checking the fix is in the synced dev commit. See §5.

---

## 2. Chat & workflow issues

### W1 — Workflow always generated (`always_workflow.png`, `always_match_workflow.png`)
- **Symptom:** "你可以直接编程统计吗 不用工作流" → "正在检索 4,000+ 个工作流…" → reply says it will code
  directly, then "✅ I've generated a workflow…" + an unrelated *Estimate Alpha Particle Radiotherapy Dosimetry* card.
- **Root cause:** Q1 (1–4).
- **Fix:**
  1. `parseActions` (GA:8781): honour an explicit classifier `needsWorkflowGeneration:false` (at minimum when
     `execution==='direct_compute'` or data is attached); keep the type list only as a default, not an override.
  2. Add a Chinese no-workflow directive — `/(不用|不要用|别用|无需|不需要|不必)\s*(?:用\s*)?(工作流|流程|pipeline)/` —
     and treat it like `noWorkflowDirective` (GA:4454): force direct compute, never search.
  3. Chinese verbs in `_isDirectCodeExecutionQuery` / `isAdhocAnalysisOfAttachedData`:
     统计|计算|解析|提取|整理|汇总|画图|可视化|编程|写代码|用\s*Python.
  4. `hasComputableData` / `isAdhocAnalysisOfAttachedData`: look at the **session's** dataset blocks (history),
     not only the current message.
  5. Regression tests (vitest, `galaxy-assistant` intent tests): the three exact founder prompts must yield
     `needsWorkflowGeneration=false`.

### W2 — Wrong workflow attached; should output nothing (`wrong_workflow_shouldnotoutputatall.png`)
- **Symptom:** "先做第一步" (extract/structure the JSONL) → metagenomics **mmuphin** card with unset inputs.
- **Root cause:** W1 forces generation; retrieval then returns its nearest hit, and **there is no relevance floor** —
  a low-scoring match is still attached as a card.
- **Fix:** W1 removes the trigger. Additionally: when a card is attached, require the match score ≥ threshold **and**
  domain/input-type compatibility with the attached data (JSONL table ≠ abundance table); otherwise attach nothing.

### W3 — "Custom workflow" with zero phases; run_code task (`nothing_customized_workflow_runcodetask.png`)
- **Symptom:** "第2-5步，并提供结果文件下载链接" → card "Custom workflow", panel "尚未定义任何阶段".
- **Root cause:** `backend/lib/galaxy/ai/ai_assistant.py:5551-5580` — on the high-confidence template path, a match
  without `workflow_json` is built from `_build_workflow_ga_from_template({}, {})`; `_composed_workflow_name`
  returns the literal `'Custom workflow'` (:235); `steps={}`; still `success: True` (:5817). The frontend
  (`frontend/shared/workflow-response-state.ts:4-13`) and server `hasRunnableWorkflow` (GA:9878) accept an
  empty `steps` as a real workflow — which also disables run_code (Q2.1).
- **Fix:** backend returns `success:False` when built steps are empty and there is no `nextflow_path`;
  `hasGeneratedWorkflow` and `hasRunnableWorkflow` require ≥1 step or a `nextflow_path`. This task (multi-step
  table extraction + CSV outputs) belongs to run_code.

### W4 — Raw "Dataset Id" UUID shown as a required param (`userdoesnotreviewID.png`)
- **Root cause:** the client puts `[Uploaded datasets: name: dataset_id=<uuid>, galaxy_dataset_id=…, s3_uri=…]`
  into the prompt (chat-interface.tsx:1776-1794); the intent LLM copies `dataset_id` into `inlineParameters`;
  `remapInlineParametersForWorkflow` passes unknown keys through (GA:1515-1530) → `metadata.inlineParameters`
  (GA:6067) → merged into `workflowData.inline_parameters` (chat-interface.tsx:1184-1193) → shown as a field.
- **Fix:** never pass dataset-reference keys (`dataset_id, galaxy_dataset_id, s3_uri`) as inline params; keep only
  keys present in the chosen workflow's `required_params`/`optional_params`; bind files via
  `extractUploadedFileParams` (GA:5562) and display the **file name**, never the id.

### W5 — Claimed output file that does not exist (`whereistheclaimedfile.png`)
- **Symptom:** "已生成 `clinical_studies_structured.csv`" — no file, no link, no run.
- **Root cause:** Q2.2–Q2.3 — no tool ran; text-only model narrated execution; the fabrication guard only exists
  in the agentic loop and only for English DB phrasing.
- **Fix:** move the unexecuted-claim guard to the common post-processing of **all** provider chains: if no tool
  call produced an artifact this turn, strip/flag claims matching
  `已生成|已保存|已导出|生成了|saved|generated|created … \.(csv|tsv|xlsx|json|png|pdf)` and `让我立即执行|I'll run|Running now`,
  and replace with an honest "not executed" line + offer to run. Long term: W1+Q2.1 make run_code available so
  the claim is backed by a real artifact with a download link.

---

## 3. Chat rendering issues

### C1 — Answer locked in the progress box (`progressinbox_answershouldputbelow.png`)
- **Root cause:** Q3.
- **Fix:**
  1. `chat-message.tsx:612`: stop passing `plan=`; render `responseContent` normally, full height, **below**
     `ProgressStreamBox` (remove `!isWorkflowMessage &&` at :681).
  2. `ProgressStreamBox`: collapsible, auto-collapsed when the message is complete; keep the 132-px tail only while streaming.
  3. Separate narration from answer at the source: stream interim agent text as `workflow_progress` (or send
     `metadata.finalText`), so `content` = final answer only.
  4. Remove the "▶ Writing response…" `<details>` wrapper (chat-message.tsx:285-286, 680; hard-coded English) —
     stream into a plain div with the stage status inline.

### C2 — Two action rows under every answer (`over_complicated_regular_bottom.png`)
- **Where:** row 1 "Save to project" + "规划我的数据分析" — `components/benchmark-evidence.tsx:565-590`
  (tooltip `research_plan.hint`, zh common.json:1396); row 2 copy/download/regenerate/👍👎 — `chat-message.tsx:1180-1270`;
  plus duplicate "Save to notes / Make instruction" in `citation-panel.tsx:398, 430`.
- **Fix:** one hover-revealed icon row — copy · regenerate · 👍 · 👎 · "⋯" menu (save to project, save as file,
  plan analysis). Delete the button row in benchmark-evidence.tsx and the panel's save buttons.

### C3 — Citations over-complicated; "Read" never shows full text (`over_compicated_ciation_structure_clickalwaysnofulltext.png`)
- **Where:** `components/citation-panel.tsx` — retrieval header 484-506, `CitationItem` 736 with expand toggle,
  "open" (764-775), DOI (817-830), "Read" (842-851). Expanded by default (`benchmark-evidence.tsx:490`).
- **Why no full text:** "Read" and "open" both just open `SourceReaderPane` (`source-reader-pane.tsx`), which shows
  `abstract/excerpt` (often absent — `toEvidenceCitations` ~benchmark-evidence.tsx:465 doesn't pass them) and
  "Full text is not available". **No full-text fetch exists.**
- **Fix:** collapsed by default; one-line numbered references (title · journal · year → DOI link); remove the
  open/Read pair and per-item expand; "How this was searched · 3 of 15 kept" → tooltip. If an in-app reader is kept,
  implement a backend fetch (Europe PMC / PMC OA by PMID/DOI) and label non-OA items as such.
- **Relevance (separate):** the 3 kept sources ("How To Do a Debridement", "Uncemented Femur", "nondimensional numbers")
  are unrelated to an EPAR question — the retrieval relevance filter let them through; track under research-agent quality.

### C4 — Redundant title (`redundanttitle.png`)
- **Where:** breadcrumb `{project||'Unfiled'} / {'chat'|'new chat'}` (hard-coded English) —
  `chat-with-artifacts.tsx:2010`; title `t('New chat')` → 新对话 (~2017); separate "项目: test" strip —
  `ActiveProjectBanner`, `App.tsx:316-355`, mounted at :518.
- **Fix:** keep one line: title + small project chip. Delete the breadcrumb span; hide the banner on chat routes.

### C5 — Landing redundancy; design card (`rude_openningword_boxoutstanding.png`)
- **Where:** heading "您想做什么?" `cold-start-dashboard.tsx:1015` (`cold_start.heading`); composer placeholder
  "您想分析什么?" `chat-input.tsx:158` (`chat.placeholder`); cards `COLD_MODULES` (cold-start-dashboard.tsx:227),
  design card `id:"design"` (~291).
- **Fix:** keep the heading, change the placeholder to a neutral prompt (e.g. "描述您的研究目标，或附加数据…");
  remove the 分子设计与生成 card from the landing (and gate `nav.design_generate` the same way) per founder mark.

### C6 — English leaks in chat
- "✅ I've generated a workflow for you based on your request." — `chat-interface.tsx:1137`, appended when the reply
  lacks the English word "workflow" (a Chinese reply never contains it → always appended), persisted into content.
  **Fix:** delete the append (the card already says it); never append after a no-workflow directive.
- Card chips "Completed/Running/Ready" and "Open" — `chat-message.tsx:~741, ~768` hard-coded. **Fix:** i18n.
  "已在面板中" chip (`chat-message.tsx:755-760`) — redundant with the open panel; remove.

---

## 4. Dataset panel issues

### D1 — JSONL shown as CSV fragments (`jsonl1format_not_wellpresented.png`)
- **Symptom:** columns `{"source": "epar_table"`, `"drug": "pluvicto"`, `"page": 30` …; "2,270 rows × 78 columns";
  type `application/octet-stream`.
- **Root cause (verified):** `backend/lib/galaxy/ai/data_perception.py` `_sniff_kind` (~490-519) has no
  `.jsonl/.ndjson` case; the content sniff `if "," in head or "\t" in head: return "table"` catches every JSON line;
  `_sniff_delimiter` picks `,`; `_read_table` (634-649) runs `csv.reader`. **Reproduced locally:** `csv.reader` on this
  file yields exactly 2,271 rows (header + 2,270) × 78 header columns — the numbers the panel shows. The real file is
  2,281 records × 5 fields. Upload stores `req.file.mimetype || "application/octet-stream"`
  (`frontend/server/project-routes.ts:731, 755`) — browsers send an empty type for `.jsonl`.
- **Fix:**
  1. `_sniff_kind`: `.jsonl/.ndjson` → `"jsonl"`; content sniff: if line 1 `json.loads` to a dict → `"jsonl"`.
  2. New `_profile_jsonl`: stream lines; columns = union of top-level keys; nested lists/dicts rendered as compact
     JSON (or "list[11]" summary) per cell; true record count; same `columns`/`sample_rows` contract.
  3. Upload: derive mime from extension when empty/octet-stream (`.jsonl` → `application/x-ndjson`).
  4. Unit test (`backend/test/...data_perception`): this file → kind `jsonl`, 2,281 rows, 5 columns.
  5. Breadcrumb truncation (`datasets/dataset-object.tsx:349-366`): add `min-w-0`; or drop the name from the
     crumb (title at :371 already shows it).

### D2 — Only 8 rows, no scroll (`no_scrolldown_only_8samples.png`)
- **Root cause:** `data_perception.py:74-76` `MAX_PREVIEW_COLS = 12`, `MAX_PREVIEW_ROWS = 8` (applied 699-701);
  the frontend renders only `profile.sampleRows` (`dataset-object.tsx:516-581`) in an `overflow-x-auto` box (:544);
  column stats computed on those 8 rows (`dataset-columns-view.tsx:120`, zh common.json:351).
- **Fix:** paged rows endpoint `GET /api/projects/:id/files/:fid/rows?offset&limit` using the same parser as the
  profiler; table in a `max-h-[60vh] overflow-auto` container with sticky header and on-scroll loading
  (virtualized). Column stats computed on the full file at ingest (or a large sample, labelled with its true size).
  Stop-gap only: raise the sample to ~200 rows.

### D3 — QC card: wrong hint, "Watch", contradictions, footer, English (`QCdoneinfull_rowtableonly8samples_removebottomline.png`)
- **Where:** `components/data-perception.tsx` — entirely hard-coded English (title :154, stats :174-190, sections
  :207/217/245/260/278, status :88/94/100, footer :293-297).
- **"Why Watch?"** `data_perception.py:703-785` sets Watch on near-constant columns (≥99%), ≥50%-missing columns,
  label spelling dupes, minority <20%, leakage or an effective-N note. Here every trigger is an **artefact of D1**:
  the CSV split creates constant columns (`{"source": "epar_table"`) and mostly-empty ragged columns. Fix D1 and
  this file will profile clean.
- **Wrong Effective-N hint:** :188-191 always says "correlation / imbalance discounted it" when `effectiveN < rows`;
  with no label column the backend computes `effective_n = _dedup_count(rows)` (:778-780) — the true reason is
  duplicate rows. **Fix:** backend sends `effectiveNReason: "dedup" | "imbalance" | "correlation"`; i18n text per reason;
  fix the hint wrapping in `Stat`.
- **Contradictory Notes:** :786-789 add "no leakage, imbalance, or constant-column issues detected" whenever `notes`
  is empty, ignoring `signal` (which lists near-constant/missing columns). **Fix:** only when both are empty.
- **Footer:** delete "Perception is computed by the backend profiler…" (:293-297) as requested.
- **i18n:** add `perception.*` to `locales/{zh,en}/common.json` and route every string through `t()`.

### D4 — QC belongs under the rows; placed in 溯源 (`QCshouldunderrows_whywatch.png`)
- **Where:** quality block inside the provenance tab — `dataset-object.tsx:842` (`tab === "wherefrom"`), block 907-946,
  "运行完整质量检查" 913-924.
- **Fix:** move the block into the 预览 tab directly under the table (~after :595). 溯源 keeps source/added/hash/runs only.

### D5 — Cannot select or drag-drop a folder; "Failed to fetch" (`cannot_select_folder.png`, `filefolder_cannotdragdrop.png`)
- **Root cause:** `components/project-file-tree.tsx` — hidden input (632-639) is `type="file" multiple` without
  `webkitdirectory`; drop handler (557-561) passes `e.dataTransfer.files` directly — a dropped folder arrives as a
  directory pseudo-File; `handleUpload` (448-469) puts it in FormData and Chrome rejects the read →
  `TypeError: Failed to fetch` → shown raw in red (466, 684-685). The server keeps only the basename
  (`project-routes.ts:718-723`), so structure would be lost anyway. The folder fix `3751a263f4` covered the chat
  input, `file-upload.tsx` and the dataset dialog — **not this tree**.
- **Fix:** reuse the existing folder logic (`chat-input.tsx:548`, `file-upload.tsx:477`): "添加 ▾ → 文件 / 文件夹"
  (second input with `webkitdirectory`); `onDrop` walks `e.dataTransfer.items` via `webkitGetAsEntry()` recursively;
  skip directory pseudo-files; send `relativePath` and use it in the S3 key/stored name so `buildTree` shows folders;
  upload per file so one failure doesn't abort the batch; localized error text.

### D6 — Data page: redundant header, short empty box (`reduandant_info_tooshot_datapanelbox.png`)
- **Where:** `pages/data-hub.tsx` — crumb "数据 / test" 213-223; `<h1>数据</h1>` :225; "进行中" badge 228-230;
  intro paragraph 252-254 (`data_hub.intro`, zh :390); empty card 308-316 sized to content (`py-8`).
- **Fix:** title = project name with a small "数据" crumb, no h1 duplicate, no status badge, no intro paragraph;
  empty pane `h-full` matching the file tree — or auto-open the first dataset.

### D7 — Project page / sidebar (`removenewchat_remove_sidebar.png`)
- **Where:** workspace "新对话" `components/app-sidebar.tsx:298-303` duplicates per-project "新建对话" (:389) and the
  page's own "新建对话" button; Notes card `pages/project-detail.tsx:858-862` ("Notes — Private to you — not read by
  the assistant", hard-coded English) beside 常驻指令 (809-820).
- **Fix:** remove the workspace-level New Chat (check `data-testid="button-new-chat"` users first; unfiled chats are
  started from the landing composer); merge Notes into the 常驻指令 card (or remove it) and localize.

---

## 5. Fix plan

**Order** (each item: root-cause fix + regression test + live verification on dev with this EPAR file):

| Pri | Items | Why first |
|---|---|---|
| **P0** | W1 (override + Chinese directives + history datasets) · Q2.1 tool gate (empty/irrelevant cards must not disable run_code) · W3 (empty workflow ≠ success) · W5 (fabrication guard on all provider chains) | One root (forced workflow flag) produces W1–W5 and C1 |
| **P0** | C1 progress box | Every data answer is currently unreadable |
| **P0** | D1 JSONL profiler | Everything shown for this file (rows, columns, QC, Watch) is computed on garbage |
| P1 | W2 relevance floor · W4 dataset-id params · D2 full rows · D3 QC card · D4 placement · D5 folders | Correctness / trust |
| P2 | C2–C6, D6, D7 | Simplification and i18n |

**Process changes (so issues stop "coming back"):**
1. **"Fixed" means:** the fix is in the commit synced to dev **and** the founder's exact scenario passes on dev.
   Docs claiming "deployed" must state the dev SHA they checked
   (`20261110_ORGANIC_USER_COMPLETE_ISSUE_COLLECTION` claims `aef0198c` deployed — it is not).
2. **Fix the class, not the screenshot.** Folder support was added to 3 upload surfaces but not the 4th; i18n fixed
   the photographed strings but not the components. Each fix must grep every surface sharing the pattern.
3. **Regression test per item** (vitest for intent/rendering, pytest for the profiler) using the founder's exact
   inputs (the three Chinese prompts; this JSONL).

Related open PRs: #347 (contrast), #348 (type ramp + light-only), #349 (refresh keeps chat).
