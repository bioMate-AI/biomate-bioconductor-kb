# Drug Discovery: 7-Workflow AWS Batch Fix — 2026-04-17

## Goal
Make ALL 7 drug discovery workflows run successfully on AWS Batch with NO mocks.

## Workflows
| # | Workflow | NF Path |
|---|----------|---------|
| 1 | GROMACS MD | `drug_discovery/gromacs_protein_md/main.nf` |
| 2 | AMBER pmemd | `drug_discovery/amber_pmemd_md/main.nf` |
| 3 | REINVENT4 Lead Design | `drug_discovery/reinvent4_lead_design/main.nf` |
| 4 | AiZynthFinder Retrosynthesis | `drug_discovery/aizynthfinder_retrosynthesis/main.nf` |
| 5 | Scaffold Hopping | `drug_discovery/scaffold_hopping/main.nf` |
| 6 | AlphaFold DB Search | `drug_discovery/alphafold_db_search/main.nf` |
| 7 | NCA_PKNCA IVIVE | `drug_discovery/nca_pknca/main.nf` |

---

## Root Causes Found (Previous Sessions)

### Round 1–3 Submissions — Failures and Causes

#### GROMACS: SMILES→SDF on head node (no rdkit)
- Symptom: `ModuleNotFoundError: No module named 'rdkit'`
- Root cause: The workflow entry closure ran `['python3', '-c', rdkit_script].execute()` on the Nextflow head node, which doesn't have rdkit installed. rdkit is only available inside the AMBERTOOLS container (`biomate/ambertools-gromacs-nf:latest`).

#### AMBER: SMILES treated as file path
- Symptom: `ERROR ~ No such file or directory: /tmp/nextflow_runs/.../work/Cc1ccc...`
- Root cause: `Channel.fromPath(params.ligand, checkIfExists: true)` was called unconditionally. When `params.ligand` is a SMILES string, Nextflow tries to open it as a file path and fails immediately.
- Secondary bug: LIGAND_PREP script used `$input_ext` and `$input_fmt` (Nextflow GString variables, evaluated to empty) instead of `\$input_ext`/`\$input_fmt` (shell variables). This would cause `if [[ "" == "sdf" ... ]]` → always hits `else` → exit 1.

#### NCA_PKNCA: Truncated `workflow {}` entry block
- Symptom: `Unexpected input: '{' @ line 550, column 10. workflow {`
- Root cause: File was truncated at line 551. The `workflow {}` entry block had `log_workflow_header()` called but no body, no channel creation, no NCA_PKNCA call, and no closing `}`. Same class of truncation bug as scaffold_hopping (fixed in previous session).
- Secondary issue: Process containers used `docker.io/rocker/r-ver:4.3.1` and `docker.io/rocker/tidyverse:4.3.1` (public images without PKNCA pre-installed). Changed to `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/r-nca:latest` which has PKNCA, rmarkdown, ggplot2 pre-installed.

#### REINVENT4 + AiZynthFinder + AlphaFold: Missing `/opt/aws-cli` in containers
- Symptom: `bash: line 1: /opt/aws-cli/bin/aws: No such file or directory` (exit status 127)
- Root cause: The Nextflow override config set `cliPath = '/opt/aws-cli/bin/aws'` (mounted from host AMI), but did NOT set `volumes = ['/opt/aws-cli']`. Without an explicit volume mount, the host's `/opt/aws-cli` is **not visible inside the Docker container** on AWS Batch. The base container (`biomate-nextflow-base:latest`) has AWS CLI baked in, so ADMET succeeded. Drug discovery containers (`biomni-drug-discovery-nf:x86`, `rocker/*`) do not.
- Secondary bug: The `_generate_executor_config()` function referenced `nf_path` in a conditional (`if "cryosparc" not in str(nf_path).lower()`) but `nf_path` is **not a parameter of that function**, causing `NameError` for all AWS Batch submissions. This was masked previously — unclear when this regressed.

#### Scaffold Hopping: ✅ FIXED in previous session
- `workflow {}` entry block was truncated; completed in prior session. Verified working (Graphviz warning is cosmetic only).

---

## Fixes Applied — 2026-04-17

### Fix 1: `nextflow_executor.py` — volumes + NameError

**File**: `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`

