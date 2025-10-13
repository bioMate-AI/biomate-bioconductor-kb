# Missing Information Summary (2025-10-13)

## Overview

Our nf-core tools are **functionally complete** (100% quality score) but **minimally documented** compared to Galaxy ToolShed standards. The nf-core `meta.yml` files contain rich metadata that we're not currently using.

## What's Missing (By Priority)

### 🔴 HIGH PRIORITY

| Missing Element | Currently | Available in nf-core | Impact | Tools Affected |
|----------------|-----------|---------------------|---------|----------------|
| **Enhanced Descriptions** | Brief 1-line | Detailed multi-paragraph with features list | Users don't understand tool capabilities | ~1,600 tools |
| **EDAM Annotations** | None | Keywords available for mapping | Tools not discoverable via ontology search | ~1,600 tools |

### 🟡 MEDIUM PRIORITY

| Missing Element | Currently | Available in nf-core | Impact | Tools Affected |
|----------------|-----------|---------------------|---------|----------------|
| **Homepage Links** | Not in help | URL in meta.yml | No link to official docs | ~1,600 tools |
| **Documentation Links** | Not in help | URL in meta.yml | Users can't find usage guides | ~1,600 tools |
| **Specific Inputs** | Generic: input, threads, advanced_options | Detailed specs with formats and patterns | Limited parameter validation | ~1,600 tools |
| **Specific Outputs** | Generic: output* | Multiple named outputs with formats | Poor output organization | ~1,600 tools |
| **Error Handling (stdio)** | None | - | Jobs may silently fail | ~1,600 tools |
| **Cross-References** | None | bio.tools identifiers | No linkage to tool registries | ~1,400 tools |

### 🟢 LOW PRIORITY

| Missing Element | Currently | Available in nf-core | Impact | Tools Affected |
|----------------|-----------|---------------------|---------|----------------|
| **License Info** | Only in citations | Explicit license field | Legal compliance issues | ~1,600 tools |
| **Version Command** | None | - | Can't auto-detect versions | ~1,600 tools |
| **Authors/Maintainers** | None | Listed in meta.yml | No contact info | ~1,600 tools |

## Example: FastQC Tool

### Current Tool (Minimal)

```xml
<tool id="nfcore_fastqc" name="fastqc" version="1.0">
    <description>Run FastQC on sequenced reads</description>
    <requirements>
        <container type="docker">biocontainers/fastqc:0.12.1</container>
    </requirements>
    <command>...</command>
    <inputs>
        <param name="input" type="data" format="auto"/>
        <param name="threads" type="integer" value="4"/>
        <param name="advanced_options" type="text"/>
    </inputs>
    <outputs>
        <data name="output" format="auto" from_work_dir="output*"/>
    </outputs>
    <help>
        Run FastQC on sequenced reads

        Module: fastqc
        Container: biocontainers/fastqc:0.12.1
    </help>
</tool>
```

### Enhanced Tool (Using nf-core metadata)

