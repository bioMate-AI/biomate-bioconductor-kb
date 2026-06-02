#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ScreenR
// ScreenR is a package suitable to perform hit identification in loss of function High Throughput Biol
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ScreenR/inst/doc/Analysis_Example.R
// Upstream  : dplyr, ggplot2, tidyr
// Downstream: none
//
// Install: BiocManager::install("ScreenR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCREENR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-screenr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-screenr:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-screenr:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_screenr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_screenr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_screenr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ScreenR)
    library(jsonlite)

    # --- tibble [] ---
    # Key functions: tibble
    data(count_table)
    data(annotation_table)
    # --- Create Object [] ---
    # Key functions: create_screenr_object

    # --- Removing all zero rows [] ---
    # Key functions: remove_all_zero_row
    object <- remove_all_zero_row(object)
    # --- normalize_data [] ---
    # Key functions: normalize_data, compute_data_table
    object <- normalize_data(object)
    object <- compute_data_table(object)
    # --- plot mapped reads [] ---
    # Key functions: plot_mapped_reads, coord_flip, scale_y_continuous, theme, ggtitle
    plot <- plot_mapped_reads(object, palette) +
    ggplot2::coord_flip() +
    ggplot2::scale_y_continuous(labels = scales::comma) +
    # --- plot mapped reads distribution boxplot [] ---
    # Key functions: plot_mapped_reads_distribution, coord_flip, theme

    # --- plot mapped reads distribution density [] ---
    # Key functions: plot_mapped_reads_distribution, theme

    # --- plot barcode lost [] ---
    # Key functions: plot_barcode_lost, coord_flip
    plot <- plot_barcode_lost(screenR_Object = object, palette = palette) +
    ggplot2::coord_flip()
    # --- plot barcode lost for gene [] ---
    # Key functions: plot_barcode_lost_for_gene

    # --- Plot MDS Sample [] ---
    # Key functions: plot_mds
    plot_mds(screenR_Object = object)
    # --- Plot MDS Treatment [] ---
    # Key functions: get_data_table, distinct, plot_mds
    group_table <- get_data_table(object)   %>%
    select(Sample, Day, Treatment) %>%
    distinct()
    # --- Plot MDS Day [] ---
    # Key functions: plot_mds

    # --- plot_zscore_distribution [] ---
    # Key functions: plot_zscore_distribution

    # --- plot_trend [] ---
    # Key functions: plot_trend
    plot_trend(screenR_Object = object,
    group_var = c("Time1", "Time2", "TRT"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_screenr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_screenr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_screenr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCREENR:", paste0("    screenr: ", packageVersion("ScreenR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_screenr_results.csv
    touch ${prefix}_screenr_output.rds
    echo "BIOC_SCREENR:" > versions.yml
    echo "    screenr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCREENR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCREENR(ch_input)

    emit:
    results  = BIOC_SCREENR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCREENR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCREENR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCREENR.out.versions  // channel: path(versions.yml)
}
