// nf-core/scrnaseq — user-facing parameter stub
// Single-cell RNA-seq: FASTQ → barcode demultiplexing → alignment → count matrix

params.input            = null          // Samplesheet CSV (sample,fastq_1,fastq_2,expected_cells)
params.genome           = null          // Reference genome: GRCh38 | GRCm39
params.protocol         = '10XV3'       // Library protocol: 10XV3 | 10XV2 | 10XV1 | dropseq | chromium
params.aligner          = 'cellranger'  // Aligner: cellranger | alevin | starsolo | kallisto | simpleaf
params.barcode_whitelist = null         // Barcode whitelist (auto-detected for 10X)
params.expected_cells   = 3000         // Expected number of cells per sample
params.skip_emptydrops  = false         // Skip EmptyDrops cell filtering
params.remove_doublets  = false         // Remove doublets using Scrublet or DoubletFinder
params.outdir           = './results'
params.email            = null
params.max_memory       = '128.GB'
params.max_cpus         = 16
params.max_time         = '240.h'

// [Input Validation]
process VALIDATE_INPUT {
    script: """
    check_samplesheet.py --input ${params.input} --protocol ${params.protocol}
    """
}

// [Preprocessing]
process FASTQC {
    script: """
    fastqc --input ${params.input} \
        ${params.barcode_whitelist ? "--whitelist ${params.barcode_whitelist}" : ''} \
        --outdir ${params.outdir}
    """
}

// [Alignment & Counting]
process CELLRANGER_COUNT {
    script: """
    cellranger count \
        --genome ${params.genome} \
        --aligner ${params.aligner} \
        --protocol ${params.protocol} \
        --expected-cells ${params.expected_cells} \
        ${params.barcode_whitelist ? "--barcode-whitelist ${params.barcode_whitelist}" : ''} \
        --outdir ${params.outdir}
    """
}

// [Cell QC]
process EMPTYDROPS_FILTER {
    script: """
    emptydrops_filter.R \
        ${params.skip_emptydrops ? '--skip' : ''} \
        ${params.remove_doublets ? '--remove-doublets' : ''} \
        --expected-cells ${params.expected_cells} \
        --outdir ${params.outdir}
    """
}

// [Report]
process MULTIQC {
    script: """
    multiqc --outdir ${params.outdir} \
        ${params.email ? "--email ${params.email}" : ''}
    """
}
