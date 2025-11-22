# Nextflow Converter Quality Analysis: Information Loss & Validation
**Date**: 2025-11-19
**Focus**: DSL2 Syntax, Conversion Fidelity, and Quality Assurance

---

## Executive Summary

**Your concern is ABSOLUTELY VALID** ✅

The current Nextflow converters **DO LOSE INFORMATION** during conversion. This document:
1. Documents Nextflow DSL2 syntax completely
2. Identifies exactly what information is lost
3. Provides strategies to ensure conversion quality
4. Explains the multi-file structure of Nextflow workflows

**Key Finding**: Current converters are **SIMPLIFIED** versions suitable for **workflow visualization and understanding**, but **NOT for production execution** without manual review.

---

## 1. Nextflow DSL2 Complete Structure

### **Official Documentation**

**Primary Sources**:
- Nextflow Official Docs: https://www.nextflow.io/docs/latest/index.html
- DSL2 Migration Guide: https://www.nextflow.io/docs/latest/dsl2.html
- nf-core Style Guide: https://nf-co.re/docs/contributing/guidelines/pipelines/requirements/dsl2_workflow_structure

**What We Have Locally**:
```bash
# nf-core RNA-seq documentation
/home/yzhang/biomate/backend/nf-core-workflows/rnaseq/README.md
/home/yzhang/biomate/backend/nf-core-workflows/rnaseq/CHANGELOG.md
/home/yzhang/biomate/backend/nf-core-workflows/rnaseq/docs/

# Working examples
/home/yzhang/biomate/backend/nf-core-workflows/rnaseq/workflows/rnaseq.nf
/home/yzhang/biomate/backend/nf-core-workflows/rnaseq/subworkflows/nf-core/*/main.nf
/home/yzhang/biomate/backend/nf-core-workflows/rnaseq/modules/nf-core/*/main.nf
```

---

### **Nextflow DSL2 Complete File Structure**

A complete nf-core workflow consists of **MULTIPLE FILES**:

```
workflow-name/
├── main.nf                      # Entry point
├── nextflow.config              # Configuration
├── workflows/
│   └── workflow-name.nf         # Main workflow logic
├── subworkflows/
│   ├── local/                   # Custom subworkflows
│   │   └── my_subworkflow.nf
│   └── nf-core/                 # Shared subworkflows
│       └── quantify_pseudo_alignment/
│           ├── main.nf          # Subworkflow definition
│           ├── meta.yml         # Metadata
│           ├── nextflow.config  # Subworkflow config
│           └── tests/           # Test configs
├── modules/
│   ├── local/                   # Custom modules
│   │   └── my_tool.nf
│   └── nf-core/                 # Shared modules
│       └── fastqc/
│           ├── main.nf          # Process definition
│           ├── meta.yml         # Metadata
│           ├── environment.yml  # Conda environment
│           └── tests/           # Test configs
├── bin/                         # Custom scripts
│   └── my_script.py
├── lib/                         # Groovy libraries
│   └── Utils.groovy
├── conf/                        # Additional configs
│   ├── base.config
│   ├── modules.config
│   └── test.config
├── assets/                      # Assets (schemas, etc.)
│   └── schema.json
└── docs/                        # Documentation
    └── usage.md
```

**Total files for a typical workflow**: **100-500 files**

---

## 2. Nextflow DSL2 Syntax Elements

### **2.1 Process Definition** (in `modules/*/main.nf`)

```groovy
process PROCESS_NAME {
    // ==== DIRECTIVES ====
    tag "${meta.id}"                    // Display tag for process execution
    label 'process_medium'              // Resource label (defined in config)

    // Container directive
    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/fastqc:0.12.1--hdfd78af_0' :
        'biocontainers/fastqc:0.12.1--hdfd78af_0' }"

    // Publishing directive
    publishDir "${params.outdir}/fastqc",
        mode: params.publish_dir_mode,
        saveAs: { filename -> filename.equals('versions.yml') ? null : filename }

    // Resource directives (can be overridden by config)
    cpus   { check_max( 4 * task.attempt, 'cpus'   ) }
    memory { check_max( 16.GB * task.attempt, 'memory' ) }
    time   { check_max( 6.h * task.attempt, 'time' ) }

    // Error strategy
    errorStrategy { task.exitStatus in [143,137,104,134,139] ? 'retry' : 'finish' }
    maxRetries 3

    // ==== INPUT ====
    input:
    tuple val(meta), path(reads)       // Tuple: metadata + file(s)
    path(index)                        // Path: reference file
    val(param)                         // Val: parameter value
    each(reference)                    // Each: iterate over items

    // ==== OUTPUT ====
    output:
    tuple val(meta), path("*.html"), emit: html
    tuple val(meta), path("*.zip"),  emit: zip
    path "versions.yml",             emit: versions
    path "*.log",                    emit: log, optional: true

    // ==== WHEN ====
    when:
    task.ext.when == null || task.ext.when

    // ==== SCRIPT ====
    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    fastqc \\
        --threads ${task.cpus} \\
        $args \\
        ${reads}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fastqc: \$( fastqc --version | sed '/FastQC v/!d; s/.*v//' )
    END_VERSIONS
    """

    // ==== STUB (for testing) ====
    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fastqc.html
    touch ${prefix}_fastqc.zip

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fastqc: 0.12.1
    END_VERSIONS
    """
}
```

