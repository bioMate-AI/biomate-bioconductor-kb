# New Tools Infrastructure Analysis

**Date:** 2026-01-20
**Status:** Analysis Complete

---

## 1. Resource Requirements Summary

| Tool | GPU Required | VRAM | CPU/RAM | Disk | API Alternative |
|------|-------------|------|---------|------|-----------------|
| **State** | Optional | 8GB+ | 16GB RAM | 10GB | - |
| **Chai-1** | **Yes** | 24-80GB | 32GB RAM | 50GB | BioLM API |
| **Boltz-2** | **Yes** | 16-40GB | 32GB RAM | 30GB | - |
| **Evo 2** | **Yes** | 80GB+ (A100) | 64GB RAM | 100GB | **NVIDIA NIM** (40/min) |
| **DrugCLIP** | Optional | 8GB+ | 16GB RAM | 20GB | - |
| **scFv_Pmpnn_AF2** | **Yes** | 16GB+ | 32GB RAM | 50GB | - |
| **ProTrek** | Optional | 8GB+ | 16GB RAM | 20GB | **search-protrek.com** |
| **ProFam-1** | Optional | 8GB+ | 16GB RAM | 10GB | - |
| **SynCraft** | No | - | 8GB RAM | 5GB | **Gemini API** (required) |
| **AlphaFold 3** | **Yes** | 80GB+ | 64GB RAM | **1TB** | **alphafoldserver.com** (20/day) |

### Heavy Resource Tools (Require Dedicated GPU Server)
1. **AlphaFold 3** - 80GB VRAM, 1TB disk, A100/H100 recommended
2. **Evo 2** - 80GB VRAM for local, use NVIDIA NIM API instead
3. **Chai-1** - 24-80GB VRAM for optimal performance

### Moderate Resource Tools (Standard GPU)
4. **Boltz-2** - 16-40GB VRAM (RTX 3090/4090 or A100)
5. **scFv_Pmpnn_AF2** - 16GB VRAM

### Light Resource Tools (CPU or Small GPU)
6. **State** - Can run on CPU, GPU optional
7. **DrugCLIP** - CPU inference possible, GPU faster
8. **ProTrek** - 8GB VRAM or API
9. **ProFam-1** - 8GB VRAM
10. **SynCraft** - CPU only (uses Gemini API for LLM)

---

## 2. Recommended Deployment Strategy

### Tier 1: API-First (No Local GPU Required)
```
Tool            API Service             Rate Limit
─────────────────────────────────────────────────
AlphaFold 3     alphafoldserver.com     20/day
Evo 2           NVIDIA NIM              40/min
ProTrek         search-protrek.com      Unlimited
SynCraft        Gemini API              Required
```

### Tier 2: Standard Docker (16-24GB GPU)
```
Tool            Docker Image            GPU Memory
─────────────────────────────────────────────────
Boltz-2         biomate/boltz:latest    16GB
scFv_Pmpnn_AF2  biomate/scfv:latest     16GB
Chai-1          biomate/chai:latest     24GB (min)
```

### Tier 3: CPU/Light GPU Docker
```
Tool            Docker Image            Resources
─────────────────────────────────────────────────
State           biomate/state:latest    CPU/8GB GPU
DrugCLIP        biomate/drugclip:latest CPU/8GB GPU
ProFam-1        biomate/profam:latest   CPU/8GB GPU
```

---

## 3. Nextflow Integration Approach

### Option A: nf-core Module Style (Recommended)
Create modules following nf-core conventions:
```
modules/
└── biomate/
    ├── boltz/
    │   ├── main.nf
    │   ├── meta.yml
    │   └── Dockerfile
    ├── chai1/
    │   ├── main.nf
    │   ├── meta.yml
    │   └── Dockerfile
    └── ... (each tool)
```

### Example: Boltz-2 Nextflow Module
```nextflow
process BOLTZ_PREDICT {
    tag "$meta.id"
    label 'process_high'
    container 'biomate/boltz:2.0'

    input:
    tuple val(meta), path(fasta)
    path(ligand_yaml)

    output:
    tuple val(meta), path("*.pdb"), emit: structures
    tuple val(meta), path("*.json"), emit: scores
    path "versions.yml", emit: versions

    script:
    """
    boltz predict \\
        ${fasta} \\
        --output_dir results/ \\
        --diffusion_samples ${params.diffusion_samples ?: 5}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        boltz: \$(boltz --version | head -1)
    END_VERSIONS
    """
}
```

