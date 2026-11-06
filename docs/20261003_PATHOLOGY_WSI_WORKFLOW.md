# Pathology WSI — RUO H&E nuclei-segmentation workflow (first deliverable)

**Date:** 2026-10-03
**Thread:** C of `docs/20261003_PARALLEL_WORKSTREAM_PLAN.md`
**Scope:** ONE narrow, honestly-scoped, research-use-only (RUO) whole-slide-image
(WSI) workflow, per the "Recommended first deliverable" in
`docs/20261003_PATHOLOGY_WSI_CAPABILITY_AUDIT.md`. This is **not** a diagnostic
device and **not** a claim that BioMate is a digital-pathology platform.

## What was built (new files only)

```
backend/biomni_workflows/nextflow_nfcore/subworkflows/pathology/wsi_he_nuclei_segmentation/
  main.nf           # the workflow (DSL2; embedded, ast-validated Python)
  meta.yml          # nf-core style metadata
  nextflow.config   # resource/profile defaults (process directive is authoritative)
```

No existing file was modified. The gitignored `galaxy_ai_tools.db` was **not**
edited — DB registration is left to the owner (row below).

## Pipeline

1. **Ingest (OpenSlide).** Accepts one OpenSlide WSI format (e.g. Aperio `.svs`)
   plus pyramidal OME-TIFF via `openslide.OpenSlide`. Reads level-0 dimensions,
   pyramid level count, vendor, and microns-per-pixel (from slide metadata, or a
   `--mpp` override). **A real `--input_wsi` is mandatory — there is NO built-in
   or fallback slide** (fabricated inputs are forbidden).
2. **Deterministic tissue tiling + QC.** Fixed raster grid at level 0 with
   `tile_size`/`tile_overlap`; per-tile coordinates recorded. Tissue detection =
   Otsu on the HSV-saturation channel of a bounded thumbnail (background flag).
   Focus QC = variance-of-Laplacian per processed tile (blur flag). Fully
   deterministic — no RNG anywhere.
3. **One pinned nuclei model (Cellpose).** `model_type='nuclei'` fed the
   hematoxylin channel (`skimage.color.rgb2hed`, min-max normalized — the
   standard H&E deconvolution so nuclei are bright, which the `nuclei` model
   expects). Real pretrained cellpose weights (downloaded to `~/.cellpose` on
   first use; requires worker network egress).
4. **Outputs.** per-tile labelled masks (`tiles/*_mask.png`, uint16), stitched
   QC overlay (`qc_overlay.png`), per-nucleus cell table (`cell_table.csv`),
   QC summary (`qc_summary.json`), model/version manifest (`model_manifest.json`),
   and a clearly-labelled `RESEARCH_USE_ONLY_report.txt`
   ("NOT FOR DIAGNOSTIC USE — PATHOLOGIST REVIEW REQUIRED"), plus `versions.yml`.

## Honesty / failure contract (no fabrication)

The process exits **non-zero with an actionable message** if:
- `openslide` (python binding + libopenslide C lib) is not importable;
- `cellpose` / `scikit-image` / `scipy` / `numpy` are not importable;
- the cellpose model weights cannot be initialized/downloaded;
- `--input_wsi` is missing or the path does not exist;
- OpenSlide cannot open the file (e.g. a plain non-pyramidal TIFF);
- no tissue tile could be segmented.

There are **no** `np.random` / `random.*` calls, no hardcoded fake numbers, and
no "this would contain…" placeholders. Every emitted number is a real
measurement (OpenSlide metadata, tissue fractions, Laplacian variance,
cellpose mask labels, `skimage.measure.regionprops` centroids/areas).

## Container — pinned, registry-verified, license-clean

- **Directive (authoritative on AWS Batch):** `container 'quay.io/biocontainers/cellpose:3.1.0'`
  set at the process level in `main.nf`. Per the executor facts this OVERRIDES
  the DB `docker_image`, so it is set in the `.nf`.
- **Existence verified read-only** via the quay.io registry API (no pull/run):
  tag `3.1.0` is active, `manifest_digest sha256:0467d790...`, size ~1.16 GB.
  (StarDist was rejected: `quay.io/biocontainers/stardist` returns an empty
  active-tag list, so Cellpose is the license-clean, container-available choice.)
- **License:** Cellpose is **BSD-3-Clause** (PyPI metadata: `License :: OSI
  Approved :: BSD License`) — clean for commercial use.

### Known validation risk (why `executable=0`)

The single-tool cellpose biocontainer may **not** ship the OpenSlide C library +
`openslide-python`. If OpenSlide is absent, the workflow honest-fails at import
time (by design) rather than silently degrading. The **owner validation run must
confirm OpenSlide is present in the running image**; if it is not, the validated
deployment image must bundle OpenSlide + cellpose (a mulled/extended image). This
unresolved container question is exactly why the DB row ships `executable=0`
until a real Batch run on a licensed, annotated slide passes end-to-end. Do not
infer success from a container exit code — define nuclei-level and slide-level
acceptance measures in advance (see audit §"Recommended first deliverable" step 5).

