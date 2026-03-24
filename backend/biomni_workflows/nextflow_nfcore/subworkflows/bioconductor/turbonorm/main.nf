#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TurboNorm
// A fast scatterplot smoother based on B-splines with second-order difference penalty. Functions for m
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TurboNorm/inst/doc/turbonorm.R
// Upstream  : lattice, marray
// Downstream: none
//
// Install: BiocManager::install("TurboNorm")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TURBONORM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-turbonorm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-turbonorm:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-turbonorm:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_turbonorm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_turbonorm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_turbonorm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TurboNorm)
    library(jsonlite)

    # --- Code1 [] ---
    # Key functions: sin, funky, rnorm
    library(TurboNorm)
    funky <- function(x) sin(2*pi*x^3)^3
    m <- 100
    x <- seq(0, 1, length=m)
    y <- funky(x) + rnorm(m, 0, 0.1)
    # --- Code2 [] ---
    # Key functions: curve, turbotrend
    plot(x, y, type='p', xlab="", ylab="")
    curve(funky, add=TRUE)
    fitOrig <- turbotrend(x, y, n=15, method="original")
    lines(fitOrig, col="green", type='b', pch=1)
    # --- Code4 [] ---
    # Key functions: pspline
    library(marray)
    data(swirl)
    x <- pspline(swirl, showArrays=2, pch=20, col="grey")
    # --- Code5 [] ---
    # Key functions: normalizeWithinArrays
    library(TurboNorm)
    data(methylation)
    indices <- methylation$weights[,1]
    weights <- rep(1, length(indices))
    weights[indices] <- length(indices)/sum(indices)
    # --- Code6 [] ---
    # Key functions: frame, factor
    data <- data.frame(M=as.vector(MA$M),
    A=as.vector(MA$A),
    Array=factor(rep(labels, each=nrow(MA$A)), levels=rev(labels)))
    library(lattice)
    print(xyplot(M~A|Array, xlab="", ylab="", data=data, type='g',
    # --- Code7 [] ---
    # Key functions: toLatex
    toLatex(sessionInfo())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_turbonorm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_turbonorm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_turbonorm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TURBONORM:", paste0("    turbonorm: ", packageVersion("TurboNorm"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_turbonorm_results.csv
    touch ${prefix}_turbonorm_output.rds
    echo "BIOC_TURBONORM:" > versions.yml
    echo "    turbonorm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TURBONORM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TURBONORM(ch_input)

    emit:
    results  = BIOC_TURBONORM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TURBONORM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TURBONORM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TURBONORM.out.versions  // channel: path(versions.yml)
}
