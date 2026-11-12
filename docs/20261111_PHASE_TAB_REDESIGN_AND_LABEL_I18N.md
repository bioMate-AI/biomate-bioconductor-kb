# Phase tab redesign + catalog label i18n (2026-11-11)

Founder: "ask Gemini to improve the phase tab view first, ugly." Deployed to dev at
`af5d5767` (branch `fix/coldstart-search-examples-dev`, PR #379; i18n work on
`feat/catalog-label-i18n-20261111`, merged in).

## Method

1. The first Gemini review used the founder's backlog screenshots — those were
   stale (e.g. the "QC gate on every phase" was already fixed in code). Re-captured
   the **live** zh phase tab on dev (Playwright, fixture login,
   `biomate-user-settings.language=zh`, MG PBMC → nf-core/differentialabundance)
   and had **Gemini 4 Carbon** review that.
2. Implemented the structural recommendations; declined its per-workflow zh string
   map for backend labels (keyword overfitting) and built a translation source
   instead (below).
3. Render tests on the real live values; full suite; deploy; live re-capture with an
   automated leak scan (`s3://`, `\bS3\b`, UUIDs) — 0 leaks.

## Phase tab — what changed (`nextflow-workflow-viewer.tsx`)

| Before (live) | After |
|---|---|
| Params `s3://biomate-nextflow-work/uploads/<uuid>/sample_metadata.csv` | `sample_metadata.csv` chip (collapsed); read-only chip + 清除 in edit mode |
| Step "Download samplesheet and count matrix **from S3**" | infra words stripped (`userFacingStepName`) |
| Badge "A" + "Phase A" + muted "Input Download" | badge "A" + semantic title |
| "尚未开始 · 1 步" + disabled 运行 on every row pre-launch | "1 个步骤"; status + per-phase run only once a run exists |
| Phase count shown 3× (tab badge, "4 个阶段", "阶段 · 4") + helper paragraph | in-list label and helper removed |
| ○ rail dot + ① ordinal | one status dot; no rail on single-step phases |
| Step-row param meta repeated the phase params (raw) | cleaned; keys already shown in the phase block skipped |
| Adjust & Rerun dialog: raw path input, hardcoded English | read-only filename for stored files; localized (zh/en) |

Sanitizers live in `client/src/lib/user-facing-text.ts` (client twin of the server's
`redactStoragePaths`).

## Catalog label i18n

Phase / step / parameter names come from `.nf` `// [Label]` annotations and the nf
schema in English. New: `POST /api/i18n/labels` (`server/label-translation.ts`) —
one batched `callGeminiFlash` (gemini-3.8-flash, JSON mode) per set of unseen
labels, cached per unique string (in-memory, keyed by `PROMPT_VERSION`), identifiers
and CJK skipped, any failure returns the English source. Client hook
`useLocalizedLabels` (identity outside zh).

Prompt measured offline on **114 real catalog labels** (69 phase names, 35 step
descriptions, 10 param labels):

| Prompt | Outputs still carrying ordinary English |
|---|---|
| v1 | 15/114 ("Count 矩阵", "Peak Calling", "下载 samplesheet 与 count 表达矩阵") |
| v2 + regex repair pass | 4/114 flagged, but **translated function names** ("pifit" → "π 拟合", "fetch()" → "获取函数") — removed |
| **v3 (deployed)** | 0 real defects; code identifiers kept exact |

Live result: 获取输入文件 · 归一化 · 差异丰度分析 · 可视化与报告; step 获取样本表与计数矩阵;
params 样本表 / 矩阵.

## Verification

- Unit/render: `nextflow-workflow-viewer.display.test.ts` (live values),
  `nextflow-workflow-viewer.test.tsx` (no storage path collapsed or in edit mode),
  `label-translation.test.ts`, `use-localized-labels.test.tsx`.
- Full vitest 3145 passed / 0 failed; tsc clean; backend py3.9 compile for merged
  backend files.
- Live dev capture after deploy: 0 leaks; screenshots in session scratchpad.