### Workflow Generation Strategy
For each tool, generate:
1. `main.nf` - Process definition
2. `meta.yml` - Metadata for nf-core
3. `nextflow.config` - Resource labels

---

## 4. Galaxy Integration

### Current Backend: Galaxy + Tool Shed
Tools need Galaxy XML wrappers in `/backend/tools/`:

```xml
<!-- tools/biomate_ai/boltz2/boltz2.xml -->
<tool id="boltz2" name="Boltz-2" version="2.0">
    <description>Protein-ligand structure prediction</description>
    <requirements>
        <container type="docker">biomate/boltz:2.0</container>
    </requirements>
    <command><![CDATA[
        boltz predict '$input_fasta'
        --output_dir output/
        --diffusion_samples $diffusion_samples
    ]]></command>
    <inputs>
        <param name="input_fasta" type="data" format="fasta" label="Protein sequence"/>
        <param name="diffusion_samples" type="integer" value="5" label="Diffusion samples"/>
    </inputs>
    <outputs>
        <data name="structure" format="pdb" from_work_dir="output/*.pdb"/>
        <data name="scores" format="json" from_work_dir="output/*.json"/>
    </outputs>
</tool>
```

### Galaxy Execution Flow
```
User Request → AI Assistant → Tool Search → Workflow Generation
                                    ↓
                            Galaxy Tool XML
                                    ↓
                         Docker Container Execution
                                    ↓
                              Output Files
```

---

## 5. Docker Container Requirements

### Multi-Architecture Build (ARM64 + x86_64)
```dockerfile
# Example: biomate/boltz:2.0
FROM --platform=$TARGETPLATFORM python:3.10-slim

ARG TARGETPLATFORM
ARG BUILDPLATFORM

RUN pip install boltz

# GPU support via NVIDIA base image for x86
# CPU-only for ARM64 (most ML tools)
```

### Build Commands
```bash
# Multi-arch build
docker buildx build --platform linux/amd64,linux/arm64 \
    -t biomate/boltz:2.0 \
    --push .
```

### Docker Status for New Tools
| Tool | Docker Image | ARM64 | x86_64 | Status |
|------|-------------|-------|--------|--------|
| State | biomate/state | ⚠️ | ⚠️ | **TODO** |
| Chai-1 | chai-discovery/chai | ❌ | ✅ | Official x86 only |
| Boltz-2 | biomate/boltz | ⚠️ | ⚠️ | **TODO** |
| Evo 2 | - | ❌ | ❌ | Use NVIDIA NIM API |
| DrugCLIP | biomate/drugclip | ⚠️ | ⚠️ | **TODO** |
| scFv_Pmpnn_AF2 | biomate/scfv | ⚠️ | ⚠️ | **TODO** |
| ProTrek | biomate/protrek | ⚠️ | ⚠️ | **TODO** |
| ProFam-1 | biomate/profam | ⚠️ | ⚠️ | **TODO** |
| SynCraft | biomate/syncraft | ✅ | ✅ | CPU-only, easy |
| AlphaFold 3 | - | ❌ | ❌ | Use API (CC-BY-NC-SA) |

---

## 6. MCP Server Status

| Server | Package | Install Command | Status |
|--------|---------|-----------------|--------|
| Boltz | tooluniverse | Already in ToolUniverse | ✅ Ready |
| Chai-1 | chai-lab | `pip install chai-lab` | ⚠️ Needs install |
| AlphaFold | alphafold-mcp-server | `pip install alphafold-mcp-server` | ⚠️ Needs install |

---

## 7. Action Items

### Immediate (This Session)
1. [ ] Create Docker directory structure for new tools
2. [ ] Build x86 Docker images for API-light tools
3. [ ] Install and test Boltz MCP server
4. [ ] Test Chai-1 MCP server (if installable)

### Short-term
5. [ ] Create Nextflow modules for each tool
6. [ ] Create Galaxy XML wrappers for each tool
7. [ ] Build ARM64 images for CPU-compatible tools

