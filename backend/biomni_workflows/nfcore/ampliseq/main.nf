// nf-core/ampliseq — user-facing parameter stub
// Amplicon sequencing: 16S/ITS/other amplicons → OTU/ASV table → diversity analysis
//
// Pipeline phases:
// * 1. Input validation — samplesheet QC, primer sequence check
// * 2. Trimming & QC — primer removal (Cutadapt), DADA2 quality profiling
// * 3. Denoising — DADA2 error learning, ASV inference, chimera removal
// * 4. Taxonomy — QIIME2 classifier, SILVA / UNITE database assignment
// * 5. Diversity — alpha rarefaction, beta diversity (UniFrac, Bray-Curtis)
// * 6. Report — MultiQC, ASV table TSV, taxonomy barplot

params.input             = null          // Samplesheet CSV or FASTQ directory
params.FW_primer         = null          // Forward primer sequence (e.g. GTGYCAGCMGCCGCGGTAA for 515F)
params.RV_primer         = null          // Reverse primer sequence (e.g. GGACTACNVGGGTWTCTAAT for 806R)
params.region            = null          // Hypervariable region: V1-V2 | V3-V4 | V4 | V6-V8 | ITS1 | ITS2
params.amplicon_type     = 'SSU'         // Amplicon type: SSU (16S/18S) | ITS | LSU
params.trunclenf         = null          // Forward read truncation length (DADA2)
params.trunclenr         = null          // Reverse read truncation length (DADA2)
params.trunc_qmin        = 25            // Minimum quality score for auto truncation
params.classifier        = null          // Taxonomy classifier: silva138 | silva_138.1 | unite
params.ignore_empty_input_files = false  // Skip samples with empty FASTQ
params.skip_dada_quality = false         // Skip DADA2 quality profiling
params.skip_taxonomy     = false         // Skip taxonomic classification
params.skip_alpha_rarefaction = false    // Skip alpha diversity rarefaction curves
params.outdir            = './results'
params.email             = null
params.max_memory        = '64.GB'
params.max_cpus          = 16
params.max_time          = '120.h'
