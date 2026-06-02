// nf-core/chipseq — user-facing parameter stub
// ChIP-seq: FASTQ → alignment → peak calling → annotation → QC

params.input            = null          // Samplesheet CSV (sample,fastq_1,fastq_2,antibody,control)
params.genome           = null          // Reference genome: GRCh38 | GRCm39 | GRCm38 | BDGP6
params.macs_gsize       = null          // MACS2 genome size: hs | mm | ce | dm
params.single_end       = false         // Single-end library (false = paired-end)
params.narrow_peak      = false         // Call narrow peaks (default: broad)
params.macs2_broad      = true          // Call broad peaks (true for histone marks)
params.qvalue           = 0.05          // MACS2 q-value (FDR) threshold
params.skip_peak_qc     = false         // Skip peak QC with deepTools
params.skip_preseq      = true          // Skip library complexity estimation
params.min_trimmed_reads = 10000        // Minimum reads after trimming
params.fragment_size    = 200           // Expected fragment size for SE reads
params.keep_dups        = false         // Keep PCR duplicates
params.outdir           = './results'
params.email            = null
params.max_memory       = '128.GB'
params.max_cpus         = 16
params.max_time         = '240.h'

// [Input Validation]
process VALIDATE_INPUT {
    script: """
    check_samplesheet.py --input ${params.input} \
        --single_end ${params.single_end} \
        --min_reads ${params.min_trimmed_reads}
    """
}

// [Trimming & QC]
process TRIMGALORE {
    script: """
    trim_galore \
        ${params.single_end ? '' : '--paired'} \
        --outdir ${params.outdir}
    """
}

// [Alignment]
process BWA_MEM {
    script: """
    bwa mem ${params.genome} \
        ${params.keep_dups ? '' : '--dedup'} \
        --fragment-size ${params.fragment_size} \
        --outdir ${params.outdir}
    """
}

// [Peak Calling]
process MACS2_CALLPEAK {
    script: """
    macs2 callpeak \
        --gsize ${params.macs_gsize} \
        --qvalue ${params.qvalue} \
        ${params.narrow_peak ? '--call-summits' : ''} \
        ${params.macs2_broad ? '--broad' : ''} \
        --outdir ${params.outdir}
    """
}

// [Annotation & Report]
process CHIPSEEKER_ANNOTATE {
    script: """
    chipseeker_annotate.R \
        --genome ${params.genome} \
        ${params.skip_peak_qc ? '--skip-qc' : ''} \
        --outdir ${params.outdir} \
        ${params.email ? "--email ${params.email}" : ''}
    """
}