**Process Directives** (40+ available):
- tag, label, container, conda
- publishDir, storeDir, scratch
- cpus, memory, time, disk
- queue, clusterOptions
- errorStrategy, maxRetries, maxErrors
- cache, stageInMode, stageOutMode
- executor, machineType
- accelerator (GPU), arch
- beforeScript, afterScript, module
- penv, secret, pod
- And many more...

---

### **2.2 Workflow Definition** (in `workflows/*.nf`)

```groovy
//
// Workflow description
//

include { FASTQC                 } from '../modules/nf-core/fastqc/main'
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { QUANTIFY_PSEUDO_ALIGNMENT } from '../subworkflows/nf-core/quantify_pseudo_alignment/main'

workflow MY_WORKFLOW {
    // ==== TAKE ====
    take:
    ch_samplesheet               // channel: [ val(meta), path(reads) ]
    ch_fasta                     // channel: path(genome.fa)
    ch_gtf                       // channel: path(genes.gtf)
    genome_version               //     val: "GRCh38"

    // ==== MAIN ====
    main:
    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()

    //
    // MODULE: Run FastQC
    //
    FASTQC (
        ch_samplesheet
    )
    ch_versions = ch_versions.mix(FASTQC.out.versions.first())
    ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip.collect{it[1]})

    //
    // SUBWORKFLOW: Quantify with Salmon or Kallisto
    //
    QUANTIFY_PSEUDO_ALIGNMENT (
        ch_samplesheet,
        ch_samplesheet,             // reads
        params.pseudo_aligner_index,
        ch_fasta,
        ch_gtf,
        params.gtf_extra_attributes,
        params.gtf_group_features,
        params.pseudo_aligner,
        params.salmon_quant_libtype,
        false
    )
    ch_versions = ch_versions.mix(QUANTIFY_PSEUDO_ALIGNMENT.out.versions)

    //
    // MODULE: MultiQC
    //
    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList()
    )

    // ==== EMIT ====
    emit:
    fastqc_html    = FASTQC.out.html                                    // channel: [ val(meta), path(html) ]
    fastqc_zip     = FASTQC.out.zip                                     // channel: [ val(meta), path(zip) ]
    salmon_results = QUANTIFY_PSEUDO_ALIGNMENT.out.results              // channel: [ val(meta), path(dir) ]
    multiqc_report = MULTIQC.out.report                                 // channel: path(report)
    versions       = ch_versions                                        // channel: path(versions.yml)
}
```

**Workflow Features**:
- `include` statements
- `take` section (workflow inputs)
- `main` section (logic)
- `emit` section (workflow outputs)
- Channel operations
- Process/subworkflow calls

---

### **2.3 Channel Operators** (50+ operators)

