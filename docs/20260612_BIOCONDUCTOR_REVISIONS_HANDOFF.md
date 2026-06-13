# Bioconductor Workflows — Session Revisions (Team Handoff)

**Date:** 2026-06-12
**Branches (pushed to origin):**
- `bioc/lessons-transfer` — execution/routing/UX production fixes
- `bioc/per-workflow-analysis` — per-workflow data/code fixes + chains + routing index
- `bioc/v2-qc-audit-panel` — `bioc/lessons-transfer` merged in (`a84d0fa30f`)

This document lists every change, where it lives, why, how it was verified, and what's open.
Audience: the team taking this forward.

---

## 1. Execution-layer fixes (branch `bioc/lessons-transfer`, merged to `bioc/v2-qc-audit-panel`)

| Item | Commit | Change | Verified |
|---|---|---|---|
| **versions.yml heredoc** | `0d5dae98f` | A bash `cat <<-END_VERSIONS` heredoc sat inside the `#!/usr/bin/env Rscript` block → R evaluated it → `object 'END_VERSIONS' not found`. Converted to `writeLines()` in **687** `.nf`. Stub tests never caught it (latent). Generators (`regenerate_thin_bioc_wrappers.py`, `regenerate_broken_bioc_llm.py`) now call `fix_bioc_versions_heredoc.sanitize_text()` so it can't be reborn. | 7 originally-failing pkgs nextflow-parse clean |
| **B-2 input staging (P0)** | `ea9a58ba7` | Bioc subworkflows expose only a `take:`-bound `*_WORKFLOW` (no anonymous entry) → `-entry` can't bind the channel → **unrunnable**. `_build_bioc_entry_wrapper()` in `nextflow_executor.py` stages each user file under its declared `// Input:` base name and builds the entry wrapper (arity-aware). | Local nextflow E2E: phyloseq real data → 7 real outputs |
| **dep bootstrap** | `77fc11466` | **1,563 / 3,350** `.nf` called `library(pkg)` with no `# [biomate-deps]` self-install block → fatal when the container lacks the pkg. Inserted the canonical bootstrap declaring exactly each block's `library()` targets. | microbiome self-installs + advances past `library()` |
| **B-1 step markers** | `1c8d047c3` | Step UI was coarse: only 192/3,353 `.nf` had `# --- … ---` markers. Regenerated from the generator's authoritative in-body step comments → coverage **192 → 1,536**; also rebuilt 385 mangled `// Steps:` blocks. | dev fleet sweep 38/40 multi-step |
| **steps precedence** | `8869c5397` | `/api/nextflow/steps` let DB `step_metadata` win unconditionally, hiding the new markers when a row had collapsed to 1 coarse step. Now a degenerate ≤1-step DB row yields to the parser; curated multi-step DB still wins. | dev: microbiome/a4classif 1→5; deseq2 8 / phyloseq 7 unchanged |
| **B-4 routing prefers runnable** | `cfd542831` | `unified_workflow_search.py` ignored the DB exec-status columns. Added `_exec_quality_bonus` (±2.0 cap, null-safe, in-row fetch) so near-ties favor `real_exec_status` ok/ok_warnings; relevance stays dominant. | dev: runnable `deepsnv` elevated; `exec_error` drops out of top-5 |

**Deployed to dev** (`biomate-galaxy-dev`): the 2 Python files hot-patched into `/app/lib/galaxy/`,
2,380 changed `.nf` into `/app/biomni_workflows/`, gunicorn restarted, verified.

---

## 2. Per-workflow + data + infra fixes (branch `bioc/per-workflow-analysis`)

### 2a. Methodology (important)
Local **fixture-collection first** (`backend/scripts/pwa_fixture_contract_audit.py`, `pwa_fixture_error_capture.py`, `pwa_local_validation_batch.py` — no spot cost) showed the residual failures are dominantly **environment (incomplete domain images) + data (fixtures)**, NOT workflow code. Fix the data, not the workflow validation.

