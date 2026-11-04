// ⚠️ NON-EXECUTABLE PARAMETER-SURFACE STUB — DO NOT RUN. (flagged 2026-10-01)
// This file documents the nf-core/chipseq *parameter surface* only. It is NOT a
// runnable Nextflow pipeline:
//   * processes have no `input:` blocks and there is no `workflow {}` wiring /
//     channels, so nothing actually executes;
//   * it uses invented tool flags that do not exist (`bwa mem --dedup`,
//     `bwa mem --fragment-size`, `trim_galore/macs2/multiqc --outdir`,
//     a non-existent `chipseeker_annotate.R`);
//   * it produces 0 real outputs.
// DB id 1492 is marked non-executable (executable=0, real_exec_status=exec_error,
// workflow_correctness_verdict=major_issues) so routing deprioritizes it.
// For a REAL ChIP-seq run, use the validated Bioconductor ChIPseeker subworkflows
// (nextflow_nfcore/subworkflows/bioconductor/chipseeker/
//  peak_annotation_and_feature_distribution.nf — validated; and
//  peak_annotation_and_enrichment.nf — validated), both on the Batch-ready
// biomate/bioc-domain-epigenomics:3.20-slim image. To run the upstream
// FASTQ→peaks nf-core/chipseq, pull the real pipeline from nf-core (nextflow run
// nf-core/chipseq) rather than this stub.
//
// nf-core/chipseq — user-facing parameter stub
// ChIP-seq: FASTQ → alignment → peak calling → annotation → QC
//
// Pipeline phases:
// * 1. [Trimming] Adapter trimming (Trim Galore + FastQC)
// * 2. [Alignment] BWA-MEM alignment → sorted deduplicated BAM
// * 3. [Peak Calling] MACS2 narrow/broad peak calling + IDR reproducibility
// * 4. [Annotation] ChIPseeker genomic context + pathway enrichment
// * 5. [QC] deepTools fingerprint + bamCompare + cross-correlation
// * 6. [Report] MultiQC HTML + peak stats TSV

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
params.email            = null
params.max_memory       = '128.GB'
params.max_cpus         = 16
params.max_time         = '240.h'

// [Trimming]
process TRIMGALORE {
    publishDir params.outdir, mode: 'copy', overwrite: true

    output:
    path "*.fq.gz",             emit: reads
    path "*_fastqc.{zip,html}", emit: fastqc

    script: """
    trim_galore \
        ${params.single_end ? '' : '--paired'} \
        --outdir ${params.outdir}
    """
}

// [Alignment]
process BWA_MEM {
    publishDir params.outdir, mode: 'copy', overwrite: true

    output:
    tuple val(meta), path("*.bam"),     emit: bam
    tuple val(meta), path("*.bai"),     emit: bai
    path "*.flagstat",                  emit: flagstat

    script: """
    bwa mem ${params.genome} \
        ${params.keep_dups ? '' : '--dedup'} \
        --fragment-size ${params.fragment_size} \
        | samtools sort -o output.bam \
        && samtools index output.bam \
        && samtools flagstat output.bam > output.flagstat
    """
}

// [Peak Calling]
process MACS2_CALLPEAK {
    publishDir params.outdir, mode: 'copy', overwrite: true

    output:
    path "*.{narrowPeak,broadPeak}",    emit: peak
    path "*.bed",                       emit: bed
    path "*_summits.bed",               emit: summits
    path "*_model.r",                   emit: model

    script: """
    macs2 callpeak \
        --gsize ${params.macs_gsize} \
        --qvalue ${params.qvalue} \
        ${params.narrow_peak ? '--call-summits' : ''} \
        ${params.macs2_broad ? '--broad' : ''} \
        --outdir ${params.outdir}
    """
}

// [Annotation]
process CHIPSEEKER_ANNOTATE {
    publishDir params.outdir, mode: 'copy', overwrite: true

    output:
    path "*_annotated.tsv",             emit: annotation
    path "*.pdf",                       emit: pdf
    path "*_piechart.png",              emit: png

    script: """
    chipseeker_annotate.R \
        --genome ${params.genome} \
        ${params.skip_peak_qc ? '--skip-qc' : ''} \
        --outdir ${params.outdir}
    """
}

// [QC]
process DEEPTOOLS_BAMCOVERAGE {
    publishDir params.outdir, mode: 'copy', overwrite: true

    output:
    path "*.bigWig",                    emit: bigwig
    path "*_fingerprint.png",           emit: fingerprint
    path "*_profile.png",               emit: profile

    script: """
    bamCoverage --bam sample.bam --outFileName sample.bigWig --normalizeUsing RPKM
    plotFingerprint -b sample.bam -plot fingerprint.png
    """
}

// [Report]
process MULTIQC {
    publishDir params.outdir, mode: 'copy', overwrite: true

    output:
    path "multiqc_report.html",         emit: report
    path "multiqc_data/",               emit: data

    script: """
    multiqc --outdir ${params.outdir} \
        ${params.email ? "--email ${params.email}" : ''}
    """
}
