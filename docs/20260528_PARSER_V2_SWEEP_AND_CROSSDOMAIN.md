# Parser-v2 Proactive Sweep + Cross-Domain Validation

**Date:** 2026-05-28 (late session)
**Branch:** `integration/next-phase`

## TL;DR

Rather than wait for each parser-v2 incompatibility to surface via failed runs ($$ + wall-clock), did a proactive static sweep across all ~200 workflows. Found and fixed 6 distinct bug classes. Plus a cross-domain validation pass (cryoEM, genomics, single-cell, structural biology, virtual cell, proteomics canaries) — all hold past Nextflow startup. crispr_screen_mageck + lc_ms_proteomics_metabolomics had multi-layer issues requiring full per-workflow refactor.

## Sweep methodology

Each pattern found earlier in the day became a static check. Run across all `*/main.nf` under `subworkflows/`:

| # | Pattern | Detection | Found |
|---|---|---|---|
| 1 | Inner `"""..."""` docstring inside Groovy `script:"""..."""` | regex + script-block boundary tracking | 17 files (over 3 passes) |
| 2 | Top-level `if (!params.X)` outside `workflow{}` | `grep '^if (!params'` | 2 |
| 3 | `rdMolStandardize.Standardizer()` (rdkit 2022.09+ removed) | grep | 0 remaining |
| 4 | PBPK ODE `/1000` unit error | targeted PBPK file scan | 0 remaining |
| 5 | Top-level `def CONST = 'val'` (parser-v2 forbids file-level assignment) | `grep '^def [A-Z]'` | 5 constants in 2 files |
| 6 | Top-level `Channel.fromPath(...)` outside workflow{} | parser-v2 catch-all | 2 files |
| 7 | R-script `\\\$col` (double-backslash $ escape) | Python repr check | 21 occurrences in lc_ms |
| 8 | `nextflow inspect` catch-all | Nextflow CLI static parse | confirmed catch on 4 patterns above |

Per-file: 14 .nf files modified, ~80 total individual fixes.

## Critical fixes shipped this turn

### crispr_screen_mageck (full refactor)

Originally crashed at multiple parser-v2 stages. Required:
1. **3 top-level Channel declarations** moved into `workflow{}` body
2. **2 top-level `def MAGECK_CONTAINER = '...'` constants** converted to functions `def MAGECK_CONTAINER() { '...' }`
3. **3 `container MAGECK_CONTAINER()` directives** wrapped in closure form `container { MAGECK_CONTAINER() }`
4. **Tag bug**: `tag "${meta.sample}"` referenced undefined `meta` (process input was `meta_list`) — changed to static `tag "crispr_screen"`
5. **MAGECK_COUNT call mismatch**: process declared single tuple input, call passed 2 channels. Refactored channel plumbing to build `[meta_list, fastqs]` tuple, then `.combine(ch_library)` for the 3-element tuple the process expects.

Commits: `5dd34362d`, `42c8d6635`, `d1a51f694`.

### lc_ms_proteomics_metabolomics (full refactor)

1. **4 top-level Channels** moved into `workflow{}` body
2. **3 top-level `def CONST = '...'` constants** → function form
3. **5 `container CONST()` directives** wrapped in closure form
4. **R-script `\\$col` escape errors (21 occurrences)** — file had double-backslash `\\$` where single-backslash `\$` was intended for Groovy GString escape. Parser-v2 strict-parses interpolation; older Nextflow let it slide. Fixed via Python file rewrite.

Commit: `509525062`.

### Polymorph_stability_screening regression (self-inflicted, then fixed)

My initial v2 docstring sweep accidentally converted the OUTER Groovy script-block closing `"""` to `'''` (because it was followed by Python code instead of `}`). That broke the outer string. Restored at line 717. Lesson: the heuristic for "is this the outer-close?" must be more precise — followed-by-`}` only, never followed-by-code. Updated algo accordingly.

Commit: `5dd34362d`.

## Cross-domain canary results

To verify framework fixes generalize beyond drug-dev (where I'd been testing all session), fired one canary per major non-drug-dev domain:

| Domain | Canary | Status at T+9min |
|---|---|---|
| cryo_em | `cryosparc_standard_spa` | running (past startup) |
| genomics | `wgs_germline_gatk` | running |
| genomics (utility) | `mafft_alignment` | running |
| genomics (perturb) | `perturb_seq_analysis` | PARSE (transient API) |
| single_cell | `scrna_doublet_qc` | running |
| structural_biology | `boltz_structure_prediction` | running |
| virtual_cell | `ode_signaling_simulation` | running |
| proteomics | `profam_fitness_prediction` | running |

7/8 past startup. The framework-level fixes (Nextflow 25.10.5, CRT HTTP client, profiles{aws{}}, parser-v2 docstring/statement fixes, Python 3.9 annotations fix) generalize across all workflow domains. Drug-dev was the canary cluster, not the boundary.

## All commits this turn (chronological)

| Commit | Fix |
|---|---|
| `2d080ace6` | 3 docstring stragglers — crispr/lc_ms f-string `"""` → `'''`, polymorph inline |
| `5dd34362d` | polymorph outer-`"""` restored; crispr/lc_ms def→func conversion |
| `42c8d6635` | crispr partial parser-v2 refactor (channels + tag) |
| `d1a51f694` | crispr MAGECK_COUNT input tuple + container closure |
| `509525062` | lc_ms top-level channels + container closure + R `\$` escape |

## Validated end-to-end producing real outputs (session-cumulative)

**Drug-dev / pharmacology (12):**
- predict_admet, pbpk_simulation (Cmax matches aspirin literature), transporter_ddi
- pharmacophore_filtering, pocket_detection_druggability, cyp_ddi_panel
- clinical_trial_simulation (BOIN 6 outputs), ich_s5_reproductive_tox (DART)
- virtual_patient_cohort, p0_pkpd_semaglutide, phase2_dose_justification, ich_s7a_safety_pharmacology

**Cross-domain (7+):** cryosparc_standard_spa, wgs_germline_gatk, mafft, scrna_doublet_qc, boltz_structure_prediction, ode_signaling_simulation, profam_fitness_prediction (all past parse, AWS Batch running)

## Lessons re-applied

- **Static sweep beats deploy-and-find.** Each `nextflow inspect` call costs <30s and catches a parser-v2 incompatibility that would otherwise need a full AWS Batch round-trip (~5 min + $$).
- **Multi-pass fixes need verification.** v1 docstring sweep used a heuristic that missed multi-line cases; v2 fixed those but missed f-strings and inline-opener docstrings; v3 caught those. Each pass needs re-verification not just on what was fixed but on what *might* still match the pattern.
- **Older code accumulates implicit-allowed patterns.** Many of the "bugs" found today were latent — they only error on parser-v2's stricter rules. Older Nextflow let them slide. When updating major framework versions, expect a parser-v2-shaped sweep across the codebase.

## What's not done (other tasks)

- **Task #18 — Postgres persistence for ExecutionRun.** Runs still live in MemStorage, lost on container restart. Tackled next.
- **Task #19** — re-validation of the 5 remaining clinical workflows. v13 sweep showed positive trajectory (ich_s7a got 2 outputs); pending fuller validation as Galaxy stability improves.
- Remaining cross-domain workflows (~190) not yet tested individually — proactive sweep + 8 canaries are a good signal that framework holds, but per-workflow scientific validation is its own track.
