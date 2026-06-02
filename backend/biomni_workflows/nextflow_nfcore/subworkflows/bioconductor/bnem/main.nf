#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: bnem
// bnem combines the use of indirect measurements of Nested Effects Models (package mnem) with the Bool
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/bnem/inst/doc/bnem.R
// Upstream  : CellNOptR, mnem
// Downstream: none
//
// Install: BiocManager::install("bnem")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BNEM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bnem"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bnem:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bnem:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bnem_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bnem_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bnem_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(bnem)
    library(jsonlite)


    # --- Global Options [] ---
    # Key functions: set, logics, truth, GTN, optmimum, pattern, PKN, center
    knitr::opts_chunk$set(message=FALSE, out.width="125%", fig.align="center",
                          strip.white=TRUE, warning=FALSE, #tidy=TRUE,
                          #out.extra='style="display:block; margin:auto;"',
                          fig.height = 4, fig.width = 8, error=FALSE)
    fig.cap0 <- "PKN and GTN. The prior knowledge network without any logics 
    (PKN, left) and the ground truth (GTN, right). Red 'tee' arrows depict
    repression the others activation of 
    the child. The stimulated S-genes are diamond shaped. Blue diamond edges 
    in the PKN depict the existence of activation and repression in one arrow."
    fig.cap1 <- "GTN and greedy optimum. The GTN (left) and the greedy 
    optmimum (right)."
    fig.cap2 <- "Expected and observed data. The expected data pattern 
    (bottom row) of S-gene S1 and the observed data patterns of the 
    E-genes attached to S1."
    fig.cap3 <- "BCR signalling. The PKN (left) and the greedy optimum 

    # --- Eval=false [] ---
    # Key functions: requireNamespace, install, simBoolGtn, addNoise, bnem
    #  if (!requireNamespace("BiocManager", quietly = TRUE)) {
    #    install.packages("BiocManager")
    #  }
    #  BiocManager::install("bnem")

    ## -----------------------------------------------------------------------------
    library(bnem)

    ## -----------------------------------------------------------------------------
    set.seed(9247)
    sim <- simBoolGtn(Sgenes = 10, maxEdges = 10, keepsif = TRUE, negation=0.1,
                      layer=1)
    fc <- addNoise(sim,sd=1)
    expression <- sim$expression
    CNOlist <- sim$CNOlist

    # --- Eval = False [] ---
    # Key functions: bnem, simBoolGtn, addNoise, exhaustive
    #  ## exhaustive search:
    #  exhaustive <- bnem(search = "exhaustive",
    #                     parallel = parallel,
    #                     CNOlist=CNOlist,
    #                     fc=fc,
    #                     expression=expression,
    #                     model=model
    #                     )

    ## -----------------------------------------------------------------------------
    set.seed(9247)
    sim <- simBoolGtn(Sgenes = 4, maxEdges = 50, dag = FALSE,
                      negation = 0, allstim = TRUE,frac=0.1)
    fc <- addNoise(sim,sd=1)
    expression <- sim$expression

    # --- Eval = False [] ---
    # Key functions: findResiduals, numeric, for
    #  residuals <- findResiduals(resString3, CNOlist, model, fc, verbose = FALSE)
    #  ## verbose = TRUE plots the residuals matrices

    ## -----------------------------------------------------------------------------
    data(bcr)
    ## head(fc)
    fc <- bcr$fc
    expression <- bcr$expression

    ## -----------------------------------------------------------------------------
    library(CellNOptR)
    negation <- FALSE # what happens if we allow negation?
    sifMatrix <- numeric()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bnem_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bnem_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bnem_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BNEM:", paste0("    bnem: ", packageVersion("bnem"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bnem_results.csv
    touch ${prefix}_bnem_output.rds
    echo "BIOC_BNEM:" > versions.yml
    echo "    bnem: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BNEM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BNEM(ch_input)

    emit:
    results  = BIOC_BNEM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BNEM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BNEM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BNEM.out.versions  // channel: path(versions.yml)
}
