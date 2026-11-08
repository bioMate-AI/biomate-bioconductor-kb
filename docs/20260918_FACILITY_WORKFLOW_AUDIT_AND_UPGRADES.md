# Facility-wide workflow audit + upgrade plan (live-tested)

**Date:** 2026-09-18
**Basis:** live workflow-search + spec probes against dev for every data-producing instrument in `Hospital Core Facility — Instrument Inventory…docx`, run by 4 parallel cluster auditors (sequencing, mass spec, cytometry/plate/gel, imaging/pathology). ~130 search queries, ~70 workflows spec-checked. Companion to `20260918_HOSPITAL_CORE_FACILITY_COVERAGE_TEST.md`.

## Headline verdict

**BioMate covers far more than the facility doc's coverage table claims.** Real workflows exist for nearly every instrument application — including flow cytometry, qPCR, Western, and multiplex imaging, all of which the doc marked "not covered / thin." The doc's table is stale. **But** the audit sharpens where the *genuine* gaps are: they sit at the **ingestion edge (vendor format readers)** and the **frontier (foundation models)**, not in the analysis middle. And several existing workflows are real but **not best-in-class** and should be upgraded to named better resources.

Two systemic edges are where nearly all real gaps cluster:
- **Format ingestion:** imaging vendor formats (`.kfb/.sdpc/.czi/.lif/.nd2/.oir`, even OpenSlide `.svs/.ndpi`) and MS vendor→mzML (`.raw/.wiff`) have **no converters** → they block otherwise-present analysis pipelines.
- **Foundation models:** BioMate's FM surface is entirely transcriptomic (scRNA/gene). **Zero pathology image FMs.**

---

## Per-instrument coverage (condensed; full detail in the 4 cluster reports)

### Sequencing (sequencer → FASTQ / .ab1 / POD5)
17/18 applications covered (13 real curated specs). **Strong & mostly current:** nf-core/rnaseq, sarek, atacseq, methylseq, ampliseq, scrnaseq, rnafusion, rnasplice, smrnaseq, demultiplex, nanoseq, spatialvi.
- Gaps: **Sanger `.ab1` assembly — none**; **POD5→dorado basecalling — only indirect**; large-genome de-novo; shotgun metagenomics (only 16S/ampliseq surfaced).

### Mass spec (→ proteomics / metabolomics)
Deepest lane. **Immunopeptidomics is best-in-class & complete** (`mhcquant` + `epitopeprediction` + `hlatyping` + `antigen_resolution`). DIA (DIA-NN), DDA-LFQ (OpenMS/proteomicslfq), TMT, PTM, metabolomics (metaboigniter) all present (many metabolomics/TMT modules are thin single-function wrappers).
- Gaps: **raw→mzML converter (msConvert/ThermoRawFileParser) — none** (blocks `.wiff/.raw`); **Skyline PRM/SRM quant — none**; lipidomics **ID** — none; de-novo (Casanovo), XL-MS — none. **FragPipe/MSFragger absent entirely.**

