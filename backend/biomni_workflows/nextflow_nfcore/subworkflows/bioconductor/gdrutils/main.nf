#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gDRutils
// This package contains utility functions used throughout the gDR platform to fit data, manipulate dat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gDRutils/inst/doc/gDRutils.R
// Upstream  : none
// Downstream: gDR
//
// Install: BiocManager::install("gDRutils")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GDRUTILS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gdrutils"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gdrutils:1.4.10--r44_0' :
        'quay.io/biocontainers/bioconductor-gdrutils:1.4.10--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gdrutils_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gdrutils_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gdrutils_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MAEpply)
    library(jsonlite)

    # --- Get Synthetic Data [] ---
    # Key functions: get_synthetic_data, MAEpply
    ---------------------------------------------------------------------
    mae <- get_synthetic_data("finalMAE_combo_matrix_small")
    MAEpply(mae, dim)
    # --- Maepply [] ---
    # Key functions: MAEpply
    ---------------------------------------------------------------------
    MAEpply(mae, rowData)
    # --- Convert Mae Assay To Dt [] ---
    # Key functions: convert_mae_assay_to_dt
    ---------------------------------------------------------------------
    mdt <- convert_mae_assay_to_dt(mae, "Metrics")
    head(mdt, 3)
    # --- Convert Se Assay To Dt [] ---
    # Key functions: convert_se_assay_to_dt
    ---------------------------------------------------------------------
    se <- mae[[1]]
    sdt <- convert_se_assay_to_dt(se, "Metrics")
    head(sdt, 3)
    # --- Get Env Identifiers [] ---
    # Key functions: get_env_identifiers
    ---------------------------------------------------------------------
    get_env_identifiers()
    # --- Set Env Identifier [] ---
    # Key functions: set_env_identifier
    ---------------------------------------------------------------------
    set_env_identifier("concentration", "Dose")
    # --- Get Env Identifiers [] ---
    # Key functions: get_env_identifiers
    ---------------------------------------------------------------------
    get_env_identifiers("concentration")
    # --- Reset Env Identifiers [] ---
    # Key functions: reset_env_identifiers
    ---------------------------------------------------------------------
    reset_env_identifiers()
    # --- Get Env Identifiers [] ---
    # Key functions: get_env_identifiers
    ---------------------------------------------------------------------
    get_env_identifiers("concentration")
    # --- Table [] ---
    # Key functions: validate_identifiers
    ---------------------------------------------------------------------
    # Example data.table
    # --- Validate Mae [] ---
    # Key functions: validate_MAE
    ---------------------------------------------------------------------
    validate_MAE(mae)
    # --- Validate Se [] ---
    # Key functions: validate_SE
    ---------------------------------------------------------------------
    validate_SE(se)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gdrutils_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gdrutils_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gdrutils_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GDRUTILS:", paste0("    gdrutils: ", packageVersion("gDRutils"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gdrutils_results.csv
    touch ${prefix}_gdrutils_output.rds
    echo "BIOC_GDRUTILS:" > versions.yml
    echo "    gdrutils: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GDRUTILS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GDRUTILS(ch_input)

    emit:
    results  = BIOC_GDRUTILS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GDRUTILS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GDRUTILS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GDRUTILS.out.versions  // channel: path(versions.yml)
}
