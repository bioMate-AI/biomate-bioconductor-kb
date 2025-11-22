# Quick Start: Multi-Source Dependency Converter

**Status**: ✅ READY TO USE
**Date**: 2025-11-20

## What It Does

Converts Galaxy workflows to complete, runnable Nextflow workflows with:
- ✅ Multi-source dependencies (Conda + Docker + Singularity + Modules)
- ✅ Accurate resource requirements (CPUs, memory, time)
- ✅ Complete environment.yml files
- ✅ nf-core style resource selectors

## How to Use

### 1. Test the Integration

```bash
cd /home/yzhang/biomate/backend/lib/galaxy/ai
python3 test_integrated_converter.py
```

Expected output:
```
✅ Conda directives
✅ Container directives (Docker/Singularity)
✅ Resource labels (process_low/medium/high)
✅ Conda environment.yml files
✅ INTEGRATION TEST COMPLETE!
```

### 2. Use in Your Code

```python
from galaxy.ai.workflow_converters.galaxy_converter import GalaxyToUnifiedConverter
from galaxy.ai.workflow_converters.nextflow_converter import UnifiedToNextflowConverter
from pathlib import Path
import json

# Load Galaxy workflow
with open("workflow.ga") as f:
    galaxy_workflow = json.load(f)

# Convert Galaxy → BUWF
galaxy_converter = GalaxyToUnifiedConverter()
unified = galaxy_converter.convert(galaxy_workflow)

# Convert BUWF → Nextflow (with multi-source support)
nextflow_converter = UnifiedToNextflowConverter(
    nfcore_base_dir=Path("/home/yzhang/biomate/backend/nf-core-workflows"),
    galaxy_tools_dir=Path("/home/yzhang/biomate/backend/database/shed_tools")
)

nextflow_files = nextflow_converter.convert(unified)

# Save files
for filepath, content in nextflow_files.items():
    output_path = Path("output") / filepath
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(content)
```

### 3. Run Generated Workflow

```bash
cd output

# Option 1: Use conda (default, no flags needed)
nextflow run main.nf

# Option 2: Use Docker
nextflow run main.nf -profile docker

# Option 3: Use Singularity
nextflow run main.nf -profile singularity

# Option 4: Use environment modules (uncomment module directives first)
nextflow run main.nf -with-module
```

## What Gets Generated

```
output/
├── main.nf                           # Main workflow
├── nextflow.config                   # Configuration with resource selectors
└── modules/
    ├── tool1/
    │   ├── main.nf                  # Process definition with all directives
    │   └── environment.yml          # Conda environment
    ├── tool2/
    │   ├── main.nf
    │   └── environment.yml
    └── ...
```

## Example Process Module

```groovy
process SALMON_QUANT {
    tag "$meta.id"
    label 'process_medium'  // 6 CPUs, 36GB RAM, 8h

    // PRIMARY: Conda (runs by default)
    conda "${moduleDir}/environment.yml"

    // OPTIONAL: Docker/Singularity (with -profile docker/singularity)
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/salmon:1.10.3'
        : 'biocontainers/salmon:1.10.3'}"

    // OPTIONAL: Modules (uncomment to use)
    // module 'salmon/1.10.3'

    input:
    tuple val(meta), path(reads)
    path index

    output:
    path "quant.sf", emit: results
    path "versions.yml", emit: versions

    script:
    """
    salmon quant -i $index -l A -r $reads -o .

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        salmon: \$(salmon --version | sed 's/salmon //')
    END_VERSIONS
    """
}
```

## Example environment.yml

```yaml
channels:
  - conda-forge
  - bioconda
dependencies:
  - salmon=1.10.3
```

## Example nextflow.config (Resource Selectors)

```groovy
process {
    withLabel: process_single {
        cpus = 1
        memory = 6.GB
        time = 4.h
    }

    withLabel: process_low {
        cpus = 2
        memory = 12.GB
        time = 4.h
    }

    withLabel: process_medium {
        cpus = 6
        memory = 36.GB
        time = 8.h
    }

    withLabel: process_high {
        cpus = 12
        memory = 72.GB
        time = 16.h
    }

    withLabel: process_high_memory {
        cpus = 12
        memory = 200.GB
        time = 16.h
    }
}

profiles {
    conda {
        conda.enabled = true
        conda.useMamba = true
    }

    docker {
        docker.enabled = true
    }

    singularity {
        singularity.enabled = true
    }
}
```

## How Resources Are Determined

### Priority Order:
1. **nf-core modules** (confidence: 1.0)
   - Reads actual resource labels from tested modules
   - Example: `label 'process_high'` → 12 CPUs, 72GB

2. **Galaxy XML GALAXY_SLOTS** (confidence: 0.7)
   - Extracts CPU hints from tool XML
   - Example: `${GALAXY_SLOTS:-4}` → 4 CPUs → process_low

3. **Category inference** (confidence: 0.5)
   - alignment → process_high
   - qc → process_low
   - quantification → process_medium

4. **Conservative default** (confidence: 0.3)
   - process_medium (6 CPUs, 36GB, 8h)

## How Dependencies Are Determined

### Priority Order:
1. **nf-core modules** (confidence: 1.0)
   - Copies exact container/conda specs from nf-core

2. **Galaxy requirements** (confidence: 0.95)
   - Reads `<requirement>` tags from tool XML
   - Maps to Bioconda packages

3. **Inference** (confidence: 0.8)
   - BioContainers naming convention
   - Galaxy ToolShed reference

4. **Fallback** (confidence: 0.5)
   - Generic ubuntu:latest container

## Files to Check

### Implementation:
- `/backend/lib/galaxy/ai/multi_source_dependency_converter.py`
- `/backend/lib/galaxy/ai/resource_resolver.py`
- `/backend/lib/galaxy/ai/workflow_converters/nextflow_converter.py`

### Test:
- `/backend/lib/galaxy/ai/test_integrated_converter.py`

### Documentation:
- `/research/MULTI_SOURCE_INTEGRATION_COMPLETE_20251120.md` (full details)
- `/research/QUICK_START_MULTI_SOURCE_CONVERTER.md` (this file)

## Troubleshooting

### Test fails with "Galaxy workflow not found"
- Check path in test script
- Available workflows in `/backend/galaxy_workflows_reformatted/*.ga`

### Import errors
- Make sure you're in `/backend/lib/galaxy/ai` directory
- Or run: `cd /home/yzhang/biomate/backend/lib/galaxy/ai && python3 test_integrated_converter.py`

### No conda specs generated
- Check if nf-core modules directory exists
- Check if tool has requirements in Galaxy XML
- Fallback will use tool name

### Resource labels all "process_medium"
- This is expected if:
  - Tool not in nf-core modules
  - No GALAXY_SLOTS in Galaxy XML
  - Category not recognized
- Conservative default is process_medium

## Key Advantages

1. **User Choice**: Generate ALL methods, user picks at runtime
2. **No Information Loss**: Everything from Galaxy is preserved or inferred
3. **Production Ready**: Resource requirements determined before execution
4. **nf-core Compatible**: Follows nf-core best practices
5. **Conda by Default**: Most common use case works out of the box
6. **Container Support**: Docker/Singularity available when needed
7. **Environment Modules**: HPC clusters can use modules

---

**Ready to use!** Run the test to verify everything works.