### Medium-term
8. [ ] Set up GPU server for heavy tools
9. [ ] Configure API routing for Evo 2, AlphaFold 3
10. [ ] Integration testing with full workflows

---

## 8. Completed Infrastructure (2026-01-20)

### Docker Images Created
```
backend/docker/biomate-ai-tools/
├── boltz/Dockerfile         # GPU: 16-40GB VRAM
├── state/Dockerfile         # CPU/GPU optional
├── drugclip/Dockerfile      # CPU/GPU optional
├── syncraft/Dockerfile      # CPU only (Gemini API)
├── chai1/                   # TODO: needs 24-80GB GPU
├── protrek/                 # TODO: CPU/8GB GPU
├── profam/                  # TODO: CPU/8GB GPU
├── scfv-pmpnn/             # TODO: 16GB GPU
└── build-all.sh            # Multi-arch build script
```

### Galaxy XML Wrappers Created
```
backend/tools/biomate_ai_tools/
├── boltz2.xml              # Structure prediction
├── drugclip.xml            # Virtual screening
├── state.xml               # Perturbation prediction
├── protrek.xml             # Protein search
└── tool_conf.xml           # Tool registration
```

### Nextflow Modules Created
```
backend/nf-core-workflows/modules/biomate/
├── boltz/main.nf           # BOLTZ_PREDICT, BOLTZ_AFFINITY
├── boltz/meta.yml          # nf-core metadata
├── state/main.nf           # STATE_PREDICT, STATE_EMBED
├── nextflow.config         # Resource labels & defaults
├── alphafold3/             # TODO
├── chai1/                  # TODO
├── drugclip/              # TODO
└── protrek/               # TODO
```

### MCP Servers Status
```
auto_update/mcp_servers/
└── AlphaFold-MCP-Server/   # ✓ Built and ready (Node.js)
    └── build/index.js      # Run: node build/index.js

ToolUniverse (existing):
└── remote/boltz/           # ✓ Ready (Python)
    └── boltz_mcp_server.py # Requires boltz package installed
```

---

## 9. Answers to User Questions

### Q1: How to integrate into Nextflow?
**Answer:** Use nf-core style modules in `modules/biomate/<tool>/main.nf`
- Each tool has a process definition with container reference
- Resource labels defined in `nextflow.config`
- Can be included in any Nextflow workflow

### Q2: Should we generate Nextflow workflow folder for each tool?
**Answer:** No, use **module-based approach** (already created)
- Tools are individual processes, not workflows
- Workflows combine multiple tools (e.g., structure → docking → scoring)
- Create workflow files in `workflows/` that import these modules

### Q3: How to execute them in Galaxy?
**Answer:** Use Galaxy XML wrappers (already created)
- Wrappers in `tools/biomate_ai_tools/*.xml`
- Register in `tool_conf.xml`
- Galaxy executes via Docker containers

### Q4: Resource consumption?
**Answer:** See Section 1 table. Summary:
- **Light (CPU/8GB):** State, DrugCLIP, ProTrek, ProFam, SynCraft
- **Medium (16-24GB GPU):** Boltz-2, scFv_Pmpnn_AF2, Chai-1 (min)
- **Heavy (80GB+ GPU):** AlphaFold 3, Evo 2, Chai-1 (optimal)
- **Recommend APIs** for Evo 2 (NVIDIA NIM), AlphaFold 3 (server)

### Q5: Docker for ARM64 + x86?
**Answer:** Partially complete
- **x86 GPU:** Boltz, State, DrugCLIP, SynCraft Dockerfiles ready
- **ARM64:** CPU-only tools (State, DrugCLIP, SynCraft) can work
- **Multi-arch build:** Use `build-all.sh` with buildx
- Note: Most ML tools are x86 GPU only (CUDA dependency)

### Q6: MCP Server Status?
**Answer:**
- **AlphaFold MCP:** ✓ Installed and built (`node build/index.js`)
- **Boltz MCP:** ✓ Available in ToolUniverse (requires boltz package)
- **Chai-1 MCP:** ⚠️ Not available (chai-lab has Python API, no MCP)
