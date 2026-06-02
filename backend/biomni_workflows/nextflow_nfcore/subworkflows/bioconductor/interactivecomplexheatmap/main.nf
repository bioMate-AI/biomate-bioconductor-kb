#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: InteractiveComplexHeatmap
// This package can easily make heatmaps which are produced by the ComplexHeatmap package into interact
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/InteractiveComplexHeatmap/inst/doc/InteractiveComplexHeatmap.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("InteractiveComplexHeatmap")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_INTERACTIVECOMPLEXHEATMAP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-interactivecomplexheatmap"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-interactivecomplexheatmap:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-interactivecomplexheatmap:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_interactivecomplexheatmap_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_interactivecomplexheatmap_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_interactivecomplexheatmap_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(InteractiveComplexHeatmap)
    library(jsonlite)


    # --- Eval = False [] ---
    # Key functions: pheatmap, htShiny, oncoPrint, htShinyExample
    #  ComplexHeatmap::pheatmap(...)
    #  htShiny()
    #  
    #  oncoPrint(...)
    #  htShiny()

    ## -----------------------------------------------------------------------------
    htShinyExample()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_interactivecomplexheatmap_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_interactivecomplexheatmap_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_interactivecomplexheatmap_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_INTERACTIVECOMPLEXHEATMAP:", paste0("    interactivecomplexheatmap: ", packageVersion("InteractiveComplexHeatmap"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interactivecomplexheatmap_results.csv
    touch ${prefix}_interactivecomplexheatmap_output.rds
    echo "BIOC_INTERACTIVECOMPLEXHEATMAP:" > versions.yml
    echo "    interactivecomplexheatmap: 0.0.0" >> versions.yml
    """
}


workflow BIOC_INTERACTIVECOMPLEXHEATMAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_INTERACTIVECOMPLEXHEATMAP(ch_input)

    emit:
    results  = BIOC_INTERACTIVECOMPLEXHEATMAP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_INTERACTIVECOMPLEXHEATMAP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_INTERACTIVECOMPLEXHEATMAP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_INTERACTIVECOMPLEXHEATMAP.out.versions  // channel: path(versions.yml)
}
