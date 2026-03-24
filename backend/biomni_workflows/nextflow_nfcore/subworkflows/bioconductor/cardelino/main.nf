#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cardelino
// Methods to infer clonal tree configuration for a population of cells using single-cell RNA-seq data 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cardelino/inst/doc/vignette-cloneid.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("cardelino")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CARDELINO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cardelino"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cardelino:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cardelino:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cardelino_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cardelino_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cardelino_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cardelino)
    library(jsonlite)

    # --- Plot hierarchical clustering heatmap [] ---
    # Key functions: pheatmap
    AF_mt <- as.matrix(AD / DP)
    pheatmap::pheatmap(AF_mt)
    # --- Load cellSNP vcf analysis [] ---
    # Key functions: load_cellSNP_vcf, plot_tree, clone_id, prob_heatmap, assign_cells_to_clones, heat_matrix, scale_fill_gradient2, ggtitle
    AD_file <- system.file("extdata", "passed_ad.mtx", package = "cardelino")
    DP_file <- system.file("extdata", "passed_dp.mtx", package = "cardelino")
    id_file <- system.file("extdata", "passed_variant_names.txt",

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cardelino_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cardelino_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cardelino_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CARDELINO:", paste0("    cardelino: ", packageVersion("cardelino"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cardelino_results.csv
    touch ${prefix}_cardelino_output.rds
    echo "BIOC_CARDELINO:" > versions.yml
    echo "    cardelino: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CARDELINO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CARDELINO(ch_input)

    emit:
    results  = BIOC_CARDELINO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CARDELINO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CARDELINO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CARDELINO.out.versions  // channel: path(versions.yml)
}
