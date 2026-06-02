#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RUVnormalize
// RUVnormalize is meant to remove unwanted variation from gene expression data when the factor of inte
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RUVnormalize/inst/doc/RUVnormalize.R
// Upstream  : RUVnormalizeData, spams
// Downstream: none
//
// Install: BiocManager::install("RUVnormalize")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RUVNORMALIZE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ruvnormalize"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ruvnormalize:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ruvnormalize:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ruvnormalize_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ruvnormalize_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ruvnormalize_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RUVnormalize)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: exprs, phenoData
    data('gender', package='RUVnormalizeData')
    Y <- t(exprs(gender))
    X <- as.numeric(phenoData(gender)$gender == 'M')
    X <- X - mean(X)
    X <- cbind(X/(sqrt(sum(X^2))))
    # --- Centering [] ---
    # Key functions: scale
    ## Remove platform effect by centering.
    Y[chip=='hgu95a.db',] <- scale(Y[chip=='hgu95a.db',], scale=FALSE)
    Y[chip=='hgu95av2.db',] <- scale(Y[chip=='hgu95av2.db',], scale=FALSE)
    # --- Uncorrected [] ---
    # Key functions: kmeans, clScore
    ## Sort genes by their standard deviation
    sdY <- apply(Y, 2, sd)
    ssd <- sort(sdY, decreasing=TRUE, index.return=TRUE)$ix
    ## Cluster the samples
    kmres <- kmeans(Y[, ssd[1:nKeep], drop=FALSE], centers=2, nstart=200)
    # --- Uncorrectedplot [] ---
    # Key functions: svdPlot

    # --- Mc [] ---
    # Key functions: scale, kmeans, clScore
    ## Centering by region-lab
    YmeanCorr <- Y
    # --- Mcplot [] ---
    # Key functions: svdPlot

    # --- Nsruv2 [] ---
    # Key functions: naiveRandRUV, kmeans, clScore
    ## Naive RUV-2 no shrinkage
    k <- 20
    nu <- 0
    nsY <- naiveRandRUV(Y, cIdx, nu.coeff=0, k=k)
    sdY <- apply(nsY, 2, sd)
    # --- svd Plot [] ---
    # Key functions: svdPlot

    # --- Sruv2 [] ---
    # Key functions: naiveRandRUV, kmeans, clScore
    ## Naive RUV-2 + shrinkage
    k <- m
    nu.coeff <- 1e-3
    nY <- naiveRandRUV(Y, cIdx, nu.coeff=nu.coeff, k=k)
    sdY <- apply(nY, 2, sd)
    # --- svd Plot [] ---
    # Key functions: svdPlot

    # --- Rep [] ---
    # Key functions: naiveReplicateRUV, kmeans, clScore
    ## Replicate-based
    sRes <- naiveReplicateRUV(Y, cIdx, scIdx, k=20)
    sdY <- apply(sRes$cY, 2, sd)
    ssd <- sort(sdY,decreasing=TRUE,index.return=TRUE)$ix
    kmresRep <- kmeans(sRes$cY[,ssd[1:nKeep],drop=FALSE],centers=2,nstart=200)
    # --- Repplot [] ---
    # Key functions: svdPlot

    # --- Rep Iter [] ---
    # Key functions: iterativeRUV

    # --- Ridge Iter [] ---
    # Key functions: iterativeRUV


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ruvnormalize_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ruvnormalize_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ruvnormalize_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RUVNORMALIZE:", paste0("    ruvnormalize: ", packageVersion("RUVnormalize"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ruvnormalize_results.csv
    touch ${prefix}_ruvnormalize_output.rds
    echo "BIOC_RUVNORMALIZE:" > versions.yml
    echo "    ruvnormalize: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RUVNORMALIZE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RUVNORMALIZE(ch_input)

    emit:
    results  = BIOC_RUVNORMALIZE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RUVNORMALIZE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RUVNORMALIZE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RUVNORMALIZE.out.versions  // channel: path(versions.yml)
}
