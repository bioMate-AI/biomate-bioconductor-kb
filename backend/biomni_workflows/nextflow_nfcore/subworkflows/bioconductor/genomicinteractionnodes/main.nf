#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GenomicInteractionNodes
// The GenomicInteractionNodes package can import interactions from bedpe file and define the interacti
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GenomicInteractionNodes/inst/doc/GenomicInteractionNodes_vignettes.R
// Upstream  : BiocManager, devtools, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("GenomicInteractionNodes")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMICINTERACTIONNODES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomicinteractionnodes"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genomicinteractionnodes:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genomicinteractionnodes:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomicinteractionnodes_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomicinteractionnodes_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomicinteractionnodes_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GenomicInteractionNodes)
    library(jsonlite)

    # --- Import genomic data file [] ---
    # Key functions: import, detectNodes, annotateNodes, enrichmentAnalysis
    library(GenomicInteractionNodes)
    library(rtracklayer)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene) ## for human hg19

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genomicinteractionnodes_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genomicinteractionnodes_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genomicinteractionnodes_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMICINTERACTIONNODES:", paste0("    genomicinteractionnodes: ", packageVersion("GenomicInteractionNodes"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomicinteractionnodes_results.csv
    touch ${prefix}_genomicinteractionnodes_output.rds
    echo "BIOC_GENOMICINTERACTIONNODES:" > versions.yml
    echo "    genomicinteractionnodes: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMICINTERACTIONNODES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMICINTERACTIONNODES(ch_input)

    emit:
    results  = BIOC_GENOMICINTERACTIONNODES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMICINTERACTIONNODES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMICINTERACTIONNODES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMICINTERACTIONNODES.out.versions  // channel: path(versions.yml)
}
