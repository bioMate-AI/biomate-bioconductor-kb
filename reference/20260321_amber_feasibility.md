# AMBER — BioMate Integration Feasibility

**Date**: 2026-03-21
**Purpose**: Phase 3 license-gated tool research — AMBER molecular dynamics
**Decision**: Research / feasibility only; no implementation yet

---

## Overview

AMBER (Assisted Model Building with Energy Refinement) is the leading MD simulation suite for:
- **sander / pmemd** — MD engine (CPU/GPU); pmemd.cuda for GPU acceleration
- **AmberTools** — free companion: LEaP, antechamber, tleap, CPPTRAJ, pytraj, ParmEd
- **ff19SB / ff14SB** — protein force fields
- **GAFF2** — small molecule force field
- **PBSA** — implicit solvation
- **MM-GBSA / MM-PBSA** — binding free energy estimation (cheaper than FEP)

**Key distinction**: Amber (the commercial package) = AmberTools + pmemd. AmberTools is always free under GPL. pmemd (fast MD engine, especially GPU) requires the commercial license.

---

## Licensing

| Aspect | Details |
|--------|---------|
| AmberTools | **Free forever** (GPL v3) — conda-forge, source |
| Amber (pmemd) | **Free for academic/non-profit** since April 2023 (Amber24+) |
| Commercial license | $500–$2,000/yr for commercial users |
| Runtime credential | **None** — binary acceptance of license, no runtime key or server |
| Distribution | Source tarball from ambermd.org; conda-forge for AmberTools only |
| Credential type (BioMate) | `license_agreement` — no runtime check; user acknowledges terms |

**Important**: Since Amber24 (April 2023), academic/non-profit users receive pmemd for free. This dramatically improves feasibility — there is no FlexLM server, no token checkout, no runtime key injection. The binary is freely downloadable once you register on ambermd.org.

**BioMate master credential**: BioMate can register once and bake pmemd into a private ECR image. Users do not need individual licenses if they use BioMate's container (covered under BioMate's institutional registration).

---

## CLI / Headless Access

AMBER is entirely CLI-driven with no GUI dependency:

```bash
# System preparation with tleap
tleap -f leap_input.in

# Run MD (CPU)
sander -O -i md.in -o md.out -p system.prmtop -c system.inpcrd -r md.rst -x md.nc

# Run MD (GPU, fast)
pmemd.cuda -O -i md.in -o md.out -p system.prmtop -c system.inpcrd -r md.rst -x md.nc

# Analysis
cpptraj -p system.prmtop -y md.nc -i analysis.in

# MM-GBSA
MMPBSA.py -O -i mmgbsa.in -o results.dat -sp solvated.prmtop -cp complex.prmtop -rp receptor.prmtop -lp ligand.prmtop -y md.nc
```

### Python APIs

**pytraj** (conda-forge, MIT-like): high-level trajectory analysis
```python
import pytraj as pt
traj = pt.load('md.nc', top='system.prmtop')
rmsd = pt.rmsd(traj, mask='@CA', ref=0)
```

**ParmEd** (conda-forge, LGPL): topology reading/editing
```python
import parmed as pmd
struct = pmd.load_file('system.prmtop', 'system.inpcrd')
struct.save('output.pdb', overwrite=True)
```

**MDTraj** (MIT): fast trajectory analysis, AMBER format support
**MDAnalysis** (GPLv2): comprehensive analysis toolkit

No proprietary Python required — all standard conda/pip packages.

---

## Docker / Container Strategy

**No official Docker image for pmemd.** AmberTools has community conda-forge builds:

```bash
conda install -c conda-forge ambertools
```

For pmemd (GPU), a private ECR image is needed:

```dockerfile
FROM nvidia/cuda:12.1.0-devel-ubuntu22.04

# System deps
RUN apt-get update && apt-get install -y \
    python3 python3-pip wget git cmake gfortran flex bison \
    libopenmpi-dev openmpi-bin

# Install Miniconda
RUN wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh \
    && bash Miniconda3-latest-Linux-x86_64.sh -b -p /opt/conda \
    && rm Miniconda3-latest-Linux-x86_64.sh
ENV PATH=/opt/conda/bin:$PATH

# AmberTools via conda-forge (free, no source build needed)
RUN conda install -c conda-forge ambertools -y

# pmemd binary (from BioMate's S3 artifact store, pre-compiled Amber24)
# Note: Build once, store compiled binary, pull here
RUN aws s3 cp s3://biomate-private-artifacts/amber24/pmemd.cuda /usr/local/bin/ \
    && chmod +x /usr/local/bin/pmemd.cuda
```

Image size: ~8 GB (CUDA base + conda + pmemd). Manageable compared to Schrödinger.

**Build AMBER from source** (alternative, ~2h build time):
```bash
# Requires Amber24 tarball from ambermd.org (free academic registration)
./configure -cuda gnu
make install
```

---

## AWS Batch / Cloud Integration

