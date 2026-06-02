#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: omicsPrint
// omicsPrint provides functionality for cross omic genetic fingerprinting, for example, to verify samp
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/omicsPrint/inst/doc/omicsPrint.R
// Upstream  : GEOquery, SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("omicsPrint")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OMICSPRINT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-omicsprint"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-omicsprint:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-omicsprint:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_omicsprint_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_omicsprint_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_omicsprint_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(omicsPrint)
    library(jsonlite)

    # --- Genotype Conversion and Verification [] ---
    # Key functions: beta2genotype, alleleSharing, inferRelations
    dnamCalls <- beta2genotype(se, assayName = "exprs")
    data <- alleleSharing(dnamCalls, relations = r, verbose = TRUE)
    mismatches <- inferRelations(data)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_omicsprint_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_omicsprint_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_omicsprint_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OMICSPRINT:", paste0("    omicsprint: ", packageVersion("omicsPrint"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_omicsprint_results.csv
    touch ${prefix}_omicsprint_output.rds
    echo "BIOC_OMICSPRINT:" > versions.yml
    echo "    omicsprint: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OMICSPRINT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OMICSPRINT(ch_input)

    emit:
    results  = BIOC_OMICSPRINT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OMICSPRINT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OMICSPRINT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OMICSPRINT.out.versions  // channel: path(versions.yml)
}
