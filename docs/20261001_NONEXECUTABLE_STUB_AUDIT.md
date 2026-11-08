# Non-Executable Stub Workflow Audit

**Date:** 2026-10-01
**Scope:** `backend/biomni_workflows/**`, `backend/nf-core-modules/**`, and the full workflow catalog in `backend/database/galaxy_ai_tools.db` (`workflows` table, 4,209 rows).
**Mode:** READ-ONLY survey. Nothing was changed. AWS was queried read-only (`aws ecr describe-images --region us-west-2`) and Docker Hub via anonymous tag-manifest GETs.
**Goal:** Find workflows that are *registered + routable* (appear executable to users) but *cannot actually run* or *fabricate results* — the "stub" classes — and recommend a disposition per class.

---

## TL;DR — the stub classes found

| # | Class | How it misleads | Confirmed count | Est. affected |
|---|-------|-----------------|-----------------|---------------|
| C1 | **Missing backing `.nf` file** — DB `nf-core/<name>` rows whose `filename` points at a file that does not exist on disk, no `docker_image`, `executable=1` | Routable + "executable", but there is no local pipeline to run and no container | **210** (executable=1, file missing) | 210 |
| C2 | **Nonexistent container image** — DB `docker_image` references an ECR repo/tag that 404s, or an nf-core monolithic image tag that was never published | Pull fails at run time | **6** ECR/placeholder + **5** nf-core monolithic-image refs | ~11 |
| C3 | **Invented-tool-flag param façade** — `biomni_workflows/nfcore/*/main.nf` calling real tools with flags that don't exist, no `input:`/channel wiring, 0 real outputs | Looks like a real pipeline card; cannot execute; flags are fiction | **2 confirmed** (chipseq already flagged; atacseq live) of 14 façade files | ~2–14 |
| C4 | **Honest-failing stub** — process body is an unconditional `sys.exit(1)` with a "not implemented / refusing to fabricate" message | Registered + routable; always errors (by design, honestly) | **11 confirmed** (sampled set) | ~15–30 |
| C5 | **Fabricated-output stub** — exits 0 and writes hardcoded/synthetic result tables presented as real science | Worst case: looks like a *successful* run with fake numbers | **1 confirmed** (`lnp_formulation_optimization`) | a few |
| C6 | **Bioconductor single-package wrapper, runtime-broken** — real image exists but the generated R harness fails (R/Bioc version skew, missing fixture data, dead synthetic fixtures) | Routable; fails at run with an R traceback, not a clean "unsupported" | **584 exec_error + 258 fixture_failed** among 2,687 bioc wrappers | ~800+ (see §Estimate) |

**Overall catalog health (from `real_exec_status`):**
`ok` 690 · `ok_warnings` 402 · `exec_error` 798 · `fixture_failed` 277 · `runnable_assumed` 109 · `timeout` 18 · `ran_empty_output` 3 · `skip_input_type` 36 · **never run (NULL) 1,876**.

So **~45% of the catalog has never been executed at all** (NULL status), and **~26% has a recorded failure** (`exec_error` + `fixture_failed`). The stub classes below are the *mechanistic* reasons behind the failing/never-run slices.

---

## Sampling method & honesty note

This is **NOT exhaustive**. What *was* exhaustive vs. sampled:

- **Exhaustive (whole catalog):** DB `real_exec_status` / `executable` / `docker_image` tallies; existence check of every `nf-core/<name>` backing file on disk (230 rows checked); distinct-image extraction.
- **Exhaustive (AWS):** every distinct `399683337364.dkr.ecr…/biomate/*` repo+tag referenced in the DB was checked with `aws ecr describe-images`; every distinct `nfcore/<pipeline>:tag` checked against Docker Hub.
- **Sampled (read in full):** 47 `.nf` files that matched honest-fail/placeholder greps were read and classified (C4/C5). Invented-flag scan (C3) was pattern-based across all `.nf` + full read of the 14 `nfcore/*` façade files, but flag fabrication was *spot-checked*, not verified flag-by-flag for every tool invocation in the catalog.
- **Not verified:** I did not pull-and-run any container, did not execute any workflow, and did not verify every single bioc wrapper's R harness. The C6 count is a *status-field* count, not a per-file root-cause confirmation.

