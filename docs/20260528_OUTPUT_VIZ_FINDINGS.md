# Output Visualization Audit — Findings (#26)

**Date:** 2026-05-28
**Sample:** 33 representative workflows across genomics, transcriptomics, single-cell, cryo-EM, protein structure, drug discovery, pharmacology, clinical

## Current renderer capability

`StepOutputPreview` (`frontend/client/src/components/step-output-preview.tsx`) handles:

| Category | Extensions | Renderer |
|---|---|---|
| Image | png, jpg, jpeg, gif, svg, pdf | `<img>` + lightbox |
| Table | csv, tsv, json, tabular, star | `TableGrid` (200-row cap, STAR-aware) |
| Sequence | fasta, fa, fastq, fq | record list, first 20 |
| VCF | vcf, bcf | table (**no decompression — `.vcf.gz` fails**) |
| Annotation | bed, gff, gtf, gff3 | table |
| **Structure** | pdb, mmcif, cif | **plain `<pre>` text fallback (no 3D viewer wired)** |
| Density | mrc, map, mrcs, rec | DensityMapViewer (good) |
| Download | cs, csg | download link only |
| HTML | html | iframe sandbox |
| Text | log, txt, sh, py, out, err | tail toggle |
| Cryo-EM JSON specials | `fsc_validation*`, `motion_report*`, `ctf_report*` | dedicated chart components |

## Critical finding

**`frontend/client/src/components/viewers/structure-viewer.tsx` contains a fully-built 3Dmol.js viewer** (cartoon/stick/sphere modes, B-factor/pLDDT coloring) — but **it is NOT wired into `StepOutputPreview`**. This is the single biggest quick win.

## Coverage stats (33 workflows audited)

| Status | Count | % |
|---|---|---|
| ✅ first-class viz | 1 | 3% |
| ⚠️ rendered but ugly | 21 | 64% |
| ❌ path only / unrenderable | 11 | 33% |

## Top 5 missing renderers (impact-ranked)

1. **3D structure viewer (PDB / mmCIF / pdbqt)** — affects boltz, chai1, openfold, docking_vina top poses, alphafold. Component exists; wiring only. **Highest ROI.**
2. **IGV.js track viewer (bam / bigWig / narrowPeak / vcf.gz)** — affects sarek, rnaseq, atacseq, chipseq, wgs_germline_gatk, raredisease, methylseq. Also requires backend gzip pass-through for `.vcf.gz`.
3. **PK / dose-response time-series chart (CSV → Recharts)** — affects pbpk_simulation `pk_profile.csv`, nca_pknca, exposure_response_modeling, gromacs RMSD/RMSF. Recharts already in deps.
4. **2D molecule grid (SDF / SMILES → RDKit-js)** — affects reinvent4, glide, vina poses, ADMET workflows. Currently SDF text dump = meaningless.
5. **h5ad / single-cell preview** — affects nfcore/scrnaseq, multiome_rna_atac, all single-cell. Even metadata summary (n_cells × n_genes, obs columns) would help.

## Per-domain recommendations

- **Genomics/transcriptomics** (sarek/rnaseq/atacseq/chipseq/raredisease/wgs): IGV.js track viewer is the universal answer. Backend needs gzip-aware decompression for `.vcf.gz`/`.bam.bai` byte-range serving
- **Single-cell** (scrnaseq/multiome/citeseq/scrna_doublet_qc): h5ad needs a Python-side summarizer endpoint (return obs/var head + UMAP coords if present)
- **Cryo-EM**: largely done — cryosparc_standard_spa is gold standard. Extend FSC/motion/CTF chart name-pattern matching to `topaz_extract_report.json` and `import_micrographs_report.json`
- **Protein structure** (boltz/chai/openfold): wire existing `structure-viewer.tsx`; add pLDDT line chart for confidence JSONs
- **Drug discovery** (ADMET/docking/MD/FEP/REINVENT): (a) ADMET radar from results.json, (b) 3D pose viewer for .pdbqt/.sdf, (c) 2D molecule grid for SDF batches, (d) score-trajectory line charts
- **Pharmacology** (PBPK/NCA/popPK/ER/hERG): PK-curve chart + dose-response/sigmoid chart. nlmixr2 popPK acceptable today (pre-rendered PDFs)
- **Clinical** (BOIN/clinical_trial_simulation): BOIN dose-escalation ladder + operating-characteristics radar (domain-specific)

## Quick wins (1-2 days each)

1. **Wire `structure-viewer.tsx` into `StepOutputPreview`** — change `case 'structure':` from `<pre>` text to import-and-render `StructureViewer`. Unlocks all protein-structure workflows in one PR
2. **Generic time-series CSV chart** — detect `pk_profile.csv`, `dose_response.csv`, `rmsf_per_residue.csv` by filename; render Recharts line/scatter
3. **ADMET radar from JSON** — pattern-match `ADMET_pred_results.json` / `predict_admet_properties_results.json` (mirroring `resolveCryoChartViewer`)
4. **xvg renderer for GROMACS** — two-column text parse to line chart; covers em_potential, nvt_temp, npt_density, energy traces
5. **Backend `.vcf.gz` gzip pass-through** — server decompresses on the fly; existing VCF viewer then works for sarek/raredisease/wgs

## Bigger lifts (1-2 weeks each)

1. **IGV.js integration** — bundle size + backend BAM/BAI byte-range + bigWig tile serving. Massive coverage win, non-trivial
2. **h5ad / scanpy-side summarizer** — new backend endpoint to read HDF5 and return JSON UMAP/obs head; vitessce for full interactivity is a stretch goal
3. **RDKit-js molecule grid** — adds ~3 MB to bundle; alternative is server-side SDF→PNG sprite
4. **NGL trajectory viewer (.xtc/.dcd)** — heavy WebGL; only for gromacs/amber MD users. Defer
5. **mzTab/mzid proteomics parser** — niche but unrenderable today

## Key files referenced

- `frontend/client/src/components/step-output-preview.tsx` (main gating logic)
- `frontend/client/src/components/phase-card.tsx` (`VISUALIZABLE_EXTS` set, lines 101-106)
- `frontend/client/src/components/viewers/structure-viewer.tsx` (3Dmol viewer — **not wired**)
- `frontend/client/src/components/viewers/{density-map,fsc-curve,motion-histogram,ctf-quality}-*.tsx` (cryo-EM specialized viewers)
