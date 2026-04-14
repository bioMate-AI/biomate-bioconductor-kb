# Docker Image Audit + AWS Batch Fix Report — 2026-04-08

## Context

All AWS Batch runs were failing with exit code 127: `bash: line 1: /usr/local/bin/aws: No such file or directory`.

Root cause: Nextflow's generated `.command.run` script hardcodes the path to `aws` from wherever it finds it on the **head process** machine. On this server, `aws` is at `/usr/local/bin/aws`. Task containers must have `aws` at that same path or Batch jobs fail before executing any user code.

---

## 1. ECR Image Status After 2026-04-07 Rebuild

| Image | Tag | Pushed | Size | Has AWS CLI at `/usr/local/bin/aws`? |
|-------|-----|--------|------|--------------------------------------|
| `biomate-nextflow-base` | `latest` | Apr-07 15:23 | 404 MB | **YES** (verified locally) |
| `biomate/biomni-tools` | `x86`, `latest` | Apr-07 15:29 | 476 MB | **UNVERIFIED** — rebuilt from `biomate-nextflow-base`, should inherit it |
| `biomate/biomni-pharma` | `x86`, `latest` | Apr-07 15:29 | 476 MB | **UNVERIFIED** — same size as `biomni-tools`, likely rebuilt together |
| `biomate/biomni-structure-to-drug` | `x86` | Apr-07 15:32 | 460 MB | **UNVERIFIED** |
| `biomate/biomni-drug-discovery-nf` | `x86` | Apr-07 15:45 | 1162 MB | **UNVERIFIED** |

**Verification needed**: The ARM64 dev machine cannot pull x86 images. Confirm AWS CLI is at `/usr/local/bin/aws` in each image by running a Batch job or using EC2:
```bash
docker run --platform linux/amd64 --rm \
  399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-pharma:x86 \
  which aws
```

---

## 2. Bug Fixed: `aws.batch {}` Empty Block — Nextflow 25.10+ Incompatibility

**File**: `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`

**Symptom**: Every AWS Batch run since the Nextflow 25.10.0 upgrade failed immediately with:
```
ERROR ~ Unknown config attribute `aws.batch` -- check config file: ...biomate_executor_override.config
```

**Cause**: The generated config included an empty `aws { batch { } }` block. Nextflow 25.10.x no longer accepts this as a valid config attribute.

**Fix applied** (2026-04-08): Removed the empty `aws.batch` block from config generation. The comment explaining why `cliPath` is omitted is preserved inline.

**Gunicorn reloaded** after the fix — no restart required.

---

## 3. `.nf` Workflow Container Changes Made (Review Requested)

The following `.nf` files were edited to replace `biomni-pharma:x86` with `biomni-tools:x86` before the rebuild was confirmed. **These changes may be reverted** if `biomni-pharma:x86` is the correct image:

| File | Old container | New container |
|------|--------------|--------------|
| `pharmacology/predict_admet_properties/main.nf` | `biomni-pharma:x86` | `biomni-tools:x86` |
| `drug_discovery/assay_ingestion_and_ranking/main.nf` | `biomni-pharma:x86` | `biomni-tools:x86` |
| `drug_discovery/cro_submission_export/main.nf` | `biomni-pharma:x86` | `biomni-tools:x86` |
| `pharmacology/ivive_hepatic_clearance/main.nf` | `biomni-pharma:x86` | `biomni-tools:x86` |

**Rationale for the change**: `biomni-pharma:x86` pre-rebuild was 175 MB (Feb 2026, no AWS CLI). `biomni-tools:x86` post-rebuild is 476 MB and likely has AWS CLI. Both are now the same size post-rebuild, suggesting they may have been built from the same base.

**Decision needed**: If `biomni-pharma:x86` now has AWS CLI and the required pharmacology tools (RDKit, ADMET libraries), revert these files to their original container reference. If `biomni-tools:x86` is sufficient, keep as-is.

---

## 4. `biomni-pharma:latest` Still References Old Container (Low Priority)

`pharmacology/apply_vcog_grade/main.nf` uses `'399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-pharma:latest'` — a static reference not conditional on `NEXTFLOW_USE_AWS`. This will use the `latest` tag which was also rebuilt Apr-07. Low priority; same verification applies.

---

## 5. Containers NOT Rebuilt (Potential AWS CLI Gap)

These containers are used by nfcore workflows but were **not** rebuilt on Apr-07:

| Image | Last pushed | Used by |
|-------|------------|---------|
| `biomate/genomics-germline:x86` | Unknown | Germline/sarek workflows |
| `biomate/sra-tools:3.1.1` | Unknown | SRA fetch step |
| `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomni-lite:latest` | Unknown | Various |

If germline E2E passes (7/7 confirmed), `sra-tools` and `genomics-germline` likely have AWS CLI already. Recommend explicit verification before claiming all workflows are production-ready.

---

## 6. `beforeScript` in Executor Config

A `beforeScript` that creates a symlink at `/opt/aws-cli/bin/aws` was added to the executor config as a fallback. **This does not help** for the S3 staging step (which runs before `beforeScript`). It should be removed once all images are confirmed to have AWS CLI baked in.

**File**: `nextflow_executor.py` lines ~948–958 in `_generate_executor_config()`.

---

## 7. Recommended Verification Steps

1. Submit a single ADMET test job via the UI and check the Batch job logs in the AWS console
2. Confirm exit status 0 for the `.command.run` execution
3. Run `npx playwright test e2e/full-workflow-e2e.e2e.ts --grep "ADMET Full Execution"` — should now pass
4. Remove `beforeScript` from `nextflow_executor.py` once images confirmed working
5. Decide on `biomni-pharma:x86` vs `biomni-tools:x86` and update `.nf` files accordingly