AMBER is well-suited for cloud HPC:

- **CPU**: Any instance (c7i.16xlarge recommended for sander MPI)
- **GPU**: g6.2xlarge (A10G) or p3.2xlarge (V100) for pmemd.cuda
- **Multi-GPU**: pmemd.cuda.MPI for large systems

For Nextflow on Batch, the standard Nextflow AWS Batch configuration applies — no special requirements beyond CUDA-enabled AMI or DLAMI.

```nextflow
process AMBER_MD {
    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/amber24-cuda:latest'
    accelerator 1, type: 'nvidia-tesla-a10g'

    input:
    path prmtop
    path inpcrd
    path md_input  // md.in file

    output:
    path 'md.nc',  emit: trajectory
    path 'md.out', emit: log

    script:
    """
    pmemd.cuda -O \
        -i ${md_input} \
        -o md.out \
        -p ${prmtop} \
        -c ${inpcrd} \
        -r md.rst \
        -x md.nc
    """
}
```

---

## Capability vs. BioMate Workflows

| Use Case | AMBER Tool | Open Source Alternative |
|----------|-----------|------------------------|
| Protein-ligand MD | pmemd.cuda + GAFF2 | OpenMM + GAFF2 (similar accuracy, slower) |
| MM-GBSA binding ΔG | MMPBSA.py | gmx_MMPBSA (Gromacs-based, free) |
| Enhanced sampling | REMD, META-D | OpenMM with OpenPathSampling |
| Nucleic acid MD | ff99bsc1 | OpenMM |
| Trajectory analysis | CPPTRAJ, pytraj | MDAnalysis, MDTraj |
| Coarse-grained | GLYCAM, lipid FF | Martini with Gromacs |

**Conclusion**: pmemd.cuda is ~5–10× faster than OpenMM on GPU for equivalent systems. For production MD pipelines, AMBER is the pragmatic choice. MM-GBSA is highly competitive with FEP at ~1/100th the compute cost. The free academic license makes this the lowest-barrier Phase 3 integration.

---

## Credential Model for BioMate `license_registry.py`

```python
"amber": {
    "display_name": "AMBER",
    "vendor": "University of California San Diego",
    "type": "license_agreement",  # no runtime key — user acknowledges academic terms
    "registration_url": "https://ambermd.org/GetAmber.php",
    "approval_time": "instant (web form)",
    "cost": "free (academic/non-profit); $500–$2,000/yr commercial",
    "container_patterns": ["pmemd", "amber24", "ambertools"],
    "env_key": None,  # no runtime credential injection needed
    "open_alternatives": [
        {"id": "openmm", "label": "OpenMM", "note": "Python API, GPU, free, slightly slower"},
        {"id": "gromacs", "label": "GROMACS", "note": "Free, HPC-optimized, wide FF support"},
        {"id": "namd", "label": "NAMD", "note": "Free academic, GPU+CPU, large systems"},
    ],
}
```

Because there is no runtime credential check, the BioMate license gate behavior for AMBER is:
- **Always `source === 'biomate'`** — BioMate's container has pmemd pre-installed
- User sees a green checkmark row: "AMBER — provided by BioMate (academic license)"
- No credential modal needed

---

## Feasibility Assessment

| Dimension | Rating | Notes |
|-----------|--------|-------|
| CLI/headless | ✅ | 100% CLI, mature, scriptable |
| Python API | ✅ | pytraj, ParmEd, MDAnalysis — all pip/conda |
| Docker | ✅ | Build private ECR; AmberTools via conda-forge |
| AWS Batch + GPU | ✅ | pmemd.cuda on g6.xlarge/p3 instances |
| Nextflow integration | ✅ | Standard process definition |
| License accessibility | ✅ | Free for academic since April 2023 |
| BioMate-provided master | ✅ | BioMate registers once, ships in ECR image |
| Overall feasibility | ✅ | **Highest feasibility of Phase 3 tools** |

**Recommendation**: Prioritize AMBER as the first Phase 3 integration. Build the ECR image, register ambermd.org, compile pmemd.cuda, and create a `protein_ligand_md` Nextflow workflow. The credential gate is trivially simple (`license_agreement`, always-biomate).

---

## Action Items

- [ ] Register on https://ambermd.org/GetAmber.php (free academic, instant)
- [ ] Build `amber24-cuda` ECR image and push to `399683337364.dkr.ecr.us-west-2.amazonaws.com/amber24-cuda:latest`
- [ ] Store compiled pmemd binaries in `s3://biomate-private-artifacts/amber24/`
- [ ] Design `protein_ligand_md` Nextflow workflow: tleap prep → minimize → equilibrate → production → MM-GBSA
- [ ] Add `amber` to `LICENSE_REGISTRY` with `type='license_agreement'` (always-biomate, no user credential needed)
- [ ] AmberTools conda-forge for lightweight analysis nodes (no GPU needed for CPPTRAJ/MM-GBSA)