Where I give an "Est. affected" I state the basis inline.

---

## C1 — Missing backing `.nf` file (nf-core name registry) — **210 rows, highest-priority**

**Evidence.** The DB holds ~230 rows named `nf-core/<pipeline>` (ids 12669–12798 plus 1491–1497) whose `filename` is `nfcore/<pipeline>/main.nf`. On disk, **only 13 of those files exist** (`biomni_workflows/nfcore/`): `rnaseq, chipseq, sarek, methylseq, diaproteomics, proteomicslfq, differentialabundance, mag, atacseq, ampliseq, drop, scrnaseq, raredisease, fetchngs` (14 dirs, one of which — `geo_scrna_pseudobulk` — is not in the `nf-core/` name set). **217 backing files are missing; 210 of those rows are `executable=1` with no `docker_image`.**

The stored `workflow_json` for these rows is the **real upstream nf-core `main.nf` entrypoint** (e.g. `nf-core/abotyper`, id 12669, 4,519 chars) — but it is just the orchestration shell that `include {...}`s subworkflows that are **not bundled** in this repo, references no local file, and has no container. A user routed to `nf-core/abotyper` gets an "executable" card backed by nothing runnable locally.

**Representative rows (all `executable=1`, no docker_image, file missing):**
`nf-core/abotyper, airrflow, alleleexpression, bacass, bactmap, bamtofastq, cageseq, callingcards, cellpainting, circdna, circrna, clipseq, coproid, crisprseq, cutandrun, demultiplex, denovotranscript, drugresponseeval, dualrnaseq, epitopeprediction, funcscan, gwas, hic, hicar, hlatyping, isoseq, mhcquant, nanoseq, oncoanalyser, pangenome, proteinfold, riboseq, rnafusion, rnasplice, rnavar, smrnaseq, taxprofiler, viralrecon …` (210 total).

**Domain spread:** these span genomics, transcriptomics, epigenomics, proteomics, immunology, metagenomics, variant_calling — effectively the entire "nf-core coverage" claim.

**Disposition — point-at-real-pipeline (bulk).** These are *real, well-supported* nf-core pipelines; the gap is that BioMate does not bundle them. Two acceptable fixes:
1. **Wire execution to the upstream pipeline** (`nextflow run nf-core/<name> -r <rev> -profile …`) with the per-module biocontainers nf-core already ships — then the registry entry becomes genuinely executable. **Preferred** (matches "BioMate is the execution engine").
2. If not wired yet, **set `executable=0`** (as was done for `nf-core/eager, genephylo, hackathon, mnaseseq, moleculardynamics, testpipeline, spatialxe` — 7 already flagged) so routing deprioritizes and the UI doesn't present a Run button that can't work.

Do **not** deprecate — the pipelines are legitimate; only the local backing is missing.

---

## C2 — Nonexistent container image — **~11 rows**

Verified against ECR (`aws ecr describe-images --region us-west-2`) and Docker Hub.

