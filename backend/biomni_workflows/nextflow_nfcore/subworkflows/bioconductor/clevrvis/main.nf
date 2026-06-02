#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: clevRvis
// clevRvis provides a set of visualization techniques for clonal evolution. These include shark plots,
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/clevRvis/inst/doc/clevRvis.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("clevRvis")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLEVRVIS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-clevrvis"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-clevrvis:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-clevrvis:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_clevrvis_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_clevrvis_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_clevrvis_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(clevRvis)
    library(jsonlite)

    # --- Shark Plot Visualization [] ---
    # Key functions: sharkPlot, extSharkPlot
    sharkPlot(seaObject_tp, showLegend = TRUE,
              main = "Example Shark plot")
    extSharkPlot(seaObject_tp, timepoints = timepoints,
                 showLegend = TRUE,
                 main = "Example Extended Shark plot")


    # --- Dolphin Plot Visualization [] ---
    # Key functions: dolphinPlot
    annotsTable <- data.frame(
        x = c(50, 75), y = c(15, 50),
        col = c("black", "white"),
        lab = c("Annotation clone 5", "Annotation clone 2")
    )
    dolphinPlot(seaObject_tp, showLegend = TRUE,
                main = "Example Dolphin Plot",
                vlines = timepoints, vlab = timepoints,
                vlabSize = 2, ylab = "Cancer cell fraction",
                annotations = annotsTable, pos = "bottom",
                separateIndependentClones = TRUE)


    # --- Combined and Plaice Plot Visualization [] ---
    # Key functions: combinedPlot, plaicePlot
    combinedPlot(seaObject_tp, showLegend = TRUE, vlines = timepoints,
                 vlab = timepoints, vlabSize = 2,
                 ylab = "Cancer cell fraction",
                 separateIndependentClones = TRUE)
    plaicePlot(seaObject_tp, showLegend = TRUE, vlines = timepoints,
               vlab = timepoints, vlabSize = 4, ylab = TRUE,
               separateIndependentClones = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_clevrvis_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_clevrvis_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_clevrvis_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLEVRVIS:", paste0("    clevrvis: ", packageVersion("clevRvis"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clevrvis_results.csv
    touch ${prefix}_clevrvis_output.rds
    echo "BIOC_CLEVRVIS:" > versions.yml
    echo "    clevrvis: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLEVRVIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLEVRVIS(ch_input)

    emit:
    results  = BIOC_CLEVRVIS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLEVRVIS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLEVRVIS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLEVRVIS.out.versions  // channel: path(versions.yml)
}
