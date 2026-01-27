# Lessons Learned: Creating Nextflow nf-core Style Workflows

This document captures lessons learned, common pitfalls, and best practices from developing 237 Nextflow workflows for the Biomni bioinformatics platform.

---

## Table of Contents

1. [Critical: Nextflow Script Block vs Python Docstrings](#1-critical-nextflow-script-block-vs-python-docstrings)
2. [Parameter Mapping and Environment Variables](#2-parameter-mapping-and-environment-variables)
3. [Docker Volume Mounting](#3-docker-volume-mounting)
4. [Self-Contained Implementations](#4-self-contained-implementations)
5. [Error Handling Patterns](#5-error-handling-patterns)
6. [Type Conversion for Parameters](#6-type-conversion-for-parameters)
7. [File Path Handling](#7-file-path-handling)
8. [Testing Strategies](#8-testing-strategies)
9. [Common Compilation Errors](#9-common-compilation-errors)
10. [nf-core Module Structure](#10-nf-core-module-structure)

---

## 1. Critical: Nextflow Script Block vs Python Docstrings

### The Problem

Nextflow uses triple double-quotes (`"""`) to delimit the script block. Python also uses triple double-quotes for docstrings. When embedding Python code in a Nextflow script block, Python docstrings will **prematurely close** the Nextflow script block.

### Example of the Bug

```nextflow
process MY_PROCESS {
    script:
    """
    python3 << 'PYEOF'
class MyClass:
    """This docstring closes the Nextflow script block!"""  # BUG!

    def method(self):
        pass
PYEOF
    """
}
```

This causes a cryptic error:
```
Script compilation error
- cause: Unexpected input: '{' @ line X, column Y
```

### The Solution

**Always use single-quoted docstrings (`'''...'''`) in embedded Python code:**

```nextflow
process MY_PROCESS {
    script:
    """
    python3 << 'PYEOF'
class MyClass:
    '''This docstring is safe - uses single quotes.'''

    def method(self):
        '''Method docstring with single quotes.'''
        pass
PYEOF
    """
}
```

### Automated Fix Script

```python
# Replace triple double-quote docstrings with single quotes
import re

def fix_docstrings(content):
    # Pattern to find Python docstrings (triple double quotes)
    # Be careful not to replace the Nextflow script block delimiters

    # Replace """...""" with '''...''' inside PYEOF blocks
    in_pyeof = False
    lines = content.split('\n')
    fixed_lines = []

    for line in lines:
        if "python3 << 'PYEOF'" in line or 'python3 << "PYEOF"' in line:
            in_pyeof = True
        elif line.strip() == 'PYEOF':
            in_pyeof = False

        if in_pyeof:
            # Replace docstring delimiters
            line = line.replace('"""', "'''")

        fixed_lines.append(line)

    return '\n'.join(fixed_lines)
```

---

## 2. Parameter Mapping and Environment Variables

### The Pattern

Nextflow parameters are passed to Python via environment variables:

```nextflow
// Parameters section
params.input_file = null
params.output_dir = './results'
params.threshold = 0.5

process MY_PROCESS {
    script:
    """
    # Export parameters as environment variables
    export PARAM_INPUT_FILE="${params.input_file?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: './results'}"
    export PARAM_THRESHOLD="${params.threshold?.toString()?.replace('"', '\\"') ?: '0.5'}"

    python3 << 'PYEOF'
import os

input_file = os.environ.get("PARAM_INPUT_FILE")
output_dir = os.environ.get("PARAM_OUTPUT_DIR", "./results")
threshold = float(os.environ.get("PARAM_THRESHOLD", "0.5"))
PYEOF
    """
}
```

### Common Mistakes

1. **Mismatched parameter names**: The Nextflow param name must match the export name
   ```nextflow
   // WRONG: params.moving_images_dir but export PARAM_MOVING_IMAGE_PATH
   params.moving_images_dir = null
   export PARAM_MOVING_IMAGE_PATH="${params.moving_image_path...}"  # Wrong!

   // CORRECT:
   params.moving_images_dir = null
   export PARAM_MOVING_IMAGES_DIR="${params.moving_images_dir...}"
   ```

2. **Missing exports**: Every parameter used in Python must be exported

3. **Forgetting default values**: Always provide sensible defaults
   ```nextflow
   // With default
   export PARAM_METRIC="${params.metric?.toString()?.replace('"', '\\"') ?: 'mutual_information'}"
   ```

---

## 3. Docker Volume Mounting

### The Problem

Docker containers cannot access host filesystem paths by default. Files must be mounted.

### Solution in nextflow.config

```groovy
profiles {
    docker {
        docker.enabled = true
        docker.runOptions = '-u $(id -u):$(id -g) -v /tmp:/tmp -v ${PWD}/test_data:${PWD}/test_data'
        singularity.enabled = false
    }
}
```

### Key Points

1. **Mount /tmp**: Many workflows use /tmp for intermediate files
2. **Mount test_data**: For testing with local test files
3. **User mapping**: `-u $(id -u):$(id -g)` preserves file ownership
4. **PWD expansion**: `${PWD}` expands at runtime to current directory

### Testing File Access

```bash
# Verify files are accessible inside container
docker run --rm -v /tmp:/tmp biomate/biomni-tools:latest \
    python3 -c "import os; print(os.path.exists('/tmp/myfile.nii.gz'))"
```

---

## 4. Self-Contained Implementations

### Principle

Each workflow should be **completely self-contained** - no external library imports that aren't in the container.

### Anti-Pattern (Avoid)

```python
# BAD: Importing from external biomni library
from biomni.tool.bioimaging import ImageRegistrationTool

tool = ImageRegistrationTool()
```

### Correct Pattern

```python
# GOOD: Self-contained implementation
import SimpleITK as sitk
import numpy as np

class ImageRegistrationTool:
    '''Medical image registration using SimpleITK.'''

    def __init__(self):
        '''Initialize the ImageRegistrationTool.'''
        self.supported_formats = [".nii", ".nii.gz", ".nrrd", ".mha", ".mhd"]

    def load_image(self, image_path):
        '''Load a medical image using SimpleITK.'''
        if not os.path.exists(image_path):
            raise FileNotFoundError(f"Image file not found: {image_path}")
        return sitk.ReadImage(image_path)

    # ... rest of implementation
```

### Benefits

1. No dependency on external package versions
2. Easier to debug and maintain
3. Container only needs standard scientific Python packages
4. Portable across environments

---

## 5. Error Handling Patterns

### Standard Output Format

Every workflow should produce:
1. `{function_name}_results.json` - Machine-readable results
2. `{function_name}_output.txt` - Human-readable output
3. `versions.yml` - Software versions

### Error Handling Template

```python
# Execute the function
try:
    result = my_function(
        param1=auto_convert(os.environ.get("PARAM_1", "")),
        param2=auto_convert(os.environ.get("PARAM_2", "")),
    )
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# Save results
output_data = {
    "success": success,
    "function": "my_function",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("my_function_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("my_function_output.txt", "w") as f:
    f.write("Biomni: My Function" + NL)
    f.write("=" * 60 + NL + NL)
    if success:
        if isinstance(result, dict):
            for key, value in result.items():
                f.write(f"{key}: {value}" + NL)
        else:
            f.write(str(result))
    else:
        f.write(f"ERROR: {error_msg}" + NL)

if not success:
    exit(1)
```

### Graceful Degradation

For optional dependencies, handle ImportError gracefully:

```python
try:
    from nnunet.inference.predict import predict_from_folder
    NNUNET_AVAILABLE = True
except ImportError:
    predict_from_folder = None
    NNUNET_AVAILABLE = False

def segment_images(...):
    if not NNUNET_AVAILABLE:
        raise ImportError("nnunet is not installed. Install with: pip install nnunet")
    # ... rest of function
```

---

## 6. Type Conversion for Parameters

### The Problem

Environment variables are always strings. Need to convert to appropriate Python types.

### Universal Auto-Convert Function

```python
def auto_convert(val):
    '''Auto-convert string to appropriate type.'''
    if val is None or val == '' or val == 'null':
        return None

    # Try bool
    if isinstance(val, str) and val.lower() in ('true', 'false'):
        return val.lower() == 'true'

    # Try JSON for lists and dicts
    if isinstance(val, str) and val.strip().startswith(('[', '{')):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            pass

    # Try int
    try:
        if isinstance(val, str) and '.' not in val:
            return int(val)
    except ValueError:
        pass

    # Try float
    try:
        return float(val)
    except ValueError:
        pass

    # Return as string
    return val
```

### Usage

```python
result = my_function(
    threshold=auto_convert(os.environ.get("PARAM_THRESHOLD", "0.5")),
    enabled=auto_convert(os.environ.get("PARAM_ENABLED", "true")),
    items=auto_convert(os.environ.get("PARAM_ITEMS", "[1, 2, 3]")),
)
```

---

## 7. File Path Handling

### Best Practices

1. **Always check file existence before processing**:
   ```python
   if not os.path.exists(input_path):
       raise FileNotFoundError(f"Input file not found: {input_path}")
   ```

2. **Create output directories**:
   ```python
   os.makedirs(output_dir, exist_ok=True)
   ```

3. **Handle .nii.gz double extension**:
   ```python
   def get_basename(path):
       name = os.path.basename(path)
       if name.endswith('.nii.gz'):
           return name[:-7]  # Remove .nii.gz
       return os.path.splitext(name)[0]
   ```

4. **Use absolute paths in results**:
   ```python
   results = {
       "output_file": os.path.abspath(output_path),
   }
   ```

---

## 8. Testing Strategies

### Creating Mock Test Data

For bioimaging workflows, create mock NIfTI files:

```python
import nibabel as nib
import numpy as np

def create_mock_nifti(path, shape=(64, 64, 32)):
    '''Create a mock 3D NIfTI file.'''
    data = np.random.randn(*shape).astype(np.float32) * 10 + 50

    # Add sphere structures
    for _ in range(5):
        cx, cy, cz = [np.random.randint(10, s-10) for s in shape]
        radius = np.random.randint(5, 15)
        for x in range(max(0, cx-radius), min(shape[0], cx+radius)):
            for y in range(max(0, cy-radius), min(shape[1], cy+radius)):
                for z in range(max(0, cz-radius), min(shape[2], cz+radius)):
                    if np.sqrt((x-cx)**2 + (y-cy)**2 + (z-cz)**2) < radius:
                        data[x, y, z] = np.random.randint(100, 200)

    affine = np.eye(4)
    img = nib.Nifti1Image(data, affine)
    nib.save(img, path)
```

### Test Execution Pattern

```bash
# 1. Generate test data (if needed)
docker run --rm -v $(pwd)/test_data:/data biomate/biomni-tools:latest \
    python3 /data/create_mock_nifti.py

# 2. Copy test files to accessible location
cp test_data/*.nii.gz /tmp/

# 3. Run workflow
nextflow run subworkflows/bioimaging/my_workflow/main.nf \
    -profile docker \
    --input_file "/tmp/mock_input.nii.gz" \
    --output_dir "/tmp/output"

# 4. Verify results
cat results/run/my_workflow_results.json
```

### Verification Checklist

- [ ] Workflow compiles without errors
- [ ] JSON results file created with `"success": true`
- [ ] Output files exist at expected paths
- [ ] Human-readable output is meaningful
- [ ] versions.yml contains correct version info

---

## 9. Common Compilation Errors

### Error: "Unexpected input: '{'"

**Cause**: Usually Python docstrings closing the Nextflow script block early.

**Fix**: Use single-quoted docstrings (`'''...'''`).

### Error: "Missing process or workflow"

**Cause**: Syntax error in Nextflow DSL2 structure.

**Check**:
- `nextflow.enable.dsl = 2` at top
- Proper `process` and `workflow` blocks
- Matching braces

### Error: "No such variable: params.xxx"

**Cause**: Parameter not declared in params section.

**Fix**: Add to params block:
```nextflow
params.my_param = null
```

### Error: "here-document at line X delimited by end-of-file"

**Cause**: Unclosed heredoc in script block.

**Check**:
- Matching `PYEOF` markers
- Matching `END_VERSIONS` markers
- No extra quotes breaking the heredoc

---

## 10. nf-core Module Structure

### Directory Layout

```
subworkflows/
└── domain/
    └── workflow_name/
        ├── main.nf          # Main workflow file
        ├── meta.yml         # Metadata (optional)
        └── tests/           # Test files (optional)
            ├── main.nf.test
            └── test_data/
```

### main.nf Template

```nextflow
#!/usr/bin/env nextflow
/*
 * domain/workflow_name
 * Brief description of what this workflow does.
 *
 * nf-core style module
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.input_file = null
params.output_dir = null

process WORKFLOW_NAME {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("workflow_name_results.json"), emit: results
    tuple val(meta), path("workflow_name_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters
    export PARAM_INPUT_FILE="${params.input_file?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Self-contained Python implementation here
import json
import os

def auto_convert(val):
    # ... type conversion
    pass

def workflow_function(input_file, output_dir):
    '''Main workflow function.'''
    # Implementation
    return {"result": "success"}

# Execute
try:
    result = workflow_function(
        input_file=auto_convert(os.environ.get("PARAM_INPUT_FILE")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR")),
    )
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# Output handling...
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        biomni_function: "workflow_name"
    END_VERSIONS
    """
}

workflow WORKFLOW_NAME_WORKFLOW {
    take:
    ch_input

    main:
    WORKFLOW_NAME(ch_input)

    emit:
    results = WORKFLOW_NAME.out.results
    output = WORKFLOW_NAME.out.output
    versions = WORKFLOW_NAME.out.versions
}

// Entry workflow for standalone execution
workflow {
    ch_input = Channel.of([id: 'run'])
    WORKFLOW_NAME_WORKFLOW(ch_input)
    WORKFLOW_NAME_WORKFLOW.out.output.view { "Output: $it" }
}
```

---

## Quick Reference: Checklist for New Workflows

- [ ] Use `nextflow.enable.dsl = 2`
- [ ] Declare all params with defaults
- [ ] Export all params as environment variables
- [ ] Use single-quoted docstrings (`'''`) in Python code
- [ ] Include `auto_convert()` function for type conversion
- [ ] Handle errors with try/except and proper JSON output
- [ ] Create both JSON and TXT output files
- [ ] Include versions.yml
- [ ] Test with Docker profile
- [ ] Verify file paths are accessible in container

---

## Appendix: Test Results Summary

### Bioimaging Workflows (10 total)

| Workflow | Status | Notes |
|----------|--------|-------|
| preprocess_image | PASS | |
| calculate_similarity_metrics | PASS | |
| quick_rigid_registration | PASS | |
| quick_affine_registration | PASS | |
| quick_deformable_registration | PASS | |
| split_modalities | PASS | |
| batch_register_images | PASS | Fixed parameter mapping |
| prepare_input_for_nnunet | PASS | |
| segment_with_nn_unet | EXPECTED FAIL | nnunet not installed |
| create_segmentation_visualization | PASS | |

---

## 11. Handling None Parameters

### The Problem

When workflows are run without all required parameters, `auto_convert()` returns `None`. Using `None` in calculations or method calls causes errors like:
- `unsupported operand type(s) for *: 'NoneType' and 'float'`
- `'NoneType' object has no attribute 'get'`

### The Fix

Add validation at the start of every function that uses numeric parameters:

```python
def my_function(param1, param2, param3=10.0):
    '''My function description.'''
    # Validate inputs - use sensible defaults if None
    if param1 is None:
        param1 = 1.0  # default value
    if param2 is None:
        param2 = 100.0  # default value
    if param3 is None:
        param3 = 10.0

    # Convert to expected types
    param1, param2, param3 = float(param1), float(param2), float(param3)

    # Now safe to use in calculations
    result = param1 * param2 / param3
    return {"result": result}
```

### For Dict Parameters

```python
def my_function(config_dict):
    '''Function expecting a dict parameter.'''
    # Ensure config_dict is a dict
    if config_dict is None or not isinstance(config_dict, dict):
        config_dict = {"default_key": "default_value"}

    # Now safe to use .get() and other dict methods
    value = config_dict.get("some_key", "fallback")
```

### For List Parameters

```python
def my_function(items_list):
    '''Function expecting a list parameter.'''
    if items_list is None:
        items_list = []
    if not isinstance(items_list, list):
        items_list = [items_list]  # Wrap single item in list

    # Now safe to iterate
    for item in items_list:
        process(item)
```

---

## 12. Python 3.10+ Compatibility

### The Problem

Python 3.10 removed direct access to `collections.MutableMapping`, `collections.Mapping`, etc. They must now be accessed via `collections.abc`.

Libraries like `FlowCytometryTools` that use the old style will fail with:
```
module 'collections' has no attribute 'MutableMapping'
```

### The Fix

Add this compatibility shim at the **very beginning** of the Python code (before any imports that might use collections):

```python
# Python 3.10+ compatibility fix for collections.MutableMapping
import collections
import collections.abc
if not hasattr(collections, 'MutableMapping'):
    collections.MutableMapping = collections.abc.MutableMapping
if not hasattr(collections, 'Mapping'):
    collections.Mapping = collections.abc.Mapping
if not hasattr(collections, 'MutableSet'):
    collections.MutableSet = collections.abc.MutableSet
if not hasattr(collections, 'Iterable'):
    collections.Iterable = collections.abc.Iterable
if not hasattr(collections, 'Sequence'):
    collections.Sequence = collections.abc.Sequence
```

### Affected Workflows

- analyze_flow_cytometry_immunophenotyping
- analyze_cell_senescence_and_apoptosis
- analyze_cfse_cell_proliferation
- analyze_cytokine_production_in_cd4_tcells

---

## Appendix B: Error Categories from Testing

### Category 1: Missing Test Data/Files
| Workflow | Missing File |
|----------|-------------|
| analyze_comparative_genomics_and_haplotypes | /data/genomes/hg38.fa |
| analyze_myofiber_morphology | test_image.png |
| retrieve_topk_repurposing_drugs_from_disease_txgnn | /data/txgnn_name_mapping.pkl |
| analyze_barcode_sequencing_data | input.txt |

### Category 2: Missing Python Packages
| Workflow | Missing Package |
|----------|----------------|
| predict_admet_properties | descriptastorus, pandas-flavor |
| segment_with_nn_unet | nnunet |
| analyze_flow_cytometry_immunophenotyping | Python 3.10+ collections.abc fix |
| analyze_cell_senescence_and_apoptosis | Python 3.10+ collections.abc fix |
| analyze_cytokine_production_in_cd4_tcells | Python 3.10+ collections.abc fix |

### Category 3: Missing System Tools
| Workflow | Missing Tool |
|----------|-------------|
| detect_and_annotate_somatic_mutations | gatk |
| detect_and_characterize_structural_variations | samtools |

### Category 4: Parameter/Function Signature Mismatches
| Workflow | Wrong Parameter |
|----------|----------------|
| get_coding_sequences | refseq_id |
| is_region_fully_covered | covered_regions |
| apply_vcog_grade | symptom |
| find_orfs_in_frame | dna_sequence |
| default_whole_cell_model | t |
| dimerization_odes | t |
| first_order | k |
| norm_chr | x |
| is_position_covered | pos |

### Category 5: Implementation Bugs
| Workflow | Error Type |
|----------|-----------|
| simulate_microbial_population_dynamics | list vs int |
| model_protein_dimerization_network | list has no keys |
| optimize_codons_for_heterologous_expression | float has no get |
| cosinor_model | NoneType operations |
| michaelis_menten | NoneType operations |
| get_hpo_names | parse_hpo_obo not defined |
| analyze_bifurcation_diagram | len() of unsized object |
| simulate_protein_signaling_network | unpacking error |

### Category 6: Permission Issues
| Workflow | Issue |
|----------|-------|
| generate_gene_embeddings_with_ESM_models | /.cache permission denied |

---

*Document last updated: 2026-01-26*
