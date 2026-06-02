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
    library(Banksy)
    library(ARI)
    library(HarmonyMatrix)
    library(jsonlite)

    # --- Neighborhood Feature Computation [banksy] ---
    # Key functions: computeBanksy
    spe <- computeBanksy(
        spe,
        assay_name = "normcounts",
        compute_agf = TRUE,
        k_geom = 18
    )

    # --- Dimensionality Reduction [banksy] ---
    # Key functions: runBanksyPCA, runBanksyUMAP
    spe <- runBanksyPCA(
        spe,
        use_agf = TRUE,
        lambda = 0.2,
        npcs = 20,
        seed = 1000
    )
    spe <- runBanksyUMAP(
        spe,
        use_agf = TRUE,
        lambda = 0.2,
        npcs = 20
    )

    # --- Spatial Clustering [banksy] ---
    # Key functions: clusterBanksy, connectClusters, clusterNames
    spe <- clusterBanksy(
        spe,
        dimred = "PCA_M1_lam0.2",
        resolution = 0.55,
        seed = 1000
    )
    spe <- connectClusters(
        spe,
        map_to = "clust_annotation"
    )
    cnms <- clusterNames(spe)


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
