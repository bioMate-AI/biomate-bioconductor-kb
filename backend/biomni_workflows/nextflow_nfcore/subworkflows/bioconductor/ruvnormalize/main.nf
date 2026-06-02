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

    # --- Uncorrected Evaluation ---
    # Key functions: clScore, svdPlot
    sdY <- apply(Y, 2, sd)
    ssd <- sort(sdY, decreasing=TRUE, index.return=TRUE)$ix
    kmres <- kmeans(Y[, ssd[1:nKeep], drop=FALSE], centers=2, nstart=200)
    uScore <- clScore(kmres$cluster, X)
    svdResUncorr <- svdPlot(
        Y[, ssd[1:nKeep], drop=FALSE],
        annot=annot,
        labels=lab.and.region,
        svdRes=NULL,
        plAnnots=plAnnots,
        kColors=gender.col,
        file=NULL
    )

    # --- Naive RUV-2 Normalization without Shrinkage ---
    # Key functions: naiveRandRUV, clScore, svdPlot
    nsY <- naiveRandRUV(Y, cIdx, nu.coeff=0, k=20)
    sdY_ns <- apply(nsY, 2, sd)
    ssd_ns <- sort(sdY_ns, decreasing=TRUE, index.return=TRUE)$ix
    kmres2ns <- kmeans(
        nsY[, ssd_ns[1:nKeep], drop=FALSE],
        centers=2,
        nstart=200
    )
    nsScore <- clScore(kmres2ns$cluster, X)
    svdRes2ns <- svdPlot(
        nsY[, ssd_ns[1:nKeep], drop=FALSE],
        annot=annot,
        labels=lab.and.region,
        svdRes=NULL,
        plAnnots=plAnnots,
        kColors=gender.col,
        file=NULL
    )

    # --- Naive RUV-2 Normalization with Shrinkage ---
    # Key functions: naiveRandRUV, clScore, svdPlot
    nY <- naiveRandRUV(Y, cIdx, nu.coeff=1e-3, k=ncol(Y))
    sdY_s <- apply(nY, 2, sd)
    ssd_s <- sort(sdY_s, decreasing=TRUE, index.return=TRUE)$ix
    kmres2 <- kmeans(
        nY[, ssd_s[1:nKeep], drop=FALSE],
        centers=2,
        nstart=200
    )
    nScore <- clScore(kmres2$cluster, X)
    svdRes2 <- svdPlot(
        nY[, ssd_s[1:nKeep], drop=FALSE],
        annot=annot,
        labels=lab.and.region,
        svdRes=NULL,
        plAnnots=plAnnots,
        kColors=gender.col,
        file=NULL
    )

    # --- Replicate-based RUV Normalization ---
    # Key functions: naiveReplicateRUV, clScore, svdPlot
    sRes <- naiveReplicateRUV(Y, cIdx, scIdx, k=20)
    sdY_rep <- apply(sRes$cY, 2, sd)
    ssd_rep <- sort(sdY_rep, decreasing=TRUE, index.return=TRUE)$ix
    kmresRep <- kmeans(
        sRes$cY[, ssd_rep[1:nKeep], drop=FALSE],
        centers=2,
        nstart=200
    )
    RepScore <- clScore(kmresRep$cluster, X)
    svdResRep <- svdPlot(
        sRes$cY[, ssd_rep[1:nKeep], drop=FALSE],
        annot=annot,
        labels=lab.and.region,
        svdRes=NULL,
        plAnnots=plAnnots,
        kColors=gender.col,
        file=NULL
    )


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