### C2a — ECR repo/tag does not exist
| Workflow | Domain | `docker_image` (DB) | ECR result | Note |
|---|---|---|---|---|
| `gears_perturbation_prediction_gpu` | drug_discovery | `…/biomate/virtual-cell-gpu:1.0` | **RepositoryNotFoundException** | but a real repo `biomate/gears-perturbation-prediction-gpu-nf` **exists** → DB image is stale |
| `transcriptformer_cell_state_gpu` | drug_discovery | `…/biomate/virtual-cell-gpu:1.0` | **RepositoryNotFoundException** | real repo `biomate/transcriptformer-cell-state-gpu-nf` exists → stale |
| `cpa_drug_combination_synergy_gpu` | drug_discovery | `…/biomate/virtual-cell-gpu:1.0` | **RepositoryNotFoundException** | real repo `biomate/cpa-drug-combination-synergy-gpu-nf` exists → stale |
| `AMBER pmemd GPU Molecular Dynamics` | drug_discovery | `399683337364…/amber24-cuda:latest` | **RepositoryNotFoundException** | real repo `biomate/ambertools-gromacs-nf` / `biomate/gromacs-cuda` exist → stale/misrouted |
| `Cryo-EM Conformational Heterogeneity (cryoDRGN)` | cryo_em | `…/biomate/cryodrgn-nf:latest` | **RepositoryNotFoundException** | real repo `biomate/cryo-heterogeneity-nf` exists (tags v1.0.2, latest) → stale |

**Disposition — fix (DB image pointer).** All five point at a dead image *but a correct image for the same science exists in ECR*. Repoint `docker_image` to the real repo/tag; verify the `.nf` `container` directive matches. These are **not** deprecate candidates — the capability exists, the DB pointer is wrong.

### C2b — nf-core monolithic image tag never published
Docker Hub returned **404** for the single-pipeline image tags recorded on the 1491–1497 façade rows:
`nfcore/chipseq:2.0.0`, `nfcore/rnaseq:3.14.0`, `nfcore/sarek:3.4.0`, `nfcore/methylseq:2.6.0`, `nfcore/differentialabundance:1.5.0` → **404**;
`nfcore/proteomicslfq:1.0.0`, `nfcore/diaproteomics:1.2.4` → 200 (these two still exist).

Modern nf-core pipelines (chipseq ≥1.x, rnaseq ≥3.x, sarek ≥3.x) **stopped shipping a monolithic `nfcore/<pipeline>` image** and use per-module biocontainers. So these `docker_image` values are *vestigial and wrong* for 5 of 7.

**Disposition — fix / clarify.** If these rows are ever wired to execute, the `docker_image` must be dropped (nf-core resolves containers per-process) rather than pointing at a 404 tag. Lower priority than C1/C2a because these 7 are the param-façade rows (see C3) — chipseq is already `executable=0`.

---

## C3 — Invented-tool-flag param façade — `biomni_workflows/nfcore/*/main.nf`

These 14 files are **intentional "parameter-surface" stubs** (CLAUDE.md explicitly blesses editing `biomni_workflows/nfcore/` stubs for param extraction). They exist to drive the param strip in the UI, not to run. All 14 have `inputs=0` (no `input:` blocks, no channel wiring) and 5–7 processes each.

The *problem* is only when (a) the invented flags or non-existent helper scripts leak into the chat/UI as if real, or (b) the DB row is `executable=1` so the UI shows a Run button.

**Confirmed invented flags:**
- `nfcore/chipseq/main.nf` — `bwa mem --dedup` (no such flag), `bwa mem --fragment-size` (no such flag), `trim_galore/macs2/multiqc --outdir` misuse, `chipseeker_annotate.R` (non-existent helper), `macs2 callpeak` with no `-t` treatment. **Already remediated this session:** file header now carries `⚠️ NON-EXECUTABLE PARAMETER-SURFACE STUB` (flagged 2026-10-01) and DB id 1492 is `executable=0, real_exec_status=exec_error, workflow_correctness_verdict=major_issues`. ✅
- `nfcore/atacseq/main.nf` — line 50 `--fragment-size` passed to the aligner (invented, same family as chipseq). **Still `executable=1` (id 12673).** Not yet flagged.

**Disposition — flag-non-executable-in-DB + annotate file (per façade).** Apply the chipseq treatment to the rest of the 14 façade files: add the `⚠️ PARAMETER-SURFACE STUB` header, set `executable=0`, and point users at the validated real subworkflows (chipseq already points at `nextflow_nfcore/subworkflows/bioconductor/chipseeker/*`). The *param surface itself is fine to keep* for extraction; it just must not be presented as runnable. Do **not** "fix" the invented flags into real ones — that would imply the façade executes, which it structurally cannot (no inputs/wiring).