## Deploy notes

The sync gate refuses when the **ledger** commit (often a backend-only deploy that
does not move build-info) is not contained — merge the commit the gate names, not
build-info's. Never kill a running sync (orphans the remote lease).

## Open / next

- Other surfaces showing catalog English in zh (workflow card, step detail,
  after-run section names) should adopt `useLocalizedLabels`.
- Translation cache is per-process; a persistent cache (DB/Redis) would avoid
  re-translating after each deploy.
- Workflow name (`nf-core/differentialabundance`) intentionally stays an identifier.

## Round 2 — other panel surfaces (deployed `d6213398`, live-verified)

Live zh capture of the chat card, settings tab and full step view found:

| Surface | Before (live) | After (live) |
|---|---|---|
| Settings tab inputs | "无必需的数据输入 · 无需上传数据" although samplesheet + matrix were bound — schema declares `required: []`, classifier dropped them | **已映射 3 个**: 样本表 / 矩阵 / 对比组 → filenames (`isBoundUserDataParam`: bound canonical-named or stored-file params count; unbound ones are not invented) |
| Settings row tooltip | raw storage URI | dataset name / filename |
| Run-button references | reply "点击Run按钮", hint “确认并运行工作流” — no such button | `server/ui-labels.ts runButtonLabel()` reads the label from the client locale bundles; prompt, Step 6r message and hint use it |
| Full step view | "Download samplesheet and count matrix from S3" · PENDING | 获取样本表与计数矩阵 · 待运行 (human name, process id as tooltip) |
| Label cache | in-memory only | migration `0023_label_translations` (keyed by prompt_version); confirmed rows on dev via read-only query |

Automated live check (`frontend/_e2e_surfaces.mjs`, scratch): settings summary, no
"no inputs" claim, no wrong button name, step-detail status localized, and a leak
scan over visible text **and tooltips** on every surface — all clean. Full vitest
3152 passed / 0 failed.

Dev deploy note: dev runs whichever branch synced last (ancestry-gated). This
round's sync merged `63ecd58f` (deploy/datasets-20261111) as the gate required.

## Round 3 — hover hints + chat tool cards (2026-11-12)

### Hover hints (`6078147d50`)

Founder: "add hint text hover for each element in the side bar, each tab in each panel".
`client/src/components/ui/hint-tip.tsx`: `HintTip` (plain elements) and `HintTabsTrigger`
(Radix tabs), one provider at the app root (`HintScope`, 400 ms delay, instant on the next
item). Strings under `hint.*` (zh + en). Covered: every sidebar item and the collapsed rail,
workflow-panel / after-run / Models / model-object / Settings / Workflows-library / dataset /
project / Connectors tabs.

Committee review (3 reviewers: Radix/a11y, copy accuracy vs code, coverage/tests):

| Finding | Fix |
|---|---|
| TabsTrigger inside TooltipTrigger: tooltip's `data-state="closed"` overwrote `active` — selected tab lost its styling (Settings, Models, model tabs) | `HintTabsTrigger` composes tabs-outside / tooltip-inside; test asserts `data-state` |
| 9 hints promised things the code does not do (model "compare any two" versions — single version, no compare button; "Used by" = registering campaigns; evidence always not-evaluated today; chat dot = roll-up, not last run; after-run summary has links, not previews; …) | rewritten against the code, zh terms aligned (项目指令, 候选提案) |
| e2e SB-12 read the dot's `title` | dot carries `data-status`; hint moved to the row (full title + status) |
| hard-coded 系统管理 / "shared" / "Run History" / "My Imports"; rail English titles | localized; rail gets short aria-labels |

Not hinted (judged self-explanatory or low reach): empty-chat track tabs (examples visible),
trajectory filter, step-detail raw/rendered toggle, chat-composer buttons (still native
localized titles).

### Chat tool cards + truncated tool turn (`86fedca8f9`)

Three founder screenshots of an image-QC chat:

