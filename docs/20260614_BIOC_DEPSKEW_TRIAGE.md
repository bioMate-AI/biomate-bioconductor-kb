# Bioconductor Dependency/Load Failure Triage — 14 workflows (2026-06-14)

Branch: `fix/bioc-dep-skew` (base `bioc/v2-qc-audit-panel`)
Source of errors: `docs/20260614_BIOC_VALIDATION_340_AUDIT.json`
Reference for the upstream-skew class: `backend/scripts/domain_images/README.md`

## Summary

| # | Workflow | Class | Exact error (abridged) | Root cause | Action |
|---|----------|-------|------------------------|------------|--------|
| 1 | ancombc/main.nf | **iii UPSTREAM** | `object 'solve' is not exported by 'namespace:CVXR'` | ANCOMBC built against older CVXR (re-exported `solve`); current CRAN CVXR dropped it | Defer — date-pinned base (same class as miaverse) |
| 2 | ancombc/ancombc2_advanced_da.nf | **iii UPSTREAM** | same | same | Defer |
| 3 | ancombc/ancombc_bias_corrected_da.nf | **iii UPSTREAM** | same | same | Defer |
| 4 | ancombc/secom_correlation_analysis.nf | **iii UPSTREAM** | same | same | Defer |
| 5 | hicool/main.nf | **iii UPSTREAM (env ABI)** | `Matrix.so: undefined symbol: NO_REFERENCES` | Runtime-installed `Matrix.so` built against R≥4.4 loaded in mismatched R (harness env, `/rlib/`) | Defer — env/base ABI, not `.bm_deps` |
| 6 | clumsid/main.nf | **iii UPSTREAM (env ABI)** | `dbscan.so: GLIBC_2.38 not found` | Runtime `dbscan` binary needs newer glibc than container | Defer — system libc, not `.bm_deps` |
| 7 | clumsid/lc_ms2_lowres.nf | **iii UPSTREAM (env ABI)** | same | same | Defer |
| 8 | methylkit/large_data_tabix_db.nf | **ii FIXABLE-IMAGE** | `there is no package called 'methylKit'` | Ran on base `:3.20` (no deps baked); runtime source-install of methylKit fails (LinkingTo Rhtslib/zlibbioc, SystemRequirements GNU make) | Bake `:3.20-deps` (genomics) — already in `deps/genomics.txt`; route to `:3.20-deps` |
| 9 | methylkit/main.nf | **ii FIXABLE-IMAGE** | same | same (also genomation) | Same |
| 10 | geodiff/main.nf | **ii FIXABLE-IMAGE** | `there is no package called 'GeoDiff'` | Ran on base `:3.20`; runtime source-install fails (LinkingTo Rcpp/RcppArmadillo/roptim) | Bake `:3.20-deps` (transcriptomics) — already in `deps/transcriptomics.txt`; route to `:3.20-deps` |
| 11 | chromdraw/bed_file_karyotype.nf | **i FIXABLE-BOOTSTRAP (script bug)** | `there is no package called 'chromdraw'` at `packageVersion("chromdraw")` | Case typo: package is `chromDraw`; only the `versions.yml` line used lowercase. Analysis ran fine. | **FIXED** — `packageVersion("chromDraw")` |
| 12 | ibbig/expression_data_preprocessing.nf | **ii FIXABLE-IMAGE** | `there is no package called 'iBBiG'` | Ran on base `:3.20`; iBBiG (noarch) + biclust were **absent from `deps/transcriptomics.txt`** → never baked | **FIXED deps file** — added `iBBiG` + `biclust`; rebuild `:3.20-deps` |
| 13 | ibbig/main.nf | **ii FIXABLE-IMAGE** | same | same | Same |
| 14 | qsutils/strand_haplotype_intersection.nf | **i FIXABLE-BOOTSTRAP (script bug)** | `there is no package called 'qsutils'` at `packageVersion("qsutils")` | Case typo: package is `QSutils`; `library(QSutils)` loads fine; only version line used lowercase | **FIXED** — `packageVersion("QSutils")` |

