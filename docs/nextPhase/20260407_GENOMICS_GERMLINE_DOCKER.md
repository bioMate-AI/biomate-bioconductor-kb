# genomics-germline Docker Image — Build Handoff (2026-04-07)

## Status: DOCKERFILE READY — IMAGE NOT YET BUILT

The Dockerfile exists and the ECR repo has been created. The image needs to be built
and pushed before the germline pipeline can execute on AWS Batch.

---

## What this image is for

`biomate/genomics-germline:x86` is the container for **all processes** in the
`wgs_germline_gatk` Nextflow workflow (except the SRA download step which uses
`biomate/sra-tools:3.1.1`).

Pipeline location:
```
backend/biomni_workflows/nextflow_nfcore/subworkflows/genomics/wgs_germline_gatk/main.nf
```

Processes that use this image:
`FASTQC`, `FASTP_TRIM`, `BWA_MEM2_ALIGN`, `SAMTOOLS_SORT_INDEX`, `MARK_DUPLICATES`,
`SAMTOOLS_FLAGSTAT`, `MOSDEPTH_COVERAGE`, `BQSR_BASE_RECALIBRATOR`, `BQSR_APPLY`,
`HAPLOTYPE_CALLER`, `GENOTYPE_GVCFS`, `VARIANT_FILTRATION`, `VARIANT_ANNOTATION`,
`MULTIQC_REPORT`

---

## Tools in the image

| Tool | Purpose |
|------|---------|
| `bwa-mem2` | Fast BWA alignment for large genomes |
| `gatk4` | BQSR, HaplotypeCaller, GenotypeGVCFs, MarkDuplicates, VariantFiltration |
| `samtools` | Sort, index, flagstat |
| `mosdepth` | Coverage metrics |
| `fastqc` | Raw read QC |
| `fastp` | Adapter trimming |
| `multiqc` | Aggregate QC report |
| `snpEff` | Variant annotation (uses its own Java 21 wrapper) |
| `pigz` | Parallel gzip |
| `aws` (inherited) | S3 staging — from `biomate-nextflow-base` |

---

## Dockerfile location

```
backend/docker/genomics-germline/Dockerfile
```

**Critical**: inherits from `biomate-nextflow-base:latest` (NOT `mambaorg/micromamba`).
This is the only reliable way to get AWS CLI into the image for Nextflow S3 staging
(`nxf_s3_upload` / `nxf_s3_download`). All other BioMate Nextflow containers use the
same base for the same reason.

---

## ECR repository

```
399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/genomics-germline
```

Repository has been created. **No image has been pushed yet.**

---

## Build command

Run from the repo root (`/home/yzhang/biomate`):

```bash
docker buildx build \
  --platform linux/amd64 \
  -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/genomics-germline:x86 \
  --push \
  -f backend/docker/genomics-germline/Dockerfile \
  .
```

Expected build time: **20–30 minutes** (conda installs bwa-mem2, gatk4, samtools, mosdepth).

---

## Smoke test after build

```bash
docker run --rm --platform linux/amd64 \
  399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/genomics-germline:x86 \
  bash -c "bwa-mem2 version && gatk --version && samtools --version | head -1 \
           && mosdepth --version && snpEff -version 2>&1 | head -1 && aws --version"
```

All six commands must succeed. `aws --version` is the critical one — if it fails, the
image was built from the wrong base and needs to be rebuilt.

---

## What was already done (do not redo)

| Done | Item |
|------|------|
| ✅ | `biomate/sra-tools:3.1.1` built and pushed to ECR |
| ✅ | `biomate/genomics-germline` ECR repo created |
| ✅ | `Dockerfile` written at `backend/docker/genomics-germline/Dockerfile` |
| ✅ | All 14 pipeline processes have `container` directives pointing to the correct ECR URI |
| ✅ | `FASTERQ_DUMP` process added to pipeline for SRA accession input |
| ✅ | `max_spots` param added to cap SRA download (0 = unlimited, 500000 = quick test) |
| ❌ | `biomate/genomics-germline:x86` image not yet built/pushed |

---

## Previous mistake (already cleaned up)

An earlier build attempted `FROM mambaorg/micromamba:1.5-jammy` (wrong base — no AWS CLI).
That build was killed and the incorrectly-named `biomate/wgs-germline` ECR repo was
deleted. The correct repo name is `biomate/genomics-germline`.

---

## Related session docs

- `docs/nextPhase/20260407_REAL_SRA_EXECUTION_AND_E2E_HARDENING.md` — full context on
  the SRA pipeline changes, E2E test updates, and fasterq-dump ECR image
