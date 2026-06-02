#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HiCBricks
// HiCBricks is a library designed for handling large high-resolution Hi-C datasets. Over the years, th
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HiCBricks/inst/doc/IntroductionToHiCBricks.R
// Upstream  : GenomicRanges, curl, knitr
// Downstream: none
//
// Install: BiocManager::install("HiCBricks")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HICBRICKS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hicbricks"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hicbricks:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hicbricks:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hicbricks_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hicbricks_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hicbricks_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Brick_add_ranges)
    library(Brick_get_ranges)
    library(Brick_vizart_plot_heatmap)
    library(jsonlite)

    # --- Load BrickContainer analysis [] ---
    # Key functions: load_BrickContainer, Brick_vizart_plot_heatmap, Brick_add_ranges, Brick_get_ranges
    BrickContainer_dir <- file.path(tempdir(), "HiCBricks_vignette_test")
    My_BrickContainer <- load_BrickContainer(project_dir = BrickContainer_dir)
    Brick_vizart_plot_heatmap(File = file.path(tempdir(),

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hicbricks_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hicbricks_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hicbricks_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HICBRICKS:", paste0("    hicbricks: ", packageVersion("HiCBricks"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hicbricks_results.csv
    touch ${prefix}_hicbricks_output.rds
    echo "BIOC_HICBRICKS:" > versions.yml
    echo "    hicbricks: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HICBRICKS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HICBRICKS(ch_input)

    emit:
    results  = BIOC_HICBRICKS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HICBRICKS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HICBRICKS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HICBRICKS.out.versions  // channel: path(versions.yml)
}
