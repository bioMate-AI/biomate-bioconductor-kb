// nf-core/ampliseq — user-facing parameter stub
// Amplicon sequencing: 16S/ITS/other amplicons → OTU/ASV table → diversity analysis

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

// [Input Validation]
process VALIDATE_INPUT {
    script: """
    check_samplesheet.py --input ${params.input} \
        --amplicon_type ${params.amplicon_type} \
        ${params.ignore_empty_input_files ? '--ignore-empty' : ''}
    """
}

// [Trimming & QC]
process CUTADAPT {
    script: """
    cutadapt --front ${params.FW_primer} --adapter ${params.RV_primer} \
        ${params.region ? "--region ${params.region}" : ''} \
        --outdir ${params.outdir}
    """
}

// [Denoising]
process DADA2_DENOISE {
    script: """
    dada2_denoise.R \
        ${params.trunclenf ? "--truncLenF ${params.trunclenf}" : ''} \
        ${params.trunclenr ? "--truncLenR ${params.trunclenr}" : ''} \
        --trunc_qmin ${params.trunc_qmin} \
        ${params.skip_dada_quality ? '--skip-quality' : ''} \
        --outdir ${params.outdir}
    """
}

// [Taxonomy]
process QIIME2_CLASSIFY {
    script: """
    qiime2_classify.py \
        ${params.classifier ? "--classifier ${params.classifier}" : ''} \
        --amplicon_type ${params.amplicon_type} \
        ${params.skip_taxonomy ? '--skip' : ''} \
        --outdir ${params.outdir}
    """
}

// [Diversity & Report]
process DIVERSITY_ANALYSIS {
    script: """
    diversity_analysis.R \
        ${params.skip_alpha_rarefaction ? '--skip-rarefaction' : ''} \
        --outdir ${params.outdir} \
        ${params.email ? "--email ${params.email}" : ''}
    """
}
