#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scRNAseqApp
// The scRNAseqApp is a Shiny app package designed for interactive visualization of single-cell data. I
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scRNAseqApp/inst/doc/scRNAseqApp.R
// Upstream  : Seurat
// Downstream: none
//
// Install: BiocManager::install("scRNAseqApp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCRNASEQAPP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scrnaseqapp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scrnaseqapp:1.6.1--r44_0' :
        'quay.io/biocontainers/bioconductor-scrnaseqapp:1.6.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scrnaseqapp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scrnaseqapp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scrnaseqapp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scRNAseqApp)
    library(jsonlite)

    # --- Scrnaseqapp [] ---
    # Key functions: scRNAseqApp
    ---------------------------------------------------------------------
    scRNAseqApp(app_path = publish_folder)
    # --- Createappconfig [] ---
    # Key functions: createAppConfig, createDataSet, path
    ---------------------------------------------------------------------
    library(Seurat)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scrnaseqapp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scrnaseqapp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scrnaseqapp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCRNASEQAPP:", paste0("    scrnaseqapp: ", packageVersion("scRNAseqApp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scrnaseqapp_results.csv
    touch ${prefix}_scrnaseqapp_output.rds
    echo "BIOC_SCRNASEQAPP:" > versions.yml
    echo "    scrnaseqapp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCRNASEQAPP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCRNASEQAPP(ch_input)

    emit:
    results  = BIOC_SCRNASEQAPP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCRNASEQAPP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCRNASEQAPP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCRNASEQAPP.out.versions  // channel: path(versions.yml)
}
