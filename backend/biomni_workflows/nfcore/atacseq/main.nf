// nf-core/atacseq — user-facing parameter stub
// ATAC-seq: FASTQ → trimming → alignment → peak calling → annotation → QC

params.input            = null          // Samplesheet CSV (sample,fastq_1,fastq_2,replicate)
params.genome           = null          // Reference genome: GRCh38 | GRCm39 | GRCm38 | BDGP6
params.macs_gsize       = null          // MACS2 genome size: hs | mm | ce | dm (or numeric)
params.paired_end       = true          // Paired-end library (true | false)
params.narrow_peak      = false         // Call narrow peaks (default: broad peaks for ATAC)
params.macs2_broad      = true          // Call broad peaks with MACS2
params.keep_mito        = false         // Keep mitochondrial reads
params.max_fragment_size = 200          // Maximum fragment size to retain (bp)
params.skip_peak_qc     = false         // Skip peak QC with deepTools
params.skip_ataqv       = false         // Skip ataqv QC
params.skip_preseq      = true          // Skip library complexity (preseq)
params.min_trimmed_reads = 10000        // Minimum reads after trimming
params.read_length      = null          // Read length for fragment calculation
params.fragment_size    = 200           // Expected fragment size for single-end
params.outdir           = './results'
params.email            = null
params.max_memory       = '128.GB'
params.max_cpus         = 16
params.max_time         = '240.h'

// [Input Validation]
process VALIDATE_INPUT {
    script: """
    check_samplesheet.py --input ${params.input} \
        --paired_end ${params.paired_end} \
        --min_reads ${params.min_trimmed_reads}
    """
}

// [Trimming & QC]
process TRIMGALORE {
    script: """
    trim_galore \
        ${params.paired_end ? '--paired' : ''} \
        --length ${params.min_trimmed_reads} \
        ${params.read_length ? "--clip_r1 $((${params.read_length} / 10))" : ''} \
        --outdir ${params.outdir}
    """
}

// [Alignment]
process BWA_MEM {
    script: """
    bwa mem ${params.genome} \
        ${params.keep_mito ? '' : '--filter-mito'} \
        --max-fragment-size ${params.max_fragment_size} \
        ${params.fragment_size ? "--fragment-size ${params.fragment_size}" : ''} \
        --outdir ${params.outdir}
    """
}

// [Peak Calling]
process MACS2_CALLPEAK {
    script: """
    macs2 callpeak \
        --gsize ${params.macs_gsize} \
        ${params.narrow_peak ? '--call-summits' : '--broad'} \
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
        ${params.skip_ataqv ? '--skip-ataqv' : ''} \
        --outdir ${params.outdir} \
        ${params.email ? "--email ${params.email}" : ''}
    """
}
