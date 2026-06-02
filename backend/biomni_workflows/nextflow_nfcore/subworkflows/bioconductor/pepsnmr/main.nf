#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PepsNMR
// This package provides R functions for common pre-procssing steps that are applied on 1H-NMR data. It
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PepsNMR/inst/doc/PepsNMR_minimal_example.R
// Upstream  : PepsNMRData
// Downstream: none
//
// Install: BiocManager::install("PepsNMR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PEPSNMR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pepsnmr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pepsnmr:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pepsnmr:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pepsnmr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pepsnmr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pepsnmr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PepsNMR)
    library(ReadFids)
    library(jsonlite)

    # --- Solvent Suppression and Apodization [] ---
    # Key functions: SolventSuppression, Apodization
    SS.res <- SolventSuppression(
        Fid_data.GDC,
        returnSolvent = TRUE
    )
    Fid_data.SS <- SS.res[["Fid_data"]]
    Fid_data.A <- Apodization(
        Fid_data.SS,
        Fid_info
    )


    # --- Fourier Transform and Zero Filling [] ---
    # Key functions: ZeroFilling, FourierTransform
    Fid_data.ZF <- ZeroFilling(
        Fid_data.A,
        fn = ncol(Fid_data.A)
    )
    RawSpect_data.FT <- FourierTransform(
        Fid_data.ZF,
        Fid_info
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pepsnmr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pepsnmr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pepsnmr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PEPSNMR:", paste0("    pepsnmr: ", packageVersion("PepsNMR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pepsnmr_results.csv
    touch ${prefix}_pepsnmr_output.rds
    echo "BIOC_PEPSNMR:" > versions.yml
    echo "    pepsnmr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PEPSNMR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PEPSNMR(ch_input)

    emit:
    results  = BIOC_PEPSNMR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PEPSNMR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PEPSNMR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PEPSNMR.out.versions  // channel: path(versions.yml)
}
