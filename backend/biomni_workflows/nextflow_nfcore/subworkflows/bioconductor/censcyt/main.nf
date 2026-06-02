#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: censcyt
// Methods for differential abundance analysis in high-dimensional cytometry data when a covariate is s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/censcyt/inst/doc/censored_covariate.R
// Upstream  : SummarizedExperiment, ggplot2, tidyr
// Downstream: none
//
// Install: BiocManager::install("censcyt")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CENSCYT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-censcyt"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-censcyt:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-censcyt:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_censcyt_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_censcyt_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_censcyt_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(censcyt)
    library(jsonlite)

    # --- Formula and Contrast Creation [] ---
    # Key functions: createFormula
    da_formula <- createFormula(
        experiment_info = experiment_info,
        cols_fixed = "X_obs",
        cols_random = "sample_id",
        event_indicator = "Event_ind"
    )
    contrast <- matrix(c(0, 1))


    # --- Differential Abundance Testing [] ---
    # Key functions: testDA_censoredGLMM
    da_out <- testDA_censoredGLMM(
        d_counts = d_counts,
        formula = da_formula,
        contrast = contrast,
        mi_reps = 30,
        imputation_method = "km",
        verbose = TRUE,
        BPPARAM = BiocParallel::SerialParam()
    )


    # --- Results Evaluation [] ---
    # Key functions: topTable
    results_table <- topTable(da_out)


    # --- Wrapper Pipeline Execution [] ---
    # Key functions: censcyt
    out_DA <- censcyt(
        d_input,
        experiment_info,
        marker_info,
        formula = da_formula,
        contrast = contrast,
        meta_clustering = TRUE,
        meta_k = 10,
        seed_clustering = 123,
        verbose = FALSE,
        mi_reps = 10,
        imputation_method = "km",
        BPPARAM = BiocParallel::SerialParam()
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_censcyt_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_censcyt_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_censcyt_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CENSCYT:", paste0("    censcyt: ", packageVersion("censcyt"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_censcyt_results.csv
    touch ${prefix}_censcyt_output.rds
    echo "BIOC_CENSCYT:" > versions.yml
    echo "    censcyt: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CENSCYT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CENSCYT(ch_input)

    emit:
    results  = BIOC_CENSCYT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CENSCYT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CENSCYT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CENSCYT.out.versions  // channel: path(versions.yml)
}
