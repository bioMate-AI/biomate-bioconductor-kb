# Manuscript figures (v1) — regeneration and outputs

## No mocked numeric data

All **plots** and **Table 1** cells are generated from archived files under `research/anti-virus/runs/` (see `docs/MANUSCRIPT_DATA_PROVENANCE.md`). **Graphical abstracts** and **workflow/funnel layouts** are **conceptual schematics** only; numeric labels on them come from the same archives (e.g. row counts, funnel **n**). Do not hand-edit generated table markdown between the `BEGIN GENERATED` / `END GENERATED` markers in the v1.0 manuscripts—re-run the table script instead.

## One-command regeneration

**Plan A (epitope / vaccine track):** from the repository root:

```bash
python3 research/anti-virus/scripts/generate_manuscript_tables.py
python3 research/anti-virus/scripts/generate_manuscript_plan_a_figures.py
```

Figures are written under `research/anti-virus/runs/manuscript_figures_v1/plan_a/`, plus `figure_metadata.json`.

**Inhibitor track (sibling):** same layout under `runs/manuscript_figures_v1/inhibitor/`:

```bash
python3 research/anti-virus/scripts/generate_manuscript_tables.py
python3 research/anti-virus/scripts/generate_manuscript_inhibitor_figures.py
```

For chain-of-custody context, the audited **181054Z** run is documented in `research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/AUDIT.md`; this script targets the **chained** **`032000Z`** archive (see `runs/andv_nf_pipeline_20260513T032000Z/README.md`).

## Plan A output files (`runs/manuscript_figures_v1/plan_a/`)

| File | Description |
|------|-------------|
| `GA_plan_a.png`, `GA_plan_a.pdf` | Graphical abstract (peptide–allele count from `len(rows)`) |
| `FigA1_workflow.png`, `FigA1_workflow.pdf` | Epitopeprediction workflow schematic |
| `FigA2_BA_by_allele.png`, `FigA2_BA_by_allele.pdf` | BA distribution by allele |
| `FigA3_metrics_by_peptide_length.png`, `FigA3_metrics_by_peptide_length.pdf` | BA and rank by peptide length (panels **a** / **b**) |
| `FigA4_multiqc_summary.png`, `FigA4_multiqc_summary.pdf` | MultiQC binding bins and length proportions |
| `FigA5_sequence_profile.png`, `FigA5_sequence_profile.pdf` | Amino-acid frequency profile (always written by the Plan A script; lengths 8–12; see design note below—not a WebLogo) |
| `figure_metadata.json` | Paths, row counts, MultiQC totals, Fig A5 position count, per-figure `kind` / `data_source` |

## Table exports (`runs/manuscript_figures_v1/tables/`)

| File | Source |
|------|--------|
| `PLAN_A_TABLE1.md` | `plan_a_epitope_…/predictions/PLAN_A_SMOKE_GP.tsv` (exemplar peptides from Results) |
| `INHIBITOR_TABLE1.md` | `andv_nf_pipeline_20260513T032000Z/04_docking_vina/docking_autodock_vina_results.json` |
| `table_metadata.json` | Paths and row counts |

## Row counts and QC consistency

The merged prediction TSV has **810** data rows (**811** lines including the header). The MultiQC binding-affinity histogram bin counts sum to **810**, matching the merged table. The Plan A graphical abstract labels the central stage with `len(rows)` from that same merged file (810 peptide–allele scores).

**Note:** Raster/PDF figure files under `runs/manuscript_figures_v1/` are produced by the scripts above; add them to version control (or your manuscript build) if you need Markdown previews in a fresh clone.

## Fig A5 (sequence profile) — design note

The script builds per-position amino-acid frequencies from the **`sequence`** column for **all** rows with peptide length **8–12** (standard 20-letter sequences only). Positions are **N-terminal–aligned** along a fixed axis of **12** positions: shorter peptides do not contribute to C-terminal positions they lack (e.g. position 12 only includes 12-mers). Each **peptide–allele** row is counted separately (the same peptide sequence can appear twice, once per allele). This is documented so readers do not confuse the profile with a unique-peptide logo.
