#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: OLINgui
// Graphical user interface for the OLIN package
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/OLINgui/inst/doc/OLINgui.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("OLINgui")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OLINGUI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-olingui"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-olingui:1.80.0--r44_0' :
        'quay.io/biocontainers/bioconductor-olingui:1.80.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_olingui_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_olingui_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_olingui_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(OLINgui)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data(sw)
      data(sw.xy)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_olingui_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_olingui_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_olingui_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OLINGUI:", paste0("    olingui: ", packageVersion("OLINgui"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_olingui_results.csv
    touch ${prefix}_olingui_output.rds
    echo "BIOC_OLINGUI:" > versions.yml
    echo "    olingui: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OLINGUI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OLINGUI(ch_input)

    emit:
    results  = BIOC_OLINGUI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OLINGUI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OLINGUI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OLINGUI.out.versions  // channel: path(versions.yml)
}
