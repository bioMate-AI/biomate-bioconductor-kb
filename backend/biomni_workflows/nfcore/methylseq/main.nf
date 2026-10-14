// nf-core/methylseq — user-facing parameter stub
// Bisulfite/WGBS: FASTQ → trimming → bismark alignment → methylation extraction → QC
//
// Pipeline phases:
// * 1. Input validation — samplesheet QC, library type detection (RRBS / WGBS / PBAT)
// * 2. Trimming — adapter trimming (Trim Galore), non-directional adapter handling
// * 3. Alignment — Bismark / bwa-meth bisulfite alignment, deduplication
// * 4. Methylation extraction — CpG / CHG / CHH context methylation calls
// * 5. Coverage filtering — minimum coverage threshold, cytosine report
// * 6. Report — MultiQC, methylation BedGraph, genome-wide cytosine TSV

params.input            = null          // Samplesheet CSV (sample,fastq_1,fastq_2)
params.genome           = null          // Reference genome: GRCh38 | GRCm39 | GRCm38
params.aligner          = 'bismark'     // Alignment tool: bismark | bismark_hisat | bwameth
params.comprehensive    = false         // Output all contexts (CpG, CHG, CHH)
params.cytosine_report  = false         // Generate genome-wide cytosine report
params.non_directional  = false         // Non-directional library (random priming)
params.skip_trimming    = false         // Skip adapter trimming
params.rrbs             = false         // RRBS mode (reduced representation)
params.pbat             = false         // PBAT (post-bisulfite adapter tagging) mode
params.min_coverage     = 1             // Minimum read coverage for methylation calling
params.ignore_flags     = false         // Ignore SAM flags for methylation extraction
params.outdir           = './results'
params.email            = null
params.max_memory       = '128.GB'
params.max_cpus         = 16
params.max_time         = '240.h'

// [Input Validation]
process VALIDATE_INPUT {
    publishDir params.outdir, mode: 'copy', overwrite: true

    script: """
    check_samplesheet.py --input ${params.input} \
        ${params.rrbs ? '--rrbs' : ''} \
        ${params.pbat ? '--pbat' : ''}
    """
}

// [Trimming]
process TRIMGALORE {
    publishDir params.outdir, mode: 'copy', overwrite: true

    script: """
    trim_galore \
        ${params.skip_trimming ? '--skip' : ''} \
        ${params.rrbs ? '--rrbs' : ''} \
        ${params.pbat ? '--pbat' : ''} \
        ${params.non_directional ? '--non_directional' : ''} \
        --outdir ${params.outdir}
    """
}

// [Alignment]
process BISMARK_ALIGN {
    publishDir params.outdir, mode: 'copy', overwrite: true

    script: """
    ${params.aligner} \
        --genome ${params.genome} \
        ${params.non_directional ? '--non_directional' : ''} \
        ${params.ignore_flags ? '--ignore_flags' : ''} \
        --outdir ${params.outdir}
    """
}

// [Methylation Extraction]
process BISMARK_METHYLATION_EXTRACTOR {
    publishDir params.outdir, mode: 'copy', overwrite: true

    script: """
    bismark_methylation_extractor \
        ${params.comprehensive ? '--comprehensive' : ''} \
        ${params.cytosine_report ? '--cytosine_report' : ''} \
        --genome ${params.genome} \
        --outdir ${params.outdir}
    """
}

// [Coverage Filtering]
process COVERAGE2CYTOSINE {
    publishDir params.outdir, mode: 'copy', overwrite: true

    script: """
    coverage2cytosine.R \
        --min_coverage ${params.min_coverage} \
        ${params.cytosine_report ? '--cytosine_report' : ''} \
        --outdir ${params.outdir}
    """
}

// [Report]
process MULTIQC {
    publishDir params.outdir, mode: 'copy', overwrite: true

    script: """
    multiqc --outdir ${params.outdir} \
        ${params.email ? "--email ${params.email}" : ''}
    """
}