---

## C4 — Honest-failing stubs (`sys.exit(1)` "refusing to fabricate")

A deliberate, *good* pattern: a subworkflow that previously fabricated results via RNG was converted to an **unconditional honest failure** with a message naming the missing real tool. These are non-executable *by design* and do **not** fabricate — but they are still registered/routable, so a user can select them and get a hard error.

**Confirmed (11 files, read in full):**

| Workflow | Domain | Missing real tool it names | Evidence |
|---|---|---|---|
| `drug_discovery/ich_s7a_safety_pharmacology` | drug_discovery | — (safety pharmacology) | "not implemented against real measurement/tool … Refusing to emit fabricated results." `sys.exit(1)` |
| `drug_discovery/sirna_offtarget_analysis` | drug_discovery | sequence off-target tool | "Refusing to emit fabricated off-target hits …" `sys.exit(1)` |
| `drug_discovery/bispecific_antibody_design` | drug_discovery | structure/biophysics tools | "Refusing to emit fabricated CDR sequences …" `sys.exit(1)` |
| `immunology/isolate_purify_immune_cells` | immunology | wet-lab (no compute equiv) | "previous implementation fabricated these numbers via RNG. Refusing…" `sys.exit(1)` |
| `immunology/analyze_atac_seq_differential_accessibility` | immunology | macs2 (real code present but **unreachable** — params default to `SIMULATE`) | `if treatment_bam == 'SIMULATE': … sys.exit(1)` — stock run always exits 1 |
| `pharmacology/biomarker_patient_enrichment` | pharmacology | real cohort | "fabricated patient responses … via RNG. Refusing…" `sys.exit(1)` |
| `biochemistry/analyze_enzyme_kinetics_assay` | biochemistry | real assay data (scipy fit is dead code below exit) | "refusing to fabricate observed kinetics data." `sys.exit(1)` |
| `single_cell/parse_split_seq_scrna` | single_cell | parsetools / STARsolo | "stub with no real implementation … Refusing…" `sys.exit(1)` |
| `single_cell/cite_seq_preprocessing` | single_cell | CITE-seq-Count / Seurat WNN | "stub with no real implementation … Refusing…" `sys.exit(1)` |
| `single_cell/bd_rhapsody_scrna` | single_cell | BD Rhapsody pipeline | "stub with no real implementation … Refusing…" `sys.exit(1)` |
| `single_cell/merfish_spatial_analysis` | single_cell | Cellpose / SpatialDE | "stub with no real implementation … Refusing…" `sys.exit(1)` |
| `bioengineering/perform_crispr_cas9_genome_editing` | bioengineering | CRISPResso2 | "stub with no real implementation … Refusing…" `sys.exit(1)` |
| `microbiology/enumerate_bacterial_cfu_by_serial_dilution` | microbiology | wet-lab plate count | "fabricated colony counts with a Poisson RNG. Refusing…" `sys.exit(1)` |

(13 rows listed; the "11 confirmed" headline counts the strict always-exit cases — `analyze_atac_seq_differential_accessibility` exits only under default `SIMULATE`, and some have dead downstream code, but all honestly fail on a stock run.)

**Disposition — flag-non-executable-in-DB (preferred) or point-at-real-pipeline.** These are honest, so they are low-harm, but they should be `executable=0` so routing never prefers them, and the chat should say "requires <named tool>; not yet wired" rather than surfacing a raw `sys.exit(1)` traceback. The best long-term fix is to **wire the named real tool** (e.g. CRISPResso2, macs2, CITE-seq-Count) and promote them to real workflows. Do **not** revert them to RNG fabrication.

---

## C5 — Fabricated-output stub (exits 0 with hardcoded science) — **worst class**

