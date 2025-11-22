# Galaxy ↔ Nextflow Comprehensive Comparison

**Purpose**: Complete piece-by-piece comparison for building a bi-directional converter
**Date**: 2025-11-21
**Scope**: Grammar, data types, data structures, execution workflow

---

## Table of Contents

1. [File Format & Grammar](#1-file-format--grammar)
2. [Data Types](#2-data-types)
3. [Data Structures](#3-data-structures)
4. [Execution Model](#4-execution-model)
5. [Control Flow](#5-control-flow)
6. [Metadata & Configuration](#6-metadata--configuration)
7. [Bi-Directional Conversion Challenges](#7-bi-directional-conversion-challenges)
8. [Implementation Roadmap](#8-implementation-roadmap)

---

## 1. File Format & Grammar

### Galaxy (.ga)

**Format**: JSON (declarative)
**Paradigm**: Configuration-based
**Extension**: `.ga` (Galaxy Workflow)

```json
{
  "a_galaxy_workflow": "true",
  "annotation": "Description",
  "format-version": "0.1",
  "name": "WORKFLOW_NAME",
  "steps": {
    "0": { /* step definition */ },
    "1": { /* step definition */ }
  }
}
```

**Key Characteristics**:
- ✅ **Declarative**: Describes what to run, not how
- ✅ **Structured**: Fixed JSON schema
- ✅ **Validation**: JSON schema validation possible
- ❌ **No imperative logic**: Cannot write custom code
- ❌ **No expressions**: Limited computation in config
- 📊 **Typical size**: 100-500 lines of JSON

---

### Nextflow (.nf)

**Format**: Groovy DSL (Domain Specific Language)
**Paradigm**: Imperative + Dataflow
**Extension**: `.nf` (Nextflow)

```groovy
// Parameters
params.input = 'data/*.fastq'

// Channels (reactive data streams)
Channel.fromPath(params.input).set { ch_input }

// Process (computation)
process ALIGN {
    input:
    path reads

    output:
    path "*.bam"

    script:
    """
    bwa mem $reads > output.bam
    """
}

// Workflow (orchestration)
workflow {
    ALIGN(ch_input)
}
```

**Key Characteristics**:
- ✅ **Imperative**: Can write arbitrary Groovy code
- ✅ **Flexible**: Custom functions, logic, transformations
- ✅ **Expressive**: Complex data flow patterns
- ❌ **Less structured**: Harder to parse/validate
- ❌ **Learning curve**: Requires Groovy/DSL knowledge
- 📊 **Typical size**: 200-2000 lines of Groovy code

---

### Grammar Comparison

| Feature | Galaxy | Nextflow | Bi-directional Challenge |
|---------|--------|----------|--------------------------|
| **Language** | JSON | Groovy DSL | HIGH: JSON → Code generation |
| **Comments** | N/A (JSON) | `//` and `/* */` | MEDIUM: Lose comments in Galaxy |
| **Variables** | Fixed schema | Dynamic (Groovy) | HIGH: Need to infer variables |
| **Expressions** | Limited (tool_state) | Full Groovy | HIGH: Cannot express all logic |
| **String interpolation** | N/A | `"${var}"` | MEDIUM: Convert to Galaxy params |
| **Code blocks** | N/A | `{ }` | HIGH: No equivalent in Galaxy |

**Conversion Difficulty**: 🔴 **VERY HIGH** (Galaxy → Nextflow: code generation; Nextflow → Galaxy: semantic loss)

---

## 2. Data Types

### Galaxy Data Types

Galaxy uses **implicit typing** based on file extensions and tool specifications.

#### 2.1 Data Input Types

```json
{
  "type": "data_input",
  "tool_state": "{\"optional\": false}"
}
```

**Implicit types based on context**:
- `fastq` / `fastqsanger` (FASTQ files)
- `bam` (Binary Alignment)
- `fasta` (FASTA sequences)
- `vcf` (Variant Call Format)
- `tabular` (Tab-delimited)
- `interval` (Genomic intervals)

**Collections**:
```json
{
  "type": "data_collection_input",
  "collection_type": "list" | "paired" | "list:paired"
}
```

#### 2.2 Parameter Types

```json
{
  "type": "parameter_input",
  "tool_state": "{\"parameter_type\": \"text\", \"optional\": true}"
}
```

**Types**:
- `text` (string)
- `integer`
- `float`
- `boolean`
- `select` (enumeration)

---

### Nextflow Data Types

Nextflow uses **explicit typing** in channel declarations.

#### 2.1 Channel Value Types

```groovy
// val - Any value (string, number, object)
val(meta)              // Metadata map
val(sample_id)         // String identifier

// path - File/directory path
path(reads)            // Single file
path("*.fastq")        // Glob pattern
path(index, stageAs: 'ref/*')  // Staged path

// tuple - Composite type
tuple val(meta), path(reads)   // Common pattern
tuple val(id), val(condition), path(bam)

// file - Deprecated (use path)
file(reads)            // Old syntax

// env - Environment variable
env(MY_VAR)

// stdin/stdout - Standard streams
stdin()
stdout()
```

#### 2.2 Data Type Examples

```groovy
// Simple value
Channel.of(1, 2, 3)                    // val: Integer

// File path
Channel.fromPath('data/*.fastq')       // path: File

// Tuple (composite)
Channel.fromFilePairs('data/*_{1,2}.fq')
// tuple(val, path): ["sample1", [file1, file2]]

// Map (metadata + file)
.map { name, files ->
    [meta: [id: name, single_end: false], reads: files]
}
// tuple(val, path): [[id: "sample1", single_end: false], [file1, file2]]
```

---

### Data Type Mapping

| Galaxy Type | Nextflow Type | Conversion Notes |
|-------------|---------------|------------------|
| `data_input` (fastq) | `path(reads)` | Direct mapping ✅ |
| `data_input` (bam) | `path(bam)` | Direct mapping ✅ |
| `data_collection_input` (list) | `path(files)` | Collection → single path ✅ |
| `data_collection_input` (paired) | `tuple val(meta), path(reads)` | Need to create meta map ⚠️ |
| `parameter_input` (text) | `val(param)` | Direct mapping ✅ |
| `parameter_input` (integer) | `val(num)` | Type inference needed ⚠️ |
| N/A | `tuple val(meta), path(file)` | **NO GALAXY EQUIVALENT** ❌ |
| N/A | `env(VAR)` | **NO GALAXY EQUIVALENT** ❌ |

**Conversion Difficulty**:
- Galaxy → Nextflow: 🟡 **MEDIUM** (need to infer types, create tuples)
- Nextflow → Galaxy: 🔴 **HIGH** (lose tuple structure, metadata)

---

## 3. Data Structures

### 3.1 Workflow Structure

#### Galaxy Workflow Structure

```json
{
  "a_galaxy_workflow": "true",           // Required marker
  "annotation": "Workflow description",   // Human-readable description
  "format-version": "0.1",                // Schema version
  "name": "WORKFLOW_NAME",                // Workflow identifier
  "license": "MIT",                       // Optional license
  "creator": [...],                       // Optional creator metadata
  "report": { "markdown": "..." },        // Optional report template
  "tags": ["rna-seq", "quantification"],  // Optional tags

  "steps": {                              // Workflow steps (ordered by ID)
    "0": { /* step definition */ },
    "1": { /* step definition */ },
    "2": { /* step definition */ }
  }
}
```

**Characteristics**:
- Steps are **numbered** starting from 0
- Execution order determined by **dependencies**, not step numbers
- All steps defined in **single JSON file**
- No concept of "subworkflows" (flat structure)

---

#### Nextflow Workflow Structure

```groovy
// 1. Parameters (configuration)
params.input = 'data/*.fastq'
params.outdir = 'results'

// 2. Imports (optional)
include { PROCESS_A } from './modules/process_a'
include { PROCESS_B } from './modules/process_b'

// 3. Process definitions
process MY_PROCESS {
    input: /* ... */
    output: /* ... */
    script: /* ... */
}

// 4. Workflow definition
workflow MY_WORKFLOW {
    take:
    input_ch

    main:
    PROCESS_A(input_ch)
    PROCESS_B(PROCESS_A.out)

    emit:
    result = PROCESS_B.out
}

// 5. Entry point
workflow {
    Channel.fromPath(params.input) | MY_WORKFLOW
}
```

**Characteristics**:
- **Modular**: Processes in separate files
- **Hierarchical**: Nested subworkflows
- **Explicit dependencies**: Process calls define order
- Multiple entry points possible

---

### 3.2 Step/Process Structure

#### Galaxy Step Structure

```json
{
  "id": 2,                                // Step number
  "type": "tool" | "data_input" | "parameter_input" | "subworkflow",
  "label": "BWA Alignment",               // Human-readable name
  "annotation": "Align reads to reference", // Description

  // Tool specification
  "tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/bwa/bwa_mem",
  "tool_version": "0.7.17",
  "tool_state": "{...}",                  // JSON-encoded tool parameters

  // Input connections (data flow)
  "input_connections": {
    "reads": {
      "id": 0,                            // Source step ID
      "output_name": "output"             // Source output name
    },
    "index": {
      "id": 1,
      "output_name": "output"
    }
  },

  // Outputs
  "outputs": [
    {
      "name": "aligned_reads",
      "type": "bam"
    }
  ],

  // Conditional execution
  "when": "${aligner} == 'bwa'",          // Conditional expression (rarely used)

  // Workflow outputs
  "workflow_outputs": [
    {
      "output_name": "aligned_reads",
      "label": "Final BAM"
    }
  ],

  // Position in GUI
  "position": {
    "left": 100,
    "top": 200
  }
}
```

---

#### Nextflow Process Structure

```groovy
process BWA_ALIGN {
    // 1. DIRECTIVES (configuration)
    tag "$meta.id"                        // Logging tag
    label 'process_high'                  // Resource label
    publishDir "${params.outdir}/bam",    // Output directory
        mode: 'copy'

    // 2. CONTAINER (software environment)
    conda "bioconda::bwa=0.7.17"
    container "biocontainers/bwa:0.7.17"

    // 3. INPUTS (strongly typed)
    input:
    tuple val(meta), path(reads)          // Paired: metadata + files
    path index                            // Reference index

    // 4. OUTPUTS (strongly typed)
    output:
    tuple val(meta), path("*.bam"), emit: bam
    path "versions.yml", emit: versions

    // 5. CONDITIONAL (when clause)
    when:
    params.aligner == 'bwa'

    // 6. SCRIPT (imperative bash)
    script:
    def prefix = meta.id                  // Groovy variable
    def args = task.ext.args ?: ''        // External args
    """
    bwa mem \\
        -t ${task.cpus} \\                # Nextflow variable
        $args \\                          # Groovy variable
        $index \\                         # Input file
        $reads \\                         # Input file
        | samtools sort -o ${prefix}.bam

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bwa: \$(bwa 2>&1 | grep Version)
    END_VERSIONS
    """
}
```

---

### 3.3 Input Connections vs Channel Wiring

#### Galaxy Input Connections (Declarative)

```json
{
  "input_connections": {
    "reads": {
      "id": 0,                    // Step 0's output
      "output_name": "output"
    },
    "reference": {
      "id": 1,                    // Step 1's output
      "output_name": "fasta"
    }
  }
}
```

**Properties**:
- Connects **step outputs** to **step inputs** by name
- Can connect **one output to multiple inputs** (implicit broadcast)
- **No transformation** of data (direct pass-through)
- Execution order inferred from connections

---

#### Nextflow Channel Wiring (Imperative)

```groovy
workflow {
    // 1. Create channels
    ch_reads = Channel.fromPath(params.reads)
        .map { file -> tuple(file.baseName, file) }

    ch_index = Channel.fromPath(params.index).collect()

    // 2. Process calls
    ALIGN(ch_reads, ch_index)

    // 3. Channel operations
    ALIGN.out.bam
        .map { meta, bam -> [meta, bam, meta.condition] }  // Transform
        .branch { meta, bam, condition ->                   // Split
            case_a: condition == 'A'
            case_b: condition == 'B'
        }
        .set { branched }

    // 4. Join channels
    branched.case_a
        .join(branched.case_b, by: 0)                       // Join
        .set { joined }
}
```

**Properties**:
- **Explicit** channel creation and passing
- **Rich transformations**: map, filter, branch, join, etc.
- **One-to-many**, **many-to-one**, **many-to-many** patterns
- Can **modify data structure** in transit

---

### Data Structure Comparison Table

| Feature | Galaxy | Nextflow | Bi-directional Challenge |
|---------|--------|----------|--------------------------|
| **File structure** | Single JSON | Multiple `.nf` files | MEDIUM: Need to split/merge |
| **Step numbering** | Integer IDs (0, 1, 2...) | Process names | LOW: Simple mapping |
| **Dependencies** | `input_connections` | Process calls | HIGH: Different paradigms |
| **Inputs** | Named connections | Typed channels | HIGH: Type inference |
| **Outputs** | Named outputs | Emit channels | MEDIUM: Name mapping |
| **Metadata** | In step definition | Separate params | LOW: Extract/embed |
| **Conditionals** | `when` field (unused) | `when:` + if/else | HIGH: Different semantics |
| **Data transformations** | None | map/filter/branch/join | **NO GALAXY EQUIVALENT** ❌ |
| **Multiple outputs** | Array of outputs | Named emit | MEDIUM: Create output array |

---

## 4. Execution Model

### 4.1 Galaxy Execution Model

**Paradigm**: **Job-based execution** (task queue)

```
┌─────────────────────────────────────────────────────────┐
│                   Galaxy Workflow                        │
│                                                          │
│  Step 0 (Input) ──┬──> Step 2 (Tool) ──> Step 4 (Tool) │
│                   │                                      │
│  Step 1 (Input) ──┴──> Step 3 (Tool) ──┘                │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│                 Job Execution Queue                      │
│                                                          │
│  [Job 1: Step 2] ──> [Job 2: Step 3] ──> [Job 3: Step 4]│
│       ↓                    ↓                   ↓         │
│   [Worker 1]          [Worker 2]          [Worker 1]    │
└─────────────────────────────────────────────────────────┘
```

**Execution Flow**:
1. **User submits workflow** with input datasets
2. Galaxy **scheduler** analyzes dependencies
3. Creates **job queue** (one job per step)
4. **Workers** execute jobs when dependencies satisfied
5. Outputs stored in **Galaxy history**

**Characteristics**:
- ✅ **Simple**: One job per step
- ✅ **Traceable**: All outputs in history
- ✅ **Resumable**: Can restart from any step
- ❌ **Sequential**: Steps run sequentially unless independent
- ❌ **No parallelism within step**: One execution per job
- ❌ **Storage overhead**: All intermediate files stored

**Parallelism**: Galaxy runs **independent steps** in parallel, but each step processes **one dataset** at a time.

---

### 4.2 Nextflow Execution Model

**Paradigm**: **Dataflow execution** (reactive streams)

```
┌─────────────────────────────────────────────────────────┐
│                   Nextflow Workflow                      │
│                                                          │
│  Channel ──> Process A ──> Process B ──> Process C      │
│   (100      (100 parallel) (100 parallel) (100 parallel) │
│   items)        tasks)         tasks)         tasks)     │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│              Nextflow Task Scheduler                     │
│                                                          │
│  Process A: [Task1] [Task2] [Task3] ... [Task100]      │
│  Process B: [Task1] [Task2] [Task3] ... [Task100]      │
│  Process C: [Task1] [Task2] [Task3] ... [Task100]      │
│                                                          │
│  ⚡ All tasks run in parallel (resource limited)         │
└─────────────────────────────────────────────────────────┘
```

**Execution Flow**:
1. **Channels emit items** (one item = one task)
2. Nextflow **creates task** for each item
3. **Scheduler** runs tasks in parallel (up to resource limits)
4. **Outputs** flow to next process via channels
5. **Automatic parallelism**: 100 files = 100 parallel tasks

**Characteristics**:
- ✅ **Massive parallelism**: Processes 1000s of files simultaneously
- ✅ **Reactive**: Processes start as soon as data available
- ✅ **Efficient**: Only stores needed intermediate files
- ✅ **Fault-tolerant**: Automatic retry on failure
- ✅ **Resumable**: `-resume` flag skips completed tasks
- ❌ **Complex**: Harder to understand execution flow
- ❌ **Resource management**: Need to tune parallel limits

**Parallelism**: Nextflow runs **all process instances** in parallel (limited by resources).

---

### 4.3 Execution Comparison

| Aspect | Galaxy | Nextflow | Conversion Challenge |
|--------|--------|----------|----------------------|
| **Paradigm** | Job queue | Dataflow | HIGH: Different mental models |
| **Parallelism** | Step-level | Item-level (within process) | **CRITICAL** ❌ |
| **Item processing** | One at a time per step | All items in parallel | **CRITICAL** ❌ |
| **Dependency model** | Step → Step | Channel → Process | MEDIUM: Can map |
| **Intermediate storage** | All files stored | Work dir (prunable) | LOW: Different semantics |
| **Resume mechanism** | Re-run from step | Cache-based resume | MEDIUM: Different implementation |
| **Resource allocation** | Per-job | Per-task | LOW: Can map |
| **Fault tolerance** | Manual retry | Automatic retry | MEDIUM: Galaxy lacks this |

**KEY SEMANTIC MISMATCH** 🔴:

**Galaxy step**:
```json
{
  "tool_id": "bwa",
  "input_connections": {
    "reads": {"id": 0}  // Single dataset reference
  }
}
```
→ Processes **ONE dataset** (or one collection)

**Nextflow process**:
```groovy
process BWA {
    input:
    tuple val(meta), path(reads)  // Channel

    script: "bwa mem $reads > out.bam"
}
```
→ Processes **ALL items** in channel in parallel (100 files = 100 parallel tasks)

**Conversion Implications**:
- **Galaxy → Nextflow**: ✅ Easy (one Galaxy step = one Nextflow process, works for both models)
- **Nextflow → Galaxy**: ⚠️  Need to clarify: is this processing one item or multiple?

---

## 5. Control Flow

### 5.1 Conditionals

#### Galaxy Conditionals

**Method 1: Step-level `when` expression** (rarely used in practice)

```json
{
  "steps": {
    "2": {
      "tool_id": "bwa",
      "when": "${aligner} == 'bwa'"
    },
    "3": {
      "tool_id": "bowtie2",
      "when": "${aligner} == 'bowtie2'"
    }
  }
}
```

**Status**: ⚠️ **Theoretically supported, but not used in practice**
- All 94 workflows analyzed have `"when": null`
- Conditional logic exists in **annotation text only**

**Method 2: Tool-level conditionals** (within tool XML)

Tool definition handles conditionals internally (not visible in workflow).

**Method 3: Implicit branching** (multiple alternative steps)

```json
{
  "annotation": "Align with bowtie2, bwamem, or dragmap",
  "steps": {
    "5": {"tool_id": "bowtie2", "when": null},
    "6": {"tool_id": "bwamem", "when": null},
    "7": {"tool_id": "dragmap", "when": null}
  }
}
```
Users manually select which path to execute.

---

#### Nextflow Conditionals

**Method 1: Process `when` directive** (execute entire process conditionally)

```groovy
process BWA {
    when:
    params.aligner == 'bwa'

    script:
    "bwa mem ..."
}
```

**Method 2: Script `if/else`** (conditional logic within process)

```groovy
process ALIGN {
    script:
    if (params.aligner == 'bwa') {
        """
        bwa mem $reads > out.bam
        """
    } else if (params.aligner == 'bowtie2') {
        """
        bowtie2 -x $index -U $reads > out.bam
        """
    }
}
```

**Method 3: Channel branching** (split data flow)

```groovy
workflow {
    ch_input
        .branch { meta, file ->
            bwa: meta.aligner == 'bwa'
            bowtie2: meta.aligner == 'bowtie2'
        }
        .set { branched }

    BWA(branched.bwa)
    BOWTIE2(branched.bowtie2)
}
```

**Method 4: Conditional channel operations**

```groovy
ch_output = params.filter ?
    ch_input.filter { it.size() > 1000 } :
    ch_input
```

---

### 5.2 Loops & Iteration

#### Galaxy Loops

**Not supported**. No loop constructs.

Workarounds:
- **Collections**: Process list of items (implicit iteration)
- **Map-over**: Some tools support mapping over collections

```json
{
  "type": "data_collection_input",
  "collection_type": "list"  // Implicit iteration
}
```

---

#### Nextflow Loops

**Fully supported** (Groovy language features)

```groovy
// Groovy loops in workflow
(1..10).each { n ->
    PROCESS_N(Channel.of("sample_${n}"))
}

// Channel operations (functional iteration)
Channel.of(1, 2, 3)
    .map { n -> n * 2 }         // Iterate and transform
    .filter { n -> n > 3 }      // Iterate and filter
    .collect()                  // Collect all items

// Process iteration (implicit)
process ALIGN {
    input:
    tuple val(meta), path(reads)  // Runs once per tuple

    script: "bwa mem $reads > out.bam"
}

// Runs ALIGN process for EVERY item in channel
workflow {
    Channel.fromPath('*.fastq')
        .map { file -> [file.baseName, file] }
        | ALIGN
}
```

---

### 5.3 Control Flow Comparison

| Feature | Galaxy | Nextflow | Bi-directional Challenge |
|---------|--------|----------|--------------------------|
| **Conditionals** | `when` (unused) | `when:` + if/else + branch | HIGH: Galaxy lacks full support |
| **Loops** | Not supported | Full Groovy support | **NO GALAXY EQUIVALENT** ❌ |
| **Branching** | Manual (multiple steps) | Channel `branch` operator | HIGH: Different paradigms |
| **Merging paths** | Implicit (same outputs) | Channel `mix` / `join` | MEDIUM: Need to detect patterns |
| **Dynamic workflows** | Not supported | Groovy code generation | **NO GALAXY EQUIVALENT** ❌ |
| **Error handling** | Not supported | try/catch + error strategy | **NO GALAXY EQUIVALENT** ❌ |

---

## 6. Metadata & Configuration

### 6.1 Parameters

#### Galaxy Parameters

**Defined in workflow**:
```json
{
  "steps": {
    "1": {
      "type": "parameter_input",
      "label": "aligner",
      "tool_state": "{\"parameter_type\": \"text\", \"optional\": false}"
    }
  }
}
```

**Characteristics**:
- Parameters are **workflow inputs** (explicit steps)
- Appear as **form fields** in Galaxy UI
- No default values in workflow (set by user)
- Limited types (text, integer, float, boolean, select)

---

#### Nextflow Parameters

**Defined in params block**:
```groovy
// In main.nf
params.reads = 'data/*.fastq.gz'
params.aligner = 'bwa'
params.outdir = 'results'
params.single_end = false

// Or in nextflow.config
params {
    reads = 'data/*.fastq.gz'
    aligner = 'bwa'
    outdir = 'results'
}

// Or command line
// nextflow run main.nf --reads 'my/*.fastq' --aligner 'bowtie2'
```

**Characteristics**:
- Parameters are **global variables**
- Have **default values**
- Can be **overridden** via command line
- Any type (string, list, map, etc.)
- Can include **file paths**, **expressions**, **closures**

---

### 6.2 Resource Specifications

#### Galaxy Resources

**Defined in tool XML** (not visible in workflow):

```xml
<tool id="bwa" name="BWA-MEM">
  <requirements>
    <container type="docker">biocontainers/bwa:0.7.17</container>
    <requirement type="package" version="0.7.17">bwa</requirement>
  </requirements>
</tool>
```

**Characteristics**:
- Resources tied to **tool definition**
- Workflow has **no resource control**
- Galaxy admin configures resources

---

#### Nextflow Resources

**Multiple levels of configuration**:

```groovy
// 1. Process-level directives
process BWA {
    cpus 8
    memory '32 GB'
    time '2h'
    queue 'long'

    script: "bwa mem -t ${task.cpus} ..."
}

// 2. Label-based (recommended)
process BWA {
    label 'process_high'

    script: "bwa mem ..."
}

// In nextflow.config
process {
    withLabel: 'process_high' {
        cpus = 8
        memory = 32.GB
        time = 2.h
    }
}

// 3. Name-based
process {
    withName: 'BWA' {
        cpus = 16
        memory = 64.GB
    }
}
```

**Characteristics**:
- **Fine-grained** resource control
- Can override per-process
- **Dynamic** (can use expressions)
- Portable (labels separate resources from logic)

---

### 6.3 Software Environment

#### Galaxy Software

**Tool-specific** (defined in tool XML):

```xml
<requirements>
  <container type="docker">biocontainers/bwa:0.7.17</container>
  <requirement type="package" version="0.7.17">bwa</requirement>
</requirements>
```

**Deployment**:
- Tools installed by Galaxy admin
- Can use: Docker, Singularity, Conda
- Workflow **does not control** software versions

---

#### Nextflow Software

**Process-level** (multiple options):

```groovy
process BWA {
    // Option 1: Conda
    conda 'bioconda::bwa=0.7.17'

    // Option 2: Container
    container 'biocontainers/bwa:0.7.17'

    // Option 3: Module
    module 'bwa/0.7.17'

    // All three can coexist (Nextflow picks based on config)

    script: "bwa mem ..."
}
```

**Deployment**:
- Users specify environment per process
- Nextflow manages deployment
- **Portable** across execution platforms

---

### Metadata Comparison

| Feature | Galaxy | Nextflow | Bi-directional Challenge |
|---------|--------|----------|--------------------------|
| **Parameters** | Workflow inputs (steps) | Global params | MEDIUM: Need to extract/embed |
| **Default values** | None (user provides) | In code | MEDIUM: Galaxy can't represent defaults |
| **Resource specs** | Tool XML (external) | In process/config | HIGH: Galaxy hides resources |
| **Software env** | Tool XML (external) | In process | HIGH: Need to extract from XML |
| **Execution profiles** | None | nextflow.config | **NO GALAXY EQUIVALENT** ❌ |
| **Module system** | None | include/require | **NO GALAXY EQUIVALENT** ❌ |

---

## 7. Bi-Directional Conversion Challenges

### 7.1 Galaxy → Nextflow Conversion

#### Easy (Low Hanging Fruit ✅)

| Galaxy Feature | Nextflow Equivalent | Difficulty |
|----------------|---------------------|------------|
| Step → Process | 1:1 mapping | 🟢 LOW |
| tool_id → process name | Extract name from ID | 🟢 LOW |
| Input connections → Channel wiring | Trace dependencies | 🟡 MEDIUM |
| data_input → Channel.fromPath | Direct mapping | 🟢 LOW |
| parameter_input → params | Direct mapping | 🟢 LOW |
| Workflow metadata → Comments | Extract and embed | 🟢 LOW |

**Code example**:

```python
# Galaxy step
{
  "id": 2,
  "tool_id": "bwa_mem",
  "input_connections": {
    "reads": {"id": 0, "output_name": "output"}
  }
}

# Convert to Nextflow
process BWA_MEM {
    input:
    path reads  // from step_0.out

    script:
    "bwa mem $reads > out.bam"
}
```

---

#### Medium (Requires Inference ⚠️)

| Galaxy Feature | Nextflow Equivalent | Challenge |
|----------------|---------------------|-----------|
| No explicit types | Infer from tool_id / file extensions | Type inference |
| Collections → Tuples | Need to detect collection types | Structure inference |
| Implicit parallelism → Explicit channels | Understand data multiplicity | Cardinality analysis |
| tool_state (JSON) → Script parameters | Parse and convert | JSON → Code |

**Challenge: Type Inference**

```json
// Galaxy (no type info)
{
  "input_connections": {
    "reads": {"id": 0, "output_name": "output"}
  }
}

// Need to infer type for Nextflow
process BWA {
    input:
    path(reads)  // ← Infer this is 'path', not 'val' or 'tuple'

    script: "bwa mem $reads > out.bam"
}
```

**Solution**: Analyze tool_id (if "fastq" in name → path), file extensions, Galaxy datatype metadata.

---

#### Hard (Semantic Loss 🔴)

| Galaxy Feature | Nextflow Feature | Impossibility |
|----------------|------------------|---------------|
| No conditionals (annotation only) | if/else in script | **Need LLM to interpret annotations** |
| No loops | Groovy loops | **Cannot auto-generate** |
| No transformations | Channel operators (map/filter) | **Not representable** |
| Simple connections | Complex channel wiring (join/branch) | **Cannot infer intent** |

**Challenge: Conditional Logic from Annotations**

```json
// Galaxy
{
  "annotation": "Align with bowtie2, bwamem, or dragmap",
  "steps": {
    "5": {"tool_id": "bowtie2", "when": null},
    "6": {"tool_id": "bwamem", "when": null},
    "7": {"tool_id": "dragmap", "when": null}
  }
}

// Desired Nextflow output
process ALIGN {
    script:
    if (params.aligner == 'bowtie2') {
        "bowtie2 ..."
    } else if (params.aligner == 'bwamem') {
        "bwa mem ..."
    } else if (params.aligner == 'dragmap') {
        "dragmap ..."
    }
}
```

**Solution**:
1. **Pattern detection**: Detect "X or Y" in annotation
2. **Tool grouping**: Group steps with same inputs
3. **LLM decision**: Ask LLM to generate conditional structure

---

### 7.2 Nextflow → Galaxy Conversion

#### Easy (Low Hanging Fruit ✅)

| Nextflow Feature | Galaxy Equivalent | Difficulty |
|------------------|-------------------|------------|
| Process → Step | 1:1 mapping | 🟢 LOW |
| params → parameter_input | Direct mapping | 🟢 LOW |
| Process name → tool_id | Use as identifier | 🟢 LOW |
| Simple script → Tool wrapper | Generate Galaxy tool XML | 🟡 MEDIUM |

---

#### Medium (Lossy Conversion ⚠️)

| Nextflow Feature | Galaxy Equivalent | Loss |
|------------------|-------------------|------|
| Tuple → data_input | Flatten tuple | Lose structure |
| Channel operators (map) → Multiple steps | Create intermediate steps | Verbose |
| Container spec → Tool requirement | Embed in tool XML | External file |
| Resource specs → (none) | Drop (Galaxy admin sets) | Lose resource control |

**Challenge: Tuple Flattening**

```groovy
// Nextflow
process ALIGN {
    input:
    tuple val(meta), path(reads), path(index)

    script: "bwa mem $index $reads > ${meta.id}.bam"
}
```

```json
// Galaxy (no tuple concept)
{
  "input_connections": {
    "meta": {"id": 0, "output_name": "metadata"},    // ← Separate inputs
    "reads": {"id": 1, "output_name": "fastq"},
    "index": {"id": 2, "output_name": "index"}
  }
}
```

**Result**: Works, but **loses semantic grouping**.

---

#### Hard (Impossible / Major Loss 🔴)

| Nextflow Feature | Galaxy Capability | Impossibility |
|------------------|-------------------|---------------|
| if/else in script | No equivalent | **Must split into multiple steps** |
| Groovy code in workflow | No code in workflow | **Cannot represent** |
| Channel transformations (map/filter/branch) | No channel concept | **Must create intermediate steps** |
| Dynamic process calls | No dynamic execution | **Cannot represent** |
| Nested workflows | Flat structure | **Must flatten** |
| Error handling | No error strategy | **Drop error handling** |

**Challenge: Conditional Process**

```groovy
// Nextflow (single process)
process ALIGN {
    script:
    if (params.aligner == 'bwa') {
        "bwa mem $reads > out.bam"
    } else if (params.aligner == 'bowtie2') {
        "bowtie2 -x $index -U $reads -S out.bam"
    }
}
```

```json
// Galaxy (must create 2 separate steps)
{
  "steps": {
    "2": {
      "tool_id": "bwa",
      "label": "BWA (use if aligner=bwa)",
      "when": "${aligner} == 'bwa'"  // ← Theoretical, not used in practice
    },
    "3": {
      "tool_id": "bowtie2",
      "label": "Bowtie2 (use if aligner=bowtie2)",
      "when": "${aligner} == 'bowtie2'"
    }
  }
}
```

**Result**: **Verbose**, **conditional logic in annotation only**, user must manually choose.

---

**Challenge: Channel Transformations**

```groovy
// Nextflow (channel operations)
workflow {
    Channel.fromPath('*.fastq')
        .map { file -> tuple(file.baseName, file) }     // Transform
        .filter { id, file -> file.size() > 1000 }      // Filter
        .branch { id, file ->                            // Branch
            large: file.size() > 1000000
            small: file.size() <= 1000000
        }
        .set { branched }

    PROCESS_LARGE(branched.large)
    PROCESS_SMALL(branched.small)
}
```

```json
// Galaxy (no transformation support)
// Would require:
// 1. Create "map" tool (converts path to tuple)
// 2. Create "filter" tool (filters by size)
// 3. Create "branch" tool (splits into 2 outputs)
// 4. Connect to PROCESS_LARGE and PROCESS_SMALL

{
  "steps": {
    "0": {"type": "data_input", "label": "input"},
    "1": {"tool_id": "map_to_tuple", "input_connections": {"input": {"id": 0}}},
    "2": {"tool_id": "filter_by_size", "input_connections": {"input": {"id": 1}}},
    "3": {"tool_id": "branch_by_size", "input_connections": {"input": {"id": 2}}},
    "4": {"tool_id": "process_large", "input_connections": {"input": {"id": 3, "output_name": "large"}}},
    "5": {"tool_id": "process_small", "input_connections": {"input": {"id": 3, "output_name": "small"}}}
  }
}
```

**Result**: **Extremely verbose**, requires creating custom **Galaxy tools** for transformations.

---

### 7.3 Semantic Equivalence Matrix

| Conversion | Fidelity | Notes |
|------------|----------|-------|
| **Galaxy → Nextflow** | 🟢 **85-95%** | Most Galaxy features map cleanly to Nextflow. Main loss: implicit conditional logic in annotations. |
| **Nextflow → Galaxy** | 🔴 **50-70%** | Major semantic loss: conditionals, loops, transformations, dynamic workflows all lost or severely degraded. |

**Recommendation**: **Galaxy → Nextflow** is the **primary direction** for accurate conversion. **Nextflow → Galaxy** should be used for **simple workflows only** or with **manual cleanup**.

---

## 8. Implementation Roadmap

### Phase 1: Galaxy → Nextflow (Core Features)

**Goal**: Convert 80% of Galaxy workflows accurately

**Features**:
- ✅ Step → Process (1:1)
- ✅ Input connections → Channel wiring
- ✅ data_input → Channel.fromPath
- ✅ parameter_input → params
- ✅ Tool metadata → Process directives
- ⚠️ Type inference (from tool_id / extensions)
- ⚠️ Generate script blocks (use LLM)

**Estimated effort**: 2-3 weeks

---

### Phase 2: Galaxy → Nextflow (Conditionals)

**Goal**: Handle annotation-based conditionals

**Features**:
- 🔴 Parse annotations for "X or Y" patterns
- 🔴 Group alternative tools by inputs
- 🔴 Generate if/else or when directives
- 🔴 Create parameter switches

**Estimated effort**: 1-2 weeks

---

### Phase 3: Nextflow → Galaxy (Basic)

**Goal**: Convert simple Nextflow workflows

**Features**:
- ✅ Process → Step
- ✅ params → parameter_input
- ⚠️ Generate Galaxy tool XML for processes
- ⚠️ Flatten tuples to separate inputs
- 🔴 Split conditional processes into multiple steps

**Estimated effort**: 3-4 weeks

---

### Phase 4: Advanced Features

**Goal**: Handle complex patterns

**Features**:
- 🔴 Channel transformations → Custom Galaxy tools
- 🔴 Nested workflows → Flatten or preserve structure
- 🔴 Dynamic workflows → (not possible)
- 🔴 Error handling → (not possible)

**Estimated effort**: 4-6 weeks (with limitations)

---

## 9. Pitfalls Summary

### Top 10 Conversion Pitfalls

1. **🔴 CRITICAL: Conditional logic loss** (Nextflow if/else → Galaxy annotation text)
2. **🔴 CRITICAL: No loops in Galaxy** (Nextflow Groovy loops → not representable)
3. **🔴 CRITICAL: Channel transformations** (map/filter/branch → need custom tools)
4. **🟡 HIGH: Type inference** (Galaxy implicit → Nextflow explicit)
5. **🟡 HIGH: Tuple flattening** (Nextflow tuple → Galaxy separate inputs)
6. **🟡 MEDIUM: Resource specifications** (Nextflow → Galaxy tool XML)
7. **🟡 MEDIUM: Software environments** (Nextflow → Galaxy requirements)
8. **🟡 MEDIUM: Execution semantics** (Galaxy job queue vs Nextflow dataflow)
9. **🟢 LOW: Module system** (Nextflow includes → Galaxy has no modules)
10. **🟢 LOW: Multiple outputs** (Nextflow emit → Galaxy output array)

---

## 10. Recommendations

### For Bi-Directional Converter

**Primary Direction**: **Galaxy → Nextflow**
- Reason: Higher fidelity (85-95% semantic preservation)
- Most Galaxy features have direct Nextflow equivalents
- Main challenge: Detecting implicit conditionals (solvable with LLM)

**Secondary Direction**: **Nextflow → Galaxy**
- Use case: Simple workflows only
- Expect semantic loss (50-70% fidelity)
- Requires manual review and cleanup
- Not suitable for complex workflows with:
  - Conditionals in scripts
  - Channel transformations
  - Groovy code
  - Dynamic execution

---

### Hybrid Approach

**Recommendation**: Build **asymmetric converter**

1. **Galaxy → Nextflow**: Fully automatic (high fidelity)
2. **Nextflow → Galaxy**: Semi-automatic (requires human review)

```
┌──────────┐  Automatic   ┌──────────┐
│  Galaxy  │ ───────────> │ Nextflow │
│          │    (95%)     │          │
└──────────┘              └──────────┘
     ▲                         │
     │                         │
     │    Semi-automatic       │
     └─────────────────────────┘
            (60% + manual)
```

---

## 11. Conclusion

### Key Takeaways

1. **Galaxy and Nextflow have fundamentally different paradigms**:
   - Galaxy: Declarative, job-based, single JSON file
   - Nextflow: Imperative, dataflow, modular Groovy code

2. **Data type mismatches**:
   - Galaxy: Implicit typing, file extensions
   - Nextflow: Explicit typing, tuples, channels

3. **Execution model differences**:
   - Galaxy: One job per step (sequential unless independent)
   - Nextflow: Massive parallelism (one task per item)

4. **Control flow limitations**:
   - Galaxy: No real conditionals, no loops, no transformations
   - Nextflow: Full Groovy language (if/else, loops, closures)

5. **Conversion asymmetry**:
   - Galaxy → Nextflow: HIGH fidelity (85-95%)
   - Nextflow → Galaxy: MEDIUM fidelity (50-70%)

### Next Steps

1. **Implement Galaxy → Nextflow converter** (high priority)
   - Focus on core features first
   - Add conditional detection later
   - Use dual-LLM system for quality

2. **Nextflow → Galaxy converter** (lower priority)
   - Start with simple workflows
   - Document limitations clearly
   - Provide manual review checklist

3. **Build test suite**:
   - 94 Galaxy workflows as test cases
   - Validate roundtrip where possible
   - Measure semantic fidelity

4. **User documentation**:
   - Clearly communicate conversion limitations
   - Provide migration guide
   - Show before/after examples

---

**Status**: Analysis complete, ready for implementation ✅

