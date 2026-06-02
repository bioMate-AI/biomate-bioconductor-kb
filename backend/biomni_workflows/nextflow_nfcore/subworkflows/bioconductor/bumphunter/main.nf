#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: bumphunter
// Tools for finding bumps in genomic data
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/bumphunter/inst/doc/bumphunter.R
// Upstream  : doParallel
// Downstream: minfi
//
// Install: BiocManager::install("bumphunter")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BUMPHUNTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bumphunter"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bumphunter:1.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bumphunter:1.48.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_bumphunter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bumphunter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bumphunter_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(bumphunter)
    library(jsonlite)

    # --- Clustermakerdata [] ---
    # Key functions: unlist
    pos <- list(pos1=seq(1,1000,35),
                pos2=seq(2001,3000,35),
                pos3=seq(1,1000,50))
    chr <- rep(paste0("chr",c(1,1,2)), times = sapply(pos,length))
    pos <- unlist(pos, use.names=FALSE)
    # --- Clustermaker [] ---
    # Key functions: clusterMaker
    cl <- clusterMaker(chr, pos, maxGap = 300)
    table(cl)
    # --- Simulatedbumps [] ---
    # Key functions: split, scale
    Indexes <- split(seq_along(cl), cl)
    beta1 <- rep(0, length(pos))
    # --- Getsegments [] ---
    # Key functions: getSegments
    segs <- getSegments(beta1, cl, cutoff=0.05)
    # --- Regionfinder [] ---
    # Key functions: regionFinder
    tab <- regionFinder(beta1, chr, pos, cl, cutoff=0.05)
    tab
    # --- Simulationofreps [] ---
    # Key functions: sin, rnorm
    beta0 <- 3*sin(2*pi*pos/720)
    X <- cbind(rep(1,20), rep(c(0,1), each=10))
    error <- matrix(rnorm(20*length(beta1), 0, 1), ncol=20)
    y <- t(X[,1])%x%beta0 + t(X[,2])%x%beta1 + error
    # --- Bumphunter [] ---
    # Key functions: bumphunter
    tab <- bumphunter(y, X, chr, pos, cl, cutoff=.5)
    tab
    names(tab)
    tab$table
    # --- Load Foreach [] ---
    # Key functions: registerDoParallel
    library(doParallel)
    registerDoParallel(cores = 2)
    # --- Parallel Bumphunter [] ---
    # Key functions: bumphunter
    tab <- bumphunter(y, X, chr, pos, cl, cutoff=.5, B=250, verbose = TRUE)
    tab
    # --- Closeconnetions [] ---
    # Key functions: foreachCleanup
    bumphunter:::foreachCleanup()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bumphunter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bumphunter_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bumphunter_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BUMPHUNTER:", paste0("    bumphunter: ", packageVersion("bumphunter"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bumphunter_results.csv
    touch ${prefix}_bumphunter_output.rds
    echo "BIOC_BUMPHUNTER:" > versions.yml
    echo "    bumphunter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BUMPHUNTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_BUMPHUNTER(ch_input)

    emit:
    results  = BIOC_BUMPHUNTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BUMPHUNTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BUMPHUNTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BUMPHUNTER.out.versions  // channel: path(versions.yml)
}
