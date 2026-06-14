# Bioconductor Lessons-Transfer Implementation + Dev Audit Loop

**Date:** 2026-06-11
**Branch:** `bioc/lessons-transfer` (off `873bf21f2`, pushed to origin)
**Context:** Implement the open BioMate-production items from
`docs/20260610_BIOCONDUCTOR_LESSONS_TO_TRANSFER_TO_BIOMATE.md`, validate locally, sync to dev,
and audit iteratively.

## Fixes implemented + verified

| Commit | Item | What | Verification |
|---|---|---|---|
| `ea9a58ba7` | **B-2 (P0)** input staging | Bioc subworkflows expose only a `take:`-bound `*_WORKFLOW` with no anonymous entry → `-entry` can't bind the channel → unrunnable. `_build_bioc_entry_wrapper()` stages each user file under its declared `// Input:` base name and binds the process channel (arity-aware). | Local nextflow run: arbitrary-named files staged as `cts`/`coldata`; **phyloseq E2E green** (real GlobalPatterns → 7 real outputs) |
| `cfd542831` | **B-4** routing | `_exec_quality_bonus` folds real_exec_status into ranking (±2.0 cap, null-safe, in-row). | Dev: `search_ranked` HTTP 200; runnable `deepsnv` elevated among relevant callers |
| `1c8d047c3` | **B-1** step markers | Regenerated `# --- … ---` markers from authoritative in-body step comments; coverage 192→1,536. | Dev fleet sweep: 38/40 multi-step |
| `77fc11466` | **dep bootstrap** | 1,563 of 3,350 bioc `.nf` called `library(pkg)` with NO `# [biomate-deps]` bootstrap → fatal when pkg not pre-baked (found via local microbiome run). Insert canonical bootstrap declaring exactly the `library()`/`require()` packages. | Dev: microbiome self-installs, advances past `library()` |
| `8869c5397` | **steps precedence** | Dev audit: `/api/nextflow/steps` let DB `step_metadata` win unconditionally, so stale single-step rows hid the new markers (microbiome/a4Classif = 1 step). Now a degenerate ≤1-step DB row yields to the richer parser; curated multi-step DB (viz/QC) still wins. | Dev: microbiome 1→5, a4classif 1→5, deseq2 8 & phyloseq 7 unchanged |

## Sync
Surgical delivery into `biomate-galaxy-dev`: 2,380 changed `.nf` → `/app/biomni_workflows/`,
`nextflow_executor.py` + `unified_workflow_search.py` → `/app/lib/galaxy/`, gunicorn restarted.
Container AST verified; 4 workers healthy.

## Dev audit loop (iterative)
1. Synced systematic fixes → 2. audited endpoints → 3. found B-1 step precedence bug →
4. fixed (`8869c5397`) → re-synced executor → 5. re-tested (microbiome 1→5) →
6. fleet sweep green (38/40 multi-step, 0 stragglers).

## Remaining: the per-workflow analysis long tail (open)
The systematic env/wiring/UX gaps are closed. What remains is **per-workflow analysis
correctness** — each needs real data + package-specific logic. Representative example surfaced
locally: `microbiome` now loads its package (bootstrap fix) but fails deeper at
`read_csv2phyloseq`: *"Non-numeric matrix provided as OTU table"* — a data-contract bug where
the taxon-ID column isn't set as rownames before matrix coercion. This class spans many
workflows and is not resolvable wholesale in one pass; it is the honest open backlog.

## Note: concurrent-session collision
A second session committing NCA/CYP work on `bioc/v2-qc-audit-panel` in `/home/yzhang/biomate`
wiped an earlier uncommitted pass of these fixes. Re-done in the **isolated worktree**
`/tmp/lessons-wt` (branch `bioc/lessons-transfer`) with immediate commits to avoid recurrence.
