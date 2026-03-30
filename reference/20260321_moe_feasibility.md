# MOE (Molecular Operating Environment) — BioMate Integration Feasibility

**Date**: 2026-03-21
**Purpose**: Phase 3 license-gated tool research — CCG MOE
**Decision**: Research / feasibility only; no implementation yet

---

## Overview

MOE (Molecular Operating Environment) by Chemical Computing Group (CCG) is a comprehensive drug discovery platform with unique strengths in:
- **Covalent docking** — best-in-class for covalent warhead placement
- **Antibody modeling** — Rosetta-competitive homology models for mAbs
- **Pharmacophore queries** — 3D pharmacophore generation and virtual screening
- **Fragment-based drug design** — FBDD workflows
- **Scaffold replacement** — bioisostere enumeration
- **Protein-protein interface analysis** — hotspot detection, interface design
- **SAR analysis** — R-group decomposition, matched molecular pairs

MOE is a unified platform (not a collection of separate tools). One license covers the full suite. This is an advantage vs. Schrödinger (module-by-module pricing).

---

## Licensing

| Aspect | Details |
|--------|---------|
| Model | FlexNet floating license server (`LM_LICENSE_FILE=port@host`) |
| Academic pricing | ~$3,000–$8,000/yr (negotiated; varies by institution size) |
| Commercial pricing | ~$20,000–$50,000/yr; contact CCG sales |
| Free tier | None; 15-day trial available via request |
| Runtime requirement | FlexNet daemon reachable from compute nodes |
| Credential type (BioMate) | `license_server`: `LM_LICENSE_FILE=27001@your-flexnet-host` |

**Note**: MOE licensing is simpler than Schrödinger — one floating license covers all modules. Academic pricing is lower. CCG sales responds quickly for academic inquiries.

**BioMate master credential**: Would require BioMate to purchase/maintain a MOE license (~$5,000–8,000/yr for a few floating seats). Possible if MOE becomes a differentiating workflow. Currently not owned.

---

## CLI / Headless Access

MOE provides `moebatch` for headless/HPC use:

```bash
# Run MOE script headlessly
moebatch -exec "run 'my_script.svl'" -exit

# Docking batch job
moebatch -exec "DockBatch ['receptor.moe', 'ligands.sdf', []]" -exit

# MOE SVL (Scientific Vector Language) — MOE's scripting language
moebatch -exec "load '\$MOE/sample/mol2/caffeine.mol2'; run 'analyze.svl'" -exit
```

`moebatch` is included with any MOE license. The `-exec` flag accepts SVL expressions directly or via script file.

### Python Integration

**No official Python bindings.** MOE uses SVL (Scientific Vector Language), its own language. Python integration pattern:

```python
import subprocess, os

def run_moe_script(svl_script: str, moe_home: str) -> dict:
    """Run a MOE SVL script via moebatch."""
    result = subprocess.run(
        [f"{moe_home}/bin/moebatch", "-exec", svl_script, "-exit"],
        env={**os.environ, "LM_LICENSE_FILE": os.environ["LM_LICENSE_FILE"]},
        capture_output=True, text=True, timeout=3600
    )
    if result.returncode != 0:
        raise RuntimeError(f"MOE failed: {result.stderr}")
    return {"stdout": result.stdout, "returncode": result.returncode}
```

For structured data exchange: MOE SVL can write results to JSON, SDF, or CSV; Python reads them back. No shared memory or socket API.

**Key limitation**: No pythonic API like RDKit or schrodinger. All MOE logic must be SVL. This is the biggest development friction vs. AMBER/OpenMM.

---

## SVL (Scientific Vector Language) Overview

SVL is MOE's proprietary scripting language. It is:
- Interpreted (like Python/Matlab but vector-first)
- Included with all MOE installations
- Well-documented in MOE documentation
- Not transferable to other platforms

```svl
// Example: covalent docking SVL script
#set title 'Covalent Docking'
local function main []
    local rec = ReadTriposMOL2 'receptor.mol2';
    local lig = ReadTriposMOL2 'warhead.mol2';
    local docks = Dock [rec, lig, [covalent:1, warhead:'SH', n_poses:20]];
    WriteSDF ['output.sdf', docks];
endfunction
```

SVL scripts are typically 50–200 lines for a complete workflow. The learning curve is moderate.

---

## Docker / Container Strategy

**No official Docker image.** Reasons similar to Schrödinger — license server required at runtime.

CCG does have an **AWS HPC quick start guide** (uses ParallelCluster), suggesting cloud use is supported but requires institutional infrastructure.

**BioMate approach** (if licensing secured):

```dockerfile
FROM amazonlinux:2023

# MOE install from private S3 (requires CCG-issued installer)
RUN aws s3 cp s3://biomate-private-artifacts/moe/moe2024.09_linux.tar.gz /tmp/ && \
    tar -xzf /tmp/moe2024.09_linux.tar.gz -C /opt/ && \
    rm /tmp/moe2024.09_linux.tar.gz

ENV MOE=/opt/moe2024.09
ENV PATH=$MOE/bin:$PATH
# LM_LICENSE_FILE injected at runtime, not baked in
```

Image size: ~5–10 GB. License server address passed via env var at Batch job start.

---

## AWS Batch / Cloud Integration

MOE on AWS requires:
1. FlexNet license server: EC2 in same VPC (t3.small, always-on, ~$15/month)
2. Batch worker pulls ECR image with MOE installed
3. `LM_LICENSE_FILE=27001@<flexnet-private-ip>` injected via Batch job environment

