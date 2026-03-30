#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: clst
// Package for modified nearest-neighbor classification based on calculation of a similarity threshold 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/clst/inst/doc/clstDemo.R
// Upstream  : none
// Downstream: clstutils
//
// Install: BiocManager::install("clst")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-clst"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-clst:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-clst:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_clst_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_clst_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_clst_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(clst)
    library(jsonlite)

    # --- Create [] ---
    # Key functions: create
    figdir <- 'figs_out'
      dir.create(figdir, showWarnings=FALSE)
    # --- Data [] ---
    # Key functions: dist
    library(clst)
    data(iris)
    dmat <- as.matrix(dist(iris[,1:4], method="euclidean"))
    groups <- iris$Species
    # --- Findthreshold [] ---
    # Key functions: findThreshold
    thresh <- findThreshold(dmat, groups, type="mutinfo")
    str(thresh)
    # --- Plot [] ---
    # Key functions: call
    plot(do.call(plotDistances, thresh))
    # --- Gettextf [] ---
    # Key functions: gettextf, classify, printClst
    ind <- 1
    species <- gettextf('I. %s', groups[ind])
    cat('class of "unknown" sample is',species)
    dmat1 <- dmat[-ind,-ind]
    groups1 <- groups[-ind]
    # --- Gettextf [] ---
    # Key functions: gettextf, pull, call, printClst
    ind <- 125
    species = gettextf('I. %s', groups[ind])
    pp <- pull(dmat, groups, ind)
    cc <- do.call(classify, pp)
    cat(paste('class of "unknown" sample is', species))
    # --- Lapply [] ---
    # Key functions: call, pull
    loo <- lapply(seq_along(groups), function(i){
      do.call(classify, pull(dmat, groups, i))
    })
    matches <- lapply(loo, function(x) rev(x)[[1]]$matches)
    result <- sapply(matches, paste, collapse='-')
    # --- Sapply [] ---
    # Key functions: scaleDistPlot
    confusion <- sapply(matches, length) > 1
     no_match <- sapply(matches, length) < 1
     plot(scaleDistPlot(dmat, groups, fill=confusion, O=confusion, X=no_match))
    # --- Lapply [] ---
    # Key functions: call, pull
    loo <- lapply(seq_along(groups), function(i){
     do.call(classify, c(pull(dmat, groups, i),minScore=0.65))
    })
    matches <- lapply(loo, function(x) rev(x)[[1]]$matches)
    result <- sapply(matches, paste, collapse='-')
    # --- Sapply [] ---
    # Key functions: scaleDistPlot
    confusion <- sapply(matches, length) > 1
     no_match <- sapply(matches, length) < 1
     plot(scaleDistPlot(dmat, groups, fill=confusion, O=confusion,
                        X=no_match, indices=no_match))
    # --- Printclst [] ---
    # Key functions: printClst
    printClst(loo[[118]])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_clst_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_clst_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_clst_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLST:", paste0("    clst: ", packageVersion("clst"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clst_results.csv
    touch ${prefix}_clst_output.rds
    echo "BIOC_CLST:" > versions.yml
    echo "    clst: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLST(ch_input)

    emit:
    results  = BIOC_CLST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLST.out.versions  // channel: path(versions.yml)
}
