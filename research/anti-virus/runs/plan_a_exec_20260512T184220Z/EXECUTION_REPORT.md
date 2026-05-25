# Plan A in silico execution report

**Run directory:** `research/anti-virus/runs/plan_a_exec_20260512T184220Z/`  
**UTC timestamp (folder):** `20260512T184220Z`  
**Host notes:** Linux **arm64** (`linux 6.11.0-1016-nvidia`); Docker Engine 28.3.3; Nextflow on PATH (25.10.0 default; 24.10.1 used where noted).

Authentication for `POST /api/nextflow/execute` used `X-API-Key` from `backend/config/galaxy.yml` (`galaxy.bootstrap_admin_api_key`) loaded in the shell environment only — **not** written into this file.

---

## 1. Structures (Guo et al. / RCSB)

| Step | Command | Exit |
|------|---------|------|
| Create run tree + copy inputs | `mkdir -p …/structures …/epitope_inputs …/logs` and `cp` template `samplesheet.csv` + `plan_a_smoke_gp_fragment.fasta` into `epitope_inputs/` | 0 |
| Fetch CIFs | `bash research/anti-virus/scripts/fetch_guo_structures.sh /home/yzhang/biomate/research/anti-virus/runs/plan_a_exec_20260512T184220Z/structures` | **0** |

**Artifacts:** `structures/9P3I.cif`, `9P3Y.cif`, `9P3X.cif`, `9P3M.cif`, `9P3L.cif` (RCSB downloads).  
**Log:** `logs/fetch_guo_structures.log` (includes `EXIT:0`).

---

## 2. Epitope / MHC (nf-core/epitopeprediction)

### 2A. Direct Nextflow (`-profile docker`)

| Command | Exit | Failure summary |
|---------|------|-------------------|
| `nextflow run nf-core/epitopeprediction -r 2.0.0 -profile docker --input …/epitope_inputs/samplesheet.csv --outdir …/epitope_nfcore_out --genome GRCh37 --tools syfpeithi` | **1** | **Nextflow 25.10.0** fails at DSL parse: `Cannot invoke method optional() on null object` in `modules/local/peptide_prediction.nf` (~line 15). Log: `logs/nfcore_epitopeprediction.log`. |

### 2B. Direct Nextflow 24.x + docker (ARM vs amd64 images)

| Command | Exit | Failure summary |
|---------|------|-------------------|
| `NXF_VER=24.10.1 nextflow run nf-core/epitopeprediction -r 2.0.0 -profile docker … --genome_version GRCh37 --tools syfpeithi` | **1** | Pipelines starts; biocontainers are **linux/amd64**. Docker: `WARNING: The requested image's platform (linux/amd64) does not match the detected host platform (linux/arm64/v8)` then `exec /bin/bash: no such file or directory`. Log: `logs/nfcore_epitopeprediction_nf24.log`. |

### 2C. Direct Nextflow + conda (workaround for ARM)

| Command | Exit | Failure summary |
|---------|------|-------------------|
| First attempt: same with original `samplesheet.csv` (columns `sample,alleles,mhc_class,filename`) | **1** | `check_samplesheet.py`: header must be `sample,alleles,filename` for this pipeline revision (no `mhc_class` column). Log: `logs/nfcore_epitopeprediction_conda.log`. |
| Second attempt: `--input …/samplesheet_ep20.csv` (three-column sheet, **only under this run dir**) + `--mhc_class 1` | **1** | Samplesheet check passed; **FRED2_GENERATEPEPTIDES** failed: `ModuleNotFoundError: No module named 'pandas'` (conda env for that process not usable as resolved). Log: `logs/nfcore_epitopeprediction_conda_fixedss.log`. |

**Extra artifact:** `epitope_inputs/samplesheet_ep20.csv` — nf-core/epitopeprediction **2.0.0**-compatible samplesheet (template in repo targets a different header shape).

### 2D. Galaxy `POST /api/nextflow/execute` (workflow id **12700** path)

| Step | Result |
|------|--------|
| `POST http://127.0.0.1:8081/api/nextflow/execute` with `nextflow_path`: `nfcore/epitopeprediction/main.nf`, `parameters.input` / `parameters.outdir` under this run, `compute_config.executor`: `local`, `profile`: `conda` | HTTP **200**, `run_id` **c2fd52e6-e015-4528-9627-7e1ffc8cb23d** |
| `GET …/api/nextflow/status/c2fd52e6-e015-4528-9627-7e1ffc8cb23d` | **`failed`**, `returncode` 1 |

**stderr / log_tail (from status JSON):**

```text
ERROR ~ No such file or directory: Config file does not exist: /home/yzhang/biomate/backend/nf-core-workflows/epitopeprediction/conf/base.config
```

Poll capture: `logs/galaxy_epitope_poll.log` (status lines). Full status JSON was retrieved once for `log_tail` above.

---

## 3. AlphaFold DB search (optional)

