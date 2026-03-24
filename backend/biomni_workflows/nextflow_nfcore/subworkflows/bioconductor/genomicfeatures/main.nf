#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GenomicFeatures
// Extract the genomic locations of genes, transcripts, exons, introns, and CDS, for the gene models st
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GenomicFeatures/inst/doc/GenomicFeatures.R
// Upstream  : none
// Downstream: Cogito, cpvSNP, ensembldb, GSReg, Guitar
//
// Install: BiocManager::install("GenomicFeatures")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMICFEATURES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomicfeatures"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genomicfeatures:1.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genomicfeatures:1.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomicfeatures_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomicfeatures_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomicfeatures_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GenomicFeatures)
    library(jsonlite)

    # --- Sequence level inspection [] ---
    # Key functions: loadDb, seqlevels, columns, keytypes, transcripts, strand, promoters, exons
    suppressPackageStartupMessages(library(BSgenome.Hsapiens.UCSC.hg19))
    genome <- BSgenome.Hsapiens.UCSC.hg19  # shorthand (for convenience)
    tx_seqs1 <- extractTranscriptSeqs(genome, hg19_txdb, use.names=TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genomicfeatures_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genomicfeatures_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genomicfeatures_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMICFEATURES:", paste0("    genomicfeatures: ", packageVersion("GenomicFeatures"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomicfeatures_results.csv
    touch ${prefix}_genomicfeatures_output.rds
    echo "BIOC_GENOMICFEATURES:" > versions.yml
    echo "    genomicfeatures: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMICFEATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMICFEATURES(ch_input)

    emit:
    results  = BIOC_GENOMICFEATURES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMICFEATURES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMICFEATURES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMICFEATURES.out.versions  // channel: path(versions.yml)
}
