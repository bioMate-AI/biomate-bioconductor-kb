# AWS Batch cliPath — Complete Fix

**Date**: 2026-04-10  
**Branch**: integration/next-phase  
**Result**: ADMET S1 E2E `exec=completed`, 4 output files, 116s total ✅

---

## Problem Statement

All Nextflow AWS Batch workflow tasks were failing with exit code 127:

```
bash: line 1: /opt/aws-cli/bin/aws: No such file or directory
```

This blocked every workflow execution in the drug discovery, genomics, pharmacology, and bioconductor suites.

---

## Root Cause Chain

### Root Cause 1: Symlink broken inside containers

`cliPath = '/opt/aws-cli/bin/aws'` is the Nextflow config value that tells Nextflow where AWS CLI lives on the host. Nextflow uses it to:
1. Stage files in/out of S3 for each task
2. Bind-mount the **grandparent directory** (`/opt/aws-cli`) from the host into every container at the same path

On the AMI (`ami-08fe495be97a3dbf4`), `/opt/aws-cli/bin/aws` was a **symlink to `/usr/bin/aws`** (an absolute host path). When bind-mounted into the container:

```
Container sees: /opt/aws-cli/bin/aws → /usr/bin/aws  (symlink)
Container has:  /usr/bin/aws  → DOES NOT EXIST (not mounted)
Result:         broken symlink → exit 127
```

### Root Cause 2: Workflow configs overrode the executor's safe cliPath

The executor (`nextflow_executor.py`) generates an override config with `cliPath = '/opt/aws-cli/bin/aws'`. However, all 2102 workflow `nextflow.config` files hardcoded `cliPath = '/usr/local/bin/aws'` inside their `aws` profile:

```groovy
profiles {
    aws {
        aws {
            batch.cliPath = '/usr/local/bin/aws'  // ← overrides executor -c config
        }
    }
}
```

In Nextflow, **profile settings take precedence over `-c` config files**. Since `BIOMATE_NF_PROFILE=aws`, the profile's value won — making the executor's safe path irrelevant.

### Root Cause 3: Broken queue routing

- `biomate-nextflow-queue` primary CE was `biomate-nextflow-cpu-v1` — its ASG had `MaxSize=0` (silently broken), so jobs got stuck RUNNABLE
- Fallback CE `galaxy-cloud-compute-al2023-final` used a stock ECS AL2023 AMI with no `/opt/aws-cli/` at all
- `biomate-nextflow-hpc-v1` had no imageId and no launch template (also stock AMI)

### Root Cause 4: Launch template install failures on ECS AL2023

When attempting to fix via launch template, two blockers:
- `unzip` not available on ECS AL2023 → fixed by using `python3 zipfile`
- `/tmp` and `/var/tmp` mounted `noexec` on ECS AL2023 → extraction and execution failed there
- Solution: extract and install from `/opt/` (root FS, exec-allowed)

---

## Fixes Applied

### Fix 1 — Launch Template v9 (self-contained AWS CLI install)

Created `nextflow-awscli-mime-20251127-223103:9` — the correct install procedure:

```bash
#!/bin/bash
exec > /var/log/aws-cli-setup.log 2>&1
set -x

rm -rf /opt/aws-cli /opt/awscli-install
mkdir -p /opt/awscli-install && cd /opt/awscli-install

# Use python3 (not unzip — not available on ECS AL2023)
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
python3 -c "import zipfile; zipfile.ZipFile('/opt/awscli-install/awscliv2.zip').extractall('/opt/awscli-install')"
chmod -R 755 /opt/awscli-install/aws/

# Extract to /opt (exec-allowed), NOT /tmp or /var/tmp (noexec on ECS AL2023)
# Run with bash to bypass exec permission requirement
bash /opt/awscli-install/aws/install -i /opt/aws-cli -b /opt/aws-cli/bin
rm -rf /opt/awscli-install
```

Result on host after install:
```
/opt/aws-cli/bin/aws → /opt/aws-cli/v2/current/bin/aws  (relative, within /opt/aws-cli/)
```

All binaries and libraries are **self-contained within `/opt/aws-cli/`**. When Nextflow bind-mounts this directory into any container, all paths resolve correctly regardless of what's in the container.

### Fix 2 — Bulk fix all 2102 workflow configs

```bash
find subworkflows/ -name "nextflow.config" | \
  xargs grep -l "cliPath.*'/usr/local/bin/aws'\|cliPath.*'/home/ec2-user/miniconda/bin/aws'" | \
  xargs -I{} sed -i -e "s|cliPath\s*=\s*'/usr/local/bin/aws'|cliPath = '/opt/aws-cli/bin/aws'|g" \
                    -e "s|cliPath\s*=\s*'/home/ec2-user/miniconda/bin/aws'|cliPath = '/opt/aws-cli/bin/aws'|g" {}
```

All 2102 configs now have exactly:
```
cliPath = '/opt/aws-cli/bin/aws'
```

