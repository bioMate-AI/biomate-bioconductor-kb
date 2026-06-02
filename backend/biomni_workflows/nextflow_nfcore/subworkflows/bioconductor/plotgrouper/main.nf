#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: plotGrouper
// A shiny app-based GUI wrapper for ggplot with built-in statistical analysis. Import data from file a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/plotGrouper/inst/doc/plotGrouper-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("plotGrouper")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PLOTGROUPER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-plotgrouper"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-plotgrouper:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-plotgrouper:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_plotgrouper_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_plotgrouper_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_plotgrouper_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(plotGrouper)
    library(jsonlite)


    # --- Logo [] ---
    # Key functions: img, image_uri, logo_small.png
    htmltools::img(src = knitr::image_uri("logo_small.png"), 
                   alt = 'logo', 
                   style = 'position:absolute; 
                   top:0; 
                   right:0; 
                   padding:10px; 
                   width:150px')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_plotgrouper_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_plotgrouper_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_plotgrouper_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PLOTGROUPER:", paste0("    plotgrouper: ", packageVersion("plotGrouper"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_plotgrouper_results.csv
    touch ${prefix}_plotgrouper_output.rds
    echo "BIOC_PLOTGROUPER:" > versions.yml
    echo "    plotgrouper: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PLOTGROUPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PLOTGROUPER(ch_input)

    emit:
    results  = BIOC_PLOTGROUPER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PLOTGROUPER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PLOTGROUPER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PLOTGROUPER.out.versions  // channel: path(versions.yml)
}