## Local validation performed (no runs, no sync)

- Embedded Python extracted from `main.nf` and `ast.parse`d → **OK** (452 lines);
  byte-identical to the standalone copy that was independently parsed.
- `grep -cE 'np\.random|random\.(uniform|choice|gauss|randint)'` on `main.nf` → **0**.
- `nextflow lint main.nf` → **no errors** (only a cosmetic `Channel`→`channel`
  deprecation warning, consistent with the sibling `merfish_spatial_analysis`).
- Container tag + license verified via read-only registry/PyPI API calls (above).

**NOT performed (owner-gated):** `scripts/sync_to_dev.sh`, any AWS Batch / cloud
dispatch, any `docker pull`/run. Real validation on a licensed annotated slide is
the owner's step.

## Exact DB registration row (owner runs this against the full `galaxy_ai_tools.db`)

Register with **`executable=0`** (not yet validated). FTS is auto-maintained by
the `workflows_au`/insert triggers — no manual FTS write needed. `workflow_json`
is the verbatim contents of the new `main.nf`.

```sql
INSERT INTO workflows (
    name, filename, description, tags, domain, workflow_json, step_count,
    tools_used, source, format, executable, docker_image, category,
    input_types, output_types, params_schema
) VALUES (
    'Wsi He Nuclei Segmentation',
    'nextflow_nfcore/subworkflows/pathology/wsi_he_nuclei_segmentation/main.nf',
    'RESEARCH-USE-ONLY whole-slide-image (WSI) H&E preprocessing and nuclei segmentation. Ingests one WSI via OpenSlide (one OpenSlide format e.g. Aperio .svs, plus pyramidal OME-TIFF), performs deterministic tissue tiling with coordinates + background/blur QC, and runs one pinned license-clean nuclei model (Cellpose, BSD-3-Clause) on the hematoxylin channel. Emits per-tile masks, stitched QC overlay, cell table, QC summary, model/version manifest, and a pathologist-review-required report. NOT a diagnostic device.',
    '["pathology","histopathology","whole_slide_image","WSI","H&E","openslide","cellpose","nuclei_segmentation","tiling","tissue_detection","research_use_only","RUO"]',
    'pathology',
    '<VERBATIM CONTENTS OF main.nf>',
    1,
    '["openslide","cellpose","scikit-image","scipy","numpy"]',
    'biomni_nextflow',
    'nextflow',
    0,
    'quay.io/biocontainers/cellpose:3.1.0',
    'pathology',
    '["wsi","svs","ome_tiff","openslide"]',
    '["png","csv","json","txt","yml"]',
    '{"input_wsi":{"type":"string","required":true,"description":"Path to one WSI (.svs / pyramidal OME-TIFF)"},"tile_size":{"type":"integer","default":512},"tile_overlap":{"type":"integer","default":0},"max_tiles":{"type":"integer","default":200},"tissue_threshold":{"type":"number","default":0.10},"blur_threshold":{"type":"number","default":100.0},"cell_diameter":{"type":"number","default":0},"flow_threshold":{"type":"number","default":0.4},"cellprob_threshold":{"type":"number","default":0.0},"mpp":{"type":"number","default":null},"use_gpu":{"type":"boolean","default":false},"model_type":{"type":"string","default":"nuclei","allowed_values":["nuclei","cyto","cyto2","cyto3"]}}'
);
```

**Field rationale**
- `executable=0` — the one field that differs from a normal registration; the
  OpenSlide-in-container question is unresolved until an owner validation run.
- `docker_image` mirrors the authoritative process-level `container` directive so
  the DB and `.nf` agree (the `.nf` wins on Batch regardless).
- `source='biomni_nextflow'`, `format='nextflow'`, `domain='pathology'`,
  `category='pathology'`, `step_count=1` — consistent with sibling rows
  (`segment_and_quantify_cells_in_multiplexed_images` id 10760;
  `merfish_spatial_analysis` id 14608).

After the owner's validation run passes with captured artifacts and acceptance
measures met, flip `executable=1` and record `real_exec_status`/`real_exec_at`.

## Open issues / next steps (owner)

1. Confirm OpenSlide availability inside `cellpose:3.1.0` on Batch; if absent,
   build/pin a mulled image bundling OpenSlide + cellpose and update both the
   `.nf` directive and the DB `docker_image`.
2. Validate on a curated, licensed annotated H&E set; define nuclei-level (e.g.
   F1 vs annotations) and slide-level acceptance BEFORE the run.
3. Confirm worker network egress for the cellpose weight download (the
   feature_distribution / ChIP-seq runs proved CRAN/Bioc egress works; expected fine).
4. Only after a passing validation: expose in the catalog and flip `executable=1`.
