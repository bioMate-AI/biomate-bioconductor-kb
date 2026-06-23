// nf-core/rnaseq — user-facing parameter stub
// Full pipeline: FASTQ → trimming → alignment → quantification → QC
//
// Pipeline phases:
// * 1. [Trimming] Adapter trimming + read-length QC (Trim Galore + FastQC)
// * 2. [Alignment] Splice-aware alignment to reference (STAR or HISAT2)
// * 3. [Quantification] Transcript-level counts (Salmon / featureCounts)
// * 4. [QC] Alignment QC + library complexity (RSeQC, Picard, dupRadar)
// * 5. [Report] MultiQC summary HTML + count matrix TSV

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
params.email            = null
params.max_memory       = '128.GB'
params.max_cpus         = 16
params.max_time         = '240.h'

// [Input Validation]
process VALIDATE_INPUT {
    output:
    path "validated_samplesheet.csv", emit: samplesheet

    script: """
    check_samplesheet.py --input ${params.input} --strandedness ${params.strandedness}
    """
}

// [Trimming]
process TRIMGALORE {
    output:
    path "*.fq.gz",         emit: reads
    path "*.txt",           emit: log
    path "*_fastqc.{zip,html}", emit: fastqc

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

// [Alignment]
process STAR_ALIGN {
    output:
    tuple val(meta), path("*.bam"),            emit: bam
    tuple val(meta), path("*.bai"),            emit: bai
    path "*.Log.final.out",                    emit: log
    path "*.SJ.out.tab",                       emit: sj
    path "*.bigWig",                           emit: bigwig

    script: """
    STAR --genome ${params.genome} \
        --readFilesIn ${params.input} \
        --outSAMtype BAM SortedByCoordinate \
        --outSAMattributes NH HI AS NM \
        --outdir ${params.outdir} \
        ${params.save_unaligned ? '--outReadsUnmapped Fastx' : ''} \
        ${params.read_length ? "--sjdbOverhang $((${params.read_length} - 1))" : ''}
    """
}

// [Quantification]
process SALMON_QUANT {
    output:
    tuple val(meta), path("${meta.id}"),       emit: results
    path "${meta.id}/quant.sf",                emit: quant
    path "${meta.id}/lib_format_counts.json",  emit: json
    path "counts_matrix.tsv",                  emit: counts_matrix

    script: """
    salmon quant \
        --libType ${params.strandedness} \
        ${params.pseudo_aligner == 'salmon' ? '--validateMappings' : ''} \
        --outdir ${params.outdir}
    """
}

// [QC]
process RSEQC_BAMSTAT {
    output:
    path "*.bam_stat.txt",  emit: txt
    path "pca_plot.png",    emit: pca
    path "heatmap.png",     emit: heatmap

    script: """
    infer_experiment.py -i sample.bam -r ${params.genome}.bed
    """
}

// [Report]
process MULTIQC {
    output:
    path "multiqc_report.html",     emit: report
    path "multiqc_data/",           emit: data

    script: """
    multiqc ${params.skip_multiqc ? '--skip' : ''} \
        --outdir ${params.outdir} \
        ${params.email ? "--email ${params.email}" : ''}
    """
}