Class tally: **i FIXABLE (code) = 3** (chromdraw, qsutils, + iBBiG deps-file gap), **ii FIXABLE-IMAGE = 5** (methylkit×2, geodiff, ibbig×2), **iii UPSTREAM = 7** (ancombc×4, hicool, clumsid×2).

---

## (i) FIXABLE — applied in this branch

### chromdraw/bed_file_karyotype.nf, qsutils/strand_haplotype_intersection.nf — `packageVersion()` case typo
The analysis body uses the correct Bioconductor package name (`library(chromDraw)`, `library(QSutils)`)
and ran to completion. Only the final `versions.yml` line called `packageVersion()` with a **lowercase**
name (`"chromdraw"` / `"qsutils"`), which R resolves case-sensitively → "no package called X". These run on
the biocontainers images where the package is pre-installed, so this was never a `.bm_deps` problem — it is a
one-token bug in the version-reporting line. Fixed to `packageVersion("chromDraw")` / `packageVersion("QSutils")`.

> Note: this was mis-bucketed as PKG-LOAD in the audit. The trace `Calls: writeLines -> paste0 -> packageVersion`
> shows the failure is *after* the analysis, in version reporting — not a load failure.

### iBBiG / biclust — missing from the domain deps manifest (image-bake gap that is code-fixable)
`iBBiG` (Bioc 3.20 v1.50.0) is **noarch** (`Depends: biclust; Imports: stats4, xtable, ade4`; no LinkingTo,
no SystemRequirements), so it bakes cleanly — but it and `biclust` were in **no** `deps/*.txt`. The ibbig
workflows ran on base `:3.20`, fell back to the runtime `.bm_deps` self-install, and that install failed
(the base image's `install.packages` source path is not reliable for Bioc — see README §"Why BiocManager, not
install.packages"). The durable fix is to bake it: added `iBBiG` and `biclust` to `deps/transcriptomics.txt`.
Requires a `transcriptomics:3.20-deps` rebuild + a run routed to `:3.20-deps` (not the base `:3.20`).

The `.bm_deps <- c(...)` lines for ibbig already list the right package (`iBBiG`, and `biclust` in the
preprocessing variant) with correct case, so no `.bm_deps` line edit was needed or made — adding more entries
would not have fixed a non-baked / failed-source-install package.

---

## (ii) FIXABLE-IMAGE — documented actions (require a domain-image rebuild, not verifiable by code edit)

These three packages are **already declared** in their domain `deps/*.txt` (methylKit + genomation in
`genomics.txt`; GeoDiff in `transcriptomics.txt`) but failed because **the validation runs used the base
`:3.20` image, not `:3.20-deps`** (confirmed from the audit `image` field). On the base image the runtime
`.bm_deps` bootstrap must source-compile them, and all three have native `LinkingTo`:

- **methylKit** — `LinkingTo: Rcpp, Rhtslib (>=1.13.1), zlibbioc`; `SystemRequirements: GNU make`. Source build
  needs the HTSlib headers + a compiler. Bake into `bioc-domain-genomics:3.20-deps`.
- **GeoDiff** — `LinkingTo: Rcpp, RcppArmadillo, roptim`. Heavy C++/Armadillo compile. Bake into
  `bioc-domain-transcriptomics:3.20-deps`.
- **iBBiG** — noarch, now added to `transcriptomics.txt` (see above). Bake into the same `:3.20-deps`.

**Precise action for the team:**
1. Rebuild `bioc-domain-genomics:3.20-deps` and `bioc-domain-transcriptomics:3.20-deps` per
   `backend/scripts/domain_images/README.md` (BiocManager template, spot box, push to ECR). The
   transcriptomics rebuild picks up the new `iBBiG`/`biclust` entries.
2. **Route these workflows to `:3.20-deps`, not the base `:3.20`.** The base tag has no baked deps; the
   validation used it and that is why already-declared packages reported "no package called X". Confirm the
   executor's image-tag selection uses `:3.20-deps` for these domains.
3. Post-build sanity per README: `requireNamespace("methylKit")`, `requireNamespace("GeoDiff")`,
   `requireNamespace("iBBiG")` must each be TRUE on the pushed image before marking runnable.

No production `.nf` param/code change is involved here — it is an image-build + image-routing action.

---

## (iii) UPSTREAM — not fixable in our pipeline (documented, deferred)

### ancombc (4 workflows) — CVXR `solve` export dropped (CRAN drift)
`ANCOMBC` was compiled against an older `CVXR` that re-exported `solve`; the current CRAN `CVXR` no longer
exports it, so `loadNamespace("ANCOMBC")` fails with `object 'solve' is not exported by 'namespace:CVXR'`.
This is **exactly** the README's documented class: a Bioc package built against an older CRAN dep that has
since dropped a symbol (`rbiom`→`unifrac`, `xfun`→`attr`). The README proved (definitively, even on the
official `bioconductor_docker:RELEASE_3_20`) that per-package pins are whack-a-mole and that the only real
fix is a **date-pinned base image** (or a Bioc 3.21/3.22 bump). `CVXR` is *not* in any `.bm_deps` (it is a
transitive dep of ANCOMBC) and pinning it here would repeat the futile chase. Defer to the same date-pinned
base remediation tracked for the miaverse.

### hicool/main.nf — `Matrix.so: undefined symbol: NO_REFERENCES` (R-core ABI mismatch)
`NO_REFERENCES` is an R-internal macro added in **R 4.4**. A `Matrix.so` referencing it but failing to load
means the runtime-installed `Matrix` was built against a different R than the loader R (the `/rlib/` path is a
runtime-installed lib in the harness environment; this entry is `fixture_failed`, `image: None`). Not a
`.bm_deps` problem — `Matrix` is a base-recommended package and a transitive dep of HiCExperiment/HiCool. Fix
is an internally-consistent base where R and the recommended `Matrix` match; defer to the base-rebuild task.

### clumsid (2 workflows) — `dbscan.so: GLIBC_2.38 not found` (system libc mismatch)
The runtime-installed `dbscan` binary was linked against glibc 2.38, newer than the container's libc. Pure
system-ABI mismatch (`fixture_failed`, `image: None`, `/rlib/dbscan`). `dbscan` is a transitive dep of CluMSID;
adding it to `.bm_deps` cannot change which glibc the binary needs. Fix is a base/runtime with glibc ≥ 2.38
(or installing `dbscan` from source against the container's libc). Defer.

---

## Verification (static)

- chromdraw: `grep packageVersion chromdraw/bed_file_karyotype.nf` → `packageVersion("chromDraw")` ✓ (matches
  `library(chromDraw)` and the biocontainers package name `chromDraw`).
- qsutils: `packageVersion("QSutils")` ✓ (matches `library(QSutils)` and the `bioconductor-qsutils` package `QSutils`).
- iBBiG/biclust: present in `deps/transcriptomics.txt` ✓ (were absent before). Both noarch → bake cleanly; no
  compile risk.
- No `.bm_deps <- c(...)` line was edited: every "no package called X" target already listed X with correct
  case, so the root cause was image-bake/routing or a `packageVersion()` typo, not a missing list entry.
  Editing the list to "add the missing package" would have been a false fix.

## What was NOT done and why
- No CVXR / Matrix / dbscan / rbiom-style version pins added — the README proves that class is upstream and
  pin-chasing does not converge. Tracked under the existing date-pinned-base infra task.
- No `:3.20-deps` rebuild executed here (spot-box infra action per README; out of scope for a code branch).
  The deps-file change (iBBiG/biclust) is staged so the next rebuild bakes it.
