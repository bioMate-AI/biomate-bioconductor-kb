# nf-core Workflow Reformatting Report

**Date:** 2025-11-19 12:57
**Total:** 93
**Success:** 93
**Failed:** 0

## Changes Made

1. Added `license: MIT`
2. Added `creator` with nf-core and BioMate attribution
3. Added `label` fields to all input steps
4. Converted top-level `outputs` to `workflow_outputs` in steps
5. Added `release` version
6. Added `report` template
7. Added `tags` for organization

## Tool ID Format

Tool IDs are kept as-is (not ToolShed format) because these are custom tools:
- `nfcore_*` - nf-core specific tools
- `umitools_*` - UMI-tools
- `Filter1`, etc. - Galaxy built-ins
- ToolShed format for tools that exist there

## Reformatted Workflows

| Workflow | Steps | Outputs | Status |
|----------|-------|---------|--------|
| ABUNDANCE_DIFFERENTIAL_FILTER | 22 | 0 | ✓ |
| ARCHIVE_EXTRACT | 5 | 0 | ✓ |
| BAM_CNV_WISECONDORX | 13 | 0 | ✓ |
| BAM_CREATE_SOM_PON_GATK | 9 | 6 | ✓ |
| BAM_DEDUP_STATS_SAMTOOLS_UMICOLLAPSE | 11 | 0 | ✓ |
| BAM_DEDUP_STATS_SAMTOOLS_UMITOOLS | 12 | 0 | ✓ |
| BAM_DEDUP_UMI | 26 | 0 | ✓ |
| BAM_DOCOUNTS_CONTAMINATION_ANGSD | 4 | 2 | ✓ |
| BAM_MARKDUPLICATES_PICARD | 16 | 0 | ✓ |
| BAM_MARKDUPLICATES_SAMTOOLS | 7 | 0 | ✓ |
| BAM_METHYLDACKEL | 9 | 3 | ✓ |
| BAM_NGSCHECKMATE | 12 | 0 | ✓ |
| BAM_QC_PICARD | 10 | 0 | ✓ |
| BAM_RSEQC | 11 | 0 | ✓ |
| BAM_SORT_STATS_SAMTOOLS | 5 | 6 | ✓ |
| BAM_SPLIT_BY_REGION | 5 | 0 | ✓ |
| BAM_STATS_MIRNA_MIRTOP | 11 | 0 | ✓ |
| BAM_STATS_SAMTOOLS | 5 | 3 | ✓ |
| BAM_STRINGTIE_MERGE | 5 | 0 | ✓ |
| BAM_SUBSAMPLEDEPTH_SAMTOOLS | 7 | 0 | ✓ |
| BAM_TAPS_CONVERSION | 8 | 3 | ✓ |
| BAM_TUMOR_NORMAL_SOMATIC_VARIANT_CALLING_GATK | 17 | 12 | ✓ |
| BAM_TUMOR_NORMAL_SOMATIC_VARIANT_CALLING_STRELKA | 10 | 0 | ✓ |
| BAM_TUMOR_ONLY_SOMATIC_VARIANT_CALLING_GATK | 24 | 0 | ✓ |
| BAM_VARIANT_CALLING_SORT_FREEBAYES_BCFTOOLS | 8 | 3 | ✓ |
| BAM_VARIANT_DEMIX_BOOT_FREYJA | 17 | 0 | ✓ |
| BCL_DEMULTIPLEX | 11 | 0 | ✓ |
| BEDGRAPH_BEDCLIP_BEDGRAPHTOBIGWIG | 4 | 2 | ✓ |
| BED_SCATTER_BEDTOOLS | 3 | 2 | ✓ |
| DEEPVARIANT | 12 | 0 | ✓ |
| DIA_PROTEOMICS_ANALYSIS | 15 | 0 | ✓ |
| DIFFERENTIAL_FUNCTIONAL_ENRICHMENT | 16 | 0 | ✓ |
| FAA_SEQFU_SEQKIT | 10 | 0 | ✓ |
| FASTA_BINNING_CONCOCT | 7 | 7 | ✓ |
| FASTA_BUILD_ADD_KRAKEN2 | 10 | 0 | ✓ |
| FASTA_BUILD_ADD_KRAKEN2_BRACKEN | 11 | 0 | ✓ |
| FASTA_CLEAN_FCS | 15 | 0 | ✓ |
| FASTA_EXPLORE_SEARCH_PLOT_TIDK | 9 | 5 | ✓ |
| FASTA_GXF_BUSCO_PLOT | 12 | 12 | ✓ |
| FASTA_HMMSEARCH_RANK_FASTAS | 6 | 2 | ✓ |
| FASTA_INDEX_BISMARK_BWAMETH | 17 | 0 | ✓ |
| FASTA_INDEX_DNA | 11 | 0 | ✓ |
| FASTA_INDEX_METHYLSEQ | 21 | 0 | ✓ |
| FASTA_NEWICK_EPANG_GAPPA | 28 | 0 | ✓ |
| FASTA_VCLUST_PREFILTER_ALIGN_CLUSTER | 13 | 0 | ✓ |
| FASTQ_ALIGN_BAMCMP_BWA | 9 | 13 | ✓ |
| FASTQ_ALIGN_BOWTIE2 | 7 | 9 | ✓ |
| FASTQ_ALIGN_BWA | 13 | 0 | ✓ |
| FASTQ_ALIGN_BWAALN | 9 | 0 | ✓ |
| FASTQ_ALIGN_CHROMAP | 14 | 0 | ✓ |
| FASTQ_ALIGN_DEDUP_BISMARK | 13 | 12 | ✓ |
| FASTQ_ALIGN_DEDUP_BWAMEM | 11 | 0 | ✓ |
| FASTQ_ALIGN_DEDUP_BWAMETH | 20 | 0 | ✓ |
| FASTQ_ALIGN_DNA | 15 | 4 | ✓ |
| FASTQ_ALIGN_HISAT2 | 6 | 9 | ✓ |
| FASTQ_ALIGN_MAPAD | 14 | 0 | ✓ |
| FASTQ_ALIGN_STAR | 8 | 18 | ✓ |
| FASTQ_CONTAM_SEQTK_KRAKEN | 7 | 0 | ✓ |
| FASTQ_CREATE_UMI_CONSENSUS_FGBIO | 37 | 8 | ✓ |
| FASTQ_DECONTAMINATE_DEACON | 4 | 3 | ✓ |
| FASTQ_DOWNLOAD_PREFETCH_FASTERQDUMP_SRATOOLS | 7 | 0 | ✓ |
| FASTQ_EXTRACT_KRAKEN_KRAKENTOOLS | 8 | 0 | ✓ |
| FASTQ_FASTQC_UMITOOLS_FASTP | 14 | 0 | ✓ |
| FASTQ_FASTQC_UMITOOLS_TRIMGALORE | 11 | 0 | ✓ |
| FASTQ_FIND_MIRNA_MIRDEEP2 | 9 | 0 | ✓ |
| FASTQ_GENERATE_STATISTICS | 6 | 7 | ✓ |
| FASTQ_NGSCHECKMATE | 12 | 0 | ✓ |
| FASTQ_PREPROCESS | 11 | 0 | ✓ |
| FASTQ_QC_TRIM_FILTER_SETSTRANDEDNESS | 25 | 0 | ✓ |
| FASTQ_SANITISE_SEQKIT | 6 | 2 | ✓ |
| FASTQ_SUBSAMPLE_FQ_SALMON | 13 | 0 | ✓ |
| FASTQ_TAXONOMIC_PROFILE_METAPHLAN | 5 | 0 | ✓ |
| FASTQ_TRIM_FASTP_FASTQC | 19 | 0 | ✓ |
| H5AD_REMOVEBACKGROUND_BARCODES_CELLBENDER_ANNDATA | 4 | 0 | ✓ |
| HOMER_GROSEQ | 12 | 0 | ✓ |
| MMSEQS_CONTIG_TAXONOMY | 7 | 4 | ✓ |
| MMSEQS_FASTA_CLUSTER | 10 | 0 | ✓ |
| MULTIPLE_IMPUTE_GLIMPSE2 | 14 | 0 | ✓ |
| QUANTIFY_PSEUDO_ALIGNMENT | 29 | 0 | ✓ |
| TIFF_SEGMENTATION_VPT | 13 | 0 | ✓ |
| UTILS_NEXTFLOW_PIPELINE | 8 | 0 | ✓ |
| UTILS_NFCORE_PIPELINE | 4 | 0 | ✓ |
| UTILS_NFSCHEMA_PLUGIN | 13 | 0 | ✓ |
| UTILS_NFVALIDATION_PLUGIN | 10 | 0 | ✓ |
| UTILS_REFERENCES | 9 | 2 | ✓ |
| VCF_ANNOTATE_ENSEMBLVEP | 14 | 0 | ✓ |
| VCF_ANNOTATE_ENSEMBLVEP_SNPEFF | 16 | 0 | ✓ |
| VCF_ANNOTATE_SNPEFF | 5 | 5 | ✓ |
| VCF_EXTRACT_RELATE_SOMALIER | 10 | 5 | ✓ |
| VCF_FILTER_BCFTOOLS_ENSEMBLVEP | 9 | 0 | ✓ |
| VCF_GATHER_BCFTOOLS | 10 | 0 | ✓ |
| VCF_IMPUTE_GLIMPSE | 10 | 0 | ✓ |
| VCF_PHASE_SHAPEIT5 | 12 | 0 | ✓ |
