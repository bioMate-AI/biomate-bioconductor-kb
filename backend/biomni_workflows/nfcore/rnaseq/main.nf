// nf-core/rnaseq — user-facing parameter stub
// Full pipeline: FASTQ → trimming → alignment → quantification → QC

params.input            = null          // Samplesheet CSV (sample,fastq_1,fastq_2,strandedness)
params.genome           = null          // Reference genome: GRCh38 | GRCm39 | GRCz11 | BDGP6 | Rnor_6.0 | R64-1-1
params.strandedness     = 'auto'        // Library strandedness: reverse | forward | unstranded | auto
params.aligner          = 'star_salmon' // Alignment tool: star_salmon | hisat2 | star_rsem
params.pseudo_aligner   = null          // Pseudo-aligner: salmon | kallisto (skips genome alignment)
params.single_end       = false         // Single-end library (false = paired-end)
params.read_length      = null          // Read length in bp (e.g. 75 | 100 | 150)
params.skip_trimming    = false         // Skip adapter trimming (Trim Galore)
params.skip_fastqc      = false         // Skip FastQC quality control
params.skip_multiqc     = false         // Skip MultiQC report generation
params.umi_discard_read = null          // Discard UMI-tagged reads: 1 | 2
params.with_umi         = false         // UMI-based library preparation
params.save_unaligned   = false         // Save unaligned reads to output
params.save_trimmed     = false         // Save trimmed FASTQ files to output
params.clip_r1          = null          // Clip adapter sequence from R1 reads
params.clip_r2          = null          // Clip adapter sequence from R2 reads
params.trim_quality     = null          // Quality cutoff Phred score for trimming (e.g. 20)
params.minlen           = null          // Minimum read length after trimming (bp)
params.min_reads        = null          // Minimum reads per UMI group to retain
params.max_reads        = null          // Maximum reads per sample (for pilot runs)
params.gpu_acceleration = null          // Enable GPU acceleration
params.outdir           = './results'
params.email            = null
params.max_memory       = '128.GB'
params.max_cpus         = 16
params.max_time         = '240.h'

// [Input Validation]
process VALIDATE_INPUT {
    script: """
    check_samplesheet.py --input ${params.input} --strandedness ${params.strandedness}
    """
}

// [Trimming & QC]
process TRIMGALORE {
    script: """
    trim_galore ${params.single_end ? '--single_end' : ''} \
        ${params.skip_trimming ? '--skip' : ''} \
        ${params.clip_r1 ? "--clip_r1 ${params.clip_r1}" : ''} \
        ${params.clip_r2 ? "--clip_r2 ${params.clip_r2}" : ''} \
        ${params.trim_quality ? "--quality ${params.trim_quality}" : ''} \
        ${params.minlen ? "--length ${params.minlen}" : ''} \
        --outdir ${params.outdir}
    """
}

// [Trimming & QC]
process FASTQC {
    script: """
    fastqc ${params.skip_fastqc ? '--skip' : ''} --outdir ${params.outdir}
    """
}

// [Alignment]
process STAR_ALIGN {
    script: """
    STAR --genome ${params.genome} \
        --readFilesIn ${params.input} \
        --outdir ${params.outdir} \
        ${params.save_unaligned ? '--outReadsUnmapped Fastx' : ''} \
        ${params.read_length ? "--sjdbOverhang $((${params.read_length} - 1))" : ''}
    """
}

// [Quantification]
process SALMON_QUANT {
    script: """
    salmon quant \
        --libType ${params.strandedness} \
        ${params.pseudo_aligner == 'salmon' ? '--validateMappings' : ''} \
        --outdir ${params.outdir}
    """
}

// [Report]
process MULTIQC {
    script: """
    multiqc ${params.skip_multiqc ? '--skip' : ''} \
        --outdir ${params.outdir} \
        ${params.email ? "--email ${params.email}" : ''}
    """
}
