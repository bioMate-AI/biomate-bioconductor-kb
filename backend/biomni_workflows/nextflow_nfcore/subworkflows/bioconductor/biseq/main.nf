#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BiSeq
// The BiSeq package provides useful classes and functions to handle and analyze targeted bisulfite seq
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BiSeq/inst/doc/BiSeq.R
// Upstream  : none
// Downstream: RRBSdata
//
// Install: BiocManager::install("BiSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BISEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biseq:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biseq:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BiSeq)
    library(BSraw)
    library(BSrel)
    library(DataFrame)
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- CpG Clustering [] ---
    # Key functions: clusterSites, clusterSitesToGR
    rrbs_clustered <- clusterSites(
        object = rrbs_filtered,
        groups = colData(rrbs_filtered)$group,
        maxDist = 100,
        minSites = 20
    )
    cluster_gr <- clusterSitesToGR(rrbs_clustered)


    # --- Methylation Smoothing [] ---
    # Key functions: predictMeth
    meth_predicted <- predictMeth(
        object = rrbs_clustered,
        simplified = TRUE
    )


    # --- Differential Methylation Testing [] ---
    # Key functions: betaRegression
    predicted_meth_subset <- meth_predicted[1:100, ]
    beta_results <- betaRegression(
        formula = ~ group,
        link = "cloglog",
        object = predicted_meth_subset,
        type = "BR"
    )


    # --- FDR Estimation and Loci Selection [] ---
    # Key functions: estFDR, postHocTest
    fdr_estimated <- estFDR(
        betaResults = beta_results,
        covariate = "group",
        m = 10
    )
    significant_loci <- postHocTest(
        betaResults = beta_results,
        FDR = fdr_estimated,
        alpha = 0.05
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BISEQ:", paste0("    biseq: ", packageVersion("BiSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biseq_results.csv
    touch ${prefix}_biseq_output.rds
    echo "BIOC_BISEQ:" > versions.yml
    echo "    biseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BISEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BISEQ(ch_input)

    emit:
    results  = BIOC_BISEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BISEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BISEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BISEQ.out.versions  // channel: path(versions.yml)
}