```groovy
// ==== CREATING CHANNELS ====
Channel.of(1, 2, 3)                          // Create from values
Channel.fromPath('data/*.fastq')             // From file pattern
Channel.fromFilePairs('*_{R1,R2}.fastq')     // From paired files
Channel.fromSRA('SRR123456')                 // From SRA accession

// ==== FILTERING ====
ch.filter { it.size() > 1000 }               // Filter by condition
ch.unique()                                  // Remove duplicates
ch.distinct()                                // Same as unique
ch.first()                                   // Take first item
ch.last()                                    // Take last item
ch.take(10)                                  // Take N items

// ==== TRANSFORMING ====
ch.map { file -> [file.baseName, file] }     // Transform items
ch.flatMap { ... }                           // Flatten nested structures
ch.flatten()                                 // Flatten collections
ch.toList()                                  // Collect all to list
ch.collect()                                 // Same as toList

// ==== SPLITTING/MERGING ====
ch.branch {                                  // Split by condition
    passed: it.status == 'ok'
    failed: it.status == 'error'
}
ch.mix(ch2, ch3)                             // Merge channels
ch.concat(ch2)                               // Concatenate
ch.merge(ch2)                                // Merge item-by-item

// ==== COMBINING ====
ch.join(ch2)                                 // Join by key
ch.join(ch2, by: 0)                          // Join by first element
ch.combine(ch2)                              // Cartesian product
ch.groupTuple()                              // Group by key
ch.groupTuple(by: [0,1])                     // Group by multiple keys

// ==== SPLITTING ====
ch.splitCsv()                                // Parse CSV
ch.splitFasta()                              // Parse FASTA
ch.splitFastq()                              // Parse FASTQ
ch.splitText()                               // Split by lines

// ==== CONTROL FLOW ====
ch.until { it == 'STOP' }                    // Emit until condition
ch.buffer(size: 10)                          // Create batches
ch.collate(3)                                // Group in chunks
ch.collate(3, 1)                             // Sliding window
ch.randomSample(10)                          // Random sampling

// ==== OPERATORS ====
ch.count()                                   // Count items
ch.min()                                     // Minimum value
ch.max()                                     // Maximum value
ch.sum()                                     // Sum values
ch.reduce { a, b -> a + b }                  // Reduce operation

// ==== CONDITIONAL ====
ch.ifEmpty('default')                        // Provide default
ch.view()                                    // Debug print
ch.tap { collector }                         // Duplicate to another channel
```

---

### **2.4 Configuration File** (`nextflow.config`)

```groovy
// ==== MANIFEST ====
manifest {
    name            = 'nf-core/rnaseq'
    author          = 'nf-core contributors'
    homePage        = 'https://github.com/nf-core/rnaseq'
    description     = 'RNA sequencing analysis pipeline'
    mainScript      = 'main.nf'
    nextflowVersion = '!>=23.04.0'
    version         = '3.14.0'
    doi             = '10.5281/zenodo.1400710'
}

// ==== PARAMETERS ====
params {
    // Input/output options
    input                      = null
    outdir                     = './results'
    email                      = null

    // Reference genome options
    genome                     = null
    fasta                      = null
    gtf                        = null

    // Tool options
    pseudo_aligner             = 'salmon'
    aligner                    = 'star_salmon'

    // Process-specific options
    skip_fastqc                = false
    skip_multiqc               = false

    // Resource limits
    max_cpus                   = 16
    max_memory                 = '128.GB'
    max_time                   = '240.h'
}

// ==== PROFILES ====
profiles {
    debug       { process.beforeScript = 'echo $HOSTNAME' }
    conda {
        conda.enabled          = true
        docker.enabled         = false
        singularity.enabled    = false
        podman.enabled         = false
    }
    docker {
        docker.enabled         = true
        conda.enabled          = false
        singularity.enabled    = false
        podman.enabled         = false
        docker.runOptions      = '-u $(id -u):$(id -g)'
    }
    singularity {
        singularity.enabled    = true
        singularity.autoMounts = true
        conda.enabled          = false
        docker.enabled         = false
        podman.enabled         = false
    }
    test      { includeConfig 'conf/test.config'      }
    test_full { includeConfig 'conf/test_full.config' }
}

// ==== PROCESS CONFIGURATION ====
process {
    // Default resources
    cpus   = { check_max( 1    * task.attempt, 'cpus'   ) }
    memory = { check_max( 6.GB * task.attempt, 'memory' ) }
    time   = { check_max( 4.h  * task.attempt, 'time'   ) }

    // Error handling
    errorStrategy = { task.exitStatus in ((130..145) + 104) ? 'retry' : 'finish' }
    maxRetries    = 1
    maxErrors     = '-1'

    // Process-specific resources
    withLabel:process_single {
        cpus   = { check_max( 1                  , 'cpus'    ) }
        memory = { check_max( 6.GB * task.attempt, 'memory'  ) }
        time   = { check_max( 4.h  * task.attempt, 'time'    ) }
    }
    withLabel:process_low {
        cpus   = { check_max( 2     * task.attempt, 'cpus'    ) }
        memory = { check_max( 12.GB * task.attempt, 'memory'  ) }
        time   = { check_max( 4.h   * task.attempt, 'time'    ) }
    }
    withLabel:process_medium {
        cpus   = { check_max( 6     * task.attempt, 'cpus'    ) }
        memory = { check_max( 36.GB * task.attempt, 'memory'  ) }
        time   = { check_max( 8.h   * task.attempt, 'time'    ) }
    }
    withLabel:process_high {
        cpus   = { check_max( 12    * task.attempt, 'cpus'    ) }
        memory = { check_max( 72.GB * task.attempt, 'memory'  ) }
        time   = { check_max( 16.h  * task.attempt, 'time'    ) }
    }

    // Tool-specific resources
    withName:FASTQC {
        cpus   = 4
        memory = 16.GB
    }
    withName:STAR_ALIGN {
        cpus   = 12
        memory = 72.GB
    }
}

// ==== EXECUTOR CONFIGURATION ====
executor {
    name = 'slurm'
    queueSize = 100
    pollInterval = '30 sec'
    submitRateLimit = '10 sec'
}

// ==== REPORT GENERATION ====
timeline {
    enabled = true
    file    = "${params.outdir}/pipeline_info/execution_timeline.html"
}
report {
    enabled = true
    file    = "${params.outdir}/pipeline_info/execution_report.html"
}
trace {
    enabled = true
    file    = "${params.outdir}/pipeline_info/execution_trace.txt"
}
dag {
    enabled = true
    file    = "${params.outdir}/pipeline_info/pipeline_dag.svg"
}
```

