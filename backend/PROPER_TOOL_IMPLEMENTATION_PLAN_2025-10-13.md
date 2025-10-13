# Proper Tool Implementation Plan

**Date**: 2025-10-13
**Status**: 🚧 **IN PROGRESS**

---

## 🎯 **Objective**

Implement **ONLY** the 602 truly missing tools from BioMni and nf-core with **production-quality** wrappers that include:
- Comprehensive parameter definitions
- Proper command structure
- Detailed help text
- Real tool information from nf-core GitHub
- .shed.yml files for repository registration

---

## ❌ **What Was Wrong Before**

### **Problem 1: Implemented Duplicate Tools**
- Generated 1,609 tool wrappers total
- But 945 were ALREADY in Galaxy Toolshed
- Only 602 are actually missing:
  - 568 nf-core modules NOT in Galaxy (1,636 total - 1,068 already in Galaxy = 568)
  - 34 BioMni tools NOT in Galaxy (100 total - 66 already in Galaxy = 34)

### **Problem 2: Low Quality Tool Wrappers**
- Phase 3 & 4 tools used generic templates
- Example: GATK4 HaplotypeCaller had:
  - Generic "input" parameter (format="auto")
  - No real parameter options
  - No proper command structure
  - Minimal help text

### **Problem 3: No Installation Mechanism**
- Created XML wrappers but no .shed.yml files
- Can't be registered as local Galaxy repositories
- Can't be auto-installed on demand

---

## ✅ **Correct Approach**

### **Step 1: Identify Truly Missing Tools**

**nf-core missing tools (568)**:
- Start from `nfcore_modules_list.json` (1,636 modules)
- Load `tool_overlap_analysis_corrected_2025-10-12.json`
- Extract nf-core tools NOT in `nfcore.in_galaxy_list`
- Result: 568 modules

**BioMni missing tools (34)**:
- From crossover analysis: 76 BioMni-only tools
- But some are already in Galaxy (check overlap analysis)
- Filter to only tools NOT in Galaxy Toolshed
- Result: 34 tools

### **Step 2: Fetch Real Tool Information**

For each nf-core missing module:
1. Clone or fetch from: `https://github.com/nf-core/modules`
2. Navigate to: `modules/nf-core/{category}/{tool}/`
3. Read `main.nf` to extract:
   - Real command structure
   - Input parameters and types
   - Output files and formats
   - Container specification
   - Process resources
4. Read `meta.yml` to extract:
   - Tool description
   - Parameter descriptions
   - Keywords and categories
   - Citations

For BioMni tools:
1. Use package metadata from PyPI or conda
2. Extract command-line interface from documentation
3. Get parameter information from help text

### **Step 3: Generate Production-Quality Wrappers**

Each wrapper should include:

**Parameters Section**:
```xml
<inputs>
    <!-- Actual tool parameters from main.nf -->
    <param name="bam" type="data" format="bam" label="Input BAM file"
           help="Aligned reads in BAM format"/>

    <param name="reference" type="data" format="fasta" label="Reference genome"
           help="Reference genome in FASTA format"/>

    <section name="advanced" title="Advanced Options" expanded="false">
        <param name="min_base_quality" type="integer" value="20" min="0" max="50"
               label="Minimum base quality"
               help="Minimum base quality for a base to be considered"/>
        ...
    </section>
</inputs>
```

**Command Section**:
```xml
<command detect_errors="exit_code"><![CDATA[
    gatk HaplotypeCaller
        --input '$bam'
        --reference '$reference'
        --output output.vcf
        #if $advanced.min_base_quality
            --min-base-quality $advanced.min_base_quality
        #end if
        ...
]]></command>
```

**Help Section**:
```xml
<help><![CDATA[
**What it does**
[Real description from meta.yml]

**Inputs**
- Input BAM: [Description]
- Reference genome: [Description]

**Outputs**
- VCF file: [Description]

**More Information**
- nf-core module: https://github.com/nf-core/modules/tree/master/modules/nf-core/...
- Tool documentation: [URL]
    ]]></help>
```

