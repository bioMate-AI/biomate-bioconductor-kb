#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: FEAST
// Cell clustering is one of the most important and commonly performed tasks in single-cell RNA sequenc
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/FEAST/inst/doc/FEAST.R
// Upstream  : ggpubr
// Downstream: none
//
// Install: BiocManager::install("FEAST")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FEAST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-feast"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-feast:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-feast:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_feast_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_feast_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_feast_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FEAST)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>"
    )

    # --- Quick [] ---
    # Key functions: process_Y, FEAST, Norm_Y, par, for
    library(FEAST)
    data(Yan)
    k = length(unique(trueclass))
    Y = process_Y(Y, thre = 2)
    # The core function. 
    ixs = FEAST(Y, k=k)
    # look at the features
    Ynorm = Norm_Y(Y)
    par(mfrow = c(3,3))
    # --- Load Data [] ---
    # Key functions: feast
    data(Yan)
    dim(Y)
    table(trueclass)

    # --- Consensus [] ---
    # Key functions: process_Y, Consensus, cal_F2
    Y = process_Y(Y, thre = 2) # preprocess the data if needed
    con_res = Consensus(Y, k=k)

    ## ----gene-level, eval = TRUE, message=FALSE, results='hide', include = TRUE----
    F_res = cal_F2(Y, con_res$cluster)
    ixs = order(F_res$F_scores, decreasing = TRUE) # order the features

    # --- Validation [] ---
    # Key functions: for, TSCAN_Clust, SC3_Clust, toString, Norm_Y, cal_MSE
    ## clustering step
    tops = c(500, 1000, 2000)
    cluster_res = NULL
    for (top in tops){
        tmp_ixs = ixs[1:top]
        tmp_markers = rownames(Y)[tmp_ixs]
        tmp_res = TSCAN_Clust(Y, k = k, input_markers = tmp_markers)
        #tmp_res = SC3_Clust(Y, k = k, input_markers = tmp_markers)
        cluster_res[[toString(top)]] = tmp_res
    }

    # --- Demo [] ---
    # Key functions: TSCAN_Clust, which.min, eval_Cluster, process_Y, Consensus, Select_Model_short_TSCAN, Select_Model_short_SC3, Visual_Rslt
    original = TSCAN_Clust(Y, k=k)
    id = which.min(mse_res)
    eval_Cluster(original$cluster, trueclass)
    eval_Cluster(cluster_res[[id]]$cluster, trueclass)

    ## ----wraper-group, eval = TRUE, message=FALSE, results='hide', include = TRUE, fig.height=4.5, fig.width=8----
    data(Yan)
    Y = process_Y(Y, thre = 2) # preprocess the data if needed
    con_res = Consensus(Y, k=k)
    mod_res = Select_Model_short_TSCAN(Y, cluster = con_res$cluster, top = c(200, 500, 1000, 2000))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_feast_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_feast_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_feast_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FEAST:", paste0("    feast: ", packageVersion("FEAST"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_feast_results.csv
    touch ${prefix}_feast_output.rds
    echo "BIOC_FEAST:" > versions.yml
    echo "    feast: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FEAST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FEAST(ch_input)

    emit:
    results  = BIOC_FEAST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FEAST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FEAST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FEAST.out.versions  // channel: path(versions.yml)
}
