# Schrödinger Suite — BioMate Integration Feasibility

**Date**: 2026-03-21
**Purpose**: Phase 3 license-gated tool research — Schrödinger Glide/FEP+/Maestro
**Decision**: Research / feasibility only; no implementation yet

---

## Overview

Schrödinger offers industry-leading computational drug discovery tools:
- **Glide** — molecular docking (XP, SP, HTVS modes)
- **FEP+** — free energy perturbation (best-in-class for lead optimization)
- **Prime** — protein structure prediction and loop modeling
- **LigPrep** — 2D→3D ligand preparation
- **Maestro** — GUI (not relevant for headless/cloud)
- **Phase** — pharmacophore modeling
- **Canvas** — QSAR/ML on molecular descriptors

---

## Licensing

| Aspect | Details |
|--------|---------|
| Model | FlexLM floating token server (`port@host`) |
| Academic pricing | ~$7,500–$15,000/yr for full suite; individual modules cheaper |
| Commercial pricing | $50,000–$200,000/yr+ |
| Free tier | **None** — no academic free tier, no trial without sales contact |
| Contract | Annual license agreement; tokens checked out per job |
| Credential type (BioMate) | `license_server`: `SCHRODINGER_LICENSE_FILE=27008@your-flexlm-host` |
| Runtime requirement | License server must be reachable from AWS Batch workers |

**License server on AWS**: Users typically run FlexLM inside their VPC or use Schrödinger's hosted license service. For BioMate users, they would need to provide their own license server address. BioMate could not provide a master credential here (cost is prohibitive).

---

## CLI / Headless Access

All modules expose full CLI via `$SCHRODINGER/run` wrapper:

```bash
# Docking
$SCHRODINGER/glide input.in -WAIT

# LigPrep
$SCHRODINGER/ligprep -isd input.sdf -osd output.sdf -WAIT

# FEP+
$SCHRODINGER/fep_plus -HOST batch -WAIT fep_job.fmp

# Generic Python script with Schrödinger API
$SCHRODINGER/run python3 my_script.py
```

Key pattern: `$SCHRODINGER` env var must point to install dir; `-WAIT` for synchronous execution; `-HOST localhost:4` for local multi-CPU.

### Python API

Schrödinger ships its own Python interpreter. The `schrodinger` package is bundled:

```python
# Must run via $SCHRODINGER/run python3, NOT system python
from schrodinger.structure import StructureReader, StructureWriter
from schrodinger.structutils.minimize import minimize_structure
from schrodinger import job_control
```

The bundled Python (3.11 as of Suite 2024) is not installable separately. All scripts must run inside `$SCHRODINGER/run python3`.

---

## Docker / Container Strategy

**No official Docker image.** Reasons:
1. License check requires network access to FlexLM server at job start
2. Binary distribution restricted by license agreement
3. Schrödinger binaries are ~100 GB extracted

**BioMate approach** (if licensing secured):
1. Build private ECR image with Schrödinger installed (non-public, never pushed to Docker Hub)
2. License server address injected at runtime via env var
3. ECR image: `399683337364.dkr.ecr.us-west-2.amazonaws.com/schrodinger-suite:2024-3`

```dockerfile
FROM amazonlinux:2023
# Copy Schrödinger installer (from S3 or private artifact store)
RUN aws s3 cp s3://biomate-private-artifacts/schrodinger/Suite2024-3-Linux.tar.gz /tmp/ && \
    tar -xzf /tmp/Suite2024-3-Linux.tar.gz -C /opt/schrodinger && \
    rm /tmp/Suite2024-3-Linux.tar.gz
ENV SCHRODINGER=/opt/schrodinger/Suite2024-3
```

Container size: ~50–80 GB. Recommendation: use EFS or S3 mount for the install dir rather than baking into image.

---

## AWS Batch / Cloud Integration

Schrödinger has a **Virtual Cluster** product for cloud HPC, but for BioMate's use case (Nextflow-orchestrated jobs), the simpler pattern is:

