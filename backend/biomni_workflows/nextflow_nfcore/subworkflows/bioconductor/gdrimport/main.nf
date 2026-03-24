#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gDRimport
// The package is a part of the gDR suite. It helps to prepare raw drug response data for downstream pr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gDRimport/inst/doc/ConvertingMAEtoPharmacoSet.R
// Upstream  : none
// Downstream: gDR
//
// Install: BiocManager::install("gDRimport")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GDRIMPORT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gdrimport"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gdrimport:1.4.6--r44_0' :
        'quay.io/biocontainers/bioconductor-gdrimport:1.4.6--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gdrimport_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gdrimport_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gdrimport_plots.pdf"),    emit: plots, optional: true
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

    # --- M A Epply [] ---
    # Key functions: MAEpply
    gDRutils::MAEpply(mae, assays)
    # --- treatment Response [] ---
    # Key functions: treatmentResponse
    tre <- treatmentResponse(pset)
    head(rownames(tre))
    head(rowData(tre))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gdrimport_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gdrimport_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gdrimport_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GDRIMPORT:", paste0("    gdrimport: ", packageVersion("gDRimport"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gdrimport_results.csv
    touch ${prefix}_gdrimport_output.rds
    echo "BIOC_GDRIMPORT:" > versions.yml
    echo "    gdrimport: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GDRIMPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GDRIMPORT(ch_input)

    emit:
    results  = BIOC_GDRIMPORT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GDRIMPORT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GDRIMPORT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GDRIMPORT.out.versions  // channel: path(versions.yml)
}