---

## 3. What Information Is LOST During Conversion

### **3.1 Galaxy → BUWF → Nextflow Conversion**

**File**: `backend/lib/galaxy/ai/workflow_converters/nextflow_converter.py`

**What IS Captured** ✅:
- Process names
- Basic input/output names
- Workflow structure (process calls)
- High-level workflow metadata (name, description)

**What IS LOST** ❌:

#### **CRITICAL LOSSES**:

1. **Process Directives** (ALL 40+ directives lost):
   ```groovy
   // LOST:
   tag, label, container, conda
   publishDir, cpus, memory, time
   errorStrategy, maxRetries
   cache, queue, clusterOptions
   // ... and 30+ more
   ```

2. **Channel Operators** (ALL 50+ operators lost):
   ```groovy
   // LOST:
   .map{}, .filter{}, .groupTuple()
   .join(), .branch{}, .mix()
   .collect(), .flatten(), .splitCsv()
   // ... and 40+ more
   ```

3. **Configuration** (entire nextflow.config lost):
   ```groovy
   // LOST:
   params {}           // All parameters
   profiles {}         // All execution profiles
   process {}          // All resource configs
   executor {}         // Executor settings
   timeline/report {}  // Reporting
   ```

4. **Scripts** (custom logic lost):
   ```groovy
   // LOST:
   script:
   def args = task.ext.args ?: ''
   def prefix = task.ext.prefix ?: "${meta.id}"
   """
   complex bash script with variables
   """
   ```

5. **Conditional Logic** (when clauses lost):
   ```groovy
   // LOST:
   when:
   task.ext.when == null || task.ext.when
   params.skip_fastqc == false
   ```

6. **Error Handling**:
   ```groovy
   // LOST:
   errorStrategy { task.exitStatus in [143,137] ? 'retry' : 'finish' }
   maxRetries 3
   ```

7. **Module Metadata** (meta.yml files not captured):
   ```yaml
   # LOST:
   name: fastqc
   description: Run FastQC on sequencing data
   keywords: [quality control, fastq]
   tools:
     - fastqc:
         description: Quality control tool
         homepage: https://www.bioinformatics.babraham.ac.uk/projects/fastqc/
   ```

8. **Test Configurations** (tests/ directory lost)

9. **Custom Scripts** (bin/ directory lost)

10. **Groovy Libraries** (lib/ directory lost)

---

### **3.2 What the Converter Actually Generates**

**Example Input** (Galaxy .ga):
```json
{
  "steps": {
    "0": {"type": "input", "label": "reads"},
    "1": {
      "tool_id": "fastqc",
      "input_connections": {"input": {"id": 0}}
    }
  }
}
```

**Actual Output** (Generated Nextflow):
```groovy
//
// Workflow description
//

include { FASTQC } from './modules/fastqc'

workflow WORKFLOW_NAME {
    take:
    reads  // Input

    main:
    ch_versions = Channel.empty()

    FASTQC ( reads )
    ch_versions = ch_versions.mix(FASTQC.out.versions.first())

    emit:
    versions = ch_versions
}
```

