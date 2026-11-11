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
- Live verification on dev after sync: re-open c0d27792. Expect `tool_error` / "too few rows" in zh, with the traceback excerpt. Try launching on `contrasts.csv`: expect the panel to refuse before submit.
