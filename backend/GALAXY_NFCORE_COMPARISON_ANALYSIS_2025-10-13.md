# Galaxy ToolShed vs nf-core Tools: Comparison Analysis (2025-10-13)

## Executive Summary

After comparing our nf-core tool wrappers with Galaxy ToolShed standards and examining the rich metadata available in nf-core's `meta.yml` files, I've identified several categories of information that are **missing from our current tools** but **should be added** to meet Galaxy best practices.

## What's Currently in Our Tools

✅ **Tool ID, name, version**
✅ **Container references** (99% versioned)
✅ **Basic description**
✅ **Command section** (with CDATA)
✅ **Generic inputs** (input file, threads, advanced_options)
✅ **Generic outputs** (output*)
✅ **Basic tests**
✅ **Help section** (minimal)
✅ **Citations** (BibTeX format)

## What's MISSING (Available in nf-core meta.yml)

### 1. **Enhanced Tool Descriptions** 🔴 HIGH PRIORITY

**Current:**
```xml
<description>Run FastQC on sequenced reads</description>
```

**Available in meta.yml:**
```yaml
tools:
  - "fastqc":
      description: |
        FastQC gives general quality metrics about your reads.
        It provides information about the quality score distribution
        across your reads, the per base sequence content (%A/C/G/T).

        You get information about adapter contamination and other
        overrepresented sequences.
```

**Impact:** Users get limited understanding of tool capabilities

### 2. **EDAM Topics and Operations** 🔴 HIGH PRIORITY

**Missing:**
```xml
<edam_topics>
    <edam_topic>topic_3168</edam_topic> <!-- Sequencing -->
</edam_topics>
<edam_operations>
    <edam_operation>operation_3218</edam_operation> <!-- Sequencing quality control -->
</edam_operations>
```

**Available in meta.yml:**
```yaml
keywords:
  - quality control
  - qc
  - adapters
  - fastq
```

**Impact:** Tools not discoverable via ontology-based search, poor semantic annotation

### 3. **Cross-References (xrefs)** 🟡 MEDIUM PRIORITY

**Missing:**
```xml
<xrefs>
    <xref type="bio.tools">fastqc</xref>
</xrefs>
```

**Available in meta.yml:**
```yaml
identifier: biotools:fastqc
```

**Impact:** No linkage to bio.tools registry, reduced tool discoverability

### 4. **Homepage and Documentation Links** 🟡 MEDIUM PRIORITY

**Current help section:**
```xml
<help><![CDATA[
**fastqc**

Run FastQC on sequenced reads

**nf-core Module Information:**
- Module: fastqc
- Container: biocontainers/fastqc:0.12.1--hdfd78af_0
]]></help>
```

**Available in meta.yml:**
```yaml
homepage: https://www.bioinformatics.babraham.ac.uk/projects/fastqc/
documentation: https://www.bioinformatics.babraham.ac.uk/projects/fastqc/Help/
tool_dev_url: https://github.com/Babraham-Bioinformatics/FastQC
```

**Should add:**
- Direct links to official documentation
- Homepage URL
- GitHub/source code repository
- Example usage
- Known limitations

### 5. **Detailed Input Parameters** 🟡 MEDIUM PRIORITY

**Current (Generic):**
```xml
<inputs>
    <param name="input" type="data" format="auto" label="Input File"/>
    <param name="threads" type="integer" value="4" label="Number of Threads"/>
    <param name="advanced_options" type="text" label="Advanced Options"/>
</inputs>
```

**Available in meta.yml:**
```yaml
input:
  - - meta:
        type: map
        description: Groovy Map containing sample information
    - reads:
        type: file
        description: List of input FastQ files of size 1 and 2 for single-end and paired-end data
        pattern: "*.{fq,fq.gz,fastq,fastq.gz}"
        ontologies:
          - edam: "http://edamontology.org/format_1930" # FASTQ
```

**Should map to specific Galaxy parameters:**
- Proper format restrictions (fastq, fastq.gz, bam, sam)
- Multiple input types when tool supports them
- Conditional parameters based on inputs
- Validators for parameter values
- Help text explaining each parameter

### 6. **Detailed Output Specifications** 🟡 MEDIUM PRIORITY

**Current (Generic):**
```xml
<outputs>
    <data name="output" format="auto" from_work_dir="output*"/>
</outputs>
```

**Available in meta.yml:**
```yaml
output:
  html:
    - - meta: {}
      - "*.html":
          description: FastQC report
          pattern: "*_fastqc.html"
  zip:
    - - meta: {}
      - "*.zip":
          description: FastQC report archive
          pattern: "*_fastqc.zip"
```

