# `andv_nf_pipeline_20260513T032000Z`

Chained reference Nextflow run for the inhibitor **v1.0** manuscript: pocket → pharmacophore → ADMET → Vina docking → generative step, with ADMET/docking inputs wired from pharmacophore-filtered SMILES.

`pipeline_manifest.json` lists five executed **steps** in the manifest (`pocket` … `reinvent4` under `06_reinvent4`); **`through_step`** may read **6** while **`05_gromacs_mmgbsa`** on disk can remain incomplete (e.g. `status.json` not `succeeded`). The manuscript’s molecular-dynamics paragraph matches that scope. For the exact manifest note and resync metadata, open `pipeline_manifest.json` in this directory.

- **Manuscript:** `research/anti-virus/docs/MANUSCRIPT_ANDV_INHIBITOR_v1_0.md` (figures and Results numbers reference this archive).
- **Figures:** `python3 research/anti-virus/scripts/generate_manuscript_inhibitor_figures.py` → `research/anti-virus/runs/manuscript_figures_v1/inhibitor/`.
- **Contrast:** `research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/AUDIT.md` audits the earlier **181054Z** run’s ligand-handoff issue only; use **032000Z** for manuscript-aligned provenance.
