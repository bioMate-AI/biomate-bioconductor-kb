# Bioc Viz Fix + r-pharma Rebuild — 2026-06-14

Companion to `docs/20260614_BIOC_VIZ_COVERAGE_AUDIT.md` (the audit that drove
the changes here) and `docs/20260613_QC_COVERAGE_BLOCKER_FIXES.md` (the
previous QC-coverage stretch). Worktree: main checkout
(`/home/yzhang/biomate`), branch `qc/coverage-and-rebuilds`.

## What landed

| Commit | Subject | Impact |
|---|---|---|
| `8947ccca1` | fix(bioc-viz): route .pdf to interactive (iframe), not image | unbreaks ~4,671 PDF figures (the dominant bioc output) |
| `cae906667` | feat(bioc-viz): P1 vocab + hints expansion | specific viz labels +126%, no-viz -85% |
| `c3e390576` | fix(ames): tuple-index bug — a[3] (desc) → a[2] (severity) | every Ames classification now correct on the canonical positive control |
| `52d1e4750` | docs(qc-coverage): record Ames accuracy fix | |
| `2f16deaf0` | fix(r-pharma): + libmpfr-dev/libgmp-dev for symengine | unblocks nlmixr2 install chain |
| `e791ecbf2` | fix(r-pharma): drop tidyverse from hard gate (later reverted) | trial-and-error on which packages must be in the structural assertion |
| `8b61d1183` | fix(r-pharma): consolidate libmpfr/libgmp/libwebp into top apt | one apt fix instead of three layer-specific patches |

## Bioconductor visualization (P0 + P1 from the audit)

### P0 — PDF rendering (highest impact, smallest change)

`docs/20260614_BIOC_VIZ_COVERAGE_AUDIT.md` quantified the problem: PDF is
**~85% of bioc figure ext occurrences (4,671 vs PNG 55)**. Two server-side
classifiers existed and **disagreed**:

- `getFileType` (`frontend/server/routes.ts:98`): routed `pdf → interactive`
  (the correct path — opens via `<iframe>`).
- `classifyFileType` (`frontend/server/routes.ts:13860`): routed
  `pdf → image` → `ImageOutput` → `<img src=blob:…pdf>` → broken-image icon.

Server-emitted `fileType` from `classifyFileType` drove both the per-step
output preview AND the chat-output attachments. So in practice every PDF
figure in every bioc workflow showed a broken image inline.

**Fix (`8947ccca1`)**: move `pdf` from `imageExts` to `interactiveExts` in
`classifyFileType`. `InteractiveOutput` already uses `<iframe>`, which
browsers render natively via the built-in `application/pdf` viewer
plugin. Same change picks up `tiff` and `bmp` — they can't render in
`<img>` either, demoted to `binary` (download link) until a server-side
PNG conversion route is added.

### P1 — Vocab + hint expansion (Layer 1 → Layer 2 coverage)

The audit listed 48 named plotting functions used in the corpus but NOT
in `VIZ_FUNCS`, and identified 16 filename patterns missing from
`FIG_HINTS`.

**Fix (`cae906667`)**:

- **`VIZ_FUNCS`**: added 35 long-tail entries (qcReport, plotDensities,
  plotRLE, mdsPlot, venn/vennDiagram/upset, qq, plotManhattan, ggbio,
  forestplot, corrplot, densityPlot, plotDiagnostics, plotDMRs,
  ideogram, plotChromosome, plotGenes, fviz_nbclust, beeswarm, plotSA,
  plotCoverage, screeplot, biplot, plotPosterior, xyplot/levelplot/
  splom/cloud (lattice), smoothScatter, plotDendrogram/dendrogram,
  stripchart, matplot, mosaicplot). The 14 highest-frequency ones were
  already added by an earlier pass; this commit picked up the long tail.
- **`FIG_HINTS`**: added 16 patterns (track, profile, correlation,
  karyotype, pathway/kegg, roc, manhattan, qq, tree/phylo, mean-sd,
  rle, forest, circos/chord, venn, upset, biplot, beeswarm, coverage,
  scree, mosaic, stripchart, mds).
- **Re-ran enrichment**: `enrich_bioc_viz_qc.py` (3,177 DB rows updated,
  backup `galaxy_ai_tools.db.bak.1781451980`) and
  `enrich_bioc_step_metadata.py` (3,177 rows updated, backup
  `.bak.1781452002`). 707 `.nf` files received refreshed header
  annotations.

### Coverage shift (vs the 06-14 audit baseline)

| Bucket | Before | After | Delta |
|---|---:|---:|---:|
| specific label | 827 | 1,873 | **+126%** |
| generic-only ("plot (ggplot/base)") | 1,487 | 1,304 | -12% |
| no viz label | 906 | 133 | **-85%** |

The headline number: **`no_viz` collapsed by 85%** because most "no
specific viz" workflows had base R figure output that the broadened
FIG_HINTS now classifies. The remaining `generic_only` bucket
(1,304/3,310 = 39%) consists of workflows where the figure filename
genuinely carries no semantic hint (`figure1.pdf`, `output.pdf`,
`result_plot.pdf`); those need direct `VIZ_FUNCS` matches against the
R body, which is already the most precise path the script has.

## Ames classifier fix (genotoxicity_ames_prediction)

The audit verification (`3be48cf6 06-12`) had flagged that the QC-gate
coverage cycle fired correctly, but the underlying workflow misclassified
4-nitroaniline as NEGATIVE. 4-nitroaniline is the canonical Ames+
positive control — both `nitro_aromatic` and `primary_aromatic_amine`
structural alerts apply.

