# Biomni Nextflow Docker Configuration Guide

**Date:** 2025-12-04
**Author:** BioMate Team

---

## Overview

This document describes how to run Biomni Nextflow workflows with the `biomate/biotools:arm64` Docker container.

## Conversion Summary

- **Total Biomni workflows converted:** 397
- **Valid Nextflow syntax:** 395 (99.5%)
- **Output location:** `/home/yzhang/biomate/Biomni/biomni_nextflow/`

---

## Problem Statement

The `biomate/biotools:arm64` Docker container has three issues that need to be addressed:

1. **Broken entrypoint** - The container has a custom entrypoint (`/usr/local/bin/biotools-shell`) that doesn't exist
2. **Python not in PATH** - Python is installed in a conda environment at `/opt/conda/envs/biotools/bin/python`, not in the standard PATH
3. **Biomni not installed** - The Biomni Python module is not pre-installed inside the container

---

## Solution

### Step 1: Create `nextflow.config`

Create a `nextflow.config` file in your working directory:

```groovy
docker.enabled = true
docker.runOptions = '-u $(id -u):$(id -g) --entrypoint "" -v /home/yzhang/biomate/Biomni:/app/Biomni:ro'

process {
    withLabel: 'process_low' {
        cpus = 1
        memory = '2 GB'
    }
    withLabel: 'process_medium' {
        cpus = 2
        memory = '4 GB'
    }
}
```

### Configuration Options Explained

| Option | Purpose |
|--------|---------|
| `docker.enabled = true` | Enable Docker execution for all processes |
| `-u $(id -u):$(id -g)` | Run container as current user to avoid file permission issues |
| `--entrypoint ""` | Override the broken default entrypoint, use shell instead |
| `-v /home/yzhang/biomate/Biomni:/app/Biomni:ro` | Mount Biomni source code into container at `/app/Biomni` (read-only) |

---

### Step 2: Workflow Script Requirements

In the Nextflow `.nf` file, use the full Python path and add Biomni to the Python path:

```groovy
process COUNT_BACTERIAL_COLONIES {
    tag "${image_path.baseName}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biotools:arm64'

    input:
    path(image_path)

    output:
    path("colony_count_results.json"), emit: results
    path("colony_count_output.txt"), emit: output

    script:
    """
    /opt/conda/envs/biotools/bin/python << 'PYEOF'
import json
import sys
sys.path.insert(0, '/app/Biomni')  # Add mounted Biomni to Python path

from biomni.tool.microbiology import count_bacterial_colonies

# Run the tool
result = count_bacterial_colonies(
    image_path="${image_path}",
    dilution_factor=${params.dilution_factor},
    plate_area_cm2=${params.plate_area_cm2},
    output_dir="."
)

# Save results
with open("colony_count_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

with open("colony_count_output.txt", "w") as f:
    f.write(str(result))

print("Completed successfully")
PYEOF
    """
}
```

**Key points:**
- Use `/opt/conda/envs/biotools/bin/python` (full path to Python in conda)
- Add `sys.path.insert(0, '/app/Biomni')` to import Biomni modules
- Use heredoc (`<< 'PYEOF'`) for multi-line Python scripts

---

### Step 3: Running the Workflow

```bash
# Navigate to working directory containing nextflow.config
cd /tmp/nf_real_test

# Run the workflow
nextflow run /path/to/workflow.nf \
  --image_path /path/to/input.png \
  --outdir ./results
```

---

## Example: Complete Test Run

### 1. Setup test directory
```bash
mkdir -p /tmp/nf_real_test
cd /tmp/nf_real_test
```

### 2. Create nextflow.config
```bash
cat > nextflow.config << 'EOF'
docker.enabled = true
docker.runOptions = '-u $(id -u):$(id -g) --entrypoint "" -v /home/yzhang/biomate/Biomni:/app/Biomni:ro'

process {
    withLabel: 'process_low' {
        cpus = 1
        memory = '2 GB'
    }
    withLabel: 'process_medium' {
        cpus = 2
        memory = '4 GB'
    }
}
EOF
```

### 3. Create test input image
```bash
python3 -c "
from PIL import Image
import random

img = Image.new('RGB', (400, 400), 'white')
pixels = img.load()

# Add random dark spots (simulating colonies)
for _ in range(50):
    x, y = random.randint(10, 390), random.randint(10, 390)
    for dx in range(-3, 4):
        for dy in range(-3, 4):
            if 0 <= x+dx < 400 and 0 <= y+dy < 400:
                pixels[x+dx, y+dy] = (50, 50, 50)

img.save('test_plate.png')
print('Test image created')
"
```