1. FlexLM server: EC2 instance in VPC (t3.small is sufficient, always-on, ~$15/month)
2. Batch workers: pull ECR image with Schrödinger installed
3. `SCHRODINGER_LICENSE_FILE=27008@<flexlm-private-ip>` injected via Batch job definition

**Networking**: Batch workers and FlexLM instance must be in the same VPC with security group allowing TCP port 27008.

### Nextflow process template

```nextflow
process GLIDE_DOCKING {
    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/schrodinger-suite:2024-3'

    input:
    path receptor_grid
    path ligand_sdf

    output:
    path 'docking_results.sdf', emit: poses
    path 'glide_score.csv',     emit: scores

    script:
    """
    export SCHRODINGER=/opt/schrodinger/Suite2024-3
    export SCHRODINGER_LICENSE_FILE=${params.schrodinger_license}

    # Prepare glide input
    python3 - << 'EOF'
    # write .in file from params
    EOF

    \$SCHRODINGER/glide docking.in -WAIT -NJOBS 1
    """
}
```

---

## Capability vs. BioMate Workflows

| Use Case | Schrödinger Tool | Alternative Open Source |
|----------|-----------------|------------------------|
| Covalent docking | CovDock | MOE CovDock, AutoDock-GPU (limited) |
| FEP for lead optimization | FEP+ | RBFE with OpenMM/Gromacs (slower, less accurate) |
| High-throughput docking | Glide HTVS | Vina, GNINA, DiffDock |
| Protein prep (missing loops) | Protein Preparation Wizard | Modeller, AlphaFold |
| ADMET prediction | QikProp | ADMETlab, SwissADME (free) |
| 3D pharmacophore | Phase | OpenPharmacophore, Pharmer |

**Conclusion**: FEP+ is the killer feature with no open-source equivalent at this accuracy level. Glide is the gold standard for docking but GNINA/DiffDock are competitive for preliminary screens. QikProp is easily substituted.

---

## Credential Model for BioMate `license_registry.py`

```python
"schrodinger": {
    "display_name": "Schrödinger Suite",
    "vendor": "Schrödinger, Inc.",
    "type": "license_server",
    "registration_url": "https://www.schrodinger.com/contact/",
    "approval_time": "contact sales (days–weeks)",
    "cost": "~$7,500+/yr academic",
    "container_patterns": ["schrodinger"],
    "env_key": "SCHRODINGER_LICENSE_FILE",  # value: "27008@hostname"
    "open_alternatives": [
        {"id": "gnina", "label": "GNINA", "note": "CNN scoring, AutoDock-based, free"},
        {"id": "diffdock", "label": "DiffDock", "note": "Diffusion-based, state-of-art, free"},
        {"id": "openmm_fep", "label": "OpenMM RBFE", "note": "FEP-like, slower, free"},
    ],
}
```

---

## Feasibility Assessment

| Dimension | Rating | Notes |
|-----------|--------|-------|
| CLI/headless | ✅ | Full CLI, all modules scriptable |
| Python API | ✅ | Bundled, mature, well-documented |
| Docker | ⚠️ | No official; DIY ECR image feasible but ~80 GB |
| AWS Batch | ✅ | Supported; need FlexLM EC2 in same VPC |
| Nextflow integration | ✅ | Standard process + env injection |
| License accessibility | ❌ | No free tier; $7,500+/yr; requires sales contact |
| BioMate-provided master | ❌ | Cost prohibitive; users must bring own license |
| Overall feasibility | ⚠️ | Technically feasible; commercially gated |

**Recommendation**: Build the credential UI + Nextflow process template now. Gate on `source === 'user'` (BioMate will not provide master). Users with institutional Schrödinger access can self-service. Prioritize after AF3 and AMBER.

---

## Action Items

- [ ] Request trial license from Schrödinger for development: https://www.schrodinger.com/freeTrial
- [ ] Decide if any user segment has existing Schrödinger licenses (survey beta users)
- [ ] Design FlexLM-on-EC2 topology (shared VPC requirement or per-user server)
- [ ] Build ECR image with Schrödinger 2024 (requires installer from Schrödinger portal)
- [ ] Add `schrodinger` to `LICENSE_REGISTRY` in `license_registry.py`
