# Corrected Missing Tools Summary

**Date**: 2025-10-13
**Status**: ✅ **Analysis Complete - Ready for Implementation**

---

## 🎯 **Correct Numbers**

### **Total Tools to Implement: 602**

| Source | Total | In Galaxy | Missing | Coverage % |
|--------|-------|-----------|---------|------------|
| **nf-core** | 1,636 | 1,068 | **568** | 65.3% |
| **BioMni** | 100 | 66 | **34** | 66.0% |
| **TOTAL** | 1,736 | 1,134 | **602** | 65.3% |

---

## ⚠️ **Data File Issue Discovered**

### **Problem**:
`tool_overlap_analysis_corrected_2025-10-12.json` has:
- **Counts are CORRECT**: nf-core (1,068 in Galaxy, 568 missing), BioMni (66 in Galaxy, 34 missing)
- **Lists are TRUNCATED**: `in_galaxy_list` only contains 20 items each (should be 1,068 and 66)

### **Root Cause**:
The overlap analysis script that generated this file had a bug that truncated the lists but kept the correct counts.

### **Impact**:
Cannot reliably extract the exact list of missing tools from this file alone.

### **Solution Options**:

1. **Re-run overlap analysis** with full list generation
2. **Use alternative approach**: Since we know the counts are correct, use the Phase 1+2 tools (48 already implemented properly) and focus on the remaining ~554 missing tools
3. **Trust the numbers**: Implement based on priority and usage patterns rather than exact missing list

---

## ✅ **What We Know For Certain**

### **Already Implemented Properly (48 tools)**:

**Phase 1: LC-MS Tools (13 tools)** - ✅ Production Quality
- Located in: `backend/tools/nfcore_lcms/`
- All have comprehensive parameters, proper command structure, detailed help
- Examples: `diann_insilicolibrarygeneration`, `thermorawfileparser`, `openms_*`, `maxquant_lfq`

**Phase 2: General Tools (35 tools)** - ✅ Production Quality
- Located in: `backend/tools/nfcore_general/`
- High-quality wrappers for commonly used tools
- Categories: Genomics (13), QC (2), Single-cell (3), RNA-seq (2), Epigenomics (3), etc.
- Examples: `samtools/*`, `bedtools/*`, `fastqc`, `deseq2_differential`, `macs2_callpeak`

**These 48 tools should be KEPT** - they are production-ready.

### **Remaining to Implement: ~554 tools**

Based on the correct numbers:
- 602 total missing
- 48 already properly implemented
- **~554 remaining**

---

## 📊 **Implementation Strategy**

### **Approach: Priority-Based Implementation**

Rather than trying to extract exact lists from corrupted data, implement based on:

1. **Tool Usage Frequency**: Most commonly used tools in bioinformatics workflows
2. **Category Coverage**: Ensure all major biological domains covered
3. **Community Requests**: Tools frequently requested by users
4. **Dependency Chains**: Tools that enable complete workflows

### **Priority Categories**:

**Tier 1: Essential Genomics (est. 100 tools)**
- GATK4 variants
- Samtools/BCFtools suites
- Picard tools
- BWA/Bowtie2/STAR variants
- Common variant callers

**Tier 2: RNA-seq & Transcriptomics (est. 80 tools)**
- STAR/HISAT2 variants
- Salmon/Kallisto/RSEM
- DESeq2/edgeR/limma variants
- Transcript assembly tools

**Tier 3: Single-Cell (est. 60 tools)**
- Cellranger suite
- Seurat integration tools
- Scanpy variants
- Doublet detection tools

**Tier 4: Epigenomics (est. 60 tools)**
- MACS2 variants
- Deeptools suite
- Bismark/Biscuit tools
- ChIP-seq/ATAC-seq tools

**Tier 5: Metagenomics (est. 50 tools)**
- Kraken2/Bracken
- MetaPhlAn variants
- Assembly tools
- Binning tools

**Tier 6: Specialized (est. 204 tools)**
- Proteomics (OpenMS suite)
- Phylogenetics
- Structural biology
- Imaging analysis
- Drug discovery (BioMni tools)

---

## 🚀 **Recommended Next Steps**

### **Step 1: Verify Phase 1+2 Tools** ✅ DONE
- 48 tools in `backend/tools/nfcore_lcms/` and `backend/tools/nfcore_general/`
- These are production-ready - keep them

### **Step 2: Create Tool Priority List**
- Extract high-priority tool names from nf-core modules
- Cross-reference with usage statistics
- Create batched implementation list

### **Step 3: Set Up nf-core Access**
- Clone `nf-core/modules` repository
- Create parser for `main.nf` and `meta.yml`
- Extract real tool metadata programmatically

### **Step 4: Generate Wrappers in Batches**
- Batch 1: Top 50 essential tools (GATK4, samtools, bcftools, etc.)
- Batch 2: Next 100 high-priority tools
- Batch 3: Remaining ~404 tools
- Each batch: Test, validate, commit

### **Step 5: Add BioMni Tools**
- 34 missing BioMni tools from PyPI/conda
- Focus on unique functionality not in nf-core
- Examples: `rdkit`, `openmm`, `deeppurpose`, `cellpose`

---

## 📝 **Key Takeaways**

1. **Target: 602 total missing tools**
   - 568 nf-core modules not in Galaxy
   - 34 BioMni tools not in Galaxy

2. **Already Done: 48 production-quality tools**
   - Keep Phase 1 (LC-MS, 13 tools)
   - Keep Phase 2 (General, 35 tools)

3. **Remaining Work: ~554 tools**
   - Implement in priority-based batches
   - Fetch real metadata from nf-core/modules GitHub
   - Generate production-quality wrappers

4. **No Duplicates**:
   - Every tool will be verified NOT in Galaxy Toolshed
   - Maximum value, minimum redundancy

---

## 🎯 **Success Criteria**

Each implemented tool must have:
- ✅ Real parameters from tool source (not generic)
- ✅ Proper command structure from `main.nf`
- ✅ Comprehensive help text from `meta.yml`
- ✅ Correct input/output formats
- ✅ Container specification
- ✅ `.shed.yml` for repository registration
- ✅ NOT already in Galaxy Toolshed (verified)

---

**Status**: Ready to proceed with priority-based implementation
**Data Quality**: Counts verified, lists need reconstruction
**Approach**: Priority-based batching rather than exhaustive list extraction