**Should have:**
- Multiple named outputs (html, zip, text reports)
- Specific format specifications
- Output labels with variable substitution
- Conditional outputs (optional: true)
- Output filters

### 7. **License Information** 🟢 LOW PRIORITY

**Missing:**
```xml
<license>GPL-2.0-only</license>
```

**Available in meta.yml:**
```yaml
licence: ["GPL-2.0-only"]
```

**Impact:** Legal compliance, user awareness of usage terms

### 8. **Error Handling (stdio)** 🟡 MEDIUM PRIORITY

**Missing:**
```xml
<stdio>
    <exit_code range="1:" level="fatal" />
    <regex match="Error:" level="fatal" />
    <regex match="Exception:" level="fatal" />
</stdio>
```

**Impact:** Poor error reporting, jobs may appear successful when they failed

### 9. **Version Detection** 🟢 LOW PRIORITY

**Missing:**
```xml
<version_command>fastqc --version</version_command>
```

**Impact:** Cannot automatically detect tool version, harder to track provenance

### 10. **Authors and Maintainers** 🟢 LOW PRIORITY

**Available in meta.yml:**
```yaml
authors:
  - "@drpatelh"
  - "@grst"
  - "@ewels"
maintainers:
  - "@drpatelh"
```

**Could add to help section or comments**

## Comparison with Example Galaxy ToolShed FastQC

Real Galaxy FastQC tool includes:

### Parameters we DON'T have:
- **Contaminants file** (optional)
- **Adapters file** (optional)
- **Limits file** (optional)
- **Format specification** (fastq vs bam input)
- **Nogroup flag** (checkbox)
- **Per base N content** (checkbox)
- Many other FastQC-specific options

### Outputs we DON'T have:
- **HTML report** (named output)
- **Raw data text file** (named output)
- **Summary text file** (named output)

### Features we DON'T have:
- Proper format restrictions on inputs
- Conditional parameters
- Multiple related outputs

## Recommendations by Priority

### 🔴 HIGH PRIORITY (Should implement immediately)

1. **Enhanced Descriptions**: Extract detailed descriptions from meta.yml `tools[].description`
2. **EDAM Annotations**: Map `keywords` to EDAM topics/operations for better discoverability

### 🟡 MEDIUM PRIORITY (Should implement soon)

3. **Homepage/Documentation Links**: Add to help section from meta.yml
4. **Detailed Inputs**: Map meta.yml input specifications to proper Galaxy parameters with formats
5. **Detailed Outputs**: Map meta.yml output specifications to named outputs with formats
6. **Error Handling**: Add stdio section with standard error patterns
7. **Cross-References**: Add bio.tools identifiers from meta.yml

### 🟢 LOW PRIORITY (Nice to have)

8. **License Information**: Add license element
9. **Version Command**: Add version detection
10. **Authors**: Include in help or comments

## Implementation Strategy

### Phase 1: Metadata Enhancement (1-2 days)
- Script to extract rich descriptions from meta.yml
- Script to map keywords to EDAM terms
- Script to add homepage/documentation links to help section
- Script to add cross-references

### Phase 2: Input/Output Mapping (3-5 days)
- Analyze meta.yml input/output specifications
- Create mapping logic from nf-core formats to Galaxy formats
- Generate specific parameters for each tool
- Handle conditional parameters

### Phase 3: Advanced Features (2-3 days)
- Add stdio error handling
- Add version commands
- Add license information
- Validate all enhancements

## Benefits of Enhancement

### For Users:
- **Better Discovery**: EDAM annotations enable semantic search
- **Clearer Understanding**: Rich descriptions explain tool purpose
- **Better Documentation**: Direct links to official docs
- **Proper Error Messages**: stdio handling provides clear failures

### For System:
- **Better Provenance**: Version tracking and proper citations
- **Better Integration**: bio.tools cross-references enable federated search
- **Better Quality**: Proper input/output validation

### For Compliance:
- **Legal**: License information
- **Standards**: EDAM ontology compliance
- **Best Practices**: Follows Galaxy IUC standards

## Conclusion

Our current tools are **functional** (100% quality score) but **minimal**. The nf-core meta.yml files contain rich metadata that would significantly improve:

1. Tool discoverability (EDAM, keywords, xrefs)
2. User understanding (detailed descriptions, documentation links)
3. Parameter specificity (detailed inputs/outputs vs generic ones)
4. Error handling (stdio section)
5. Compliance with Galaxy standards

**Recommendation**: Implement Phase 1 (metadata enhancement) immediately to bring tools closer to Galaxy ToolShed standards while maintaining production readiness.