**`drug_discovery/lnp_formulation_optimization/main.nf`** — exits **0** and writes `formulation_predictions.csv`, `recommended_formulation.json`, `qc_metrics.json` whose headline content is **hardcoded lookup dicts and invented empirical formulas**, not any real formulation tool:
- tissue targeting from `base_scores = {'liver': {'mRNA': 0.85, …}}` (hardcoded);
- particle size / encapsulation-efficiency from invented formulas `size_base = 80 + (il_mol_pct-50)*0.5 …`.

RDKit *is* called for real MW/logP/pKa-proxy descriptors, so it is not purely dummy — but the deliverable (the "recommended formulation" and EE/size numbers) is synthetic and presented as a successful result. This is the dangerous case: a user sees a green "completed" run with fabricated recommendations.

**Disposition — deprecate or honest-fail convert.** Either convert to the C4 honest-fail pattern ("LNP formulation optimization requires a real formulation model; refusing to emit fabricated EE/size") or wire a real model. Must not stay as a silent exit-0 fabrication. **Flag `executable=0` immediately** pending that.

> Note: two C4/C5-adjacent files have *honestly-disclosed* fallbacks and are **not** stubs: `genomics/alphagenome_track_prediction` (mechanistic `structural_proxy` labeled "NOT AlphaGenome or Enformer" in output) and `pharmacology/qsar_rf_model` (`mock_random` featurizer labeled in output if RDKit import fails). Disclosure-in-output ≠ fabrication-as-success; leave as-is.

---

## C6 — Bioconductor single-package wrappers, runtime-broken — **largest by volume**

2,687 workflows use the `…/biomate/bioc-domain-<domain>:3.20` images (the images **do exist** in ECR — verified: tags `3.20`, `3.20-slim`, `3.20-deps` present for transcriptomics/general/genomics/metabolomics/spatial). These are auto-generated single-Bioconductor-package demo wrappers (`alabaster_*`, `Biostrings`, `GenomicRanges`, `mzR`, `SingleCellExperiment`, etc.). They are not "stubs" in the invented sense, but a large fraction **fail at runtime**, so they mislead the same way (routable, looks executable, errors on run):

Among the 2,687: `exec_error` 584 · `fixture_failed` 258 · never-run 988 · `ok` 453 · `ok_warnings` 323.

**Dominant failure signatures (from `real_exec_err`):**
- **R/Bioconductor version skew — 58 rows:** `Error: Bioconductor version '3.22' requires R version '4.5'` — the image is tagged `3.20` but the generated R harness pins Bioc 3.22. This is a single systemic image/pin mismatch, not 58 unique bugs.
- **Missing fixture/input data — many:** `cannot open the connection`, `Missing required input files in the working directory: ctcf.bam, gfp.bam`, header-only reads — the generated fixtures were never staged.
- **Dead synthetic fixtures / package-load failures:** `package 'sm' required by 'vioplot' could not be found`, `no package called 'Rfastp'`, `'\.' is an unrecognized escape` (R string-escaping bug in generated code).
- **Transient infra (NOT a stub):** `failed to Lchown /var/lib/containerd/…`, layer-extract/`Pull complete` lines — these are containerd/disk hiccups on the test runner, not workflow defects. Exclude from the stub count.

**Disposition — fix systemically, not per-row.** The 58 R-version failures are one fix (align the image R/Bioc version with the harness pin, or rebuild `bioc-domain-*:3.22`). The fixture-missing failures are a generator fix (stage demo inputs). `runnable_assumed` rows (109, mostly genomics) were manually flagged runnable despite a test-env data limitation — audit a sample before trusting. Recommend a `real_exec_status`-driven triage pass rather than touching 800 files.

---

## Estimate: how many of ~4,209 are affected?

**Method:** combine the exhaustive DB status tally with the exhaustive disk/ECR checks, then bound the file-read-sampled classes (C4/C5).

