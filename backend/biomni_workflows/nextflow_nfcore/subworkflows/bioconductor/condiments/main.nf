#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: condiments
// This package encapsulate many functions to conduct a differential topology analysis. It focuses on a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/condiments/inst/doc/condiments.R
// Upstream  : RColorBrewer, dplyr, ggplot2, knitr, slingshot
// Downstream: none
//
// Install: BiocManager::install("condiments")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CONDIMENTS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-condiments"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-condiments:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-condiments:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_condiments_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_condiments_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_condiments_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(condiments)
    library(jsonlite)

    # --- Imbalance Score Calculation [Imbalance Score] ---
    # Key functions: imbalance_score
    data("toy_dataset", package = "condiments")
    df <- toy_dataset$sd
    rd <- as.matrix(df[, c("Dim1", "Dim2")])
    scores <- imbalance_score(
        Object = rd,
        conditions = df$conditions
    )
    df$scores <- scores$scores
    df$scaled_scores <- scores$scaled_scores

    # --- Differential Topology Testing [Topology Test] ---
    # Key functions: topologyTest
    data("toy_dataset", package = "condiments")
    df <- toy_dataset$sd
    rd <- as.matrix(df[, c("Dim1", "Dim2")])
    sds <- slingshot::slingshot(rd, df$cl)
    top_res <- topologyTest(
        sds = sds,
        conditions = df$conditions
    )

    # --- Differential Progression Testing [Progression Test] ---
    # Key functions: progressionTest
    data("toy_dataset", package = "condiments")
    df <- toy_dataset$sd
    rd <- as.matrix(df[, c("Dim1", "Dim2")])
    sds <- slingshot::slingshot(rd, df$cl)
    prog_res <- progressionTest(
        sds = sds,
        conditions = df$conditions,
        global = TRUE,
        lineages = TRUE
    )

    # --- Differential Fate Selection Testing [Fate Selection Test] ---
    # Key functions: fateSelectionTest
    data("toy_dataset", package = "condiments")
    df <- toy_dataset$sd
    rd <- as.matrix(df[, c("Dim1", "Dim2")])
    sds <- slingshot::slingshot(rd, df$cl)
    dif_res <- fateSelectionTest(
        sds = sds,
        conditions = df$conditions,
        global = FALSE,
        pairwise = TRUE
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_condiments_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_condiments_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_condiments_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CONDIMENTS:", paste0("    condiments: ", packageVersion("condiments"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_condiments_results.csv
    touch ${prefix}_condiments_output.rds
    echo "BIOC_CONDIMENTS:" > versions.yml
    echo "    condiments: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CONDIMENTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CONDIMENTS(ch_input)

    emit:
    results  = BIOC_CONDIMENTS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CONDIMENTS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CONDIMENTS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CONDIMENTS.out.versions  // channel: path(versions.yml)
}
