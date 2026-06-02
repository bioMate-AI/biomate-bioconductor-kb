#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AIMS
// This package contains the AIMS implementation. It contains necessary functions to assign the five in
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AIMS/inst/doc/AIMS.R
// Upstream  : breastCancerVDX
// Downstream: none
//
// Install: BiocManager::install("AIMS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AIMS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-aims"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-aims:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-aims:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_aims_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_aims_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_aims_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AIMS)
    library(ExpressionSet)
    library(jsonlite)

    # --- Subtype Assignment [] ---
    # Key functions: applyAIMS
    mcgill_subtypes <- applyAIMS(
        eset_data,
        entrez_ids
    )
    subtype_classes <- mcgill_subtypes$cl
    subtype_probs <- mcgill_subtypes$prob


    # --- Single Sample Classification [] ---
    # Key functions: applyAIMS
    single_sample_eset <- eset_data[, 1, drop = FALSE]
    single_subtype <- applyAIMS(
        single_sample_eset,
        entrez_ids
    )
    single_class <- single_subtype$cl
    single_prob <- single_subtype$prob


    # --- Cross Platform Subtyping [] ---
    # Key functions: applyAIMS
    data(vdx)
    vdx_entrez <- as.character(
        as.list(hgu133aENTREZID)[featureNames(vdx)]
    )
    vdx_subtypes <- applyAIMS(
        vdx,
        vdx_entrez
    )
    vdx_classes <- vdx_subtypes$cl

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_aims_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_aims_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_aims_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AIMS:", paste0("    aims: ", packageVersion("AIMS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_aims_results.csv
    touch ${prefix}_aims_output.rds
    echo "BIOC_AIMS:" > versions.yml
    echo "    aims: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AIMS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AIMS(ch_input)

    emit:
    results  = BIOC_AIMS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AIMS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AIMS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AIMS.out.versions  // channel: path(versions.yml)
}