### Cytometry & plate/gel
**Flow is deep** (flowCore, flowgate, FlowSOM, flowSpecs, flowClean, flowFP, flowgraph, flowPloidy). **qPCR best-in-class** (NormqPCR, ddCt, qpcrNorm, MAST, stableexpression). **Western densitometry real.** HTS plate QC (Z'/4PL) real.
- Gaps: **CyTOF/mass cytometry — none**; luciferase reporter — none; **RIN/Bioanalyzer, NanoDrop, cell-counter QC — none**; real **dose-response/IC50 data-fitter — none** (the `dose_response` workflow is a scalar curve *plotter*); ELISA exists but EBV-specific; real gel-image densitometry — none (only in-silico gel sim); CCK-8/MTT — only ATP-luminescence.

### Imaging & pathology (biggest gap — CONFIRMED)
Real multiplex/spatial pipelines exist: **mcmicro, imcyto, imcRtools, molkart, MERFISH** — all research multiplex/FISH, all requiring **OME-TIFF** input. Routine digital pathology (H&E WSI, IHC scoring, tumor grading) = thin Galaxy wrappers or legacy **CRImage (2011)**.
- Gaps (both hardest, highest-value): **(a) no readers for the facility's actual formats** — `.kfb/.sdpc` (Chinese scanners), `.czi/.lif/.nd2/.oir` (confocal), even OpenSlide `.svs/.ndpi` have no general reader; **(b) no pathology foundation models** (UNI/CONCH/Virchow2/GigaPath all absent — FM queries fall back to scRNA models). Also: no z-stack/3D confocal workflow, no TrackMate-grade tracking, no organoid segmentation.

---

## A. Upgrade list — existing workflows, better resource available (the "do the tools need an upgrade" answer)

Prioritized; each is an in-place improvement to a *present* workflow.

| # | Workflow (path) | Current | Upgrade to | Why |
|---|---|---|---|---|
| U1 | WGS germline (`.../genomics/wgs_germline_gatk/main.nf`) | GATK HaplotypeCaller default | default **DeepVariant** (Clair3 for ONT) — param already exists | higher SNV/indel accuracy than GATK+VQSR |
| U2 | ChIP-seq (`.../genomics/perform_chipseq_peak_calling_with_macs2/main.nf`) | bare 2-param MACS2 | full **nf-core/chipseq** (align→peaks→consensus→diffbind→QC) | current match is a peak-caller, not a pipeline |
| U3 | Nanopore (`nfcore/nanoseq`) | Guppy basecaller (legacy) | **dorado** (+ Clair3 variants) | Guppy is EOL |
| U4 | DIA proteomics (`nfcore/dia_proteomics_analysis`) | DIA-NN unpinned | **pin DIA-NN 2.x**; expose version | 2.x MBR/FDR, timsTOF `.d` |
| U5 | DDA-LFQ (`nfcore/proteomicslfq`) | MSGF+/Comet | add **FragPipe/MSFragger** (or AlphaPept) | 10–100× faster, open/PTM search; MSFragger absent today |
| U6 | TMT (isobar/msstatstmt/qPLEXanalyzer thin wrappers) | fragmented modules | adopt **nf-core/quantms** umbrella | one curated DDA/DIA/TMT pipeline replaces several thin wrappers |
| U7 | Phospho/PTM (`.../isobar/ptm_localization…`) | PhosphoRS | **PTMShepherd / FragPipe** | modern localization + open-search PTM |
| U8 | Metabolomics (`nfcore/metaboigniter`) | feature detect + MS2Query | add **SIRIUS 6**, **MS-DIAL 5 / MZmine 3**, **MetaboAnalyst 6** | best-in-class formula/structure ID + enrichment |
| U9 | Flow QC (`.../flowclean`) | flowClean | **PeacoQC / flowAI** | current-generation anomaly QC |
| U10 | Flow DA/CyTOF | flow stack lacks it | add **CATALYST** (+ cytonorm batch) | de-facto standard for differential abundance/state & CyTOF |
| U11 | Dose-response (`.../biochemistry/dose_response/main.nf`) | scalar curve plotter | **drc / nplr** (real 4/5PL fit) + **PharmacoGx** | current one does not fit raw well data |
| U12 | Cell segmentation (`.../segment_cells_with_deep_learning`, CRImage) | generic/legacy | **Cellpose 3 / StarDist / Mesmer** standalone | generalist, denoise, crowded-nuclei accuracy |
| U13 | CNV/purity (`.../analyze_copy_number…`) | CNVkit approximation | **ASCAT / PURPLE** (already in sarek) | rigorous tumor purity/ploidy |

## B. Build list — genuine gaps, no real workflow (prioritized by leverage)

| # | Gap | Build | Unblocks |
|---|---|---|---|
| B1 | **Imaging format readers/converters** | BioFormats/`bfconvert` + OpenSlide/libvips; vendor **KFB→TIFF, SDPC→TIFF**; `czi/lif/nd2/oir` readers (aicsimageio/readlif/nd2reader) | **ALL** facility imaging (WSI + confocal) — currently every file must be pre-converted externally |
| B2 | **Pathology foundation models** | **UNI, CONCH, Virchow2, Prov-GigaPath / GigaPath** (tile + slide encoders) | tumor-content QC, IHC/antigen validation, few-shot subtyping — the antigen programme's upstream |
| B3 | **QuPath digital-pathology workflow** | QuPath (WSI annotation, IHC positivity, tumor detect) + HistomicsTK + Macenko/Vahadane stain norm | routine H&E/IHC pathology (only thin/legacy today) |
| B4 | **MS raw→mzML converter** | ProteoWizard **msConvert** + **ThermoRawFileParser** | `.wiff`/`.raw`/`.d` ingestion into all MS pipelines |
| B5 | **Sanger `.ab1` assembly** | **Tracy** (trim → consensus/contig) | routine Sanger confirmation (hospital staple) |
| B6 | **POD5→dorado basecalling** (standalone) | dorado (+ modified-base models) | Nanopore raw-signal front end |
| B7 | **CyTOF / mass cytometry** | **CATALYST** (norm/debarcode/DA) | the instrument list's biggest cytometry hole |
| B8 | **Instrument QC modules** | RIN/Bioanalyzer (bioanalyzeR), NanoDrop 260/280·260/230, cell-count/viability | sample-QC metadata (trivial, genuinely missing) |
| B9 | Assay gaps | luciferase reporter; CCK-8/MTT viability; real gel densitometry (Fiji lane-profile); generic 4PL ELISA (drc) | routine bench assays |
| B10 | MS niche | **Skyline** PRM/SRM quant; **lipidomics ID** (MS-DIAL 5); **Casanovo** de-novo | targeted/lipid/de-novo proteomics |

## Bottom line for the facility

- **Don't rebuild what exists.** Flow, qPCR, Western, sequencing, and the MS/immunopeptidomics lanes are real and mostly current — update the doc's coverage table.
- **The two highest-leverage BUILDS are format ingestion (B1/B4) and pathology foundation models (B2)** — they unblock entire instrument axes (all imaging; all vendor-format MS) rather than a single analysis.
- **The cheapest wins** are the U-series in-place upgrades (flip DeepVariant default, pin DIA-NN 2.x, swap flowClean→PeacoQC, replace the scalar dose-response with drc) and B8 QC parsers.
- **Instrument-model unknowns still gate value:** immunopeptidomics needs Orbitrap/Astral-class MS; pathology usefulness depends on the scanner vendor (which decides B1 converter effort). These are facility questions, not BioMate gaps.
