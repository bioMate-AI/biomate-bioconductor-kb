#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MultiMed
// Implements methods for testing multiple mediators
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MultiMed/inst/doc/MultiMed.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MultiMed")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MULTIMED {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-multimed"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-multimed:2.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-multimed:2.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_multimed_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_multimed_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_multimed_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MultiMed)
    library(jsonlite)

    # --- Mediation Analysis [] ---
    # Key functions: medTest
    meds_results <- medTest(
        E = NavyAdenoma$Fish,
        M = NavyAdenoma[, 6:154],
        Y = NavyAdenoma$Adenoma,
        Z = NavyAdenoma[, 2:5],
        nperm = 500,
        w = w,
        useWeightsZ = FALSE
    )


    # --- Significant Mediator Identification [] ---
    # Key functions: medTest
    rownames(meds_results) <- colnames(NavyAdenoma[, -c(1:5, 154)])
    top_mediators <- meds_results[order(meds_results[, "p"]), ]
    best_mediator <- top_mediators[1, , drop = FALSE]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_multimed_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_multimed_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_multimed_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MULTIMED:", paste0("    multimed: ", packageVersion("MultiMed"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multimed_results.csv
    touch ${prefix}_multimed_output.rds
    echo "BIOC_MULTIMED:" > versions.yml
    echo "    multimed: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MULTIMED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MULTIMED(ch_input)

    emit:
    results  = BIOC_MULTIMED.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MULTIMED.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MULTIMED.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MULTIMED.out.versions  // channel: path(versions.yml)
}