### 4. Run the workflow
```bash
nextflow run /home/yzhang/biomate/Biomni/biomni_nextflow/subworkflows/microbiology/count_bacterial_colonies.nf \
  --image_path /tmp/nf_real_test/test_plate.png \
  --outdir /tmp/nf_real_test/results
```

### 5. Expected output
```
executor >  local (2)
[10/e4c8e8] BIOMNI_MICROBIOLOGY_COUNT_BACTERIAL_COLONIES:COUNT_BACTERIAL_COLONIES (test_plate) | 1 of 1 ✔
[26/7a60d1] BIOMNI_MICROBIOLOGY_COUNT_BACTERIAL_COLONIES:CONCATENATE_OUTPUT                    | 1 of 1 ✔
```

### 6. Check results
```bash
cat /tmp/nf_real_test/results/colony_count_output.txt
```

Output:
```
Colony Count Results
==================================================
Date and Time: 2025-12-04 11:23:35
Input Image: test_plate.png
Dilution Factor: 1
Plate Area: 65.0 cm²

Results:
- Total Colony Count: 46 CFUs
- Concentration: 46.00 CFU/ml
- Area Density: 0.71 CFU/cm²
```

---

## File Structure

```
Working Directory:
├── nextflow.config          # Docker configuration
├── test_plate.png           # Input file
├── work/                    # Nextflow work directory (auto-created)
│   └── xx/xxxxxx/           # Process-specific work dirs
└── results/                 # Output directory
    ├── colony_count_results.json
    ├── colony_count_output.txt
    └── final_output.txt

Biomni Nextflow Workflows:
/home/yzhang/biomate/Biomni/biomni_nextflow/
├── subworkflows/
│   ├── biochemistry/
│   ├── bioengineering/
│   ├── bioimaging/
│   ├── biophysics/
│   ├── cancer_biology/
│   ├── cell_biology/
│   ├── database/
│   ├── genetics/
│   ├── genomics/
│   ├── glycoengineering/
│   ├── immunology/
│   ├── lab_automation/
│   ├── literature/
│   ├── microbiology/
│   ├── molecular_biology/
│   ├── pathology/
│   ├── pharmacology/
│   ├── physiology/
│   ├── protocols/
│   └── structural_biology/
└── workflows/
    └── [similar categories]
```

---

## Alternative: Build Custom Docker Image

Instead of mounting Biomni at runtime, you can build a Docker image with Biomni pre-installed:

### Dockerfile
```dockerfile
FROM biomate/biotools:arm64

# Copy Biomni source code
COPY Biomni /app/Biomni

# Add to Python path
ENV PYTHONPATH=/app/Biomni:$PYTHONPATH

# Override broken entrypoint
ENTRYPOINT []
```

### Build and use
```bash
docker build -t biomate/biotools-biomni:arm64 .
```

Then simplify `nextflow.config`:
```groovy
docker.enabled = true
docker.runOptions = '-u $(id -u):$(id -g)'

process {
    container = 'biomate/biotools-biomni:arm64'
}
```

---

## Troubleshooting

### Error: `exec /usr/local/bin/biotools-shell: no such file or directory`
**Cause:** Container's default entrypoint is broken
**Solution:** Add `--entrypoint ""` to docker.runOptions

### Error: `python3: command not found`
**Cause:** Python is in conda environment, not in PATH
**Solution:** Use full path `/opt/conda/envs/biotools/bin/python`

### Error: `ModuleNotFoundError: No module named 'biomni'`
**Cause:** Biomni is not installed in container
**Solution:** Mount Biomni with `-v /path/to/Biomni:/app/Biomni:ro` and add `sys.path.insert(0, '/app/Biomni')` in Python script

### Error: Permission denied on output files
**Cause:** Container running as root creates files owned by root
**Solution:** Add `-u $(id -u):$(id -g)` to run as current user

---

## Related Files

- Converter: `/home/yzhang/biomate/backend/lib/galaxy/ai/llm_workflow_converter.py`
- Galaxy job config: `/home/yzhang/biomate/backend/config/job_conf.yml`
- Conversion error report: `/home/yzhang/biomate/Biomni/conversion_error_report.json`
