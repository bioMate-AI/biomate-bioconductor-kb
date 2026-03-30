#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MSstatsConvert
// MSstatsConvert provides tools for importing reports of Mass Spectrometry data processing tools into 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MSstatsConvert/inst/doc/msstats_data_format.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MSstatsConvert")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSSTATSCONVERT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msstatsconvert"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msstatsconvert:1.16.1--r44_0' :
        'quay.io/biocontainers/bioconductor-msstatsconvert:1.16.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msstatsconvert_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msstatsconvert_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msstatsconvert_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MSstatsLogsSettings)
    library(MSstatsSaveSessionInfo)
    library(jsonlite)

    # --- M Sstats Logs Settings [] ---
    # Key functions: MSstatsLogsSettings, MSstatsSaveSessionInfo, getInputFile
    library(MSstatsConvert)
    MSstatsLogsSettings(use_log_file = TRUE, append = FALSE)
    MSstatsLogsSettings(use_log_file = TRUE, append = TRUE,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msstatsconvert_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msstatsconvert_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msstatsconvert_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSSTATSCONVERT:", paste0("    msstatsconvert: ", packageVersion("MSstatsConvert"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msstatsconvert_results.csv
    touch ${prefix}_msstatsconvert_output.rds
    echo "BIOC_MSSTATSCONVERT:" > versions.yml
    echo "    msstatsconvert: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSSTATSCONVERT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSSTATSCONVERT(ch_input)

    emit:
    results  = BIOC_MSSTATSCONVERT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSSTATSCONVERT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSSTATSCONVERT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSSTATSCONVERT.out.versions  // channel: path(versions.yml)
}
