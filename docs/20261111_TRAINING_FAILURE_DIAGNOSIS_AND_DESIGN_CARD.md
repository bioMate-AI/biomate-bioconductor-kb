# 2026-11-11 — Training failure diagnosis + restored molecule-design card

Branch `integration/tracks-20261111` (worktree `/Users/kky/biomate-epar-p0`).

## 1. "Molecule generation cold-start module disappears"

**Cause.** Commit `2c652b2a0b` (Track D chat cleanup, 2026-11-10) hid the landing
card *Molecule design & generate* and the `/design` route behind a new
`VITE_ENABLE_DESIGN_GENERATE` flag that defaults to off. Its comment cited a founder
"over-claim" review. That review was about the two chat-footer buttons ("Save to
project", "规划我的数据分析"), not this module. The commit reached dev in `3b329654`.

**Fix (`dbf9b89f5d`).** The flag is removed, and the card and route are always on.
`cold-start-dashboard.test.tsx` now asserts that the card renders.

## 2. Training run "failed — missing command or image" (dev run c0d27792)

**What actually happened.** The user trained `sklearn_tabular` on
`contrasts.csv` from the MG PBMC demo project, using target `variable`. That
file is a one-row DESeq2 contrast spec, not a training table. The task's
`.command.err` on S3 says:

```
ValueError: cannot make 5 folds from 1 rows
```

The training container behaved correctly. Every layer that reported the failure
was wrong:

| Layer | Wrong output | Root cause | Fix |
|---|---|---|---|
| `frontend/shared/run-failure-classifier.ts` | "A tool or container … was not available (missing command or image)" | The container rule matched the bare word `container` plus `error`. Nextflow prints a `Container:` banner on every failed task. | Match specific phrases only (`command not found`, `pull access denied`, `CannotPullContainerError`, exit 127 …). New classes `too_few_rows` and `tool_error` (the tool's own exception). The raw line prefers the exception. |
| Galaxy `_classify_failure` | `unknown` → "You can resume from the last completed step" | For `s3://` (AWS Batch) work dirs, `.command.err` was never read. A deterministic exception fell through to "unknown/resume". | `_collect_failed_task_errors_s3`: tasks with a non-zero `.exitcode`, cached per terminal run. Tool exceptions → `tool_error`/`check_input`. New `error_detail` field. |
| Galaxy snippet | Last 20 log lines = executor shutdown noise → the UI said "No error log captured" | The snippet was always the tail. | The snippet ends at the exception, with its traceback just before it. |
| Workflow-panel diagnosis card | English in a zh session; a false "process was killed … `docker logs`" note | Hard-coded English | Locale keys `panel.diag.*` (title, category sentences, advice). The false note is removed. |
| AfterRunReport cause | English cause under 失败原因 | Classifier sentences were English only | Classifier results carry `i18n` keys + vars, rendered with `tOr`. `failure.*` locale block in zh and en. |
| Failure toast | Sticky red toast over the panel | `duration: 0` | 12 s. Not shown for the run already open in the panel. |

**Prevention at launch.** `MIN_TRAIN_ROWS = 10` (k-fold: `max(10, 2k)`):
- **Server:** enforced in Galaxy `/api/model-training/plan`. Delimited tables are profiled with the perception profiler. An unreadable file counts as unknown, not as 0 rows.
- **Panel:** submit is disabled, with a localized message.
- **Server refusal message:** `dataset_too_small:<rows>:<need>`, which maps to the same message.

## Tests

- `frontend/shared/run-failure-classifier.test.ts` — 13 pass. Includes the real `log_tail` of c0d27792.
- `backend/test/unit/webapps/api/test_nextflow_failure_batch_stderr.py` — 5 pass. Replays the real `log_tail` and `.command.err`, with a fake S3 for the collector and its cache.
- `backend/lib/galaxy/ai/ml_training/tests/test_general_tables_and_plan.py` — 19 pass, 1 skipped (clean venv; local Anaconda scipy is broken).
- `workflow-failure-settings.test.tsx` (localized diagnosis).
- Models, launcher, viewer and AfterRunReport suites — pass. `afterrun-evidence-navigation` timed out once under machine load and passes alone.

## Open

- There are two diagnosis surfaces for one failed run: the panel "AI 诊断" card (Galaxy verdict) and the AfterRunReport 运行失败 block (TS classifier). Both now agree and are localized, but they should become one surface.

## Live verification on dev (2026-11-11, dev = `279d6d27`, guarded syncs `3b329654 → e5dd8c3b → 279d6d27`, both healthy)

- **Landing:** 4 cards, `search`, `analysis`, `design` (分子设计与生成) and `models`; `/design` renders.
- **Galaxy status for c0d27792:** `failure.category=tool_error`, `suggested_action=check_input`, `error_detail="cannot make 5 folds from 1 rows"`. The snippet ends at the ValueError traceback (it was `unknown`/`resume` with a noise-only snippet).
- **`POST /api/model-training/plan` with contrasts.csv:** HTTP 400 `dataset_too_small:1:10`.
- **Models → 训练:** choosing contrasts.csv shows "该文件只有 1 行数据，训练至少需要 10 行……" and 开始训练 is disabled. counts_matrix.csv is not refused.
  - The first deploy (`e5dd8c3b`) did NOT show this message: the launcher read `body.rows`, while `DataProfile.to_dict()` emits `shape.rows`. Fixed in `279d6d27`, and the unit test now uses the real shape.


## Overnight session (2026-11-11, autonomous)

Dev line: `279d6d27 → 42234e2a → 27e93b96 → c7ab2b79 → 276e4e79`, all through the guarded sync. One sync was blocked by the lock while another session (`fix/coldstart-search-examples-dev`) deployed. That session had merged this branch first. Its branch was merged back here (clean) before the next sync.

| # | Defect found (live) | Root cause | Fix | Live check |
|---|---|---|---|---|
| 1 | 训练运行 showed "Not recorded" for a completed run with accuracy 0.896 | The `biomate-nextflow-work` bucket is in us-east-1. The metrics reader used a us-west-2 client, got `PermanentRedirect`, and swallowed it. | Use `_s3ClientForBucket`, which resolves the region and is MinIO-aware. Unreadable metrics are logged. | `/api/model-tracks/train`: `accuracy 0.896 · pass · 0.6` |
| 2 | "Adaptation retrain" rows in 训练运行 | The house-style prompt-rules compile was registered as `workflow_type: training`. | New runs use `adaptation`. Legacy rows are recognised by the `adapt_compile` step. They stay in Run Manager. | Rows gone |
| 3 | Metric name in English in zh (`accuracy 0.896`) | Raw metric id was shown | `models.metric_*` names; added f1/rmse/pr_auc | 准确率 0.896 |
| 4 | An interrupted run showed 排队中 | Unknown status fell back to `queued` | `interrupted` → 已中断 (terminal). Unknown → 状态未知. | unit |
| 5 | Raw ISO time in 训练运行 | No formatting | Local date-time in the UI language | unit |
| 6 | Run Manager in English (bucket titles, status, CTAs, readiness, "4m ago", run/inv) | Hard-coded strings | `runs_ui.*`. Identifiers are unchanged. A failed card says 查看失败原因, not "Retry Search". | screenshot: fully zh |
| 7 | 需要关注 = 46, mostly successful runs | `getOutputCount` ignored `s3_output_files` (AWS Batch) | Count them | 需要关注 46 → 25; cards say 查看输出 (5) |
| 8 | URL import: `数据.csv` and `样本.csv` → one `__.csv` object; same name with new bytes overwrote the old | Lossy basename key, no versioning | Shared `_storeProjectInput` with upload: `projectInputPath` key and versioning | route tests |
| 9 | Project page in English (tabs, instructions empty state, plan card, Details, dialogs, "6 messages · 6d ago"); Notes card marked for removal | Hard-coded strings | `projects.page.*`; Notes card hidden (API kept); 404 page localized | pending sync |

Live journeys: 4/4 on `279d6d27` and 4/4 on `42234e2a`. Journey (e) now also asserts that a 1-row table gets `dataset_too_small` at plan time, and that the completed run carries its score and gate in API and UI.

Left for the founder:
- The workspace-level 新对话 (blue box in `removenewchat_remove_sidebar.png`) is still there. Removing it leaves no entry point for an unfiled chat other than the landing, and ~10 e2e specs click it. This needs a decision.
- The leaked test project "live-journeys 2026-11-11T04:35:27.433Z (auto-deleted)" belongs to an interrupted run before the state-file move. Delete it on approval.
- Two diagnosis boxes on a failed run (still to merge into one).
