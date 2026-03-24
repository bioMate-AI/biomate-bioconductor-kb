#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: protGear
// A generic three-step pre-processing package for protein microarray data. This package contains diffe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/protGear/inst/doc/vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("protGear")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROTGEAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-protgear"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-protgear:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-protgear:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_protgear_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_protgear_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_protgear_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(protGear)
    library(jsonlite)

    # --- Principal component analysis [] ---
    # Key functions: prcomp, get_pca_var, fviz_pca_ind, fviz_pca_biplot, theme_minimal
    res_pca <- prcomp( norm_df, scale = TRUE)
    var <- get_pca_var(res_pca)
    p1 <- fviz_pca_ind(res_pca,
    # --- Custom ggplot2 visualization [] ---
    # Key functions: sym, ggplot, geom_violin, ylab, theme_minimal, ggtitle, gather, geom_boxplot
    less_20 <- rlang::sym(paste0("CV <= ",cv_cut_off, "_perc"))
    gt_20 <- rlang::sym(paste0("CV > ",cv_cut_off, "_perc"))
    less_20_per <-  rlang::sym(paste0("% CV <=",cv_cut_off))
    # --- Table formatting and display [] ---
    # Key functions: array_vars, visualize_slide, visualize_slide_2d, map, set_names, ldply, plot_FB, plot_bg
    dataCV_best2 <- purrr::map(.x=dataCV, .f=best_CV_estimation , slide_id="iden",lab_replicates=3,
    dataCV_best2 <- set_names(dataCV_best2, purrr::map(filenames, name_of_files))
    dataCV_sample_best2 <- purrr::map(.x=dataCV_best2, .f=cv_by_sample_estimation ,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_protgear_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_protgear_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_protgear_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PROTGEAR:", paste0("    protgear: ", packageVersion("protGear"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_protgear_results.csv
    touch ${prefix}_protgear_output.rds
    echo "BIOC_PROTGEAR:" > versions.yml
    echo "    protgear: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PROTGEAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PROTGEAR(ch_input)

    emit:
    results  = BIOC_PROTGEAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PROTGEAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PROTGEAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PROTGEAR.out.versions  // channel: path(versions.yml)
}
