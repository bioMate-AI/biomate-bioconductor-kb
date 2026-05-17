# Manuscript data provenance — Plan A & inhibitor v1.0

This document states which manuscript elements are **read from archived run artifacts** versus **conceptual schematics** (layout only; not synthetic numeric results).

## Policy

- **No mocked numeric results:** Plots and tables must trace to files under `research/anti-virus/runs/`.
- **Schematics** (workflow boxes, graphical abstracts) illustrate pipeline order only; they are labeled **conceptual** in figure titles and legends.
- **Funnel box widths** (inhibitor Fig B2) are **not** proportional to library size; only the printed **n = …** integers come from JSON.

## Plan A (epitope)

| Output | Kind | Source artifact(s) |
|--------|------|---------------------|
| GA, Fig A1 | Conceptual schematic | Pipeline narrative; GA center count = `len(rows)` from merged TSV |
| Fig A2 | Data plot | `plan_a_epitope_…/predictions/PLAN_A_SMOKE_GP.tsv` (`allele`, `BA`) |
| Fig A3 | Data plot | Same TSV (`sequence`, `rank`, `BA`) |
| Fig A4 | Data plot | `multiqc/multiqc_data/multiqc_binding_affinity_distribution.txt`, `multiqc_binder_length_distribution.txt` |
| Fig A5 | Data plot | Same TSV (`sequence`, lengths 8–12) |
| Table 1 | Data table | Same TSV; rows for peptides cited in Results (`GVCYTLTL`, `WYLVVLGV`, `TSMAQKSF`) |

**Evidence run:** `runs/plan_a_epitope_a44876b7_s3_mirror/`

## Inhibitor

| Output | Kind | Source artifact(s) |
|--------|------|---------------------|
| GA, Fig B2 (layout) | Conceptual schematic | Stage order; counts on B2 from JSON when available |
| Fig B1 | Data plot | `andv_nf_pipeline_20260513T032000Z/01_pocket/structure_pockets.json` |
| Fig B2 (n labels) | Data labels | `02_pharmacophore/summary.json`, `04_docking_vina/docking_autodock_vina_results.json` |
| Fig B3, B5 | Data plot / 2D | Docking JSON (`results`, `smiles`, `best_affinity_kcal_mol`) |
| Fig B4 | Data plot | `06_reinvent4/score_history.json` (`tool` field names implementation) |
| Table 1 | Data table | Docking JSON (all pharmacophore-filtered ligands in chained run) |

**Evidence run:** `runs/andv_nf_pipeline_20260513T032000Z/` (not `181054Z`; see that run’s `AUDIT.md`).

## Regeneration

```bash
python3 research/anti-virus/scripts/generate_manuscript_plan_a_figures.py
python3 research/anti-virus/scripts/generate_manuscript_inhibitor_figures.py
python3 research/anti-virus/scripts/generate_manuscript_tables.py
```

See also `docs/README_MANUSCRIPT_FIGURES.md`.
