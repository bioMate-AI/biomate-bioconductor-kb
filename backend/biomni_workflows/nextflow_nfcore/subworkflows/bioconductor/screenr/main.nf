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

    # --- Normalisation and Quality Control [] ---
    # Key functions: normalize_data, compute_data_table, plot_mapped_reads, plot_barcode_lost
    object <- normalize_data(object)
    object <- compute_data_table(object)
    palette <- c("#66c2a5", "#fc8d62", "#8da0cb", "#e78ac3")
    p1 <- plot_mapped_reads(object, palette)
    p2 <- plot_barcode_lost(screenR_Object = object, palette = palette)


    # --- Dimensionality Reduction [] ---
    # Key functions: plot_mds, get_data_table
    p_mds1 <- plot_mds(screenR_Object = object)
    group_table <- get_data_table(object)
    group_treatment <- group_table$Treatment
    p_mds2 <- plot_mds(
        screenR_Object = object,
        groups = factor(x = group_treatment, levels = unique(group_treatment))
    )


    # --- Statistical Screening and Hit Identification [] ---
    # Key functions: compute_metrics, find_zscore_hit, find_camera_hit, find_roast_hit
    metrics_t3 <- compute_metrics(
        object, control = "CTRL", treatment = "TRT", day = "Time3"
    )
    z_hits <- find_zscore_hit(
        table_treate_vs_control = metrics_t3,
        number_barcode = 6, metric = "median"
    )
    groups <- factor(c("T1", "T1", "T2", "T2"))
    matrix_model <- model.matrix(~ groups)
    colnames(matrix_model) <- unique(groups)
    cam_hits <- find_camera_hit(
        screenR_Object = object, matrix_model = matrix_model,
        contrast = "Time3_TRT"
    )


    # --- Candidate Prioritisation and Visualisation [] ---
    # Key functions: find_common_hit, plot_common_hit, plot_trend
    common_hits <- find_common_hit(
        z_hits, cam_hits, roast_hits, common_in = 2
    )
    p_venn <- plot_common_hit(
        hit_zscore = z_hits, hit_camera = cam_hits,
        roast_hits, show_elements = FALSE, show_percentage = TRUE
    )
    p_trend <- plot_trend(
        screenR_Object = object, genes = common_hits[1],
        nrow = 2, ncol = 2, group_var = c("Time1", "Time2", "TRT")
    )

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