| Bucket | Count | Confidence |
|---|---|---|
| C1 missing backing file, executable=1 | **210** | exact (disk check) |
| C2 nonexistent image (ECR + nf-core 404) | **~11** | exact (AWS/DockerHub) |
| C3 invented-flag façade (of 14) | **2 confirmed**, up to 14 | 2 exact, rest by pattern |
| C4 honest-fail stubs | **11 confirmed**; likely **~20–30** total | sampled (47 grep-matched files read) |
| C5 fabricated-output | **1 confirmed**; likely **a handful** | sampled |
| C6 bioc wrappers with recorded failure | **584 exec_error + 258 fixture_failed = 842** (minus ~tens of transient-infra rows) | exact status tally, root-cause sampled |

**Lower bound (clearly stub/broken, de-duplicated):** ~210 (C1) + 11 (C2) + ~14 (C3) + ~25 (C4) + ~5 (C5) ≈ **265 structural stubs** (~6.3% of the catalog) — these cannot run as registered regardless of data.

**Upper bound incl. runtime-broken bioc wrappers (C6):** add ~842 recorded failures → **~1,100 (~26%)** are currently non-executable or failing. On top of that, **1,876 rows (45%) have never been executed**, so their true runnability is *unknown* — the realistic "would mislead a user today" figure is plausibly **30–50%** of the catalog, dominated by C6 and the never-run slice.

**Caveat:** C6 and the never-run slice are *status-field* inferences; I did not run them. The 265 structural-stub lower bound is the high-confidence number to act on first.

---

## Recommended cleanup order

1. **C1 (210 rows) — biggest credibility risk.** Either wire upstream nf-core execution (preferred) or set `executable=0`. Follow the precedent already set for `eager/genephylo/hackathon/mnaseseq/moleculardynamics/testpipeline/spatialxe`.
2. **C5 (`lnp_formulation_optimization`) — set `executable=0` now.** It fabricates a "successful" result; highest per-row harm.
3. **C2a (5 stale ECR pointers) — repoint `docker_image`** to the real repos that already exist (`gears-…-nf`, `transcriptformer-…-nf`, `cpa-…-nf`, `gromacs-cuda`, `cryo-heterogeneity-nf`). Pure DB fix, restores real capability.
4. **C3 (13 remaining façade files) — apply the chipseq treatment:** header warning + `executable=0` + pointer to the validated real subworkflows. Fix atacseq's `--fragment-size` note first.
5. **C4 (honest-fail stubs) — set `executable=0`** and improve the chat message; schedule the named real tools (CRISPResso2, macs2, CITE-seq-Count, Cellpose/SpatialDE) for real wiring.
6. **C6 — one systemic image/pin fix** for the 58 R-version failures, one generator fix for missing fixtures; then a `runnable_assumed` audit. Do not hand-edit 800 wrappers.

## What is NOT a stub (explicitly cleared)

- `bioc-domain-*:3.20` images — **exist** in ECR; failures are R-version/fixture bugs (C6), not missing images.
- `schrodinger2024, moe2024, biomni-lite, biomate-nextflow-base, biomni-tools, biomni-pharma, r-pharma, genomics-germline, protein-dynamics-nf, cryo-heterogeneity-nf, af3-nf, biomni-structure-to-drug, ai-tools/{boltz,chai1,drugclip,profam,protrek,scfv-pmpnn,state,syncraft}` — all **exist** in ECR with the referenced tags.
- `nfcore/proteomicslfq:1.0.0`, `nfcore/diaproteomics:1.2.4` — still on Docker Hub (200).
- Legitimate SIMULATE workflows (`biostatistics/virtual_trial_gate3`, `qsp_virtual_population`) — consume real user design specs, label output SIMULATED, fail-fast if spec missing. Real, not stubs.
- Disclosed fallbacks (`alphagenome_track_prediction` structural_proxy, `qsar_rf_model` mock_random) — labeled in output, not fabrication-as-success.
- `Lchown`/containerd `real_exec_err` rows — transient test-runner infra, not workflow defects.
