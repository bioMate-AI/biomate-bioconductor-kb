# Workflow Repository Comparison Analysis

**Date:** 2025-11-18
**Status:** Research Complete
**Purpose:** Compare workflow collections to build optimal workflow repository

---

## Executive Summary

Three distinct workflow collections exist in the BioMate project:

| Collection | Location | Count | Format | Naming |
|------------|----------|-------|--------|--------|
| **Structured (User's)** | `backend/galaxy_workflows/` | 94 | .ga | Descriptive |
| **Full IWC Collection** | `research/galaxy/lib/galaxy/ai/data/workflows/` | 951 | .json | Hash-based |
| **nf-core Pipelines** | `backend/nf-core-workflows/` | 7 | Nextflow | Pipeline names |

The colleague's "entire collection" appears to be the 951 JSON files - approximately **10x more workflows** than the structured repository.

---

## Detailed Repository Analysis

### 1. Structured Galaxy Workflows (User's Repository)

**Location:** `/home/yzhang/biomate/backend/galaxy_workflows/`

**Characteristics:**
- **Count:** 94 files
- **Format:** .ga (Galaxy Archive - native Galaxy format)
- **Organization:** Flat directory structure
- **Naming Convention:** Descriptive, human-readable names

**Sample Files:**
```
assembly_flye_long_reads.ga
assembly_megahit_metagenome.ga
assembly_spades_bacterial.ga
bam_filter_by_quality.ga
bam_merge_samples.ga
bam_sort_index.ga
chip_seq_peak_calling.ga
fastq_align_dna.ga
fastq_align_rna.ga
fastq_quality_control.ga
fastq_trim_adapters.ga
metagenomics_taxonomic_classification.ga
rnaseq_deseq2_analysis.ga
rnaseq_differential_expression.ga
variant_calling_freebayes.ga
vcf_annotate_snpeff.ga
vcf_filter_quality.ga
```

**Strengths:**
- Clear, self-documenting filenames
- Easy to browse and find workflows
- Production-ready, curated selection
- Covers major bioinformatics domains

**Weaknesses:**
- Limited coverage (only 94 workflows)
- May miss specialized/niche analyses

---

### 2. Full IWC Collection (Colleague's Repository)

**Location:** `/home/yzhang/biomate/research/galaxy/lib/galaxy/ai/data/workflows/`

**Characteristics:**
- **Count:** 951 files
- **Format:** .json (Galaxy workflow JSON export)
- **Organization:** Flat directory structure
- **Naming Convention:** Hash-based identifiers

**Sample Files:**
```
workflow_00381bbae3fd7e78.json
workflow_0044c3c24b5c76c1.json
workflow_009c5bdb619fa08f.json
workflow_00a0f6fcdbd7a4f8.json
workflow_00b6c8c73a0e4f5f.json
workflow_00c7e51d1d15eec5.json
workflow_00dfb27eb12d20b5.json
workflow_00e84e1ec46dbb2a.json
workflow_0107f97ed2c9c25d.json
workflow_011c2bc14a8d43f1.json
```

**Strengths:**
- Comprehensive coverage (951 workflows)
- Likely includes IWC (Intergalactic Workflow Commission) standard workflows
- Good for training AI models
- Complete reference collection

**Weaknesses:**
- Hash-based names provide no context
- Difficult to find specific workflows
- May include duplicates or variations
- Quality/testing status unknown
- Requires metadata lookup to understand each workflow

---

### 3. nf-core Workflows (Nextflow Pipelines)

**Location:** `/home/yzhang/biomate/backend/nf-core-workflows/`

**Pipelines:**
1. **chipseq** - ChIP-seq peak calling and analysis
2. **diaproteomics** - DIA mass spectrometry proteomics
3. **differentialabundance** - Differential abundance analysis
4. **methylseq** - Bisulfite sequencing methylation analysis
5. **proteomicslfq** - Label-free quantitative proteomics
6. **rnaseq** - RNA sequencing analysis
7. **sarek** - Germline and somatic variant calling

**Characteristics:**
- **Count:** 7 pipelines
- **Format:** Nextflow DSL2
- **Quality:** nf-core certified (high quality, well-tested)

**Note:** These are Nextflow pipelines, not Galaxy workflows. They require separate execution infrastructure but represent gold-standard bioinformatics pipelines.

---

## Comparison Matrix

| Aspect | Structured (94) | Full Collection (951) | nf-core (7) |
|--------|-----------------|----------------------|-------------|
| **Discovery** | Easy (descriptive names) | Hard (hash names) | Easy (pipeline names) |
| **Coverage** | Moderate | Comprehensive | Specialized |
| **Quality Assurance** | Curated | Unknown | Certified |
| **AI Training** | Good | Excellent | N/A (different format) |
| **Production Use** | Immediate | Needs curation | Needs Nextflow runtime |
| **Maintenance** | Easy to update | Hard to track changes | Community maintained |

---

## Gap Analysis

### What Structured Repository Has That Full Collection Lacks
- Clear organization by domain (assembly, alignment, variant calling, etc.)
- Immediate usability without metadata lookup
- Known quality/testing status

### What Full Collection Has That Structured Repository Lacks
- **857 additional workflows** (951 - 94 = 857)
- Likely includes:
  - Specialized domain workflows
  - Alternative approaches to same analyses
  - Edge case workflows
  - Community-contributed workflows
  - IWC reference implementations

---

## Recommendations

### Short-term Actions

1. **Extract Metadata from Full Collection**
   - Parse JSON files to extract workflow names, descriptions, tool lists
   - Create an index/catalog of all 951 workflows
   - Identify workflows by their actual content, not hash names

2. **Identify High-Value Gaps**
   - Compare tool coverage between collections
   - Find workflows in full collection that cover domains missing from structured repo
   - Prioritize adding workflows for underrepresented analysis types

3. **Deduplication Analysis**
   - Check for duplicate/similar workflows in full collection
   - Identify "best" version of each workflow type

### Medium-term Actions

4. **Merge and Curate**
   - Add selected workflows from full collection to structured repo
   - Rename with descriptive names
   - Test and validate before inclusion
   - Target: Expand from 94 to 200-300 high-quality workflows

5. **Create Categorization System**
   - Organize by analysis domain (genomics, transcriptomics, proteomics, etc.)
   - Tag by data type (Illumina, PacBio, Nanopore, etc.)
   - Tag by organism type (human, bacterial, plant, etc.)

6. **Integrate nf-core Equivalents**
   - For each nf-core pipeline, ensure Galaxy equivalent exists
   - Document mapping between Galaxy workflows and nf-core pipelines

### Long-term Actions

7. **Automated Workflow Discovery**
   - Set up pipeline to automatically fetch new IWC workflows
   - Auto-generate metadata and categorization
   - Queue for human review before adding to structured repo

8. **Quality Metrics**
   - Track usage statistics for each workflow
   - Collect user feedback
   - A/B test alternative workflows for same analysis

---

## Technical Details

### File Format Comparison

**Galaxy Archive (.ga):**
- Native Galaxy format
- Can be directly imported
- May reference specific tool versions

**Galaxy JSON (.json):**
- Export format
- More portable
- Easier to parse programmatically

**Conversion:** Both formats are interchangeable within Galaxy.

### IWC (Intergalactic Workflow Commission)

The full collection likely contains workflows from:
- https://github.com/galaxyproject/iwc
- Community-contributed best practices
- Reference implementations for common analyses

These are considered "gold standard" Galaxy workflows with:
- Defined inputs/outputs
- Comprehensive testing
- Documentation
- Version control

---

## Next Steps

### Immediate (This Session)
1. Create script to extract metadata from all 951 JSON workflows
2. Generate catalog with: name, description, tools used, input types
3. Compare tool coverage between collections

### Follow-up (Next Session)
1. Identify top 50 workflows to add to structured repo
2. Develop naming convention and categorization scheme
3. Set up workflow validation pipeline

---

## Files Referenced

| Path | Purpose |
|------|---------|
| `/home/yzhang/biomate/backend/galaxy_workflows/` | Structured workflow repository |
| `/home/yzhang/biomate/research/galaxy/lib/galaxy/ai/data/workflows/` | Full IWC collection |
| `/home/yzhang/biomate/backend/nf-core-workflows/` | Nextflow pipelines |
| `/home/yzhang/biomate/frontend/client/src/lib/workflow-templates.ts` | Frontend workflow templates |

---

## Conclusion

The user's structured repository (94 workflows) provides a curated, production-ready foundation with excellent discoverability. The colleague's full collection (951 workflows) offers 10x the coverage but requires significant curation effort to be usable.

**Recommended Strategy:** Use structured repo as the production foundation, selectively add high-value workflows from full collection after metadata extraction and quality validation.

**Target State:** 200-300 well-documented, categorized, tested workflows covering all major bioinformatics analysis types.

---

**Document Version:** 1.0
**Author:** AI Assistant (Claude)
