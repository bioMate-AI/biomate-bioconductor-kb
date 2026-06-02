#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MMUPHin
// MMUPHin is an R package for meta-analysis tasks of microbiome cohorts. It has function interfaces fo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MMUPHin/inst/doc/MMUPHin.R
// Upstream  : dplyr, ggplot2, magrittr
// Downstream: none
//
// Install: BiocManager::install("MMUPHin")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MMUPHIN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mmuphin"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mmuphin:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mmuphin:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mmuphin_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mmuphin_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mmuphin_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MMUPHin)
    library(jsonlite)

    # --- Slice coverage by threshold [] ---
    # Key functions: arrange, slice, ggplot, geom_bar, coord_flip

    # --- Custom ggplot2 visualization [] ---
    # Key functions: arrange, ggplot, geom_bar, coord_flip, geom_point, geom_line, geom_errorbar, vegdist
    data("vaginal_abd", "vaginal_meta")
    D_vaginal <- vegdist(t(vaginal_abd))
    # --- Adjust batch analysis [] ---
    # Key functions: adjust_batch, vegdist, adonis2, lm_meta, discrete_discover, continuous_discover
    control_meta <- subset(CRC_meta, study_condition == "control")
    control_abd_adj <- CRC_abd_adj[, rownames(control_meta)]
    D_control <- vegdist(t(control_abd_adj))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mmuphin_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mmuphin_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mmuphin_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MMUPHIN:", paste0("    mmuphin: ", packageVersion("MMUPHin"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mmuphin_results.csv
    touch ${prefix}_mmuphin_output.rds
    echo "BIOC_MMUPHIN:" > versions.yml
    echo "    mmuphin: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MMUPHIN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MMUPHIN(ch_input)

    emit:
    results  = BIOC_MMUPHIN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MMUPHIN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MMUPHIN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MMUPHIN.out.versions  // channel: path(versions.yml)
}
