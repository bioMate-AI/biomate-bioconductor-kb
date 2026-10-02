# Spatial-Omics Validation Plan (imaging-based first)

**Date:** 2026-10-01
**Author:** Yaoyun Zhang
**Context:** Catalog breadth in spatial omics is strong (106 workflows, nearly all important
Bioconductor spatial packages — see the capability audit below). The gap is **validated
execution**, not coverage. This session proved "indexed" ≠ "runs": `merfish_spatial_analysis`
was emitting **RNG-fabricated** results and needed a 5-fix chain before it executed; `sc3` was
broken on a missing `library()`. This plan converts breadth into a *defensible* capability by
validating execution, imaging-based first (per direction).

Companion docs: `20261001_MERFISH_SPATIAL.md` (the 5-fix chain + lessons),
`20260928_DOMAIN_VALIDATION_UNTESTED.md` (single-cell/bioc validation method),
memory `reference_executor_container_resolution`.

---

## Guiding method (per workflow) — cheap-first

1. **Static fabrication audit (no Batch, ~free).** Grep the `.nf` script body for fabrication
   tells: `random.(uniform|choice|gauss|seed)`, `np.random`, hardcoded gene/value lists, canned
   round numbers, a `versions.yml` naming tools the body never imports. A workflow that fabricates
   is worse than one that honest-fails. **This is the #1 risk** (merfish fabricated).
2. **Container/infra audit (no Batch).** Compare the `.nf` process `container` directive vs the DB
   `docker_image` (the **directive wins** — see memory). Flag any workflow whose task image is a
   bare `quay.io/biocontainers/*` AND whose `nf_path` is **outside** the executor's libz-mount gate
   (`is_nfcore | /bioconductor/ | /nf-core-modules/ | /single_cell/`) → it will **exit 127** on S3
   staging. Confirm the image actually ships the package (runtime probe, not the Dockerfile).
3. **Execution (Batch).** Dispatch via the public `/api/workflows/execute` path (fixture auth),
   with squidpy/bioc built-in or S3-staged demo data. Read the S3 work dir directly:
   `.exitcode == 0`, real non-empty outputs, and **content sanity** (e.g. Moran's I ranking is
   biologically plausible), not just "it ran."
4. **Fix at root cause**, re-run, record. No fabrication workaround, no reverting to a stub to pass.

> Dispatch/verify recipe, run-state gotchas (stale-exec race, completion lag), and the S3 work-dir
> inspection commands are all in `20261001_MERFISH_SPATIAL.md`.

---

## Shared infra fixes (do these ONCE; they unblock groups)

| Fix | Status | Unblocks |
|---|---|---|
| libz mount gate → include `/single_cell/` | ✅ done (2026-10-01) | merfish + single_cell quay-biocontainer workflows |
| libz mount gate → include `/spatial/` | ⬜ **TODO** | `squidpy_spatial_analysis` (14453) and any `biomni_workflows/spatial/*` quay-biocontainer wf |
| Systematic anti-fabrication grep across all spatial `.nf` | ⬜ TODO (Phase 0) | triages the whole set cheaply |
| Container-directive vs DB docker_image consistency pass | ⬜ TODO (Phase 0) | prevents "DB change does nothing" surprises |
| merfish `fdr_bh = nan` → fix BH-FDR step | ⬜ TODO | correct SVG significance (ranking already OK) |

---

## Phase 0 — static triage (no Batch, do first)

Run the fabrication + container audit across **all 106** spatial workflows. Output: a table of
`real | stub | fabricating | infra-blocked`. Expect this to reclassify several "indexed" workflows
as non-executable (candidates for `executable=0`, like the earlier stub cleanup) and to find more
RNG stubs of the merfish class. **This is the highest value-per-minute step.**

### Phase 0 — FIRST PASS RESULTS (2026-10-01)

Audited the executable spatial set statically (fabrication tells + libz-gate coverage). Findings:

- **Phantom cluster — the whole `spatial_transcriptomics` domain (6 rows) has NO `.nf` on disk**
  (`biomni_workflows/spatial/` does not exist) yet was `executable=1`. These would fail
  file-not-found if run. **Marked `executable=0`** (rides the sync): `spatial_visium_banksy` (14450),
  `spatial_deconvolution_rctd` (14451), `spatial_ligand_receptor_liana` (14452),
  `squidpy_spatial_analysis` (14453), `spatial_multiomics_integration` (14454),
  `spatial_immune_aging_thymus` (14455). **These are BUILD TARGETS** — all are desirable
  (BANKSY domains, RCTD deconvolution, LIANA ligand-receptor, multi-omics integration) and several
  overlap functionally with real workflows already present (banksy [10928/13078/13079], RCTD via
  `spatial_deconvolution_rctd` logic, etc.). The working squidpy-spatial pipeline is
  `merfish_spatial_analysis` (validated); `squidpy_spatial_analysis` (14453) was a phantom duplicate.
