#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: IsoCorrectoRGUI
// IsoCorrectoRGUI is a Graphical User Interface for the IsoCorrectoR package. IsoCorrectoR performs th
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/IsoCorrectoRGUI/inst/doc/IsoCorrectoRGUI.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("IsoCorrectoRGUI")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISOCORRECTORGUI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-isocorrectorgui"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-isocorrectorgui:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-isocorrectorgui:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_isocorrectorgui_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_isocorrectorgui_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_isocorrectorgui_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(IsoCorrectoRGUI)
    library(jsonlite)

    # --- kable [] ---
    # Key functions: kable
    fileExample[is.na(fileExample)] <- ""
    knitr::kable(

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_isocorrectorgui_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_isocorrectorgui_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_isocorrectorgui_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISOCORRECTORGUI:", paste0("    isocorrectorgui: ", packageVersion("IsoCorrectoRGUI"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_isocorrectorgui_results.csv
    touch ${prefix}_isocorrectorgui_output.rds
    echo "BIOC_ISOCORRECTORGUI:" > versions.yml
    echo "    isocorrectorgui: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISOCORRECTORGUI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ISOCORRECTORGUI(ch_input)

    emit:
    results  = BIOC_ISOCORRECTORGUI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISOCORRECTORGUI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISOCORRECTORGUI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISOCORRECTORGUI.out.versions  // channel: path(versions.yml)
}