### 2b. Changes
| Item | Commit | Change |
|---|---|---|
| **fixture data fixes** | `6c196ad2e` | microbiome + dirichletmultinomial fixtures emit **real contract-conforming data** (named `taxon_id`/`sample` columns; real shipped `extdata/Twins.csv` instead of hallucinated `data("fit")`). |
| **biomformat code fixes** | `388eb455d` | 4 genuine code bugs (data-contract, hallucinated `biom_to_SummarizedExperiment`, missing SE library, ragged taxonomy). **Known-remaining:** a deep `as.data.frame(biom_obj)` quirk — not green. |
| **SE library** | `eb7bc47e4` | **378** workflows call `SummarizedExperiment()`/`assay()`/`colData()` without `library(SummarizedExperiment)`. Added the call + bm_deps entry. |
| **:3.20-deps repoint** | `58f8fffec` | **119** metagenomics/metabolomics/imaging workflows repointed to the rebuilt `:3.20-deps` images. |
| **sentence-transformers dep** | `ca2b847fa` | Declared the BGE dense-retrieval dependency in `pinned-requirements.txt` (was a local-only dependency → prod container never had it → silent lexical-only fallback). |
| **chain resolver** | `9e4a52b8e` | `resolve_workflow_name_to_path` now strips a leading `BIOC_` and matches the bare package name (chains referenced `BIOC_<PKG>` but workflows are indexed under bare names → 0 rows). |
| **chain cleanup + register** | `57e12c50dd` | Removed 6 non-workflow data-container/utility steps (SingleCellExperiment, GenomicRanges, ensembldb, uwot, MSstats) from the chain templates + rewired; **all 6 chains resolve 14/14 end-to-end**. Re-registered `_v2` chains into `workflow_chains`. |

### 2c. Domain-image rebuild (spot m5.4xlarge, $0.22, terminated)
Pushed `:3.20-deps` (base `:3.20` untouched) for metagenomics/metabolomics/imaging.
- **imaging = clean win** (all pkgs load: Cardinal, EBImage, flowCore, FuseSOM, matter…)
- metabolomics/metagenomics improved (phyloseq, scater, Spectra, QFeatures, FELLA load)
- **Genuine Bioc dep-hell remainders (need version pinning, NOT workflow bugs):**
  - `metaMS` ← `xcms` won't compile (R_NO_REMAP vs xcms 2.x source in Bioc 3.20)
  - `mia`/`iSEEtree`/`miaViz` ← newer `rbiom` dropped the `unifrac` export → load fails
  - `combi`/`immunoClust` were not in the deps lists → add + rebuild
- **Fix for the rebuild:** the build uses `install.packages(repos=bioc-urls)` which does NOT
  resolve Bioc deps version-matched — switch to `BiocManager::install()`. ECR is a VPC
  interface-endpoint: builder SG must be allowed inbound 443 on the endpoint SG
  (`sg-0de9af2d4437a8c90`) or reuse `sg-0a70bb26e47332c55`.

---

## 3. Routing index
- All **3,310** bioc workflows were already in the lexical FTS index (`workflows_fts`) — routable.
- BGE **dense** embeddings were incomplete (1,818/3,310). **Regenerated the full index locally → 3,310/3,310** (`galaxy_ai_workflow_embeddings.npz`, gitignored artifact, rebuild in ~67s via the snippet in `unified_workflow_search._build_workflow_embeddings`).
- **Dev had NO dense layer at all**: `sentence_transformers` not in the container + `.npz` never synced + a silent `try/except ImportError → _ST=None` fallback. To productionize: install `sentence-transformers` + BGE model in the container (now declared in requirements) and ship the `.npz`.

---

## 4. Public KB
`bioMate-AI/biomate-bioconductor-kb` README (`main`): added a **Domain | Packages** table for the top-100 packages (grouped by domain). Live.

---

## 5. Dev deployment status (env: `biomate-galaxy-dev` @ dev-public.biomate.ai — staging, NOT confirmed prod)
**DONE + verified on dev:**
- 687 heredoc `.nf` + 2,380 changed `.nf` + B-2 executor + B-4 ranker (hot-patched, gunicorn restarted)
- 6 `_v2` workflow chains upserted into `workflow_chains` (resolver + templates live) — all resolve 14/14 end-to-end on dev
- BGE embeddings `.npz` (4,005 vectors) synced; `sentence-transformers 5.1.2` + BGE model installed → **dense retrieval confirmed active** (was lexical-only before)