1. `Read File {"galaxy_dataset_id":"<uuid>"}` — raw tool input shown. Server now attaches a
   user-facing `display` to each `tool_call` (`shared/tool-call-display.ts`: dataset id → its
   name, other ids dropped, storage path → file name); the card renders it, never the JSON.
   Card labels localized.
2. Collapsed code preview cut its second line in half — `max-h-12` clip + leading blank line.
   Now two whole lines + "+N more lines".
3. Answer was only "现在让我生成可视化的 QC 报告：". **Dev logs** (05:10–05:25 UTC,
   z-ai/glm-5.2 via OpenRouter): tool turn 5 ended `stop_reason: 'max_tokens'`; the loop took
   the fragment as the final answer and the plotting script never ran. Fix: a `max_tokens` turn
   keeps its text, drops the unrun tool_use, instructs the model to continue with a shorter
   script; at the tool budget the final-answer turn fires after `max_tokens` too.
   **Root cause of the truncation itself** — reasoning tokens counted against `max_tokens:
   4096` on OpenRouter reasoning models — is §2 above (fix deferred by the founder; the
   OpenRouter-vision lane owns `local-llm.ts`).

Verification: tsc clean; full vitest 3239 passed / 1 failed (`pdf-canvas-viewer`, unchanged
file, passes in isolation — load flake; the previous run's single flake was a different
file). Live verification on dev pending the deploy lane.

## Round 4 — "no galaxy in output", committee review, leak sweep (2026-11-12, overnight loop)

Founder: "there should not have galaxy in output!!!!"; then "keep audit, fix, sync, test loops".

| Commit | What |
|---|---|
| `69488bd245` | Response model sees one neutral `dataset_id` per file (`modelFacingUploads`, incl. legacy `[Galaxy dataset: …]` history lines); tool schemas `dataset_id`; system prompt without the backend name; final-reply guard; tool card result/error sanitized; UI copy |
| `553cb8d449` | Committee correctness review (6 verified defects): prose answers keep their text on `max_tokens` (only mid-work turns are continued, text carried); OpenRouter length stops become `max_tokens` turns (`lengthStopMessage`) instead of throwing; backend-name guard narrowed (prose only — fenced/inline/indented code untouched; Galaxy-platform answers unchanged); upload entries with spaces / ':'; Gemini fallback history; run_code earlier-turn mapping |
| `ae19b4cbed` | Leak sweep of every user-reachable surface: shared `userFacingErrorText` for panel + after-run report; 12-h stuck-run message; methods-report prompts/params/filename; step view job id + work dir hidden; failure classifier file names; response prompts ("BioMate cloud compute" + never-name-infrastructure rule); chain reply; IT launch error; ai_assistant.py composer note; tour / Models / public pages / billing copy |
| `303d4fdfeb` | Merge of dev build `6474f200` (08's sync; its `redactInternalRefs` combined with the tool-card sanitizer) |

Reasoning-budget fix (OpenRouter reasoning tokens counted against `max_tokens`) was already
committed (`9a5f98c58e`) and live on dev; the "uncommitted" copy in `/Users/kky/biomate-review`
is a stale duplicate.

**Incident — branches reset by another account.** GitHub user `zheganjue519` force-pushed the
`integration/next-phase` tip over `fix/coldstart-search-examples-dev` (06:43 UTC, 13b0206c6f →
5a1abf0990) and over `fix/hints-toolcards-no-backend-20261112` (07:04 UTC, 553cb8d449 →
d1f7477c75), which auto-closed PRs #388 and #389. Integration does NOT contain these changes.
Not a GitHub workflow (auto-merge-on-approval only enables auto-merge). The work is preserved
under tag `keep/f9-hints-toolcards-20261112` and re-pushed before each sync; no force-push war.
**Needs the founder:** ask who/what runs as `zheganjue519` and whether PR head branches of the
dev line should be left alone.

Verification: tsc clean; server+shared 1953/1953; client 1348 + 1 known load flake
(`pdf-canvas-viewer`, passes alone).
