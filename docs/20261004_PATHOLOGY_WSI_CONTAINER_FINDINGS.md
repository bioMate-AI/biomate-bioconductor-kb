# Pathology WSI H&E Nuclei Segmentation — Container Findings & Demo-Slide Quick Run

Date: 2026-10-04
Workflow: `backend/biomni_workflows/nextflow_nfcore/subworkflows/pathology/wsi_he_nuclei_segmentation/main.nf`

## Summary

Two changes were made to the WSI H&E nuclei-segmentation workflow:

1. **Param-less "quick run" demo slide** — when no `--input_wsi` is supplied, the
   workflow now downloads and segments a **real, clearly-labelled public demo
   slide** (`CMU-1-Small-Region.svs`) through the same OpenSlide + Cellpose path,
   matching the `merfish_spatial_analysis` demo-fallback pattern. No fabrication;
   honest-fail if the download fails.
2. **Container blocker investigated and documented** — no clean off-the-shelf
   image bundles OpenSlide + Cellpose + scikit-image. `executable` stays **0**.

## Container investigation (the real blocker)

The pinned process-level container is `quay.io/biocontainers/cellpose:3.1.0`
(it overrides the DB `docker_image` on AWS Batch). The workflow requires, in one
image: **openslide-python + libopenslide (C lib)**, **cellpose**, **scikit-image**
(and scipy/numpy, which cellpose already pulls).

### What was checked (quay.io/biocontainers, 2026-10-04)

Mulled v2 repo names were computed with the Galaxy `galaxy-tool-util` convention
(`mulled-v2-<sha1 of newline-joined, alphabetically-sorted package names>`) and
their existence probed via the quay.io API (calibrated: HTTP 200 = exists,
HTTP 401 = absent/404; verified against known repos `cellpose`,
`openslide-python`, `samtools` → 200, and a bogus hash → 401):

| Package set | Mulled repo | quay.io |
|---|---|---|
| cellpose + openslide-python | `mulled-v2-a7990a2cb1ea07c47b04b50f48074ba563f7782a` | **absent (401)** |
| cellpose + openslide-python + scikit-image | `mulled-v2-ff7268b4c5599c60b9f8ca05df5278f0b0267ceb` | **absent (401)** |
| openslide-python + scikit-image | `mulled-v2-fb9651934e61c3da7682fba0bb7a742d57b1ae32` | **absent (401)** |

### What the single cellpose image actually ships

`cellpose` 3.1.0 core deps (PyPI `requires_dist`): numpy, scipy, natsort,
tifffile, tqdm, numba, llvmlite, torch, opencv-python-headless, fastremap,
imagecodecs, roifile. It lists **NEITHER openslide-python NOR scikit-image**.

So `quay.io/biocontainers/cellpose:3.1.0` is missing **BOTH**:
- the OpenSlide reader (python binding + the `libopenslide` C library), and
- scikit-image (used for H&E stain deconvolution, QC, overlay rendering).

The workflow therefore honest-fails at `import openslide` on this image — exactly
the current behaviour. This is correct, not a bug.

### Conclusion

**No clean all-in-one registry image exists.** The remaining owner/infra step is
to **build a custom image** bundling `libopenslide` + `openslide-python` +
`scikit-image` + `cellpose` (e.g. a small `mamba`/conda Dockerfile, or request a
bioconda mulled build for the `cellpose, openslide-python, scikit-image` triplet).
Until that image exists and an owner validation run on a real slide confirms the
pipeline end-to-end, the DB row **stays `executable=0`**. Honesty over a green
checkmark.

## Demo-slide quick run (how it is wired)

- Trigger: `params.input_wsi` is null/empty (param-less run). An explicitly
  supplied path that does not exist still honest-fails (unchanged).
- Source: `https://openslide.cs.cmu.edu/download/openslide-testdata/Aperio/CMU-1-Small-Region.svs`
  (the canonical OpenSlide test slide, ~1.8 MB Aperio SVS, genuine H&E).
- Downloaded at runtime via `urllib.request` into the task workdir, size-sanity
  checked (`>= 100 KB`), then fed to the **same real** `openslide.OpenSlide(...)`
  + Cellpose segmentation path.
- Labelled everywhere: stdout (`[DEMO DATA]`), `qc_summary.json`
  (`input.is_demo = true`, `input.source = "DEMO: CMU-1-Small-Region.svs ..."`),
  and the RESEARCH_USE_ONLY report (`[DEMO DATA]` + an explicit NOTE line).
- Honest-fail contract preserved: if the demo download fails or is corrupt, the
  process exits non-zero — a fabricated slide is never synthesized.

## executable recommendation

**Keep `executable=0`.** It can be flipped to 1 only *after* a custom image with
all three libraries is built and a real validation run (demo slide is sufficient
for the smoke test, a licensed annotated slide for quality) passes end-to-end.
The parent session owns that validation; this change does not flip the flag.

## Validation performed (local, free)

- `python3 scripts/audit_fabrication.py` → PASS (no non-allowlisted fabricators).
- Extracted the process Python body and `py_compile`d it → syntax OK.
- Confirmed no bare/unescaped `$` was introduced in the Groovy script string
  (only the pre-existing intentional `${params.*}` interpolations remain).
