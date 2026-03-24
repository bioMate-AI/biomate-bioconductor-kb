#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: affylmGUI
// A Graphical User Interface (GUI) for analysis of Affymetrix microarray gene expression data using th
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/affylmGUI/inst/doc/affylmGUI.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("affylmGUI")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AFFYLMGUI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-affylmgui"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-affylmgui:1.80.0--r44_0' :
        'quay.io/biocontainers/bioconductor-affylmgui:1.80.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_affylmgui_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_affylmgui_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_affylmgui_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(affylmGUI)
    library(jsonlite)

    # --- Onlinedoc [] ---
    # Key functions: interactive
    ## if (interactive())
    ##   browseURL("http://bioinf.wehi.edu.au/affylmGUI/Doc/")
    # --- Localdoc [] ---
    # Key functions: interactive, affylmGUIhelp
    ## if (interactive())
    ## {
    ##   library(affylmGUI)
    ##   affylmGUIhelp()
    ## }
    # --- interactive [] ---
    # Key functions: interactive, start
    ## if (interactive())
    ##   help.start()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_affylmgui_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_affylmgui_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_affylmgui_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AFFYLMGUI:", paste0("    affylmgui: ", packageVersion("affylmGUI"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_affylmgui_results.csv
    touch ${prefix}_affylmgui_output.rds
    echo "BIOC_AFFYLMGUI:" > versions.yml
    echo "    affylmgui: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AFFYLMGUI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AFFYLMGUI(ch_input)

    emit:
    results  = BIOC_AFFYLMGUI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AFFYLMGUI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AFFYLMGUI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AFFYLMGUI.out.versions  // channel: path(versions.yml)
}