**Root cause (`c3e390576`)**: `ames_verdict()` at line 108-112 read
`a[3] == 'HIGH'`, but the triggered tuple is built at line 153 as
`(name, cat, severity, desc)` — so `a[3]` is the long description
string ("Aromatic nitro -- DNA adduct former, Ames-positive"), not the
severity (which is `a[2]`). The equality never held; every compound
silently returned NEGATIVE regardless of alerts.

Confirmed via manual RDKit check before the fix: both SMARTS patterns
DO match 4-nitroaniline. The patterns are correct; only the verdict
function was wrong.

## r-pharma container rebuild

Background activity all session. Goal: get `biomate/r-pharma:x86` into
ECR so the nlmixr2 verification (the last remaining QC-coverage blocker)
can run.

### Build journey (7 attempts so far, current is in-flight)

| # | Trigger | Outcome |
|---|---|---|
| 1 | Initial attempt with the two-tier QEMU pattern | Cached layer from earlier broken state replayed empty; hard gate caught |
| 2 | Per-package install split | s2/geospatial cascade (23-min C++ build for an irrelevant lib) before I killed it |
| 3 | `dependencies = TRUE` → `c('Depends','Imports','LinkingTo')` to drop Suggests | Cleared geospatial cascade; hit `fs` → `libuv` failure |
| 4 | `ENV USE_BUNDLED_LIBUV=1` | fs cleared; tidyverse layer failed via `ragg` → `libwebp` cascade |
| 5 | Dropped tidyverse from hard gate (reverted later) | Got past tidyverse; rxode2 cleared in 56 min; nlmixr2 failed at `symengine` → `libmpfr` |
| 6 | Bash quote escape error (typo in my docker buildx command) | Failed instantly at "invalid tag" |
| 7 | Consolidated `libmpfr-dev + libgmp-dev + libwebp-dev` into top apt block | **in flight at time of writing** |

### Why this took 7 iterations

QEMU x86-on-ARM emulation made every package install a multi-hour
experiment. Three layered constraints:

1. **Native extensions segfault at load time** under QEMU — that's
   what the original `|| true` masks were guarding against. Removing
   them naively (build #1) made the build fail at QEMU artifacts, not
   real bugs.
2. **One giant `install.packages(c(...))` swallows individual
   failures** under `|| true`, then the hard `test -d` gate catches
   the missing artifact with no signal as to which subdep failed.
   Splitting per-package (build #2) was step one for diagnosability.
3. **`dependencies = TRUE` drags in Suggests/Enhances** which pulled
   in geospatial (s2/sf), web tooling (sass/bslib), and 50+ other
   irrelevant subgraphs. Narrowing to required-only deps (build #3)
   was step two.

Even after those, three system libs were missing from the base
`rocker/r-ver:4.3.1` image and surfaced one at a time across builds 4-6:
`libuv`/`fs`, `libwebp`/`ragg`, `libmpfr+libgmp`/`symengine`. Build #7
consolidates all three into the top apt block.

### What the two-tier pattern protects

When build #7 lands:

- **Soft layer**: `RUN Rscript -e "install.packages('<pkg>', ...)" || true`
  — actually installs the package, writes files to
  `/usr/local/lib/R/site-library/<pkg>/`, but tolerates a QEMU
  segfault during the post-install load smoke test.
- **Hard layer**: `RUN test -d /usr/local/lib/R/site-library/<pkg>
  || (echo "FATAL: ..." && exit 1)` — pure file existence check, no
  native-extension load, runs cleanly under QEMU. This is the **real**
  build-phase verification: the question of "does the next ECR pull get
  a working install" depends only on what files actually landed.

The runtime smoke test on real x86 (Batch tasks pulling from ECR) is
what catches actual load failures — that's not the build's job.

## State of QC coverage at time of doc

Per `docs/20260609_QC_COVERAGE_EXPANSION.md` (the canonical coverage
table): 19 of 20 candidate workflows verified end-to-end. nlmixr2 is the
remaining gap and is blocked solely on the r-pharma image landing in
ECR. Once build #7 (or a successor) finishes, the existing nlmixr2
fixture (`s3://biomate-nextflow-work/fixtures/popPK/synthetic_pk_theo.csv`)
and the existing nlmixr2 workflow (which has fixes for algorithm switch
+ R `$` escape + failure-state qc_metrics from the prior session) can
be re-tested to close the final 20/20.

## Branch + push state

- Current branch: `qc/coverage-and-rebuilds` (tracked at
  `origin/qc/coverage-and-rebuilds`).
- All commits in this stretch are pushed to that branch.
- The Ames fix `c3e390576` was also mirrored to `bioc/v2-qc-audit-panel`
  via cherry-pick, so it'll reach `integration/next-phase` through
  whichever merge path lands there first.

## Files referenced

- Audit:
  `docs/20260614_BIOC_VIZ_COVERAGE_AUDIT.md`
- Previous QC blocker writeup:
  `docs/20260613_QC_COVERAGE_BLOCKER_FIXES.md`
- Canonical coverage table:
  `docs/20260609_QC_COVERAGE_EXPANSION.md`
- Vocab + hint source:
  `backend/scripts/enrich_bioc_viz_qc.py`
- Step attribution source:
  `backend/scripts/enrich_bioc_step_metadata.py`
- Server-side classifier:
  `frontend/server/routes.ts` (`classifyFileType` line 13857,
  `getFileType` line 98)
- Per-step renderer:
  `frontend/client/src/components/step-output-preview.tsx`
- Chat-output renderer:
  `frontend/client/src/components/chat-output-attachments.tsx`
- Ames workflow:
  `backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/genotoxicity_ames_prediction/main.nf`
- r-pharma Dockerfile:
  `backend/docker/r-pharma/Dockerfile`
