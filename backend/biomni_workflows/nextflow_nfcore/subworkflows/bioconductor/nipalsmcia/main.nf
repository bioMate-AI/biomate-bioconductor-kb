#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: nipalsMCIA
// Computes Multiple Co-Inertia Analysis (MCIA), a dimensionality reduction (jDR) algorithm, for a mult
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/nipalsMCIA/inst/doc/Analysis-of-MCIA-Decomposition.R
// Upstream  : BiocFileCache, ComplexHeatmap, MultiAssayExperiment, Seurat, dplyr
// Downstream: none
//
// Install: BiocManager::install("nipalsMCIA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NIPALSMCIA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-nipalsmcia"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-nipalsmcia:1.4.4--r44_0' :
        'quay.io/biocontainers/bioconductor-nipalsmcia:1.4.4--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_nipalsmcia_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_nipalsmcia_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_nipalsmcia_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(nipalsMCIA)
    library(jsonlite)

    # --- Simple mae analysis [] ---
    # Key functions: install_github, simple_mae, nipals_multiblock, slotNames, projection_plot, get_metadata_colors, global_scores_heatmap, block_weights_heatmap
    meta_colors = c("blue", "grey", "yellow") can use color names
    meta_colors = c("#00204DFF", "#7C7B78FF", "#FFEA46FF") can use hex codes
    meta_colors <- get_metadata_colors(mcia_results, color_col = 1,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_nipalsmcia_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_nipalsmcia_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_nipalsmcia_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NIPALSMCIA:", paste0("    nipalsmcia: ", packageVersion("nipalsMCIA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nipalsmcia_results.csv
    touch ${prefix}_nipalsmcia_output.rds
    echo "BIOC_NIPALSMCIA:" > versions.yml
    echo "    nipalsmcia: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NIPALSMCIA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NIPALSMCIA(ch_input)

    emit:
    results  = BIOC_NIPALSMCIA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NIPALSMCIA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NIPALSMCIA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NIPALSMCIA.out.versions  // channel: path(versions.yml)
}
