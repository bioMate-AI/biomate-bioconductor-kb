#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CellMixS
// CellMixS provides metrics and functions to evaluate batch effects, data integration and batch effect
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CellMixS/inst/doc/CellMixS.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CellMixS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CELLMIXS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cellmixs"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cellmixs:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cellmixs:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cellmixs_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cellmixs_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cellmixs_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CellMixS)
    library(jsonlite)

    # --- Cell-Specific Mixing Score [] ---
    # Key functions: cms
    sce50 <- cms(sce50, k = 30, group = "batch", res_name = "unaligned",
                 n_dim = 3, cell_min = 4)
    sim_list <- lapply(c("batch0", "batch20"), function(name) {
        sce <- sim_list[[name]]
        cms(sce, k = 30, group = "batch", res_name = "unaligned",
            n_dim = 3, cell_min = 4)
    })


    # --- Metric Visualization [] ---
    # Key functions: visHist, visMetric, visOverview, visCluster
    p_hist <- visHist(sce50)
    metric_plot <- visMetric(sce20, metric_var = "cms_smooth.unaligned")
    sce20[["celltype"]] <- as.factor(rep(c("CD4+", "CD8+"),
                                         length.out = ncol(sce20)))
    overview_plot <- visOverview(sce20, "batch", other_var = "celltype")
    cluster_plot <- visCluster(sce20, metric_var = "cms.unaligned",
                               cluster_var = "celltype")


    # --- Local Density Factor Difference [] ---
    # Key functions: ldfDiff, visIntegration
    sce_pre_list <- list("1" = sce20[, sce20$batch == "1"],
                         "2" = sce20[, sce20$batch == "2"],
                         "3" = sce20[, sce20$batch == "3"])
    sce20 <- ldfDiff(sce_pre_list, sce_combined = sce20,
                     group = "batch", k = 70, dim_red = "PCA",
                     dim_combined = "MNN", assay_pre = "counts",
                     n_dim = 3, res_name = "MNN")
    vis_ldf <- visIntegration(sce20, metric = "diff_ldf",
                              metric_name = "ldfDiff")


    # --- Integration Evaluation [] ---
    # Key functions: evalIntegration, visOverview
    sce50 <- evalIntegration(metrics = c("isi", "entropy"), sce50,
                             group = "batch", k = 30, n_dim = 2,
                             cell_min = 4,
                             res_name = c("weighted_isi", "entropy"))
    vis_eval <- visOverview(sce50, "batch",
                            metric = c("cms_smooth.unaligned",
                                       "weighted_isi", "entropy"),
                            prefix = FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cellmixs_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cellmixs_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cellmixs_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CELLMIXS:", paste0("    cellmixs: ", packageVersion("CellMixS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cellmixs_results.csv
    touch ${prefix}_cellmixs_output.rds
    echo "BIOC_CELLMIXS:" > versions.yml
    echo "    cellmixs: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CELLMIXS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CELLMIXS(ch_input)

    emit:
    results  = BIOC_CELLMIXS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CELLMIXS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CELLMIXS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CELLMIXS.out.versions  // channel: path(versions.yml)
}