```nextflow
process MOE_COVALENT_DOCKING {
    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/moe2024:latest'

    input:
    path receptor
    path warhead_sdf
    val  n_poses

    output:
    path 'docking_results.sdf', emit: poses
    path 'docking_report.html', emit: report

    script:
    """
    export LM_LICENSE_FILE=${params.moe_license}
    export MOE=/opt/moe2024.09

    # Generate SVL script
    python3 - << 'PYEOF'
    svl = f'''
    local function main []
        local rec = ReadTriposMOL2 '{receptor}';
        local docks = Dock [rec, ReadTriposMOL2 '{warhead_sdf}'),
            [covalent:1, n_poses:{n_poses}]];
        WriteSDF ['docking_results.sdf', docks];
    endfunction
    '''
    open('dock.svl', 'w').write(svl)
    PYEOF

    \$MOE/bin/moebatch -exec "run 'dock.svl'" -exit
    """
}
```

---

## Capability vs. BioMate Workflows

| Use Case | MOE Tool | Alternative |
|----------|---------|-------------|
| Covalent docking | MOE CovDock (best-in-class) | Schrödinger CovDock, AutoDock-GPU (limited) |
| Antibody modeling | MOE Antibody Modeler | ABodyBuilder2, IgFold (free, comparable) |
| Fragment linking | MOE Lead Finder | FragGen, OpenBabel (simpler) |
| Pharmacophore | MOE Pharmacophore | LigandScout (paid), Pharmer (free) |
| Scaffold replacement | MOE Scaffold Replacement | REINVENT (generative, free) |
| Protein-protein docking | MOE Protein Docking | HADDOCK, ClusPro (free, web) |
| General docking | MOE Dock | GNINA, DiffDock, Vina (free) |
| SAR analysis | MOE SAR Dashboard | RDKit + custom scripts |

**Unique MOE strengths vs. all alternatives**:
1. **Covalent docking** — better warhead geometry and scoring than any free tool
2. **Fragment FBDD** — BREED, scaffold replacement workflows
3. **Integrated platform** — receptor prep → docking → SAR → ADMET in one tool

---

## Credential Model for BioMate `license_registry.py`

```python
"moe": {
    "display_name": "MOE (Molecular Operating Environment)",
    "vendor": "Chemical Computing Group (CCG)",
    "type": "license_server",
    "registration_url": "https://www.chemcomp.com/MOE-Molecular_Operating_Environment.htm",
    "approval_time": "contact sales (1–5 days for academic)",
    "cost": "~$3,000–$8,000/yr academic",
    "container_patterns": ["moe", "moebatch", "chemcomp"],
    "env_key": "LM_LICENSE_FILE",  # value: "27001@hostname"
    "open_alternatives": [
        {"id": "gnina", "label": "GNINA", "note": "Free, CNN scoring, good for non-covalent"},
        {"id": "diffdock", "label": "DiffDock", "note": "SOTA diffusion docking, free"},
        {"id": "abodybuilder2", "label": "ABodyBuilder2", "note": "Free antibody homology modeling"},
    ],
}
```

---

## MOE vs. Schrödinger vs. AMBER — Decision Matrix

| Criterion | MOE | Schrödinger | AMBER |
|-----------|-----|-------------|-------|
| Cost (academic) | ~~$5k~~/yr | ~~$10k+~~/yr | Free |
| Runtime credential | license_server | license_server | none |
| Python API | ❌ (SVL only) | ✅ (bundled) | ✅ (pytraj, ParmEd) |
| Docker feasibility | ⚠️ private ECR | ⚠️ private ECR (~80 GB) | ✅ conda-forge |
| Unique capability | Covalent docking, FBDD | FEP+ (no equiv) | GPU MD (fast) |
| BioMate priority | Low | Medium | **High** |
| Implementation effort | High (SVL bridge) | High (token server) | **Low** |

---

## Feasibility Assessment

| Dimension | Rating | Notes |
|-----------|--------|-------|
| CLI/headless | ✅ | moebatch fully headless |
| Python API | ❌ | SVL only; subprocess wrapper needed |
| Docker | ⚠️ | Private ECR; license server required |
| AWS Batch | ✅ | With FlexNet EC2 in VPC |
| Nextflow integration | ⚠️ | Needs SVL script generation layer |
| License accessibility | ⚠️ | No free tier; ~$5k/yr; requires sales contact |
| BioMate-provided master | ⚠️ | Possible at ~$5k/yr if covalent docking is a key workflow |
| Overall feasibility | ⚠️ | Technically feasible; medium priority |

**Recommendation**: Defer MOE integration after AMBER. MOE's unique value is covalent docking and FBDD, which are specialized workflows. The SVL-only API is a development friction. Revisit when BioMate has a clear customer demand for covalent docking (e.g., KRAS inhibitor design, serine protease series). At that point, request a CCG academic license.

---

## Action Items

- [ ] Monitor user demand for covalent docking workflows — if 3+ early adopters ask, prioritize MOE
- [ ] Request 15-day MOE trial from CCG for development evaluation
- [ ] Survey if any beta institution already has a MOE site license
- [ ] Add `moe` to `LICENSE_REGISTRY` (implement credential UI but leave container unbuilt)
- [ ] Consider partnering with CCG — they run a cloud program for academic groups
