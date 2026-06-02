#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MEIGOR
// MEIGOR provides a comprehensive environment for performing global optimization tasks in bioinformati
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MEIGOR/inst/doc/MEIGOR-vignette.R
// Upstream  : CNORode, CellNOptR
// Downstream: none
//
// Install: BiocManager::install("MEIGOR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MEIGOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-meigor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-meigor:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-meigor:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_meigor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_meigor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_meigor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MEIGOR)
    library(MEIGO)
    library(jsonlite)

    # --- Model Calibration with Non-linear Constraints [] ---
    # Key functions: MEIGO
    ex2 <- function(x) {
        F <- -x[1] - x[2]
        g <- rep(0, 2)
        g[1] <- x[2] - 2 * x[1]^4 + 8 * x[1]^3 - 8 * x[1]^2
        g[2] <- x[2] - 4 * x[1]^4 + 32 * x[1]^3 - 88 * x[1]^2 + 96 * x[1]
        return(list(F = F, g = g))
    }
    problem <- list(
        f = "ex2", x_L = rep(0, 2), x_U = c(3, 4),
        c_L = rep(-Inf, 2), c_U = c(2, 36)
    )
    opts <- list(
        maxeval = 750, local_solver = "DHC",
        local_n1 = 2, local_n2 = 3
    )
    Results <- MEIGO(problem, opts, algorithm = "ESS")


    # --- Mixed-Integer Parameter Estimation [] ---
    # Key functions: MEIGO
    ex4 <- function(x) {
        F <- x[2]^2 + x[3]^2 + 2.0 * x[1]^2 + x[4]^2 -
            5.0 * x[2] - 5.0 * x[3] - 21.0 * x[1] + 7.0 * x[4]
        g <- rep(0, 3)
        g[1] <- x[2]^2 + x[3]^2 + x[1]^2 + x[4]^2 + x[2] - x[3] + x[1] - x[4]
        g[2] <- x[2]^2 + 2.0 * x[3]^2 + x[1]^2 + 2.0 * x[4]^2 - x[2] - x[4]
        g[3] <- 2.0 * x[2]^2 + x[3]^2 + x[1]^2 + 2.0 * x[2] - x[3] - x[4]
        return(list(F = F, g = g))
    }
    problem <- list(
        f = "ex4", x_L = rep(0, 4), x_U = rep(10, 4),
        x_0 = c(3, 4, 5, 1), int_var = 3,
        c_L = rep(-Inf, 3), c_U = c(8, 10, 5)
    )
    opts <- list(maxtime = 2)
    Results <- MEIGO(problem, opts, algorithm = "ESS")


    # --- Global Optimization of Biological Pathways [] ---
    # Key functions: MEIGO
    rosen10 <- function(x) {
        f <- 0
        n <- length(x)
        for (i in 1:(n - 1)) {
            f <- f + 100 * (x[i]^2 - x[i + 1])^2 + (x[i] - 1)^2
        }
        return(f)
    }
    problem <- list(f = "rosen10", x_L = rep(-5, 10), x_U = rep(1, 10))
    opts <- list(
        maxeval = 2000, maxtime = 100, use_local = 1,
        aggr = 0, local_search_type = 1, decomp = 1, maxdist = 0.5
    )
    Results <- MEIGO(problem, opts, algorithm = "VNS")


    # --- Cooperative Parallel Parameter Estimation [] ---
    # Key functions: MEIGO
    rosen10 <- function(x) {
        f <- 0
        n <- length(x)
        for (i in 1:(n - 1)) {
            f <- f + 100 * (x[i]^2 - x[i + 1])^2 + (x[i] - 1)^2
        }
        return(f)
    }
    problem <- list(f = rosen10, x_L = rep(-100, 10), x_U = rep(100, 10))
    opts <- list()
    opts[[1]] <- list(local_balance = 0, dim_refset = 10, local_n2 = 0)
    opts[[2]] <- list(local_balance = 0.25, dim_refset = 15, local_n2 = 5)
    opts$hosts <- c("localhost", "localhost")
    opts$ce_niter <- 2
    opts$ce_type <- "SOCKS"
    opts$ce_isparallel <- TRUE
    Results <- MEIGO(problem, opts, algorithm = "CeSSR")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_meigor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_meigor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_meigor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MEIGOR:", paste0("    meigor: ", packageVersion("MEIGOR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_meigor_results.csv
    touch ${prefix}_meigor_output.rds
    echo "BIOC_MEIGOR:" > versions.yml
    echo "    meigor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MEIGOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MEIGOR(ch_input)

    emit:
    results  = BIOC_MEIGOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MEIGOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MEIGOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MEIGOR.out.versions  // channel: path(versions.yml)
}
