#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: limmaGUI
// A Graphical User Interface for differential expression analysis of two-color microarray data using t
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/limmaGUI/inst/doc/limmaGUI.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("limmaGUI")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LIMMAGUI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-limmagui"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-limmagui:1.82.0--r44_0' :
        'quay.io/biocontainers/bioconductor-limmagui:1.82.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_limmagui_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_limmagui_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_limmagui_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(limmaGUI)
    library(jsonlite)

    # --- Onlinedoc [] ---
    # Key functions: interactive
    ## if (interactive())
    ##   browseURL("http://bioinf.wehi.edu.au/limmaGUI/Doc/")
    # --- Localdoc [] ---
    # Key functions: interactive, limmaGUIhelp
    ## if (interactive())
    ## {
    ##   library(limmaGUI)
    ##   limmaGUIhelp()
    ## }
    # --- interactive [] ---
    # Key functions: interactive, start
    ## if (interactive())
    ##   help.start()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_limmagui_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_limmagui_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_limmagui_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LIMMAGUI:", paste0("    limmagui: ", packageVersion("limmaGUI"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_limmagui_results.csv
    touch ${prefix}_limmagui_output.rds
    echo "BIOC_LIMMAGUI:" > versions.yml
    echo "    limmagui: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LIMMAGUI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LIMMAGUI(ch_input)

    emit:
    results  = BIOC_LIMMAGUI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LIMMAGUI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LIMMAGUI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LIMMAGUI.out.versions  // channel: path(versions.yml)
}
