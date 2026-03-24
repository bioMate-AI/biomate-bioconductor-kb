#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CytoPipeline
// This package provides support for automation and visualization of flow cytometry data analysis pipel
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CytoPipeline/inst/doc/CytoPipeline.R
// Upstream  : ggplot2, reshape2
// Downstream: CytoPipelineGUI
//
// Install: BiocManager::install("CytoPipeline")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYTOPIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cytopipeline"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cytopipeline:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cytopipeline:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cytopipeline_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cytopipeline_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cytopipeline_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CytoPipeline)
    library(CytoProcessingStep)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: reshape, ggplot, geom_point, ggtitle
    myGGPlot <- function(DF, title){
    stepNames = colnames(DF)
    rowNames = rownames(DF)
    # --- CytoPipeline analysis [] ---
    # Key functions: include_graphics, CytoPipeline, addProcessingStep, CytoProcessingStep, execute, getCytoPipelineObjectInfos, getCytoPipelineFlowFrame, ggplotEvents
    sampleFiles <- file.path(rawDataDir, list.files(rawDataDir,
    pipL_PeacoQC <- CytoPipeline(experimentName = experimentName,
    addProcessingStep(pipL_PeacoQC,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cytopipeline_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cytopipeline_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cytopipeline_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CYTOPIPELINE:", paste0("    cytopipeline: ", packageVersion("CytoPipeline"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cytopipeline_results.csv
    touch ${prefix}_cytopipeline_output.rds
    echo "BIOC_CYTOPIPELINE:" > versions.yml
    echo "    cytopipeline: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CYTOPIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CYTOPIPELINE(ch_input)

    emit:
    results  = BIOC_CYTOPIPELINE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CYTOPIPELINE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CYTOPIPELINE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CYTOPIPELINE.out.versions  // channel: path(versions.yml)
}
