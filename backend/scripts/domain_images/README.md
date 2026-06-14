# Bioconductor domain-image dependency builds (`:3.20-deps`)

Bakes each domain's software dependencies into `bioc-domain-<domain>:3.20-deps` (base `:3.20`
untouched) so workflow runs don't pay a per-run `install.packages`. Run on a spot box (native
amd64), push to ECR.

## Why `BiocManager`, not `install.packages`
The first build (2026-06-12) used `install.packages(repos=bioc-urls)`, which does **not**
resolve Bioconductor dependency versions to the image's Bioc release. That pulled the *latest*
CRAN deps and broke:
- `mia`/`iSEEtree`/`miaViz` — newer `rbiom` dropped the `unifrac` export → installed but won't load
- `metaMS` — `xcms` 2.x source vs newer R headers (`R_NO_REMAP`) → compile fail

`Dockerfile.tmpl` now uses `BiocManager::install(update=FALSE, ask=FALSE)` (Bioc-release-pinned)
and reports both `STILL MISSING` and `INSTALLED BUT WONT LOAD`.

## Inputs
- `Dockerfile.tmpl` — `__DOMAIN__` is substituted per domain.
- `deps/<domain>.txt` — per-domain package list (the workflow packages + their deps).
  `combi` (metagenomics) and `immunoClust` (imaging) were added after the first build flagged them missing.

## Run (per the documented guards — do NOT skip)
1. Launch ONE spot box ≤4xlarge in us-west-2a (NEVER on-demand / 24xlarge). Use stock Ubuntu
   22.04 (the Batch worker AMI has no ec2-instance-connect → SSH unreachable).
2. ECR is a VPC interface-endpoint: the builder SG must be allowed inbound 443 on the endpoint
   SG (`sg-0de9af2d4437a8c90`) or reuse `sg-0a70bb26e47332c55`, else `ecr get-login-password` hangs.
3. Re-inject the ec2-instance-connect key before EVERY ssh/scp (60 s TTL).
4. Run the build under `systemd-run`/nohup so it survives SSH drops.
5. For each domain: `sed s/__DOMAIN__/$dom/ Dockerfile.tmpl`, `docker build -t .../bioc-domain-$dom:3.20-deps .`,
   sanity-check (`requireNamespace` on the previously-missing pkgs must be TRUE), `docker push`.
6. **Terminate the spot box** when pushes complete (cost guard).

`build_bioc_domain_deps_images.sh` is the reference orchestration (its `rf_00..rf_03` instance
IDs/IPs are stale — launch fresh boxes and update them).

## Status (2026-06-12 first build)
- **imaging:3.20-deps** — clean win, all packages load.
- **metabolomics / metagenomics :3.20-deps** — improved; `metaMS` and `mia`/`iSEEtree` still
  failed under `install.packages` → re-run with this `BiocManager` template to recover them.

## 2026-06-13 — BiocManager rebuild result: still insufficient for mia/metaMS
Rebuilt metagenomics with the BiocManager template; `mia`/`iSEEtree`/`miaViz` **still won't load**.
Root cause is deeper than the install method: the BASE `:3.20` image already carries a **too-new
`rbiom`** (CRAN package — BiocManager does NOT pin it to a Bioc release) that dropped the
`unifrac` export, and `BiocManager::install(update=FALSE)` won't downgrade it. So `mia` (built
against old `rbiom`) fails at load.

**Precise fix the team needs (per-package version pin, before installing mia):**
```r
install.packages("remotes")
remotes::install_version("rbiom", version = "<last version exporting unifrac>")  # then rebuild mia/miaViz
```
For `metaMS`: its `xcms` dep fails to COMPILE from source (R_NO_REMAP vs xcms 2.x). Install the
**xcms binary** from the Bioc container-binaries repo (or pin a compatible xcms), not source.

Until those pins are added, `mia`/`iSEEtree`/`miaViz`/`metaMS` remain non-runnable; their
workflows keep the runtime self-install fallback (which hits the same conflict). imaging is the
clean win and is already good.

## 2026-06-13 (cont.) — root cause is a CASCADE of CRAN version skews (definitive)
Verified locally without spot: pinning `rbiom` 1.0.3 DOES restore `unifrac`, but `mia` then fails
with `object 'attr' is not exported by 'namespace:xfun'` — i.e. ANOTHER CRAN package (`xfun`) is
too new. The base `:3.20` image was built with CRAN packages **newer than what the Bioc 3.20
packages were compiled against**, so it's a cascade (rbiom → xfun → …), not a single pin.

**Correct fix (base-image level, NOT per-package pins):** rebuild the domain base images so all
CRAN deps are version-matched to the Bioc 3.20 release date. Either:
- `FROM bioconductor/bioconductor_docker:RELEASE_3_20` (CRAN+Bioc already snapshot-consistent), or
- set a dated CRAN snapshot before installing, e.g.
  `options(repos = c(CRAN = "https://packagemanager.posit.co/cran/2024-10-30"))`
  (use the Posit Package Manager snapshot nearest the Bioc 3.20 release) so `install.packages`/
  `BiocManager::install` pull compatible CRAN versions.

Chasing individual pins (rbiom, then xfun, then the next) is whack-a-mole — fix the snapshot once.
This affects metagenomics (mia/iSEEtree/miaViz) and metabolomics (metaMS/xcms). imaging happened
to have no such skew → clean.

## 2026-06-13 (cont.) — snapshot fix VERIFIED + baked into Dockerfile.tmpl
Verified locally in the metagenomics base image: with `options(repos=c(CRAN="…/cran/2024-10-30"))`
and `install.packages(c("rbiom","xfun"))` from the snapshot, `loadNamespace("mia")` SUCCEEDS
(rbiom 1.0.3, xfun 0.48). `Dockerfile.tmpl` now applies this snapshot + offender-downgrade before
BiocManager. A rebuild with this template should recover mia/iSEEtree/miaViz (metagenomics).
metaMS/xcms (metabolomics) is a separate SOURCE-COMPILE failure — the snapshot may supply an xcms
binary (Posit PPM has linux binaries); verify `metaMS` load on the built image, and if it still
fails, the base image needs rebuilding FROM bioconductor/bioconductor_docker:RELEASE_3_20.

## 2026-06-13 (final) — incremental patching CANNOT fix it; base must be rebuilt
Built metagenomics with the snapshot+downgrade template and verified on the PUSHED image:
rbiom 1.0.3 + xfun 0.48 are correctly baked, but `mia` STILL fails — now with
`namespace 'xfun' 0.48 is being loaded, but >= 0.52 is required`. The conflict is
**bidirectional**: `mia` (base, built against old deps) needs OLD xfun, while the
`BiocManager::install` of the other deps.txt packages pulls packages that need xfun >= 0.52.
No single CRAN snapshot or per-package pin can satisfy both — the base `:3.20` image is an
internally-inconsistent mix of packages built against different dates.

**Conclusion (definitive): the domain base images must be REBUILT from a consistent base** —
`FROM bioconductor/bioconductor_docker:RELEASE_3_20` (where Bioc + all CRAN deps are
snapshot-consistent), then install the domain deps on top. Patching the existing `:3.20`
images (snapshots, downgrades, BiocManager) is whack-a-mole and provably can't converge.

The pushed `metagenomics:3.20-deps` has `mia` still broken — but **no regression** (the prior
`:3.20-deps` was equally broken for mia; everything else that loaded still loads). Box
terminated, no orphans. This is the honest end of the incremental track; the base rebuild is
the real fix and is a deliberate infra task.
