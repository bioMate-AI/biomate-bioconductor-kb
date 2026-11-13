# 2026-11-13 — MD sibling figures + Run Manager E2E retest

## Problem

Live dig `chat-files-and-reports` E2E opened `ADMET_QC_report.md` beside chat but showed `未找到图片：fig1_physchem_dili.png` despite the PNGs being listed in Generated files. Run Manager flow B flaked on strict-mode when a run appeared in both `needs_attention` and `failed`.

## Root cause

1. **MD figures:** `MarkdownReport` only fetched `/api/projects/:id/files` when an inline `![](…)` regex matched the raw text. Reference-style images (`![alt][id]` + `[id]: fig.png`) still render as `<img>` via remark, but left `files === null` / skipped the wait path and showed “missing”. Path mismatches (tree `分析结果/` prefix vs stored `<chat · time>/…`, or basename-only report names) also defeated exact/same-dir lookup.
2. **Run Manager B:** Duplicate `data-testid=run-manager-item-*` across buckets; locator needed `.first()`.

## Fix

- Always fetch the project file list when `projectId` is set; wait on relative `<img src>` until the list arrives before declaring missing.
- `resolveSiblingImage`: leaf-folder + basename fallbacks; safe `decodeURIComponent`.
- E2E B: `.first()` + filter `e2e-probe*` sessions.

## Scope

**General product path** (not ADMET/Chinese/e2e-only): every project-chat MD/HTML report with relative figures goes through `MarkdownReport` / `HtmlReport` → `resolveSiblingImage`. Founder class: `mdReportNoFigures` (2026-11-12).

## Verify (live dig tip `ecf9fedc4d`, 2026-11-13)

- `npx vitest run client/src/components/datasets/markdown-report.test.tsx` (7 tests, incl. reference-style)
- `npx tsc --noEmit -p .`
- **3/3 Playwright green** on `https://dev-public.biomate.ai`:
  - `chat-files-and-reports.e2e.ts` — Generated files (.png/.md/.docx); MD panel shows `markdown-figure` (no 未找到图片)
  - A: CryoSPARC license `source=none` → execute **402** → LicenseGate + Confirm disabled
  - B: Run Manager → `?session=&focusRun=` → owning chat (not empty New Chat)
- Shots: `frontend/e2e/screenshots/chat-files-and-reports/` · `frontend/e2e/execshots/run-manager-cryosparc-license/`
