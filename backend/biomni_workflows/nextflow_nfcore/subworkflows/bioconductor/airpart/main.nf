#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: airpart
// Airpart identifies sets of genes displaying differential cell-type-specific allelic imbalance across
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/airpart/inst/doc/airpart.R
// Upstream  : SingleCellExperiment
// Downstream: none
//
// Install: BiocManager::install("airpart")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AIRPART {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-airpart"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-airpart:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-airpart:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_airpart_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_airpart_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_airpart_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(airpart)
    library(jsonlite)

    # --- Gene Clustering [] ---
    # Key functions: geneCluster, summaryAllelicRatio
    sce <- geneCluster(sce, G = 1:4)
    sce_hc <- geneCluster(sce, method = "hierarchical")
    summary_ar <- summaryAllelicRatio(sce)
    cluster_metadata <- metadata(sce)$geneCluster


    # --- Cell Type Partitioning [] ---
    # Key functions: estDisp, fusedLasso, consensusPart, wilcoxExt
    disp_est <- estDisp(sce, genecluster = 1)
    sce_sub <- fusedLasso(sce, model = "binomial", genecluster = 1,
        ncores = 1, niter = 2)
    sce_sub <- consensusPart(sce_sub)
    thrs <- 10^seq(from = -2, to = -0.4, by = 0.2)
    sce_sub_w <- wilcoxExt(sce, genecluster = 1, threshold = thrs)


    # --- Allelic Ratio Estimation and Testing [] ---
    # Key functions: allelicRatio, extractResult
    sce_sub <- allelicRatio(sce_sub, DAItest = TRUE)
    ar_results <- extractResult(sce_sub)
    s_values <- extractResult(sce_sub, "svalue")
    adj_p <- mcols(sce_sub)$adj.p.value


    # --- Visualisation [] ---
    # Key functions: makeHeatmap, makeForest, makeViolin, makeStep
    makeHeatmap(sce_sub, order_by_group = FALSE)
    makeForest(sce_sub, showtext = TRUE)
    makeViolin(sce_sub)
    makeStep(sce_sub[1:5, ])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_airpart_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_airpart_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_airpart_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AIRPART:", paste0("    airpart: ", packageVersion("airpart"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_airpart_results.csv
    touch ${prefix}_airpart_output.rds
    echo "BIOC_AIRPART:" > versions.yml
    echo "    airpart: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AIRPART_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AIRPART(ch_input)

    emit:
    results  = BIOC_AIRPART.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AIRPART.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AIRPART.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AIRPART.out.versions  // channel: path(versions.yml)
}
