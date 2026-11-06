# Phase 1C audit — Compatibility validation for comparisons

**Date:** 2026-09-13
**Scope:** the Phase-1 requirement "comparisons validate compatibility and
request a typed mapping only when needed" in
[`20260912_V2_GAP_REBASE_AFTER_SIMPLIFICATION.md`](20260912_V2_GAP_REBASE_AFTER_SIMPLIFICATION.md).
**Commit(s):** `900dfc093`.

## Problem

When a user compares two result files, the comparison is only meaningful if the
files share a schema — but nothing validated that before a comparison. A schema
mismatch (different columns / counts / formats) would surface only as a runtime
failure. (`result_comparison` is a *tool/method* comparison chat intent — e.g.
"DESeq2 vs edgeR" — not a data-file comparison; no file-schema check existed
anywhere.)

## Design decision

A broad execute-time gate over "any run with 2+ file inputs" would **false-block
legitimate multi-input workflows** (reference + sample, index + reads, …) that
are not meant to share a schema, and there is no reliable "this run is a
comparison" signal in the execute request today. So this delivers the reusable,
correct **primitive** — a pure compatibility decision core plus an authenticated
pre-launch endpoint the comparison flow calls — rather than a speculative gate
with false-positive risk. No compute path is gated, so nothing can regress.

## Fix

- **`input-compatibility.ts`** (pure, unit-tested):
  - `parseHeaderColumns(text, format)` — header → column names (tab for tsv,
    else comma; quote/space stripping; tab auto-detect).
  - `checkTabularCompatibility(files)` — compatible on equal column sets
    (order-independent); incompatible across differing formats or column counts;
    `needsTypedMapping` with a positional suggestion when arity matches but names
    differ; reports per-file missing columns and the shared set.
- **`POST /api/projects/:id/files/compatibility`** (authenticateToken +
  `_isOwnerOrMember` gate, exact-id scoped): resolves 2+ project file ids, reads
  each header via a **ranged S3 GET** (no full download), and returns
  `{ compatible, reason?, sharedColumns, perFile, needsTypedMapping,
  suggestedMapping?, files }`. Returns 400 for < 2 ids, 404 for
  unauthorized/missing files. No compute launched.

Reuses the Phase-1A project authorization and the exact-id file scoping from the
chat-to-file work.

## Tests

- `input-compatibility.test.ts` (12): header parsing (csv/tsv/quoted/auto-tab/
  empty), format extraction, and every compatibility verdict (identical,
  order-permuted, different formats, typed-mapping suggestion, different counts,
  single-file trivial).
- `project-routes.test.ts`: authenticated-endpoint count 18 → 19 (the new route
  goes through `authenticateToken`).
- Commands: `npx tsc --noEmit -p .` → clean; `npx vitest run` → **1490 passed,
  7 skipped, 0 failed**.

## Authenticated dev exercise

- **Environment:** https://dev-public.biomate.ai; frontend rebuilt to `900dfc09`
  (freshness-verified, image age 14s at swap).
- **Identity:** shared E2E fixture `lifeifei163361@163.com`.
- Uploaded four CSVs to a fresh project and called the endpoint (real S3 header
  reads, **no Batch compute**):

| Case | Files | Result |
|---|---|---|
| Same header | `gene,value` vs `gene,value` | `compatible=true` |
| Remapped names | `gene,value` vs `symbol,score` | `compatible=false`, `needsTypedMapping=true`, suggestion `symbol→gene, score→value` |
| Different counts | `gene,value` vs `gene,value,extra` | `compatible=false`, no mapping, reason "different column counts" |
| One id | `[A]` | **400** `at_least_two_files_required` |
| No token | `[A,B]` | **401** |

## Remaining risks / follow-ups

- The endpoint compares tabular headers (csv/tsv/txt). Non-tabular formats
  (h5ad, bam, vcf …) fall back to format-equality only; deeper schema checks for
  those are a follow-up if a comparison flow needs them.
- Consumer wiring: the chat/UI comparison flow should call this endpoint before
  launching a two-file comparison and surface `suggestedMapping` when
  `needsTypedMapping` — a small UI task, tracked separately.
- Still open in Phase 1: **honest blocked states** (block
  `workflowGenerationFailed` at execute; thread unresolved chat references into
  the execute gate).

## Conclusion

**GO** for "compatibility validation for comparisons": the platform can now
validate that two result files are comparable and propose a typed mapping when
their columns differ, authorized and exact-id scoped, verified by unit tests and
a live dev exercise across all verdicts. Phase 1 is not yet complete — the
honest-blocked-state items remain.
