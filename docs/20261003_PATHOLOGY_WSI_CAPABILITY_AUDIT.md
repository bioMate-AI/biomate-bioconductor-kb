# BioMate pathology and whole-slide imaging capability audit

**Date:** 2026-10-03  
**Scope:** code, workflow definitions, container declarations, and recorded local workflow evidence in this repository. This is a capability audit, not a clinical validation and not a claim of diagnostic fitness.

## Decision

BioMate must **not** currently be described as a whole-slide digital-pathology platform. It has some useful image-analysis building blocks and prototypes, especially for small multichannel images and imaging-mass-cytometry-adjacent data. It does not yet provide the end-to-end, evidence-backed WSI path required for H&E/IHC pathology work.

The distinction matters: a workflow name, an installed package, a generated wrapper, or a smoke-test artifact is not evidence that a pathologist's slide can be ingested, analyzed, quality-controlled, and reported reliably.

## Evidence categories

- **Usable only after validation:** code consumes an input format and performs a bounded computation, but has not been shown here to run on representative user data with scientific acceptance criteria.
- **Prototype / not a product claim:** generated or hard-coded workflow whose assumptions make it unsuitable for general pathology input.
- **Absent:** no implementation or executable integration found in this repository.

## What exists

| Area | Evidence | Audit status | Exact limitation |
|---|---|---|---|
| Small multichannel image cell segmentation and marker-intensity table | `backend/biomni_workflows/nextflow_nfcore/subworkflows/pathology/segment_and_quantify_cells_in_multiplexed_images/main.nf` | **Usable only after validation** | Reads one multichannel image, applies Otsu thresholding and watershed expansion from a nuclear channel, and writes a mask/table. It is not a learned segmentation model, does not tile WSI, and has no cell-type classifier, uncertainty estimate, calibration, or annotated-slide benchmark. |
| Thrombus H&E color-threshold prototype | `.../pathology/analyze_thrombus_histology/main.nf` | **Prototype / not a product claim** | Uses fixed LAB-color thresholds and explicitly says they may need adjustment. Component masks can overlap; there is no stain normalization, supervised validation, WSI handling, or clinical acceptance criterion. |
| Aortic geometry and bone micro-CT routines | `.../pathology/analyze_aortic_diameter_and_geometry/main.nf`; `.../analyze_bone_microct_morphometry/main.nf` | **Prototype / domain-adjacent** | These are research-image heuristics, not histopathology/WSI. The aortic routine assumes the largest contour is the aorta; the bone routine documents simplified morphometry. |
| IMC/CellProfiler import | `.../bioconductor/imcrtools/main.nf` | **Usable only after validation** | It imports already-segmented CellProfiler/Steinbock-style outputs into R objects. It is not a raw IMC segmentation or a WSI workflow, and its expected directory/file contract must be tested with a real data package. |
| Cytoviewer multi-channel visualization | `.../bioconductor/cytoviewer/main.nf` | **Prototype / not an interactive product surface** | It makes a basic Otsu mask and serializes an RDS object. It does not deploy an interactive viewer in BioMate and does not provide WSI navigation. |
| CRImage cellularity prototype | `.../bioconductor/crimage/main.nf` | **Prototype / not generic input** | The script names fixed files (`trainingData.txt`, `exImg2.jpg`) rather than binding arbitrary user-selected files; no uploaded-slide validation is recorded. |
| Rhod-2 calcium and corneal nerve-fiber routines | `.../pathology/analyze_intracellular_calcium_with_rhod2/main.nf`; `.../quantify_corneal_nerve_fibers/main.nf` | **Not available for user-data claims** | Both embed/mock test-image defaults in the executable definition. They can support development fixtures, not an assertion that user pathology images are analyzed. |
| Existing historical run artifacts | `backend/biomni_workflows/nextflow_nfcore/test_results/` and `STATUS.md` | **Insufficient evidence** | The status file records broad smoke-test success and explicitly says OpenCV pathology image workflows may need testing. It is not a representative WSI/pathology validation report. |

## Incorrect or unsupported current claims

The assistant catalog currently states that `nf-core/mcmicro` supports multiplexed tissue imaging for CODEX, CyCIF, and MIBI (`frontend/server/galaxy-assistant.ts`). That statement is not currently supportable as a BioMate runnable capability:

- The repository has `backend/tools/nfcore_generated/scimap_mcmicro.xml`, but its command invokes the literal `scimap/mcmicro`; it is not an end-to-end BioMate Nextflow workflow.
- Its test contains no representative input binding and only asserts an output size.
- No BioMate runtime workflow, sample data, successful representative execution, or output acceptance test was found for MCMICRO.

Until these are supplied, the truthful wording is: **“MCMICRO is a candidate integration, not an available BioMate analysis.”** The catalog claim must be removed or gated before pathology-facing use.

## Missing WSI capabilities

No implementation was found for the following essentials:

1. WSI ingestion for SVS, NDPI, MRXS, and pyramidal/OME-TIFF with safe metadata extraction (microns-per-pixel, level, stain/scanner information).
2. Tile generation, tissue detection, background/blur/focus QC, coordinate tracking, and tile-to-slide reassembly.
3. Stain normalization and robust handling of scanner/site variation.
4. A packaged, versioned nuclei/cell segmentation model for histology (for example a validated StarDist, HoVer-Net, or Cellpose deployment), with model weights, license review, hardware specification, and per-slide QC.
5. H&E tissue/tumor/necrosis/region classification; IHC positive-cell quantification with calibration; spatial summary and slide-level reporting.
6. Annotation import/export, pathologist review, uncertainty/failure flags, representative datasets, and acceptance metrics against annotations.
7. Clinical/diagnostic validation, intended-use restrictions, and regulated-data governance. None should be implied by the presence of image scripts.

There is also no `OpenSlide`, `QuPath`, `StarDist`, `HoVer-Net`, or executable `Cellpose` WSI pipeline in the shipped workflow path. Mentions in historical inventories or package-extraction JSON are not integrations.

## Recommended first deliverable

Build one narrow, scientifically auditable pathway before adding a catalog of names:

**Research-use-only H&E/IHC WSI preprocessing and nuclei segmentation.**

1. Accept a declared WSI format, initially one format plus OME-TIFF; preserve slide metadata and enforce size limits.
2. Create deterministic tissue tiles with coordinates and basic image-QC flags.
3. Run one pinned segmentation model with known weights and declared hardware requirements.
4. Emit tile masks, a stitched overlay, cell table, QC summary, model/version manifest, and an explicit “research use only / pathologist review required” report.
5. Validate it on a curated, licensed annotated set before it is exposed in the product catalog. Define nuclei-level and slide-level acceptance measures in advance; do not infer success from a container exit code.

MCMICRO/IMC can be a second, separately validated pathway for multiplexed tissue imaging. It should not be merged conceptually with H&E/IHC WSI because the input contracts, biological outputs, and scientific QC differ.

## Immediate product actions

- Remove or gate the current MCMICRO availability statement until a representative run passes with captured artifacts.
- Do not route generic “analyze my pathology slide” requests to the generated pathology scripts as if they are clinically or scientifically validated.
- Keep the existing small-image/IMC routines discoverable only with their input and prototype constraints made explicit.
- Create test cases from real, licensed data before implementing more pathology models; every promoted workflow needs an input fixture, a non-fabricated output assertion, and a documented acceptance criterion.