**What's Missing**:
- ❌ No container/conda specification
- ❌ No resource requirements (cpus, memory, time)
- ❌ No error handling
- ❌ No publishDir for outputs
- ❌ No process labels
- ❌ No configuration file
- ❌ No actual process implementation (just placeholder)

---

### **3.3 Comparison: Real nf-core vs. Generated**

**Real nf-core module** (`modules/nf-core/fastqc/main.nf`):
```groovy
process FASTQC {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' ?
        'https://depot.galaxyproject.org/singularity/fastqc:0.12.1' :
        'biocontainers/fastqc:0.12.1' }"

    publishDir "${params.outdir}/fastqc", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("*.html"), emit: html
    tuple val(meta), path("*.zip"),  emit: zip
    path "versions.yml",             emit: versions

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    fastqc --threads ${task.cpus} $args ${reads}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fastqc: \$( fastqc --version | sed '/FastQC v/!d; s/.*v//' )
    END_VERSIONS
    """
}
```

**Generated by converter** (`modules/fastqc.nf`):
```groovy
// PLACEHOLDER: This is a simplified process definition
process FASTQC {
    input:
    path(reads)

    output:
    path("*")

    script:
    """
    echo "FastQC process placeholder"
    """
}
```

**Information Loss**: ~90% of functionality

---

## 4. How to Ensure Conversion Quality

### **4.1 Current Validation (What Exists)**

**File**: `backend/lib/galaxy/ai/workflow_converters/nextflow_converter.py:111-129`

```python
def validate(self, nf_workflow: NextflowWorkflow) -> tuple[bool, list[str]]:
    """Validate Nextflow workflow structure."""
    errors = []

    if not nf_workflow.name:
        errors.append("Workflow has no name")

    if not nf_workflow.process_calls:
        errors.append("Workflow has no process calls")

    return (len(errors) == 0, errors)
```

**What This Validates**: Almost nothing ❌
- Only checks if workflow has a name
- Only checks if there are process calls
- **Does NOT validate**:
  - Process definitions
  - Channel operations
  - Configuration
  - Scripts
  - Resource requirements

---

### **4.2 Recommended Validation Strategy**

#### **Level 1: Syntax Validation**
```python
def validate_nextflow_syntax(nf_file: Path) -> tuple[bool, list[str]]:
    """
    Use Nextflow's built-in syntax checker.

    Command: nextflow run -check-syntax
    """
    import subprocess

    result = subprocess.run(
        ['nextflow', 'run', str(nf_file), '-check-syntax'],
        capture_output=True,
        text=True
    )

    if result.returncode == 0:
        return (True, [])
    else:
        return (False, [result.stderr])
```

#### **Level 2: Structural Validation**
```python
def validate_nextflow_structure(nf_workflow: NextflowWorkflow) -> tuple[bool, list[str]]:
    """Validate complete workflow structure."""
    errors = []

    # Check required sections
    if not nf_workflow.inputs:
        errors.append("Missing take: section")

    if not nf_workflow.process_calls:
        errors.append("Missing main: section with process calls")

    if not nf_workflow.outputs:
        errors.append("Missing emit: section")

    # Validate each process call
    for pc in nf_workflow.process_calls:
        if not pc.process_name:
            errors.append(f"Process call missing name")

        if not pc.inputs:
            errors.append(f"Process {pc.process_name} has no inputs")

    # Validate data flow
    process_outputs = set()
    for pc in nf_workflow.process_calls:
        for inp in pc.inputs:
            # Check if input is available
            if '.' in inp:  # Process output reference
                source_process = inp.split('.')[0]
                if source_process not in process_outputs:
                    errors.append(
                        f"Process {pc.process_name} references undefined output: {inp}"
                    )

        process_outputs.add(pc.process_name)

    return (len(errors) == 0, errors)
```

