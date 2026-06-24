// nf-core/sarek — user-facing parameter stub
// Somatic/germline variant calling: WGS/WES → trimming → alignment → variant calling → annotation
//
// Pipeline phases:
// * 1. [Preprocessing] FastQC + MarkDuplicates + BQSR
// * 2. [Alignment] BWA-MEM2 read alignment → sorted indexed BAM
// * 3. [Variant Calling] HaplotypeCaller / Mutect2 / Strelka / DeepVariant
// * 4. [Annotation] VEP / ANNOVAR: consequence + population frequencies
// * 5. [Report] MultiQC HTML + variant stats + TMB/MSI report

params.input            = null          // Samplesheet CSV (patient,sample,status,fastq_1,fastq_2)
params.genome           = 'GRCh38'      // Reference genome: GRCh38 | GRCh37 | GRCm38
params.tools            = null          // Variant callers: mutect2 | haplotypecaller | strelka | freebayes | deepvariant | cnvkit | manta
params.analysis_type    = 'germline'    // Analysis type: germline | somatic | tumor_only
params.step             = 'mapping'     // Pipeline step: mapping | markduplicates | prepare_recalibration | recalibrate | variant_calling | annotate
params.wes              = false         // Whole exome sequencing mode (uses intervals)
params.intervals        = null          // BED file with target regions for WES
params.genome_coverage  = null          // Target sequencing coverage in X (e.g. 30 | 50 | 100)
params.target_coverage  = null          // Target amplicon/panel coverage depth
params.nucleotides_per_second = 200000  // Genome size estimate for interval splitting
params.no_intervals     = false         // Disable interval splitting (use full genome)
params.skip_tools       = null          // Tools to skip: baserecalibrator | markduplicates | bamqc
params.joint_germline   = false         // Joint germline calling across samples
params.split_fastq      = 50000000      // Split FASTQ at this read count (0 = no split)
params.email            = null
params.max_memory       = '128.GB'
params.max_cpus         = 16
params.max_time         = '240.h'

// [Preprocessing]
process FASTQC {
    output:
    path "*.html",  emit: html
    path "*.zip",   emit: zip

    script: """
    fastqc --input ${params.input} --outdir ${params.outdir}
    """
}

// [Preprocessing]
process MARKDUPLICATES {
    output:
    tuple val(meta), path("*.bam"),                 emit: bam
    tuple val(meta), path("*.bai"),                 emit: bai
    path "*.metrics.txt",                           emit: metrics

    script: """
    gatk MarkDuplicates \
        ${params.skip_tools?.contains('markduplicates') ? '--skip' : ''} \
        --outdir ${params.outdir}
    """
}

// [Alignment]
process BWAMEM2_MEM {
    output:
    tuple val(meta), path("*.bam"),   emit: bam
    tuple val(meta), path("*.bai"),   emit: bai
    path "*.flagstat",                emit: flagstat

    script: """
    bwa-mem2 mem \
        -R "@RG\\tID:${params.input}\\tSM:SAMPLE" \
        ${params.genome} \
        ${params.split_fastq ? "--split-reads ${params.split_fastq}" : ''} \
        | samtools sort -o output.bam \
        && samtools index output.bam \
        && samtools flagstat output.bam > output.flagstat
    """
}

// [Alignment]
process GATK_BQSR {
    output:
    tuple val(meta), path("*.bam"),           emit: bam_bqsr
    path "*.recal_data.table",                emit: recal_table

    script: """
    gatk BaseRecalibrator \
        --reference ${params.genome} \
        ${params.wes ? "--intervals ${params.intervals}" : ''} \
        ${params.no_intervals ? '--disable-sequence-dictionary-validation' : ''} \
        --outdir ${params.outdir}
    """
}

// [Variant Calling]
process GATK_HAPLOTYPECALLER {
    output:
    tuple val(meta), path("*.vcf.gz"),        emit: vcf
    tuple val(meta), path("*.vcf.gz.tbi"),    emit: tbi
    path "*.stats",                           emit: stats

    script: """
    gatk HaplotypeCaller \
        --reference ${params.genome} \
        --tools ${params.tools} \
        ${params.joint_germline ? '--joint-genotyping' : ''} \
        ${params.wes ? "--intervals ${params.intervals}" : ''} \
        --target-coverage ${params.target_coverage} \
        --outdir ${params.outdir}
    """
}

// [Annotation]
process VEP {
    output:
    tuple val(meta), path("*.vcf.gz"),        emit: vcf_annotated
    path "*.html",                            emit: html_report
    path "*_summary.txt",                     emit: summary

    script: """
    vep --genome ${params.genome} \
        --everything --fork ${task.cpus} \
        --vcf --compress_output gzip \
        ${params.skip_tools?.contains('vep') ? '--skip' : ''} \
        --outdir ${params.outdir} \
        ${params.email ? "--email ${params.email}" : ''}
    """
}

// [Report]
process MULTIQC {
    output:
    path "multiqc_report.html",  emit: report
    path "multiqc_data/",        emit: data

    script: """
    multiqc --outdir ${params.outdir} \
        ${params.email ? "--email ${params.email}" : ''}
    """
}
