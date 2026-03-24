#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Banksy
// Banksy is an R package that incorporates spatial information to cluster cells in a feature space (e.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Banksy/inst/doc/batch-correction.R
// Upstream  : ExperimentHub, Seurat, SpatialExperiment, SummarizedExperiment, cowplot
// Downstream: none
//
// Install: BiocManager::install("Banksy")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BANKSY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-banksy"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-banksy:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-banksy:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_banksy_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_banksy_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_banksy_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ARI)
    library(HarmonyMatrix)
    library(jsonlite)

    # --- run Banksy P C A [] ---
    # Key functions: runBanksyPCA
    spe <- runBanksyPCA(spe, use_agf = use_agf, lambda = lambda, npcs = npcs, seed = SEED)
    # --- Harmony Matrix [] ---
    # Key functions: HarmonyMatrix, reducedDim
    set.seed(SEED)
    harmony_embedding <- HarmonyMatrix(
    data_mat = reducedDim(spe, "PCA_M1_lam0.2"),
    # --- run Banksy U M A P [] ---
    # Key functions: runBanksyUMAP
    spe <- runBanksyUMAP(spe, use_agf = TRUE, lambda = lambda, npcs = npcs)
    spe <- runBanksyUMAP(spe, dimred = "Harmony_BANKSY")
    # --- plot_grid [] ---
    # Key functions: plot_grid, plotReducedDim, theme, guides
    plot_grid(
    plotReducedDim(spe, "UMAP_M1_lam0.2",
    theme(legend.position = "none"),
    # --- Custom ggplot2 visualization [] ---
    # Key functions: clusterNames, ARI, ggplot, geom_point
    cnm <- clusterNames(spe)[2]
    spatial_plots <- lapply(sample_names, function(snm) {
    ari <- aricode::ARI(x$clust_annotation, colData(x)[, cnm])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_banksy_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_banksy_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_banksy_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BANKSY:", paste0("    banksy: ", packageVersion("Banksy"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_banksy_results.csv
    touch ${prefix}_banksy_output.rds
    echo "BIOC_BANKSY:" > versions.yml
    echo "    banksy: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BANKSY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BANKSY(ch_input)

    emit:
    results  = BIOC_BANKSY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BANKSY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BANKSY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BANKSY.out.versions  // channel: path(versions.yml)
}
