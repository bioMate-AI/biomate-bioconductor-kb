#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CellBench
// This package contains infrastructure for benchmarking analysis methods and access to single cell mix
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CellBench/inst/doc/DataManipulation.R
// Upstream  : dplyr, ggplot2, limma, purrr, tibble
// Downstream: none
//
// Install: BiocManager::install("CellBench")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CELLBENCH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cellbench"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cellbench:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cellbench:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cellbench_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cellbench_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cellbench_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CellBench)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: runif, function, pearson, kendall
    library(CellBench)
    library(dplyr)
    library(purrr)

    ## -----------------------------------------------------------------------------
    library(CellBench)
    datasets <- list(
        random_mat1 = matrix(runif(100), 10, 10),
        random_mat2 = matrix(runif(100), 10, 10)
    )

    cor_method <- list(
        pearson = function(x) { cor(x, method = "pearson") },
        kendall = function(x) { cor(x, method = "kendall") }
    )

    # --- Eval = False [] ---
    # Key functions: mutate, unlist
    #  # this code will fail
    #  res %>%
    #      mutate(exp_result = exp(result))

    ## -----------------------------------------------------------------------------
    res %>%
        mutate(exp_result = lapply(result, exp)) %>%
        mutate(sum_of_exp = unlist(lapply(exp_result, sum)))

    ## -----------------------------------------------------------------------------
    library(tibble)

    # --- Result = 'hide' [] ---
    # Key functions: function
    # a numeric literal
    1

    # a character literal
    "a"

    # a function literal
    function(x) { print(x) }

    # --- Result = 'hide' [] ---
    # Key functions: function
    # assigning numeric literal
    x <- 1

    # assigning character literal
    x <- "a"

    # assigning function literal
    f <- function(x) { print(x) }

    # --- Result = 'hide' [] ---
    # Key functions: function
    # assigning numeric literal
    x <- 1
    y <- x # y = 1

    # assigning character literal
    x <- "a"
    y <- x # y = "a"

    # assigning function literal
    f <- function(x) { print(x) }
    g <- f # g = function(x) { print(x) }

    ## -----------------------------------------------------------------------------
    # function to add two things
    plus <- function(x, y) { x + y }

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cellbench_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cellbench_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cellbench_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CELLBENCH:", paste0("    cellbench: ", packageVersion("CellBench"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cellbench_results.csv
    touch ${prefix}_cellbench_output.rds
    echo "BIOC_CELLBENCH:" > versions.yml
    echo "    cellbench: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CELLBENCH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CELLBENCH(ch_input)

    emit:
    results  = BIOC_CELLBENCH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CELLBENCH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CELLBENCH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CELLBENCH.out.versions  // channel: path(versions.yml)
}
