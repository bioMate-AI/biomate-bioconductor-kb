# BioMate vendoring notice — nf_encyclopedia

**Vendored from:** https://github.com/mriffle/nf-encyclopedia (upstream by Talus Bio / mriffle)
**Upstream commit:** `ac2f91227864adfe3258512035b54947b632a002`
**License:** Apache-2.0 (see `LICENSE`) — wrapper. The wrapped tool **EncyclopeDIA** (Searle lab) is also **Apache-2.0**. Both are license-clean for BioMate commercial hosting.
**Why vendored:** license-clean DIA search capability (Option B) — DIA-NN/MSFragger/Spectronaut are license-restricted for commercial hosting; see `docs/20260908_PROTEOMICS_DDA_SEARCH_CAPABILITY.md` and the `reference_proteomics_engine_licenses` memory.

## Local trims (removed from the upstream tree to keep the vendor lean)
`.github/` (CI), `docs/static/` + `static/` (images), `tests/data/` (binary mzML/dlib/fasta blobs), `mkdocs.yml`. Runtime code is intact (`main.nf`, `subworkflows/`, `modules/`, `lib/TalusTemplate.groovy`, `conf/`, `bin/`, `environment.yml`, `Dockerfile`, `assets/`).

## Containers
- EncyclopeDIA/quant/library steps: `ghcr.io/talusbio/nf-encyclopedia:latest` (Apache-2.0 stack).
- **msconvert (RAW→mzML): `chambm/pwiz-skyline-i-agree-to-the-vendor-licenses`** — ProteoWizard bundling **instrument-vendor DLLs** under a "you agree to the vendor licenses" term. **BioMate default: accept mzML input and skip msconvert**, so we do not host the vendor-DLL conversion. Only enable the msconvert path where the vendor-license agreement is acceptable.

## Integration status
- Registration is a dev-only DB step (workflow DB is gitignored; local is a stub): `filename = "nfcore/nf_encyclopedia/main.nf"`, `format=nextflow`, `domain=proteomics`, `source=nfcore`.
- Batch validation is gated (costs) — not yet run. First run validates the container pulls + the chromatogram-library / per-run quant fan-out on real DIA mzML.
- Cohort fan-out (library-once → per-run quant → aggregate) is already the pipeline's native structure — matches the DIA-cohort "days→hours" design in `docs/20260908_DIANN_COHORT_SCALE_DIAGNOSIS.md`.
