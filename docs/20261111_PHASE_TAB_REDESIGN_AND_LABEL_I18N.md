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
