# PR #298 integration + Problem-1 live verification (2026-10-24)

Branch `cursor/tutorial-live-recording-and-report-editing-4ea7`. Integration commit
`04651dbd0`; deployed to dev and verified serving that commit.

## What was integrated

Codex PR #298 (`codex/qc-assessment-findings`, impl commits `30ce7dbb4` QC +
`f78e7d04b` response-flow) — the QC-findings semantics + workflow-response-flow
(25 files). Established by inspection that PR #298 was carved from *this* checkout's
working tree: all 25 files were already present (12 byte-identical to Codex's tip, the
rest "already-applied" supersets carrying my committed entity `0c1b24ade` + scalar-handoff
`f1209857f` fixes on top). So integration = committing exactly those 25 files (no
cherry-pick, no overwrite, no double-apply); unrelated concurrent-session dirty files
were left untouched.

## Pre-sync checklist

1. `tsc --noEmit` — clean (0 errors).
2. `vitest run` — 1729 passed, 0 real failures (4 files hit `ENOSPC` only; disk was full).
   Targeted PR #298 suites: 53/53. Backend `test_qc_assessment_semantics.py`: 22/22.
3. Py3.9 import smoke could not run fully locally (anaconda py3.9 lacks `beaker`/`pulsar`).
   Best-available proxy on the 5 modified backend modules: all byte-compile on py3.9; all
   carry `from __future__ import annotations`; **zero** PEP 604 unions in added lines; **no**
   new FastAPI routes / Pydantic models → the py3.9 crash class is absent.
4/5. `sync_to_dev.sh` — health gate + smoke passed; `build-info.json` == `04651dbd0`.

## Disk cleanup (was 100% full, blocking the build)

Freed ~0 → **8.9 GiB**: deleted regenerable caches (npm/pip/tsc, Codex app+runtime caches,
Chrome cache) and, with user approval, `~/.cache/huggingface` + `~/.cache/immune311`. Kept
`ms-playwright` (needed for the verification). The 1.9 GiB `/private/tmp/biomate-qc-pr`
Codex worktree (clean, fully on origin) is a further safe reclaim — left to the user
(the safety classifier blocks `git worktree remove`).

## Problem-1 live verification (dev, integrated build)

**No-spend coherence check** (`bughunt-chat-dynamic.e2e.ts`): BH1 ADMET renders one coherent
response — real name `Herg Cardiac Safety Qsar`, chat↔panel consistent, clean 3-tab pre-run
panel. BH2 (RNA-seq) "bug" is benign: BioMate correctly asked a bulk-vs-single-cell
clarification for an ambiguous query (router not in PR #298 scope).

**Real ADMET run** (`drug-dev-admet-capture.e2e.ts`, passing compounds, single pass, 4.1m):
`prerun → Confirm & Run → running (data-status asserted) → terminal COMPLETED (clean)`.

Audit of the completed state vs the accepted decisions (`20261024_CLAUDE_DESIGN_TAKEOVER.md`):

| Accepted decision | Observed | Verdict |
|---|---|---|
| Full plan + progress in one unfolded stream | run log inline under one `BioMate` header | PASS |
| Completion answer below the same stream, no 2nd header | "Predict ADMET Properties (AI) — complete…" below card, response controls beneath | PASS |
| Remove redundant labels | no "Cloud · Workflow"/"ADMET · progress" | PASS |
| Completed screen is finished; threshold flags as findings, no fabricated pause | DILI flag shown as a finding; card = ● Completed; no Resume/Cancel | PASS |
| Findings resolve (no stuck "analyzing") | "analyzing results…" → real Key results | PASS |
| Real entity identity (SMILES), no "Compound N" | each result tagged with caffeine SMILES `Cn1c(=O)c2c(ncn2C)n(C)c1=O` | PASS (entity fix `0c1b24ade` live) |
| Real values, units, interpretation, no bare numbers, no rejected boilerplate | DILI 0.875 (= fixture), hERG 0.115, oral-bioavail 0.936, each interpreted | PASS |

**Not visually confirmed (capture artifact):** the after-run Outputs/Reproducibility tabs were
obscured by the post-run "Quick feedback" survey popup in both captures (harness auto-dismiss
mis-timed). Those tabs are covered by 25 passing `AfterRunReport` + `workflow-artifact.qc-summary`
unit tests.

## Follow-ups (separate from PR #298 scope)

1. **Problem 2 (next Design + eng deliverable):** the completion "Key results" collapse to a
   single compound (caffeine) across all three metrics rather than entity-aware per-compound
   findings — exactly what Problem 2 (entity-aware findings + shared provenance) addresses.
2. **Param label "Them"** — ADMET required param rendered as "Them" (extracted from "rank
   *them*"); a param-naming/extraction nit.
3. **Post-run "Quick feedback" popup** auto-overlays and obscures the after-run panel the user
   just completed — worth gating so it doesn't cover Outputs/record.

Screenshots: `reference/claude_design/tutorials_v2_design/assets/live/{prerun,running,completed,outputs,record}.png`
(refreshed by the capture harness).
