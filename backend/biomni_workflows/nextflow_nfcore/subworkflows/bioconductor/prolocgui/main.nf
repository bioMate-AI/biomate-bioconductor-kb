#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pRolocGUI
// The package pRolocGUI comprises functions to interactively visualise spatial proteomics data on the 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pRolocGUI/inst/doc/pRolocGUI.R
// Upstream  : BiocStyle, pRolocdata
// Downstream: none
//
// Install: BiocManager::install("pRolocGUI")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROLOCGUI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-prolocgui"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-prolocgui:2.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-prolocgui:2.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_prolocgui_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_prolocgui_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_prolocgui_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MSnSetList)
    library(jsonlite)

    # --- p Roloc Vis [] ---
    # Key functions: pRolocVis
    pRolocVis(object = hyperLOPIT2015, fcol = "markers")
    # --- M Sn Set List [] ---
    # Key functions: MSnSetList, pRolocVis
    data(hyperLOPIT2015ms3r1)
    data(hyperLOPIT2015ms3r2)
    mydata <- MSnSetList(list(hyperLOPIT2015ms3r1, hyperLOPIT2015ms3r2))
    # --- p Roloc Vis [] ---
    # Key functions: pRolocVis
    data("hyperLOPIT2015ms2psm")
    # --- Combine peptide features to proteins [] ---
    # Key functions: combineFeatures, pRolocVis


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_prolocgui_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_prolocgui_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_prolocgui_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PROLOCGUI:", paste0("    prolocgui: ", packageVersion("pRolocGUI"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_prolocgui_results.csv
    touch ${prefix}_prolocgui_output.rds
    echo "BIOC_PROLOCGUI:" > versions.yml
    echo "    prolocgui: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PROLOCGUI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PROLOCGUI(ch_input)

    emit:
    results  = BIOC_PROLOCGUI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PROLOCGUI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PROLOCGUI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PROLOCGUI.out.versions  // channel: path(versions.yml)
}