#### **Level 3: Semantic Validation** (roundtrip test)
```python
def validate_conversion_roundtrip(galaxy_workflow: Dict,
                                   converted_nf: Dict[str, str]) -> tuple[bool, list[str]]:
    """
    Test round-trip conversion:
    Galaxy → BUWF → Nextflow → BUWF → Galaxy

    Verify that the final Galaxy workflow has the same structure.
    """
    from .galaxy_converter import GalaxyToUnifiedConverter, UnifiedToGalaxyConverter
    from .nextflow_converter import NextflowToUnifiedConverter

    errors = []

    # Original: Galaxy → BUWF
    to_unified = GalaxyToUnifiedConverter()
    buwf_original = to_unified.convert(galaxy_workflow)

    # Nextflow → BUWF
    nf_parser = NextflowParser()
    nf_workflow = nf_parser.parse_string(converted_nf['main.nf'])

    to_unified_nf = NextflowToUnifiedConverter()
    buwf_from_nf = to_unified_nf.convert(nf_workflow)

    # Compare structures
    if len(buwf_original.high_level_steps) != len(buwf_from_nf.high_level_steps):
        errors.append(
            f"Step count mismatch: {len(buwf_original.high_level_steps)} vs {len(buwf_from_nf.high_level_steps)}"
        )

    # Compare tool counts
    original_tools = sum(len(hl.detailed_steps) for hl in buwf_original.high_level_steps)
    converted_tools = sum(len(hl.detailed_steps) for hl in buwf_from_nf.high_level_steps)

    if original_tools != converted_tools:
        errors.append(
            f"Tool count mismatch: {original_tools} vs {converted_tools}"
        )

    return (len(errors) == 0, errors)
```

#### **Level 4: Execution Validation**
```python
def validate_nextflow_execution(nf_files: Dict[str, str],
                                 test_data: Path) -> tuple[bool, list[str]]:
    """
    Actually execute the generated Nextflow workflow on test data.

    This is the GOLD STANDARD validation.
    """
    import subprocess
    import tempfile
    from pathlib import Path

    errors = []

    # Create temporary directory
    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir = Path(tmpdir)

        # Write Nextflow files
        for filename, content in nf_files.items():
            filepath = tmpdir / filename
            filepath.parent.mkdir(parents=True, exist_ok=True)
            filepath.write_text(content)

        # Run Nextflow
        result = subprocess.run(
            [
                'nextflow', 'run',
                str(tmpdir / 'main.nf'),
                '--input', str(test_data),
                '-profile', 'test,docker',
                '-work-dir', str(tmpdir / 'work')
            ],
            capture_output=True,
            text=True,
            timeout=300  # 5 minutes
        )

        if result.returncode != 0:
            errors.append(f"Execution failed: {result.stderr}")

    return (len(errors) == 0, errors)
```

---

### **4.3 Recommended Testing Suite**

**Create**: `backend/tests/test_nextflow_conversion_quality.py`

```python
import pytest
from pathlib import Path

class TestNextflowConversionQuality:
    """Test suite for Nextflow conversion quality."""

    def test_syntax_validation(self):
        """Test that generated Nextflow has valid syntax."""
        # Load Galaxy workflow
        # Convert to Nextflow
        # Validate syntax with Nextflow CLI
        pass

    def test_structure_completeness(self):
        """Test that all workflow elements are preserved."""
        # Check: inputs, outputs, process calls
        pass

    def test_data_flow_integrity(self):
        """Test that process dependencies are correct."""
        # Verify no undefined references
        # Verify DAG is acyclic
        pass

    def test_roundtrip_fidelity(self):
        """Test Galaxy → Nextflow → Galaxy preserves structure."""
        # Compare step counts
        # Compare tool counts
        # Compare connections
        pass

    def test_execution_equivalence(self):
        """Test that Galaxy and Nextflow produce same results."""
        # Run both on same test data
        # Compare outputs
        pass
```

---

## 5. Multi-File Nextflow Structure Handling

### **5.1 Current Converter Output**

**Generated Files**:
```python
result = {
    "main.nf": "...",              # Main workflow
    "nextflow.config": "...",      # Basic config
    "modules/process1.nf": "...",  # Process definitions (placeholders)
}
```

**Missing Files**:
- ❌ `meta.yml` (module metadata)
- ❌ `environment.yml` (Conda environment)
- ❌ `tests/*.config` (test configurations)
- ❌ `bin/*.py` (custom scripts)
- ❌ `lib/*.groovy` (helper functions)
- ❌ `conf/modules.config` (module-specific configs)

---

### **5.2 Recommended: Complete File Generation**