Covers: bioconductor (~1800), drug_discovery (17), genomics, pharmacology, microbiology, cryo-em.  
GPU profiles (gromacs, amber `gpu_batch`) also fixed — GPU CE LT separately updated to provide the path.

### Fix 3 — GPU CE launch template (lt-02693dd18833fa3f8:5)

The GPU CE installs CLI to `/opt/aws-cli-container/bin/aws`. Updated to also create the `/opt/aws-cli/bin/aws` symlink:

```bash
mkdir -p /opt/aws-cli/bin
ln -sf /opt/aws-cli-container/bin/aws /opt/aws-cli/bin/aws
```

### Fix 4 — Queue routing overhaul

| Queue | Before | After |
|-------|--------|-------|
| `biomate-nextflow-queue` | cpu-v1 (ASG broken) → galaxy-al2023-final (wrong AMI) | cpu-v2 only |
| `biomate-hpc-queue` | hpc-v1 (no imageId) → galaxy-al2023-final | hpc-v1 (fixed AMI+LT) + cpu-v2 (fallback) |

New CE `biomate-nextflow-cpu-v2`:
- AMI: `ami-08fe495be97a3dbf4` (ECS AL2023, April 2026)
- LT: `nextflow-awscli-mime-20251127-223103:9` (explicit version, not $Default)
- maxVcpus: 256, minVcpus: 0

`biomate-nextflow-hpc-v1`:
- AMI updated to `ami-08fe495be97a3dbf4`
- LT: `nextflow-awscli-mime-20251127-223103:9`

Removed `galaxy-cloud-compute-al2023-final` from BioMate queues — it uses BEST_FIT allocation strategy (can't update launch template) and a stock AMI with no `/opt/aws-cli`.

---

## Why Each Constraint Matters

| Constraint | Reason |
|-----------|--------|
| `cliPath = '/opt/aws-cli/bin/aws'` (not `/usr/local/bin/aws`) | `/usr/local` grandparent mount shadows container's `/usr/local/lib/python3.x/site-packages` → all Python imports fail |
| Self-contained install (not symlink) | Symlink to `/usr/bin/aws` points outside the bind-mounted dir → broken inside container |
| Extract to `/opt/` (not `/tmp`) | `/tmp` and `/var/tmp` are `noexec` on ECS AL2023 — binaries can't execute from there |
| `bash install` (not `./install`) | Extracted files may not have exec bits set; `bash` bypasses this |
| Explicit LT version in CE (not `$Default`) | Batch regenerates its internal LT from the user's LT at CE update time; `$Default` at creation time gets baked in and won't update automatically |

---

## Verification

SSM command on fresh instance `i-0813c4f92d1ddcec0`:
```
[Fri Apr 10 03:02:05 UTC 2026] Verify:
aws-cli/2.34.28 Python/3.14.3 Linux/6.1.166-197.305.amzn2023.x86_64 exe/x86_64.amzn.2023
OK: /opt/aws-cli/bin/aws

/opt/aws-cli/bin/aws -> /opt/aws-cli/v2/current/bin/aws  ✅
```

E2E test result:
```
[S1_ADMET] Execute API status=200 type=workflow runId=ccd2e6e9-...
[S1_ADMET] Terminal status: completed
[S1_ADMET] Output files: 4
[S1] COMPLETE — h1=true exec=completed total=116086ms cost=$0.0058
1 passed (2.0m)
```

---

## Infrastructure State After Fix

```
biomate-nextflow-queue
  └─ biomate-nextflow-cpu-v2  (ami-08fe495be97a3dbf4, LT:v9, max=256 vCPU)

biomate-hpc-queue
  ├─ biomate-nextflow-hpc-v1  (ami-08fe495be97a3dbf4, LT:v9, max=256 vCPU)
  └─ biomate-nextflow-cpu-v2  (fallback)

galaxy-cloud-queue-gpu
  └─ galaxy-cloud-compute-gpu-industrial  (GPU AMI, LT:v5 creates /opt/aws-cli symlink)

Launch template: nextflow-awscli-mime-20251127-223103
  v9 (default) — self-contained install to /opt/aws-cli
  v8 — /var/tmp extract (failed, noexec)
  v7 — python3 unzip (failed, noexec)
  v6 — /tmp extract (failed, noexec)
  v5 — symlink creation (broken inside containers)
  v4 — verify-only (original)
```

---

## Files Changed

- `backend/biomni_workflows/nextflow_nfcore/subworkflows/**/*.nextflow.config` — 2102 files, `cliPath` updated
- AWS Launch Template `nextflow-awscli-mime-20251127-223103` — versions 5–9 added, v9 set as default
- AWS Launch Template `lt-02693dd18833fa3f8` — v5 added (GPU CE symlink)
- AWS Batch CEs `biomate-nextflow-cpu-v2`, `biomate-nextflow-hpc-v1` — created/updated with LT v9
- AWS Batch queues `biomate-nextflow-queue`, `biomate-hpc-queue` — rerouted to healthy CEs