- **CardinalIO (11038)** — synthesizes a random image (`matrix(runif(...))` → `writeImzML`) to
  demo the imzML I/O round-trip. Borderline: acceptable for an **I/O-format utility** demo, NOT for
  analysis. Recommend labeling it a demo/round-trip, not a results-producing workflow. Low urgency
  (does not pass fake *analysis* off as science, unlike the old merfish RNG stub).
- **fpsim2_chemical_similarity (14461)** — quay biocontainer under `/drug_discovery/`, which is
  OUTSIDE the libz-mount gate → same **exit-127** class as merfish (cross-domain, not spatial).
  Noted for a broader fix: the libz mount should ideally key off "task image is a bare quay
  biocontainer" rather than the nf_path allow-list (the allow-list is whack-a-mole: nf-core →
  +bioconductor → +nf-core-modules → +single_cell → now drug_discovery…).
- **False positives:** `merfish` 14608 (`fab-word` = my own anti-fabrication guard text),
  REINVENT4 / AutoDock-Vina / turep (generative/comment-level randomness, non-spatial).

**Net:** breadth number drops honestly (6 phantom spatial_transcriptomics rows removed from the
executable set), and two real infra/quality items are logged. Next: Phase 1 execution of the
**real** imaging-based bioc workflows (the table below), which DO have files + images.

## Phase 1 — imaging-based (PRIORITY), cheap Bioc/py runs

Already validated: `merfish_spatial_analysis` ✅, `visium_voyager_spatial_esda` ✅.

**1a. `squidpy_spatial_analysis` (14453) — do first.** Direct merfish analog
(`biomni_workflows/spatial/…`, docker_image=none → check its `.nf` container directive). Needs the
`/spatial/` libz-gate fix above. Likely one infra fix + one run from green.

**1b. Bioconductor imaging set** — run in `bioc-domain-imaging:3.20` (full image, aws baked) OR
their own quay biocontainers (already libz-covered via `/bioconductor/`). Validate like sc3
(dispatch + demo/staged SCE/SPE input, exit 0, real outputs, fabrication audit):

| id | workflow | image |
|---|---|---|
| 11628 | imcRtools (IMC spatial) | bioc-domain-imaging:3.20 |
| 11204 | cytomapper | bioconductor-cytomapper (quay) |
| 11210 | cytoviewer | bioc-domain-imaging:3.20 |
| 11037 / 14204 | Cardinal (MS imaging) | bioconductor-cardinal (quay) |
| 11705 | lisaClust | bioc-domain-imaging:3.20 |
| 12444 | spicyR | bioc-domain-imaging:3.20 |
| 13570 | fuseSOM | bioc-domain-imaging:3.20 |
| 12429 | spaSim | bioc-domain-imaging:3.20 |
| 11856 | MoleculeExperiment | bioconductor-moleculeexperiment (quay) |
| 12634 | xenLite (Xenium) | bioc-domain-general:3.20 |
| 12474 | statial | bioc-domain-transcriptomics:3.20 |
| 12316 | scider | bioc-domain-transcriptomics:3.20 |

*Risk ranking:* the 3 **quay-biocontainer** ones (cytomapper, cardinal, moleculeexperiment) carry
the highest infra risk (biocontainer completeness); the `bioc-domain-*` ones carry the highest
fabrication / R-library-attach risk.

## Phase 2 — sequencing-based spatial (Visium / GeoMx), same method

SpatialExperiment, SpatialFeatureExperiment, nnSVG, BayesSpace, Banksy (+joint/Harmony variants),
SpatialDE, SPOTlight, RCTD (`spatial_deconvolution_rctd`), spatialdecon, geomxtools, standR, spoon,
tpsvg, despace, smoothclust, spotclean, spotsweeper. All `/bioconductor/` (libz-covered). Triage via
Phase 0, then run the ones that pass the fabrication audit.

## Phase 3 — heavy nf-core imaging pipelines (defer / test-profile only)

imcyto, mcmicro, molkart, spatialvi (spatialxe already `executable=0`). Real nf-core pipelines
needing real imaging inputs + larger compute — validate with nf-core `-profile test` where it
exists, not ad-hoc; budget accordingly. Lower value-per-dollar than Phases 0–2.

---

## Known gaps (package absent; functional substitute present)

`spatialLIBD`, `SPARK/SPARK-X` (≈ nnSVG/SpatialDE/spoon), `MERINGUE`, `STdeconvolve`/`CARD`
(≈ RCTD/SPOTlight/spatialdecon/DeMixT), `Giotto` (≈ squidpy). Adding these is **lower priority than
validating what's already indexed** — coverage is good; execution is the moat.

## Success criterion

Not "N workflows indexed" but "N workflows **proven** to run on real data with non-fabricated,
biologically-sensible output, on the production Batch path." Target a first milestone of the
~14 imaging-based workflows (Phases 1a+1b) green, which also shakes out the shared infra fixes for
everything else.
