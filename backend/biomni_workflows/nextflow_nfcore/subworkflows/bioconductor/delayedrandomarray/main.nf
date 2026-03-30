#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DelayedRandomArray
// Implements a DelayedArray of random values where the realization of the sampled values is delayed un
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DelayedRandomArray/inst/doc/userguide.R
// Upstream  : BiocStyle
// Downstream: none
//
// Install: BiocManager::install("DelayedRandomArray")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DELAYEDRANDOMARRAY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-delayedrandomarray"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-delayedrandomarray:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-delayedrandomarray:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_delayedrandomarray_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_delayedrandomarray_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_delayedrandomarray_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DelayedArray)
    library(RandomGammaArray)
    library(RandomNbinomArray)
    library(RandomNormArray)
    library(RandomPoisArray)
    library(RandomUnifArray)
    library(RandomWeibullArray)
    library(jsonlite)

    # --- Randomunifarray [] ---
    # Key functions: RandomUnifArray
    ---------------------------------------------------------------------
    library(DelayedRandomArray)
    X <- RandomUnifArray(c(1e6, 1e6))
    X
    # --- Randomnormarray [] ---
    # Key functions: RandomNormArray, RandomPoisArray, RandomGammaArray, RandomWeibullArray
    ---------------------------------------------------------------------
    RandomNormArray(c(100, 50))
    RandomPoisArray(c(100, 50), lambda=5)
    RandomGammaArray(c(100, 50), shape=2, rate=5)
    RandomWeibullArray(c(100, 50), shape=5)
    # --- Randomnormarray [] ---
    # Key functions: RandomNormArray
    ---------------------------------------------------------------------
    RandomNormArray(c(100, 50), mean=1)
    # --- Randomnormarray [] ---
    # Key functions: RandomNormArray, RandomPoisArray
    ---------------------------------------------------------------------
    means <- RandomNormArray(c(100, 50))
    RandomPoisArray(c(100, 50), lambda=2^means)
    # --- Runif [] ---
    # Key functions: runif, rnorm, sample, DelayedArray, RandomNbinomArray
    ---------------------------------------------------------------------
    ngenes <- 20000
    log.abundances <- runif(ngenes, -2, 5)
    nclusters <- 20 # define 20 clusters and their population means.
    cluster.means <- matrix(2^rnorm(ngenes*nclusters, log.abundances, sd=2), ncol=nclusters)
    # --- Randomunifarray [] ---
    # Key functions: RandomUnifArray
    ---------------------------------------------------------------------
    # Row-wise chunks:
    RandomUnifArray(c(1000, 500), chunkdim=c(1, 500))
    # Column-wise chunks:
    RandomUnifArray(c(1000, 500), chunkdim=c(1000, 1))
    # --- Randompoisarray [] ---
    # Key functions: RandomPoisArray
    ---------------------------------------------------------------------
    RandomPoisArray(c(1e6, 1e6), lambda=0.5) # dense by default
    RandomPoisArray(c(1e6, 1e6), lambda=0.5, sparse=TRUE) # treat as sparse

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_delayedrandomarray_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_delayedrandomarray_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_delayedrandomarray_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DELAYEDRANDOMARRAY:", paste0("    delayedrandomarray: ", packageVersion("DelayedRandomArray"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_delayedrandomarray_results.csv
    touch ${prefix}_delayedrandomarray_output.rds
    echo "BIOC_DELAYEDRANDOMARRAY:" > versions.yml
    echo "    delayedrandomarray: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DELAYEDRANDOMARRAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DELAYEDRANDOMARRAY(ch_input)

    emit:
    results  = BIOC_DELAYEDRANDOMARRAY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DELAYEDRANDOMARRAY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DELAYEDRANDOMARRAY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DELAYEDRANDOMARRAY.out.versions  // channel: path(versions.yml)
}