Changed `_generate_executor_config()` (around line 1070):
- Removed the broken `if "cryosparc" not in str(nf_path).lower()` conditional (NameError — `nf_path` not in scope)
- Always emit `cliPath = '/opt/aws-cli/bin/aws'` for AWS Batch (CryoSPARC's own `nextflow.config` overrides it at merge time)
- **Added** `volumes = ['/opt/aws-cli']` — explicitly bind-mounts `/opt/aws-cli` from the AMI host into every container, making the AWS CLI accessible regardless of whether the container image has it built in

```groovy
// In biomate_executor_override.config (generated):
aws {
    batch {
        cliPath = '/opt/aws-cli/bin/aws'
        volumes = ['/opt/aws-cli']   // NEW: bind-mount from AMI host
    }
}
```

### Fix 2: `gromacs_protein_md/main.nf` — SMILES via .smi file + in-container rdkit

**Entry workflow** (`workflow {}` ~line 1022): Replace `['python3', '-c', rdkit_script].execute()` (head-node execution, no rdkit) with writing SMILES to a `.smi` file using Groovy's `file.text =` (no external process, no rdkit needed on head node).

**LIGAND_PREP process script** (~line 119): Added `.smi` case before the `.sdf` case. When the input has `.smi` extension, run rdkit **inside the AMBERTOOLS container** (which has rdkit):
```python
python3 -c "
from rdkit import Chem; from rdkit.Chem import AllChem; import sys
with open('${ligand_file}') as f: smi = f.read().strip()
mol = Chem.MolFromSmiles(smi)
mol = Chem.AddHs(mol)
AllChem.EmbedMolecule(mol, AllChem.ETKDGv3()); AllChem.MMFFOptimizeMolecule(mol)
Chem.SDWriter('ligand_from_smiles.sdf').write(mol)
"
lig_file="ligand_from_smiles.sdf"; in_fmt="sdf"
```

### Fix 3: `amber_pmemd_md/main.nf` — SMILES detection + LIGAND_PREP GString fix

**Entry workflow**: Added the same SMILES detection pattern (same regex as GROMACS). When SMILES detected: write to `.smi` file via `smi_file.text = ligand_input`. Otherwise: `Channel.fromPath(ligand_input, checkIfExists: true)`.

**LIGAND_PREP process script**: Fixed all GString escaping bugs (`$input_ext` → `\$input_ext`, `$input_fmt` → `\$input_fmt`, etc.). Added `.smi` → SDF conversion using rdkit (same pattern as GROMACS LIGAND_PREP).

### Fix 4: `nca_pknca/main.nf` — Complete entry workflow + fix containers

**Containers**: Changed all 3 processes from `docker.io/rocker/*` to `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/r-nca:latest` (has PKNCA, rmarkdown, ggplot2 pre-installed).

**Entry workflow**: Completed the truncated `workflow {}` block:
```groovy
workflow {
    log_workflow_header()
    if (!params.input_csv) { error "..." }
    ch_csv = Channel.fromPath(params.input_csv, checkIfExists: true)
    NCA_PKNCA(ch_csv)
    NCA_PKNCA.out.report.view { ... }
    ...
}
```

**Test data**: Created minimal PK concentration-time CSV (2 subjects × 11 timepoints) and uploaded to `s3://biomate-nextflow-work/test-data/pk_concentration_time.csv`.

---

## Submission Round 4 — Run IDs

| Workflow | Run ID | Outcome |
|----------|--------|---------|
| GROMACS | `456d0843-84b7-4186-9233-572085404e7b` | Nextflow init died (resource pressure during concurrent launches) |
| AMBER | `9eedad69-a4bd-4784-a44d-eec24c90d83e` | Nextflow init died |
| NCA_PKNCA | `6d9005fd-eb3d-4e67-b393-709f153aa314` | Nextflow init died |
| REINVENT4 | `38438692-acf6-4cb1-b858-93c10cfc83b3` | exit 127: `/opt/aws-cli/bin/aws` missing in container |
| AiZynthFinder | `21ff2804-89a7-460a-bbab-281cd7d793f8` | exit 127: `/opt/aws-cli/bin/aws` missing in container |
| AlphaFold DB Search | `31179fb6-053b-4380-921a-2354151183fa` | exit 127: `/opt/aws-cli/bin/aws` missing in container |

Scaffold Hopping was verified working in previous round (run `a77b2d83`).

---

## Root Cause: Launch Template v9 Destroys AWS CLI

### Discovery
After adding `volumes = ['/opt/aws-cli']` to the override config (Fix 1), REINVENT4/AiZynthFinder/AlphaFold **still** failed with `exit 127: /opt/aws-cli/bin/aws: No such file or directory`. The Docker bind-mount was correctly configured in the submitted job definition, yet the path was empty.

### Investigation
The `biomate-nextflow-cpu-v2` compute environment was using **Launch Template v9** (`nextflow-awscli-mime-20251127-223103 version 9`). LT v9 user-data contains:
```bash
rm -rf /opt/aws-cli          # unconditionally wipe the AMI's baked-in CLI
# then attempt internet re-download …
# if network unavailable during ECS bootstrapping → /opt/aws-cli is GONE
```

This affected **all jobs on `galaxy-cloud-queue`** (not just drug discovery). Even ADMET runs were failing with exit 127. The infrastructure-wide issue was masked as per-workflow bugs.

### Fix 5: Updated Both CEs to Launch Template v11

LT v11 user-data was already written in a prior session to avoid this:
```bash
if [ -x /opt/aws-cli/bin/aws ]; then
    echo "AWS CLI already present at /opt/aws-cli/bin/aws — skipping install"
else
    # install from S3 ...
fi
```

Both CEs updated to LT v11:
```bash
aws batch update-compute-environment --compute-environment biomate-nextflow-cpu-v2 \
  --compute-resources "launchTemplate={launchTemplateName=nextflow-awscli-mime-20251127-223103,version=11}"

aws batch update-compute-environment --compute-environment biomate-nextflow-cpu-v1 \
  --state ENABLED \
  --compute-resources "launchTemplate={launchTemplateName=nextflow-awscli-mime-20251127-223103,version=11}"
```

After the CE update, all existing warm instances (launched by LT v9) were drained. Both CEs now show `desiredvCpus=0` — fresh submissions trigger new instances with LT v11.

### Round 5 — Still Failed (Warm LT v9 Instances)

Round 5 REINVENT4/AiZynthFinder/AlphaFold submitted while CE was transitioning. Jobs landed on surviving LT v9 instances (already had `/opt/aws-cli` destroyed). Still exit 127.

After Round 5: CEs drained to 0 instances. Both confirmed using LT v11. Infrastructure ready for Round 6.

---

## Fix 6: `workflow.workDir` is S3 on AWS Batch — Use `/tmp` for Local Staging

When `NEXTFLOW_USE_AWS=true`, `workflow.workDir` resolves to the S3 work bucket (e.g. `s3://biomate-nextflow-work/nextflow/work/...`). Calling `file("${workflow.workDir}/...").parent.mkdirs()` tried to create directories on S3 as a local path — which failed with `No such file or directory`.

**Files fixed**: `gromacs_protein_md/main.nf` and `amber_pmemd_md/main.nf`

Changed:
```groovy
def smi_file = file("${workflow.workDir}/ligand_inputs/ligand.smi")
smi_file.parent.mkdirs()
```
To:
```groovy
def smi_file = file("/tmp/biomate_nf_inputs/smi/ligand_${System.currentTimeMillis()}.smi")
smi_file.parent.mkdirs()
```

Same fix applied to the PDB download staging path in GROMACS (`/tmp/biomate_nf_inputs/pdb/${pdb_id}.pdb`).

Also added PDB ID → RCSB download logic to AMBER entry workflow (same as GROMACS — `receptor = "1IEP"` was calling `Channel.fromPath("1IEP", checkIfExists: true)` which fails).

## Fix 7: NCA_PKNCA GString Escaping — `e$message` and R `$` operators

**Error**: `No such variable: message -- Check script at line: 89`

**Root cause**: Multiple R `$` operators inside `"""..."""` Groovy blocks were being interpolated as Groovy variables:
- Line 102: `e$message` in `error = function(e) stop(paste("Cannot read CSV:", e$message))`
- Line 354: `knitr::opts_chunk$set(...)` in NCA_REPORT_HTML process
- Lines 366-372: `smry$study_info`, `info$dose`, `info$route`, `info$time_unit`, `info$conc_unit`, `info$auc_unit`, `info$n_subjects`

**Fix**: Escaped all 8 occurrences: `$var` → `\$var`.

---

## Submission Round 6 — Fresh LT v11 Instances (workDir bug discovered)

| Workflow | Run ID | Outcome |
|----------|--------|---------|
| GROMACS | `83ddeb07-c456-418f-a831-45519068c53d` | Failed: `No such file or directory: /biomate-nextflow-work/.../ligand.smi` (workDir=S3) |
| AMBER | `947d970c-78ee-48ba-9212-9b8f47afb35a` | Failed: same workDir issue |
| NCA_PKNCA | `9a9de608-e776-414b-95a7-9f3fb70c7c4d` | Failed: `No such variable: message` (GString escaping) |
| REINVENT4 | `1389b25f-8259-4a73-b12a-b35d5ad201f5` | Running on AWS Batch ✓ |
| AiZynthFinder | `790e5a2a-c277-4974-8202-3d9ddcfcff76` | Running on AWS Batch ✓ |
| AlphaFold | `59352327-0a72-49e9-ab2a-a103f815c9c2` | Running on AWS Batch ✓ |

---

## Submission Round 7 — All 6 Running

After Fixes 6 (workDir→/tmp) and 7 (GString escaping), all 6 workflows are live on AWS Batch:

| Workflow | Run ID | Status |
|----------|--------|--------|
| GROMACS | `6ee91f64-3d1b-4899-be57-f47df4c65026` | Running — LIGAND_PREP, SYSTEM_SETUP queued |
| AMBER | `483835f0-4666-4794-8032-0142ecaa022a` | Running — LIGAND_PREP queued |
| NCA_PKNCA | `56679376-f9e6-405b-b07e-7b9ad6e03a38` | Running — NCA_INPUT_VALIDATION on Batch |
| REINVENT4 | `1389b25f-8259-4a73-b12a-b35d5ad201f5` | Running — VALIDATE_INPUT on Batch |
| AiZynthFinder | `790e5a2a-c277-4974-8202-3d9ddcfcff76` | Running — AIZYNTHFINDER_PREDICT on Batch |
| AlphaFold | `59352327-0a72-49e9-ab2a-a103f815c9c2` | Running — 2 Batch jobs active (structural + sequence search) |

Scaffold Hopping: verified working (run `a77b2d83`). **7/7 workflows launched.**

---

## Previous Session Fixes (Context Summary)

These were already fixed before this session:

### AMBER: Syntax errors (fixed in prior context)
1. Shebang `#\!/usr/bin/env nextflow` → `#!/usr/bin/env nextflow`
2. Unescaped `$()` subshell at line 110: `input_ext=$(...)` → `input_ext=\$(...)`
3. Heredoc delimiters: `<< 'MIN1EOF'` → `<< MIN1EOF` (8 heredocs)
4. Escaped backslashes in Python PYEOF blocks: `\n` → `\\n`, `\s` → `\\s`, etc.

### Scaffold Hopping: Truncated workflow (fixed in prior context)
- Added complete `workflow {}` entry block with `--smiles` and `--input_smiles` support.

### AiZynthFinder: Missing `--seed_smiles` param (fixed in prior context)
- Entry workflow previously only accepted `--smiles_file` (file path). Added `params.seed_smiles` fallback for inline SMILES input.

### AlphaFold DB Search: Wrong parameter name (fixed in prior context)
- Was submitting `"query"` instead of `"query_pdb"`.

### `_accession_chain_thread` skip_next bug (fixed in prior context)
- Off-by-one error caused the NEXT flag (e.g., `--ligand`) to be dropped after accession substitution (e.g., `receptor = "1IEP"` → PDB download). Fixed by using `i += 2` instead of `skip_next = True` + double `i += 1`.

---

---

## Fix 8: LT v13 Symlink — `[ -x ]` Passes on Host but Breaks in Docker

### Discovery (Current Session)
After the team member created LT v12/v13, GROMACS/AMBER/NCA/REINVENT4/AiZynthFinder jobs went RUNNABLE on AWS Batch. But AlphaFold kept failing with:
```
bash: line 1: /opt/aws-cli/bin/aws: No such file or directory (exit 127)
```

### Root Cause
The AMI `ami-08fe495be97a3dbf4` has `/opt/aws-cli/bin/aws` as a **symlink** → `/usr/local/bin/aws`.

LT v13 check:
```bash
if [ -x /opt/aws-cli/bin/aws ]; then
    echo "OK: Already installed"   # ← SKIPS reinstall
```

On the EC2 host: `[ -x symlink ]` follows the symlink; `/usr/local/bin/aws` exists → condition is TRUE → reinstall is SKIPPED.

When Nextflow mounts `/opt/aws-cli` into the Docker container:
- The symlink `/opt/aws-cli/bin/aws → /usr/local/bin/aws` is copied into the container
- `/usr/local/bin/aws` does NOT exist inside the container image
- → Broken symlink → `No such file or directory`

### Fix: LT v14 — `[ ! -L ]` Detects Symlinks

Created LT v14 on `nextflow-awscli-mime-20251127-223103`:
```bash
# Reinstall if: missing, not executable, OR is a symlink
if [ -f /opt/aws-cli/bin/aws ] && [ ! -L /opt/aws-cli/bin/aws ] && [ -x /opt/aws-cli/bin/aws ]; then
    echo "OK: Real binary (not symlink), executable — no reinstall needed"
else
    echo "Installing: path missing, is a symlink, or not executable"
    # ... AWS CLI v2 installer ...
    bash /opt/awscli-install/aws/install -i /opt/aws-cli -b /opt/aws-cli/bin
fi
```

The AWS CLI v2 installer creates a **relative** symlink inside the `/opt/aws-cli` tree:
`/opt/aws-cli/bin/aws → ../v2/current/bin/aws`
This relative symlink resolves correctly inside Docker bind-mounts.

Updated both CEs to LT v14:
```bash
aws batch update-compute-environment --compute-environment biomate-nextflow-cpu-v1 \
  --compute-resources "launchTemplate={launchTemplateName=nextflow-awscli-mime-20251127-223103,version=14}"
aws batch update-compute-environment --compute-environment biomate-nextflow-cpu-v2 \
  --compute-resources "launchTemplate={launchTemplateName=nextflow-awscli-mime-20251127-223103,version=14}"
```

Verified LT v14 is embedded in Batch-generated LT `lt-04dd0c132e11d23a6` (used by cpu-v1 ASG).

Terminated stale m5.xlarge instance `i-079683fef63d1b604` (provisioned with old LT, was serving AlphaFold jobs with broken symlink).

---

## AlphaFold DB Search: API Rewrite

### Motivation
Original workflow required 20 GB Foldseek DB download from S3 → 64 GB RAM (r5.4xlarge on HPC queue). User request: "why not just use API? why use the db?"

### Solution
Rewrote `alphafold_db_search/main.nf` to use public web APIs:
1. **Foldseek web server** (`search.foldseek.com/api/ticket` → poll → `/api/result/{id}/0`) — structural search against AlphaFold DB / PDB100 / SwissProt via 3Di alphabet
2. **EBI HMMER phmmer** (`hmmer.ebi.ac.uk/Tools/hmmer/search/phmmer`) — sequence homology vs UniProtKB

Single `ALPHAFOLD_API_SEARCH` process: 1 vCPU, 2 GB, standard queue, ~10 min max.

### Groovy Lexer Issues Fixed

1. **`r'^[A-Z0-9]{4}$'`** → Changed to double-quoted `"^[A-Z0-9]{4}\$"` (Groovy GString can't parse `'...'` single-quoted strings inside `"""..."""` blocks)

2. **`f'''...'''`** triple-single-quote HTML template → Replaced with string concatenation:
```python
html_parts = [
    "<!DOCTYPE html><html>...",
    ...
]
open("combined_report.html", "w").write("".join(html_parts))
```

3. **`$"` in regex** → `"^[A-Z0-9]{4}$"` has `$"` which Groovy sees as GString interpolation start → escaped to `\$`.

---

## Submission Round 8 — Current State

| Workflow | Run ID (Latest) | Status |
|----------|-----------------|--------|
| GROMACS | Round 8 | RUNNABLE on Batch (LIGAND_PREP ×2) |
| AMBER | Round 8 | RUNNABLE on Batch |
| REINVENT4 | Round 8 | RUNNABLE on Batch (VALIDATE_INPUT) |
| AiZynthFinder | Round 8 | RUNNABLE on Batch (AIZYNTHFINDER_PREDICT) |
| NCA_PKNCA | Round 8 | RUNNABLE on Batch (NCA_INPUT_VALIDATION) |
| AlphaFold | `259ccd64` → `RESUBMIT` | AWS CLI stale instance; LT v14 deployed; resubmitting |
| Scaffold Hopping | `a77b2d83` | ✅ Verified completed |

Stale instance `i-079683fef63d1b604` terminated. New instances will use LT v14 with proper AWS CLI binary.

## ECR Images

| Image | ECR URI | Status |
|-------|---------|--------|
| AmberTools+GROMACS | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ambertools-gromacs-nf:latest` | Built (AMD64, 1.0 GB) |
| r-nca (PKNCA + tidyverse) | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/r-nca:latest` | Built (rocker/tidyverse:4.3.1 + PKNCA) |
| biomni-drug-discovery-nf | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86` | Pre-existing; no AWS CLI (AMI provides via volume mount) |
