#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pmp
// Methods and tools for (pre-)processing of metabolomics datasets (i.e. peak matrices), including filt
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pmp/inst/doc/pmp_vignette_peak_matrix_processing_for_metabolomics_datasets.R
// Upstream  : S4Vectors, SummarizedExperiment, ggplot2, gridExtra, reshape2
// Downstream: none
//
// Install: BiocManager::install("pmp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PMP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pmp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pmp:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pmp:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pmp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pmp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pmp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pmp)
    library(jsonlite)

    # --- Peak Filtering [] ---
    # Key functions: filter_peaks_by_fraction, filter_peaks_by_rsd
    MTBLS79_filtered <- filter_peaks_by_fraction(
        df = MTBLS79_filtered,
        min_frac = 0.9,
        classes = MTBLS79_filtered$Class,
        method = "QC",
        qc_label = "QC"
    )
    MTBLS79_filtered <- filter_peaks_by_rsd(
        df = MTBLS79_filtered,
        max_rsd = 30,
        classes = MTBLS79_filtered$Class,
        qc_label = "QC"
    )


    # --- Normalisation [] ---
    # Key functions: pqn_normalisation
    MTBLS79_pqn_normalised <- pqn_normalisation(
        df = MTBLS79_filtered,
        classes = MTBLS79_filtered$Class,
        qc_label = "QC"
    )


    # --- Missing Value Imputation [] ---
    # Key functions: mv_imputation
    MTBLS79_mv_imputed <- mv_imputation(
        df = MTBLS79_pqn_normalised,
        method = "knn"
    )


    # --- Glog Transformation and Visualisation [] ---
    # Key functions: glog_transformation, processing_history, glog_plot_optimised_lambda
    MTBLS79_glog <- glog_transformation(
        df = MTBLS79_mv_imputed,
        classes = MTBLS79_filtered$Class,
        qc_label = "QC"
    )
    opt_lambda <- processing_history(
        MTBLS79_glog
    )$glog_transformation$lambda_opt
    glog_plot_optimised_lambda(
        df = MTBLS79_mv_imputed,
        optimised_lambda = opt_lambda,
        classes = MTBLS79_filtered$Class,
        qc_label = "QC"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pmp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pmp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pmp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PMP:", paste0("    pmp: ", packageVersion("pmp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pmp_results.csv
    touch ${prefix}_pmp_output.rds
    echo "BIOC_PMP:" > versions.yml
    echo "    pmp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PMP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PMP(ch_input)

    emit:
    results  = BIOC_PMP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PMP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PMP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PMP.out.versions  // channel: path(versions.yml)
}