```python
class EnhancedNextflowConverter:
    """Enhanced converter that generates ALL required files."""

    def convert(self, unified_workflow: UnifiedWorkflow) -> Dict[str, str]:
        """Generate complete Nextflow workflow structure."""

        result = {}

        # 1. Main workflow
        result['main.nf'] = self._generate_main_workflow(unified_workflow)

        # 2. Base configuration
        result['nextflow.config'] = self._generate_config(unified_workflow)

        # 3. Process modules with FULL definitions
        for hl_step in unified_workflow.high_level_steps:
            for detailed_step in hl_step.detailed_steps:
                module_dir = f"modules/nf-core/{detailed_step.tool_id}"

                # Process definition
                result[f"{module_dir}/main.nf"] = self._generate_process_definition(
                    detailed_step
                )

                # Module metadata
                result[f"{module_dir}/meta.yml"] = self._generate_module_metadata(
                    detailed_step
                )

                # Conda environment
                result[f"{module_dir}/environment.yml"] = self._generate_conda_env(
                    detailed_step
                )

                # Test config
                result[f"{module_dir}/tests/main.nf.test"] = self._generate_test_config(
                    detailed_step
                )

        # 4. Additional configs
        result['conf/base.config'] = self._generate_base_config()
        result['conf/modules.config'] = self._generate_modules_config(unified_workflow)
        result['conf/test.config'] = self._generate_test_config_workflow()

        # 5. Assets
        result['assets/schema_input.json'] = self._generate_input_schema(unified_workflow)

        return result

    def _generate_process_definition(self, step: DetailedStep) -> str:
        """Generate COMPLETE process definition with all directives."""
        return f"""
process {step.tool_name.upper().replace(' ', '_')} {{
    tag "${{meta.id}}"
    label 'process_medium'

    conda "${{moduleDir}}/environment.yml"
    container "biocontainers/{step.tool_id}:{step.tool_version}"

    publishDir "${{params.outdir}}/{step.tool_id}",
        mode: params.publish_dir_mode,
        saveAs: {{ filename -> filename.equals('versions.yml') ? null : filename }}

    input:
    tuple val(meta), path(inputs)

    output:
    tuple val(meta), path("*.{step.outputs[0].format}"), emit: results
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${{meta.id}}"
    \"\"\"
    {step.tool_id} \\
        --threads ${{task.cpus}} \\
        $args \\
        ${{inputs}}

    cat <<-END_VERSIONS > versions.yml
    "${{task.process}}":
        {step.tool_id}: \$( {step.tool_id} --version | sed 's/^.*{step.tool_id} //' )
    END_VERSIONS
    \"\"\"
}}
"""

    def _generate_module_metadata(self, step: DetailedStep) -> str:
        """Generate meta.yml for module."""
        return f"""
name: {step.tool_id}
description: {step.description}
keywords:
  - {step.category}
tools:
  - {step.tool_id}:
      description: {step.description}
      homepage: https://example.com/{step.tool_id}
      documentation: https://example.com/{step.tool_id}/docs
      tool_dev_url: https://github.com/example/{step.tool_id}
      licence: ['MIT']
input:
{self._format_meta_inputs(step.inputs)}
output:
{self._format_meta_outputs(step.outputs)}
authors:
  - "@biomate"
"""

    def _generate_conda_env(self, step: DetailedStep) -> str:
        """Generate Conda environment.yml."""
        return f"""
name: {step.tool_id}
channels:
  - conda-forge
  - bioconda
  - defaults
dependencies:
  - {step.tool_id}={step.tool_version}
"""
```

---

## 6. Quality Assurance Metrics

### **6.1 Conversion Completeness Score**

```python
def calculate_completeness_score(
    original_galaxy: Dict,
    converted_nextflow: Dict[str, str]
) -> Dict[str, float]:
    """
    Calculate how much information is preserved.

    Returns scores for different aspects (0.0 - 1.0):
    - structure_score: DAG structure preservation
    - metadata_score: Metadata preservation
    - config_score: Configuration completeness
    - execution_score: Ability to execute
    """

    scores = {}

    # 1. Structure score (step count, connections)
    original_steps = len(original_galaxy.get('steps', {}))
    nf_processes = converted_nextflow['main.nf'].count('include {')
    scores['structure_score'] = min(nf_processes / original_steps, 1.0)

    # 2. Metadata score (name, description, etc.)
    has_name = 'workflow' in converted_nextflow['main.nf']
    has_config = 'nextflow.config' in converted_nextflow
    has_docs = 'README.md' in converted_nextflow
    scores['metadata_score'] = sum([has_name, has_config, has_docs]) / 3.0

    # 3. Config score (how many config elements present)
    config_elements = [
        'params {',
        'process {',
        'executor {',
        'profiles {'
    ]
    config_present = sum(
        elem in converted_nextflow.get('nextflow.config', '')
        for elem in config_elements
    )
    scores['config_score'] = config_present / len(config_elements)

    # 4. Execution score (can it run?)
    has_processes = any('process ' in v for v in converted_nextflow.values())
    has_workflow = 'workflow ' in converted_nextflow.get('main.nf', '')
    has_containers = 'container' in str(converted_nextflow.values())
    scores['execution_score'] = sum([has_processes, has_workflow, has_containers]) / 3.0

    # Overall score
    scores['overall'] = sum(scores.values()) / len(scores)

    return scores
```