```xml
<tool id="nfcore_fastqc" name="FastQC" version="0.12.1">
    <description>A quality control tool for high throughput sequence data</description>

    <edam_topics>
        <edam_topic>topic_3168</edam_topic> <!-- Sequencing -->
        <edam_topic>topic_3572</edam_topic> <!-- Data quality management -->
    </edam_topics>
    <edam_operations>
        <edam_operation>operation_3218</edam_operation> <!-- Sequencing quality control -->
    </edam_operations>

    <xrefs>
        <xref type="bio.tools">fastqc</xref>
    </xrefs>

    <requirements>
        <container type="docker">biocontainers/fastqc:0.12.1--hdfd78af_0</container>
    </requirements>

    <stdio>
        <exit_code range="1:" level="fatal"/>
        <regex match="Error:" level="fatal"/>
    </stdio>

    <version_command>fastqc --version</version_command>

    <command>...</command>

    <inputs>
        <param name="input" type="data" format="fastq,fastq.gz,bam,sam"
               label="Input sequencing data"/>
        <param name="contaminants" type="data" format="tabular" optional="true"
               label="Contaminants file"/>
        <param name="threads" type="integer" value="1" min="1" max="32"
               label="Number of threads"/>
    </inputs>

    <outputs>
        <data name="html_report" format="html" from_work_dir="*_fastqc.html"
              label="${tool.name} on ${on_string}: HTML report"/>
        <data name="zip_archive" format="zip" from_work_dir="*_fastqc.zip"
              label="${tool.name} on ${on_string}: Raw data"/>
    </outputs>

    <help><![CDATA[
**What it does**

FastQC gives general quality metrics about your sequencing reads. It provides
information about the quality score distribution across your reads, per base
sequence content (%A/C/G/T), adapter contamination and other overrepresented
sequences.

**Inputs**

- Sequencing reads in FASTQ, BAM, or SAM format
- Optional contaminants file for custom contamination screening

**Outputs**

- HTML report with quality metrics and plots
- ZIP archive containing raw data and images

**More Information**

- Homepage: https://www.bioinformatics.babraham.ac.uk/projects/fastqc/
- Documentation: https://www.bioinformatics.babraham.ac.uk/projects/fastqc/Help/
- Source code: https://github.com/s-andrews/FastQC

**Keywords:** quality control, qc, adapters, fastq, sequencing

**nf-core Module:** fastqc
**Container:** biocontainers/fastqc:0.12.1--hdfd78af_0
**Authors:** @drpatelh, @grst, @ewels, @FelixKrueger
    ]]></help>

    <citations>
        <citation type="bibtex">
            @misc{nfcore_fastqc,
                title = {nf-core fastqc module},
                url = {https://github.com/nf-core/modules/tree/master/modules/nf-core/fastqc},
                year = {2024}
            }
        </citation>
    </citations>

    <license>GPL-2.0-only</license>
</tool>
```

## Benefits of Enhancement

### Immediate Benefits
- ✅ **Better Discovery**: EDAM annotations enable semantic/ontology-based search
- ✅ **User Understanding**: Rich descriptions explain what tools actually do
- ✅ **Documentation Access**: Direct links to official guides and tutorials
- ✅ **Better Errors**: stdio handling provides clear failure messages

### Long-term Benefits
- ✅ **Compliance**: Meets Galaxy IUC standards and best practices
- ✅ **Interoperability**: bio.tools cross-references enable federated search
- ✅ **Maintainability**: Clear authorship and version tracking
- ✅ **Legal**: Explicit license information

## Recommended Actions

### Phase 1: Metadata Enhancement (Priority: 🔴 HIGH)
**Effort:** 1-2 days | **Impact:** Immediate user benefit

1. Extract detailed descriptions from meta.yml
2. Map keywords to EDAM topics/operations
3. Add homepage and documentation links
4. Add bio.tools cross-references

**Result:** Users can discover, understand, and learn about tools

### Phase 2: Input/Output Enhancement (Priority: 🟡 MEDIUM)
**Effort:** 3-5 days | **Impact:** Better validation and usability

1. Parse meta.yml input specifications
2. Map to Galaxy format restrictions
3. Create specific named outputs
4. Add parameter validators

**Result:** Better parameter validation, clearer outputs

### Phase 3: Advanced Features (Priority: 🟢 LOW)
**Effort:** 2-3 days | **Impact:** Professional polish

1. Add stdio error handling
2. Add version commands
3. Add license information
4. Include author/maintainer info

**Result:** Production-grade Galaxy tools

## Current Status

✅ **Functional:** 100% quality, all tools work
⚠️ **Documentation:** Minimal, lacks rich metadata
⚠️ **Discoverability:** No EDAM annotations or cross-references
⚠️ **Standards Compliance:** Basic but not IUC-compliant

## Next Steps

**Decision Point:** Should we enhance these 1,632 tools with nf-core metadata?

**Option 1:** Keep as-is (functional but minimal)
- ✅ Pro: No additional work
- ❌ Con: Poor user experience, limited discoverability

**Option 2:** Enhance with Phase 1 (recommended)
- ✅ Pro: Much better UX, standards-compliant
- ✅ Pro: Leverages existing nf-core metadata
- ⚠️ Effort: 1-2 days automation work

**Option 3:** Full enhancement (all phases)
- ✅ Pro: Professional Galaxy ToolShed quality
- ⚠️ Effort: 6-10 days work
