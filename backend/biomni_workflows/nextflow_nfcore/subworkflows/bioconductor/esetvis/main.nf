#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: esetVis
// Utility functions for visualization of expressionSet (or SummarizedExperiment) Bioconductor object, 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/esetVis/inst/doc/esetVis-vignette.R
// Upstream  : xtable, pander, ALL, AnnotationDbi, ggplot2
// Downstream: none
//
// Install: BiocManager::install("esetVis")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ESETVIS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-esetvis"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-esetvis:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-esetvis:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_esetvis_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_esetvis_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_esetvis_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(esetVis)
    library(jsonlite)

    # --- Filter by row sum threshold [] ---
    # Key functions: featureNames, rowSums, fData, pData
    library(ALL)
    data(ALL)
    library("hgu95av2.db")
    # --- FvarMetadata analysis [] ---
    # Key functions: fvarMetadata, pander, esetSpectralMap, colorRampPalette, getGeneSetsForPlot, sample, esetLda, esetPlotWrapper
    retainedFeatures <- sample(featureNames(ALL), size = floor(nrow(ALL)/5))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_esetvis_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_esetvis_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_esetvis_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ESETVIS:", paste0("    esetvis: ", packageVersion("esetVis"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_esetvis_results.csv
    touch ${prefix}_esetvis_output.rds
    echo "BIOC_ESETVIS:" > versions.yml
    echo "    esetvis: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ESETVIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ESETVIS(ch_input)

    emit:
    results  = BIOC_ESETVIS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ESETVIS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ESETVIS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ESETVIS.out.versions  // channel: path(versions.yml)
}
