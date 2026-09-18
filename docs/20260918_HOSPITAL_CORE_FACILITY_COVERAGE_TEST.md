# Hospital core-facility coverage — live test vs the doc's claims

**Date:** 2026-09-18
**Source doc:** `Hospital Core Facility — Instrument Inventory, Data Outputs, and BioMate Coverage.docx`
**Method:** For each instrument data output, ran a real workflow-routing use case against dev (`POST /api/workflows/search`) and spec-checked the surprising matches (`GET /api/workflows/spec`). The doc's own coverage table is treated as a hypothesis to validate, not ground truth.

## Headline

**BioMate's actual routing coverage is broader than the doc claims.** Every instrument data output — including the ones the doc marked "not covered" (flow cytometry, qPCR, pathology, confocal, plate reader) — routes to a **real, on-domain, registered workflow** with a parameter schema. The doc's coverage table is stale/conservative.

The doc's *deeper* points (validation, vendor formats, foundation models) are still valid, but they are **not** "no workflow exists" — they are runnability/validation/format gaps.

## Live result vs doc claim

| Instrument data | Doc claim | Live search match (domain) | Real spec? | Verdict |
|---|---|---|---|---|
| Sequencer / FASTQ (RNA-seq) | Covered | *Bulk RNA-seq Differential Expression* (transcriptomics, chain) | ✓ | **Confirmed covered** |
| Sequencer / FASTQ (WGS) | Covered | *Wgs Germline Gatk* (genomics) | ✓ | **Confirmed covered** |
| Mass spec — proteomics (DIA) | Covered | *nf-core/diaproteomics* (proteomics) | ✓ | **Confirmed covered** |
| Mass spec — metabolomics | Covered | *LC-MS Metabolomics → Multi-Method* (metabolomics, chain) | ✓ | **Confirmed covered** |
| Flow cytometer / FCS | **Partial — "nothing built or validated"** | *Analyze Flow Cytometry Immunophenotyping* (cell_biology) — 1 req/3 opt params | ✓ registered | **Doc understates — a workflow exists** (validation unverified) |
| qPCR / ddCt | **Not covered — "gap to build"** | *normqpcr delta_delta_cq_normalization* (bioconductor) | ✓ registered | **Doc wrong — covered** |
| Slide scanner / WSI (pathology) | **Not covered — "nothing in the stack"** | *nf-core/mcmicro* (imaging) | ✓ registered | **Doc understates — a multiplex-imaging pipeline exists** (see format caveat) |
| Confocal / fluorescence imaging | **Not covered** | *Segment Cells With Deep Learning* (microbiology) — 4 opt params | ✓ registered | **Doc understates — a DL segmentation workflow exists** |
| Plate reader / ELISA | **Not covered — "low effort to build"** | *Hts Plate Qc Hit Calling* (drug_discovery) — 5 opt params | ✓ registered | **Doc understates — a plate-QC/hit-calling workflow exists** |
| Single-cell RNA-seq (bonus) | (facility has no sc platform) | *Single-Cell RNA-seq Multi-Sample Analysis* (single_cell, chain) | ✓ | **Capability exceeds the facility** |

Every query returned `success=True` with a real nf-core/subworkflow `nextflow_path`, a description, and (for most) a parameter schema — i.e. genuine registrations, not the forced low-relevance best-match failure mode (cf. the rrBLUP relevance defect, tracked separately in #32).

## The gaps that survive live testing (the doc's real value)

These are NOT discoverable by search and are the genuine work:

1. **Vendor format handling (P1).** Chinese slide-scanner outputs (`.kfb`, `.sdpc`) and confocal formats (`.czi/.lif/.nd2/.oir`) need converters (OpenSlide/BioFormats/vendor tools) before `mcmicro`/QuPath can read them. A registered imaging workflow ≠ it opens `.kfb`. **Real gap.**
2. **Validation, not existence (P1).** The thin workflows (flow cytometry, qPCR, imaging) are *registered* but their end-to-end runnability + correctness are **unverified** by this test — routing coverage ≠ validated results. The doc's "nothing built or validated" holds at the *validation* level for flow, even though a workflow exists.
3. **Pathology foundation models (P2, capability).** UNI/CONCH/Virchow/Prov-GigaPath embeddings for tissue QC + IHC antigen validation are a model capability, not a pipeline — genuinely absent.
4. **Data-quality prerequisites (not a BioMate gap).** Mass-spec instrument class (Orbitrap/timsTOF vs triple-quad) and sequencer/scanner models are facility unknowns that gate immunopeptidomics/pathology usefulness regardless of BioMate.

## Honest bottom line

- **Discoverability/routing:** BROAD and better than the doc — a real workflow routes for **every** instrument data type. Update the doc's coverage table.
- **Validated runnability:** UNVERIFIED beyond the well-trodden FASTQ/mass-spec paths. The credible next test is to **actually run** one surprising case end-to-end (e.g. flow-cytometry immunophenotyping on a public `.fcs`, or `mcmicro` on a public OME-TIFF) to convert "registered" → "validated." That needs real input data + compute.
- **True build items:** vendor-format converters (`.kfb/.sdpc/.czi`) and pathology foundation models — the doc's genuine, testing-confirmed gaps.
