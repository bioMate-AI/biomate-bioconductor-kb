# Tool Exceptions Guide for x86 Docker Images

**Date:** December 19, 2025
**Platform:** x86_64 (linux/amd64)

This document describes tools that **cannot be included** in the Docker images and important notes for your x86 system.

---

## 1. Tools NOT Included (Use Separate Containers)

These tools cannot be included due to fundamental technical constraints. **Use their official containers when needed.**

### 1.1 DeepVariant
**Reason:** Requires TensorFlow with specific GPU/CPU configurations
**Official Container:** `google/deepvariant:1.6.0`
```bash
docker run -v /data:/data google/deepvariant:1.6.0 \
    /opt/deepvariant/bin/run_deepvariant \
    --model_type=WGS \
    --ref=/data/ref.fa \
    --reads=/data/sample.bam \
    --output_vcf=/data/output.vcf.gz
```

### 1.2 Strelka2
**Reason:** Requires Python 2.7 (end-of-life, incompatible with Python 3 environment)
**Official Container:** `quay.io/biocontainers/strelka:2.9.10--h9ee0642_1`
```bash
docker run -v /data:/data quay.io/biocontainers/strelka:2.9.10--h9ee0642_1 \
    configureStrelkaSomaticWorkflow.py \
    --normalBam /data/normal.bam \
    --tumorBam /data/tumor.bam \
    --ref /data/ref.fa \
    --runDir /data/strelka_run
```

### 1.3 Manta
**Reason:** Requires Python 2.7 (end-of-life, incompatible with Python 3 environment)
**Official Container:** `quay.io/biocontainers/manta:1.6.0--h9ee0642_2`
```bash
docker run -v /data:/data quay.io/biocontainers/manta:1.6.0--h9ee0642_2 \
    configManta.py \
    --bam /data/sample.bam \
    --referenceFasta /data/ref.fa \
    --runDir /data/manta_run
```

### 1.4 ASCAT (R package)
**Reason:** Package not available in bioconda/conda-forge
**Alternative:** Install manually via R if needed:
```R
# Inside container
if (!require("devtools")) install.packages("devtools")
devtools::install_github("VanLoo-lab/ascat/ASCAT")
```
**Note:** nf-core workflows handle ASCAT via their own containerized process.

### 1.5 Sentieon
**Reason:** Commercial software requiring license
**Solution:** Use Sentieon's official containers with your license:
```bash
export SENTIEON_LICENSE=server:port
docker run -e SENTIEON_LICENSE=$SENTIEON_LICENSE sentieon/sentieon:202308.01 ...
```

---

## 2. Important Notes for VEP Users

VEP (Variant Effect Predictor) is **included** in the wgs-wes image, but you need to **download cache files separately** before running annotations:

```bash
# Download VEP cache for GRCh38 (run once)
docker run -v /data:/data biomate/wgs-wes:x86 bash -c \
    "vep_install -a c -s homo_sapiens -y GRCh38 -c /data/vep_cache"

# Then run VEP with the cache
docker run -v /data:/data biomate/wgs-wes:x86 \
    vep -i /data/input.vcf -o /data/output.vcf \
    --cache --dir_cache /data/vep_cache
```

---

## 3. nf-core Workflow Compatibility

**Good news:** For nf-core workflows (sarek, raredisease, rnaseq, drop, cutandrun), the Docker images cover **most required tools**. nf-core automatically pulls specialized containers for:
- DeepVariant
- Strelka2
- Manta

So you don't need to manually run these - nf-core handles it.

---

## 4. Summary Table

| Tool | Status | Action Required |
|------|--------|-----------------|
| DeepVariant | **NOT included** | Use `google/deepvariant:1.6.0` |
| Strelka2 | **NOT included** | Use `quay.io/biocontainers/strelka:2.9.10--h9ee0642_1` |
| Manta | **NOT included** | Use `quay.io/biocontainers/manta:1.6.0--h9ee0642_2` |
| ASCAT | **NOT included** | Install via R devtools if needed |
| Sentieon | **NOT included** | Requires commercial license |
| VEP | Included | Download cache files before use |
| All other tools | Included | Ready to use |

---

## 5. Available Docker Images

| Image | Size | Primary Workflows | ECR URI |
|-------|------|-------------------|---------|
| biomate/wgs-wes:x86 | ~9GB | nf-core/sarek, nf-core/raredisease | 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/wgs-wes:x86 |
| biomate/rnaseq:x86 | ~10GB | nf-core/rnaseq, nf-core/drop | 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/rnaseq:x86 |
| biomate/cutandrun:x86 | ~6GB | nf-core/cutandrun | 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/cutandrun:x86 |
| biomate/singlecell:x86 | ~9GB | scAuto, 10x Genomics | 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/singlecell:x86 |

---

## 6. Quick Start

```bash
# Pull from ECR (requires AWS credentials)
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com

docker pull 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/rnaseq:x86

# Run verification
docker run --rm biomate/wgs-wes:x86
docker run --rm biomate/rnaseq:x86
docker run --rm biomate/cutandrun:x86
docker run --rm biomate/singlecell:x86

# Run interactive shell
docker run -it -v /data:/data biomate/wgs-wes:x86 bash
```

---

## 7. Contact

All tools listed in the WORKING_TOOLS_INVENTORY.md are verified working on native x86 systems.