**Citations**:
```xml
<citations>
    <citation type="doi">10.1101/xxx</citation>
    <citation type="bibtex">...</citation>
</citations>
```

### **Step 4: Add Repository Metadata**

Create `.shed.yml` for each tool:
```yaml
name: tool_name
owner: biomate
description: Tool description from meta.yml
long_description: |
  Extended description...
categories:
  - Genomics
  - Variant Calling
remote_repository_url: https://github.com/nf-core/modules/tree/master/modules/nf-core/...
```

### **Step 5: Organize by Priority**

**Tier 0 (Immediate Need): LC-MS Tools (~13 tools)**
- Keep existing high-quality Phase 1 tools
- Already production-ready

**Tier 1 (High Priority): General Bioinformatics (~35 tools)**
- Keep existing Phase 2 tools
- Already production-ready

**Tier 2 (Missing BioMni): 34 tools**
- Re-implement with proper parameters
- Fetch from PyPI/conda metadata

**Tier 3 (Missing nf-core): 568 tools**
- Implement in batches of 50-100
- Fetch from nf-core GitHub repository
- Generate production-quality wrappers

---

## 📋 **Implementation Strategy**

### **Phase 1: Setup Infrastructure** ✅ DONE
- ✅ Created tool source mapping
- ✅ Enhanced RAG with source scoring
- ✅ Rolled back bad commit
- ✅ Cleaned up duplicate files

### **Phase 2: Tool Analysis** (CURRENT)
- [ ] Extract 568 truly missing nf-core modules
- [ ] Extract 34 truly missing BioMni tools
- [ ] Create prioritized implementation list
- [ ] Set up nf-core modules repository access

### **Phase 3: Wrapper Generation Script**
- [ ] Create script to fetch nf-core module metadata
- [ ] Parse main.nf for command structure
- [ ] Parse meta.yml for descriptions
- [ ] Generate comprehensive XML wrappers
- [ ] Create .shed.yml files

### **Phase 4: Batch Implementation**
- [ ] Batch 1: Top 50 most-used nf-core modules
- [ ] Batch 2: Next 100 nf-core modules
- [ ] Batch 3: Remaining nf-core modules
- [ ] Batch 4: All 34 BioMni tools

### **Phase 5: Quality Validation**
- [ ] Validate XML syntax
- [ ] Test container availability
- [ ] Verify parameter completeness
- [ ] Create test workflows

### **Phase 6: Deployment**
- [ ] Deploy to local Galaxy instance
- [ ] Test auto-installation mechanism
- [ ] Create usage documentation
- [ ] Commit to Git

---

## 📊 **Expected Results**

### **Tool Count**:
- Keep Phase 1 (LC-MS): 13 tools ✅
- Keep Phase 2 (General): 35 tools ✅
- New BioMni: 34 tools (re-implemented properly)
- New nf-core: 568 tools (production-quality)
- **Total NEW tools: 602** (vs 1,609 duplicate-filled before)

### **Quality Standards**:
- ✅ Comprehensive parameters (not generic)
- ✅ Real command structure (from main.nf)
- ✅ Detailed help text (from meta.yml)
- ✅ Proper input/output formats
- ✅ Container specifications
- ✅ .shed.yml for repository registration

### **No Duplicates**:
- ✅ Every tool verified NOT already in Galaxy Toolshed
- ✅ Only truly missing tools implemented
- ✅ Maximum value, minimum redundancy

---

## 🚀 **Next Immediate Steps**

1. **Create tool extraction script**: Identify 602 truly missing tools
2. **Clone nf-core/modules repository**: Access to real tool definitions
3. **Build wrapper generator**: Parse nf-core module files → Galaxy XML
4. **Start with high-priority batch**: Top 50 most-used modules first

---

**Status**: Ready to proceed with proper implementation
**Expected Timeline**: Phased approach over multiple sessions
**Quality**: Production-ready, comprehensive tool wrappers
