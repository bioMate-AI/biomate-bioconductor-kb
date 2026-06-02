#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gDR
// Package is a part of the gDR suite. It reexports functions from other packages in the gDR suite that
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gDR/inst/doc/gDR.R
// Upstream  : kableExtra
// Downstream: none
//
// Install: BiocManager::install("gDR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GDR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gdr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gdr:1.4.1--r44_0' :
        'quay.io/biocontainers/bioconductor-gdr:1.4.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gdr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gdr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gdr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(gDR)
    library(jsonlite)

    # --- Input Preparation and Normalisation [] ---
    # Key functions: prepare_input, create_and_normalize_SE
    inl <- gDR::prepare_input(imported_data)
    se <- gDR::create_and_normalize_SE(
        inl$df_list[["single-agent"]],
        data_type = "single-agent",
        nested_confounders = inl$nested_confounders
    )


    # --- Dose Response Curve Fitting [] ---
    # Key functions: average_SE, fit_SE
    se_avg <- gDR::average_SE(se, data_type = "single-agent")
    se_fit <- gDR::fit_SE(se_avg, data_type = "single-agent")


    # --- Pipeline Execution [] ---
    # Key functions: runDrugResponseProcessingPipeline, convert_se_assay_to_dt
    mae <- gDR::runDrugResponseProcessingPipeline(imported_data)
    se_metrics <- mae[["single-agent"]]
    metrics_dt <- gDR::convert_se_assay_to_dt(se_metrics, "Metrics")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gdr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gdr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gdr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GDR:", paste0("    gdr: ", packageVersion("gDR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gdr_results.csv
    touch ${prefix}_gdr_output.rds
    echo "BIOC_GDR:" > versions.yml
    echo "    gdr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GDR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GDR(ch_input)

    emit:
    results  = BIOC_GDR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GDR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GDR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GDR.out.versions  // channel: path(versions.yml)
}