**Example Output**:
```python
{
    'structure_score': 1.0,      # Perfect DAG preservation
    'metadata_score': 0.67,      # Has name and config, no README
    'config_score': 0.25,        # Only params{}, missing others
    'execution_score': 0.33,     # Has processes and workflow, no containers
    'overall': 0.56              # 56% complete
}
```

---

## 7. Recommended Improvements

### **Priority 1: Essential (Must-Have)**

1. **Add Container Specifications**
   - Every process MUST have container/conda
   - Without this, workflows cannot execute

2. **Add Resource Requirements**
   - cpus, memory, time for each process
   - Essential for HPC/cloud execution

3. **Add Configuration File**
   - params, profiles, process configs
   - Without this, workflow not configurable

4. **Add Error Handling**
   - errorStrategy, maxRetries
   - Critical for production reliability

### **Priority 2: Important (Should-Have)**

5. **Add Process Directives**
   - publishDir, tag, label
   - Improves usability and debugging

6. **Add Module Metadata**
   - meta.yml for each module
   - Required for nf-core compliance

7. **Add Test Configurations**
   - tests/*.nf.test
   - Essential for validation

8. **Add Channel Operations**
   - Preserve .map{}, .filter{}, etc.
   - Needed for complex dataflow

### **Priority 3: Nice-to-Have**

9. **Add Conda Environments**
   - environment.yml per module
   - Alternative to containers

10. **Add Documentation**
    - README.md, usage docs
    - Improves usability

---

## 8. Conclusion

### **Current State Assessment**

**Converter Quality**: ⭐⭐ (2/5 stars)
- **Good for**: Workflow visualization, understanding structure
- **NOT good for**: Production execution, HPC deployment

**Information Preservation**: ~10-20%
- Structure: ✅ Mostly preserved
- Metadata: ⚠️ Partially preserved
- Configuration: ❌ Lost (90%)
- Execution details: ❌ Lost (100%)

### **Honest Answer to Your Question**

**"How can you make sure not a single piece of information is lost?"**

**You CANNOT** with the current converter implementation ❌

The converter is fundamentally **lossy** because:
1. Nextflow has 10× more features than Galaxy
2. Configuration is separate from workflow definition
3. Many Nextflow features have no Galaxy equivalent

### **What You CAN Do**

**Option 1: Accept Information Loss** (current approach)
- Use converters for **visualization only**
- Manually review and enhance generated Nextflow
- Treat generated code as **template**, not production code

**Option 2: Enhance Converters** (recommended)
- Implement Priority 1 improvements
- Add validation tests
- Calculate completeness scores
- Document what's missing

**Option 3: Hybrid Approach** (best)
- Convert Galaxy → BUWF (lossless for visualization)
- Generate Nextflow **template** from BUWF
- **Manually complete** Nextflow with:
  - Container specifications
  - Resource requirements
  - Error handling
  - Configuration
- Store completed Nextflow alongside BUWF

### **Recommendation**

For production use, I recommend:

1. **Use converters to bootstrap** Nextflow workflows
2. **Manually review and enhance** generated code
3. **Validate with execution tests**
4. **Store both versions**: Galaxy .ga AND completed Nextflow
5. **Document deviations** between formats

**Do NOT blindly trust converted workflows for production**

The converters are **80% automated, 20% manual completion** tools.

---

**Last Updated**: 2025-11-19
**See Also**:
- Official Nextflow docs: https://www.nextflow.io/docs/latest/
- nf-core guidelines: https://nf-co.re/docs/contributing/guidelines
- `GALAXY_VS_NEXTFLOW_TECHNICAL_COMPARISON.md` - Detailed comparison