| Command | Exit | Notes |
|---------|------|-------|
| `nextflow run backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/alphafold_db_search/main.nf -preview --query_pdb 9P3I --outdir …/alphafold_db_preview_out` | **0** | DSL2 preview only (no process execution). Log: `logs/alphafold_db_search_preview.log`. |

---

## 4. Summary

| Objective | Outcome |
|-----------|---------|
| RCSB / Guo structures under run folder | **Success** |
| nf-core epitopeprediction end-to-end | **Not completed** (NF25 parse error; Docker amd64 on arm64; conda env incomplete; Galaxy vendored tree missing `conf/base.config`) |
| AlphaFold DB search | **Preview succeeded** (`-preview`, exit 0) |

**Overall:** **partial** — primary structural downloads and AlphaFold subworkflow preview succeeded; epitope/MHC pipeline did not produce binding predictions on this host without further Nextflow version / container-platform / conda or vendored-workflow fixes.

---

## 5. Fix (2026-05-12) — vendored `epitopeprediction` missing `conf/`

**Root cause:** The nested git clone at `backend/nf-core-workflows/epitopeprediction` had **sparse-checkout** rules (`/*` + `!/*/`) that **excluded all top-level directories**, including **`conf/`**. `nextflow.config` does `includeConfig 'conf/base.config'`, so any run (including BioMate `POST /api/nextflow/execute` for `nfcore/epitopeprediction/main.nf`) failed before processes started.

**Remediation applied on this machine:**

```bash
cd backend/nf-core-workflows/epitopeprediction
git sparse-checkout disable
git checkout .
```

**Repeatable helper (committed in biomate repo):**

```bash
bash research/anti-virus/scripts/ensure_nfcore_epitopeprediction_worktree.sh
```

**Verification:** `test -f backend/nf-core-workflows/epitopeprediction/conf/base.config` → present; `nextflow run main.nf -preview` now loads config and only fails parameter validation (`input`, `outdir` required) — not missing config.

**Still environment-specific (unchanged):** direct `nextflow run nf-core/epitopeprediction` from the registry with **Docker on ARM64** may hit **linux/amd64** image issues; use **AWS Batch** (`POST …/execute` with `executor: awsbatch`) or an **x86** runner for full epitopeprediction with biocontainers.

**Samplesheet on S3 (nf-schema):** when `--input` is an `s3://…/samplesheet.csv`, each row’s `filename` must be an **absolute** `s3://…` URL (or another resolvable URI). A bare relative path such as `plan_a_smoke_gp_fragment.fasta` is validated against the head-node filesystem and fails. Use the checked-in template `research/anti-virus/runs/plan_a_epitope_samplesheet_template/samplesheet_s3_batch.csv` (matches `s3://biomate-nextflow-work/inputs/andv_campaign/plan_a_epitope_samplesheet/`).

**Profile:** nf-core/epitopeprediction does **not** ship an `aws` profile. Use **`docker`** (or `conda`, `test`, …) with Batch — not `profile: aws`.

**Batch + biocontainers + host-mounted AWS CLI:** tasks that use `quay.io/biocontainers/...` images could exit **127** with `/opt/aws-cli/bin/aws: … libz.so.1: cannot open shared object file` when staging S3 work dirs. Nextflow runs S3 staging **before** `process.beforeScript` and before `process.environment` is applied to the task shell, so BioMate injects `LD_LIBRARY_PATH` via **`process.containerOptions = '-e LD_LIBRARY_PATH=…'`** (ECS-visible from container start). The path list must include **Conda env library dirs** used by biocontainers (`/opt/conda/lib`, `/opt/conda/x86_64-conda-linux-gnu/lib`, `/usr/local/lib`, plus Debian/RHEL multiarch paths). **Restart Galaxy gunicorn** after pulling this change so workers reload `nextflow_executor.py`.

**Verification (2026-05-12, Batch):** After deploying `containerOptions` `LD_LIBRARY_PATH`, a Galaxy smoke run (`run_id` **2718f312-1de4-4061-a277-f397167a157f**, `tools: mhcnuggets`, samplesheet `s3://biomate-nextflow-work/inputs/andv_campaign/plan_a_epitope_samplesheet/samplesheet.csv`) advanced through `FASTA2PEPTIDES`, `SPLIT_PEPTIDES`, `PREPARE_PREDICTION_INPUT`, `MHCNUGGETS`, and submitted `MERGE_PREDICTIONS` — i.e. the prior **`libz.so.1` / exit 127 on `/opt/aws-cli/bin/aws`** failure is cleared for biocontainers on this stack.

**Re-test BioMate API:** after the helper script **and** a server restart, `POST …/execute` with `nextflow_path`: `nfcore/epitopeprediction/main.nf`, `parameters.input`: `s3://biomate-nextflow-work/inputs/andv_campaign/plan_a_epitope_samplesheet/samplesheet.csv`, `parameters.outdir` under `s3://biomate-nextflow-work/…`, `compute_config.executor`: `awsbatch`, `profile`: **`docker`**, and prediction params such as `tools` / `genome_reference` as required by the pipeline.