NOTE: the only app deployment found on `i-06696b0d91f4346e0` (tagged BioMate-Production) is the
**dev** stack at `dev-public.biomate.ai`. `biomate.ai` on that box is the static marketing site.
No separate prod app container was found. If a distinct production app exists on other infra,
these changes have NOT been promoted there.

## 6. Open items (for the team)
1. **Bioc dep-hell follow-up build** — `BiocManager::install`-based rebuild with `xcms`/`rbiom` version pins to recover `metaMS`/`mia`; add `combi`/`immunoClust` to the deps lists.
2. **Validation wave** — run `realrun_test_bioc_workflows.py` on a fresh spot box (native amd64) against the `:3.20-deps` images + corrected fixtures to measure the true executable-rate lift. Local emulation is too slow (40-min timeouts on heavy pkgs).
3. **biomformat** — the residual `as.data.frame(biom_obj)` serialization quirk is unsolved.
4. **Production promotion** — confirm where the customer-facing app is served and promote the above there (only the `dev` stack was updated this session).

---

## 7. Reproducible tooling added (`backend/scripts/`)
- `fix_bioc_versions_heredoc.py` — heredoc→writeLines transform + importable sanitizer
- `add_bioc_dep_bootstrap.py` — dep self-install bootstrap inserter
- `add_bioc_section_markers.py` — step-marker regeneration
- `pwa_fixture_contract_audit.py` / `pwa_fixture_error_capture.py` / `pwa_local_validation_batch.py` — local (no-spot) fixture/data diagnostics

---

## 8. Post-handoff updates (2026-06-13)

### Conflict-check items (from the other team's `20260612_HANDOFF_CONFLICT_CHECK.md`) — all resolved
1. **Stale embeddings on 4 workflows** — re-ran the full embed (4,005 vectors, current descriptions for deseq2/clusterprofiler/differentialabundance/+) and **re-synced the `.npz` to dev**. (no separate commit — `.npz` is a gitignored artifact; rebuild via `unified_workflow_search._build_workflow_embeddings`.)
2. **`BIOC_DMRcate` case-mismatch** — **confirmed safe (no fix needed):** `resolve_workflow_name_to_path` uses `lower(name)=lower(?)`, so `BIOC_DMRcate`/`BIOC_DMRCATE` both resolve to `dmrcate/main.nf`. (Their cross-check saw the verbatim name because `compose_chain` returns step names un-resolved; the resolution layer normalizes case.)
3. **Chain coexistence** (`6e8eec579d`) — the 6 `_v2` chains overlap 3 consensus/analog chains. `workflow_chains` has no `when_to_use` field, so sharpened the 3 overlapping **descriptions** (distinct entry point: downstream-from-count-matrix / single-method wrapper) + fixed the stale scrna description (named removed steps). Re-registered + re-synced to dev. The deeper chain-level differentiation remains the other team's deferred item.

### Domain-image build tooling persisted + dep resolution fixed (`cebc5dc4a`)
`backend/scripts/domain_images/` now holds the Dockerfile template, per-domain deps lists
(with `combi`/`immunoClust` added), build script, and README. **Root-cause fix:** the template
uses `BiocManager::install` (Bioc-release-pinned dep resolution) instead of `install.packages`
(which pulled latest CRAN deps → broke `mia` via `rbiom unifrac` and `metaMS` via `xcms` compile).

### Dep-hell follow-up rebuild — DONE, still insufficient (honest negative result)
Rebuilt metagenomics with BiocManager; `mia`/`iSEEtree`/`miaViz` **still FALSE**. The base image's
`rbiom` (CRAN, not Bioc-pinned) is too new and dropped `unifrac`; `BiocManager::install(update=FALSE)`
won't downgrade it, so `mia` still fails to load. NOT pushed (no improvement). Box terminated, no
orphans/SG-leftovers. **Real fix:** `remotes::install_version("rbiom", "<unifrac version>")` then
rebuild mia; install the `xcms` BINARY (not source) for metaMS. Details in
`backend/scripts/domain_images/README.md`.
