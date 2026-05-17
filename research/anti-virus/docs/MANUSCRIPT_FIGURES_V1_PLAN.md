# Figure & diagram plan — Plan A vaccine paper + Inhibitor paper (v1.0)

**Output root:** `research/anti-virus/runs/manuscript_figures_v1/`  
**Conventions (Nature-style figure hygiene):** 300 dpi raster exports; Arial or DejaVu Sans; avoid red–green only contrast; legible axis labels; panel labels **a**, **b** where multi-panel.

---

## Track A — Plan A vaccine / epitope manuscript

**Manuscript:** `docs/MANUSCRIPT_PLAN_A_VACCINE_v1_0.md`  
**Primary data:** `runs/plan_a_epitope_a44876b7_s3_mirror/predictions/PLAN_A_SMOKE_GP.tsv` (811 lines including header; 810 peptide–allele rows); MultiQC tabular exports under `runs/plan_a_epitope_a44876b7_s3_mirror/multiqc/multiqc_data/`.

| ID | Type | Purpose | Data / method | Deliverable |
|----|------|---------|----------------|-------------|
| **GA-A** | Graphical abstract | One-glance story: antigen segment → epitopeprediction → allele-specific scores → “baseline catalogue” | Scripted schematic (no wet lab iconography) | `plan_a/GA_plan_a.png` + `.pdf` |
| **Fig A1** | Workflow diagram | Methods: inputs → nf-core epitopeprediction → outputs | Matplotlib flowchart / boxes | `plan_a/FigA1_workflow.png` + `.pdf` |
| **Fig A2** | Distribution | Results: predicted binding affinity (BA) by **allele** | Parse TSV columns `allele`, `BA` | `plan_a/FigA2_BA_by_allele.png` + `.pdf` |
| **Fig A3** | Distribution | Results: **BA** and **rank** by **peptide length** (panels **a** / **b**) | Parse `sequence`, `rank`, `BA` | `plan_a/FigA3_metrics_by_peptide_length.png` + `.pdf` |
| **Fig A4** | Multi-panel summary | Results / QC: MultiQC binding-affinity **bin counts** and binder **length proportions** (panels **a** / **b**) | Parse `multiqc_binding_affinity_distribution.txt`, `multiqc_binder_length_distribution.txt` for `PLAN_A_SMOKE_GP` | `plan_a/FigA4_multiqc_summary.png` + `.pdf` |
| **Fig A5** | Stacked bar “sequence profile” | Results / exploration: per-position amino-acid frequencies from **`sequence`** (lengths **8–12**; N-terminal–aligned positions; all peptide–allele rows; not a WebLogo; emitted whenever the Plan A script runs) | Matplotlib stacked bars from merged TSV + **numpy** | `plan_a/FigA5_sequence_profile.png` + `.pdf` |

**Optional later (not blocking v1):** sequence **logo** for top peptides (needs `weblogo` or similar) — distinct from **Fig A5**, which is a matplotlib-only frequency profile.

**Script:** `research/anti-virus/scripts/generate_manuscript_plan_a_figures.py`

---

## Track B — Inhibitor manuscript

**Manuscript:** `docs/MANUSCRIPT_ANDV_INHIBITOR_v1_0.md`  
**Primary data:** `runs/andv_nf_pipeline_20260513T032000Z/01_pocket/structure_pockets.json`, `04_docking_vina/docking_autodock_vina_results.json`, `06_reinvent4/score_history.json`, `02_pharmacophore/summary.json` (if present for counts).

| ID | Type | Purpose | Data / method | Deliverable |
|----|------|---------|----------------|-------------|
| **GA-B** | Graphical abstract | Pocket → filter → ADMET → dock → generative | Scripted pipeline schematic | `inhibitor/GA_inhibitor.png` + `.pdf` |
| **Fig B1** | Bar + line (twin y) | Pocket survey: **druggability** (bars) and **volume (Å³)** (line, right axis) for top pockets | `structure_pockets.json` | `inhibitor/FigB1_pocket_druggability.png` + `.pdf` |
| **Fig B2** | Funnel / schematic | Library → pharmacophore → docked: **integer counts** from `02_pharmacophore/summary.json` (`n_library_screened`, `n_passed_filter`) and docking JSON (`n_ligands_docked` or `len(results)`); schematic fallback if summary missing | `summary.json` + `docking_autodock_vina_results.json` | `inhibitor/FigB2_pipeline_funnel.png` + `.pdf` |
| **Fig B3** | Bar chart | Vina best affinity (kcal/mol) for three compounds | `docking_autodock_vina_results.json` | `inhibitor/FigB3_docking_scores.png` + `.pdf` |
| **Fig B4** | Line / scatter | Generative-step score trajectory from `score_history.json` (title includes `tool`, e.g. `rdkit_brics_generation` in archive) | `score_history.json` | `inhibitor/FigB4_generative_score_history.png` + `.pdf` |
| **Fig B5** | 2D structures (optional) | RDKit **MolToImage** strip of the three docked SMILES (**same order** as Fig B3) | `docking_autodock_vina_results.json` + RDKit (best-effort) | `inhibitor/FigB5_docked_ligands_2d.png` + `.pdf` (written only when RDKit imports) |

**Optional later:** PyMOL/ChimerX surface or interaction panel (manual). **Fig B5** is emitted automatically by the Track B script when RDKit is importable; otherwise the script skips those files (see one-line comment in `generate_manuscript_inhibitor_figures.py`).

**Script:** `research/anti-virus/scripts/generate_manuscript_inhibitor_figures.py`

---

## Parallel execution

1. Run **Track A** script and **Track B** script concurrently (two terminals or one `wait`).  
2. v1.0 Markdown manuscripts already embed `../runs/manuscript_figures_v1/...` images; for LaTeX, point `\\includegraphics` at the same PNG/PDF paths (or copy figures into a `figures/` build dir).  
3. **Version** figure bundle with same tag as manuscript (`v1`) in directory name; bump if panels change.

---

## Dependencies

- **Python 3** with **`matplotlib`** (both tracks) and **`numpy`** (Plan A script only, for **Fig A5** sequence profile math).  
- **Optional:** **RDKit** for **Fig B5** 2D ligand panels; the inhibitor script skips B5 when RDKit is not importable **or** when any docked SMILES fails `MolFromSmiles`.  
- No proprietary tools required for v1 deliverables.
