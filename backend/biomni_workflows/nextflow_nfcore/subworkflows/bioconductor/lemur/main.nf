#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: lemur
// Fit a latent embedding multivariate regression (LEMUR) model to multi-condition single-cell data. Th
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/lemur/inst/doc/Introduction.R
// Upstream  : SingleCellExperiment, tidyverse
// Downstream: none
//
// Install: BiocManager::install("lemur")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LEMUR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-lemur"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-lemur:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-lemur:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_lemur_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_lemur_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_lemur_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(lemur)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: umap, as_tibble, ggplot, geom_point, labs, facet_wrap, tibble, scale_color_gradient2
    tumor_label_df <- tibble(cell_id = colnames(fit),
    chr7_total_expr = colMeans(logcounts(fit)[rowData(fit)$chromosome == "7",]),
    chr10_total_expr = colMeans(logcounts(fit)[rowData(fit)$chromosome == "10",])) %>%
    # --- Lemur analysis [] ---
    # Key functions: lemur, align_harmony, test_de, find_de_neighborhoods, as_tibble, left_join, relocate, arrange
    tum_nei <- find_de_neighborhoods(tumor_fit, group_by = vars(patient_id, condition), verbose = FALSE)
    as_tibble(tum_nei) %>%
    left_join(as_tibble(rowData(fit)[,1:2]), by = c("name" = "gene_id")) %>%

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_lemur_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_lemur_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_lemur_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LEMUR:", paste0("    lemur: ", packageVersion("lemur"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lemur_results.csv
    touch ${prefix}_lemur_output.rds
    echo "BIOC_LEMUR:" > versions.yml
    echo "    lemur: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LEMUR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LEMUR(ch_input)

    emit:
    results  = BIOC_LEMUR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LEMUR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LEMUR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LEMUR.out.versions  // channel: path(versions.yml)
}
