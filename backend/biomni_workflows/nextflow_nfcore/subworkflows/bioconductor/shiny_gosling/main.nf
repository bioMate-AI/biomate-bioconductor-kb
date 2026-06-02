#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: shiny.gosling
// A Grammar-based Toolkit for Scalable and Interactive Genomics Data Visualization. http://gosling-lan
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/shiny.gosling/inst/doc/GRanges.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("shiny.gosling")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SHINY_GOSLING {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-shiny_gosling"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-shiny.gosling:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-shiny.gosling:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_shiny_gosling_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_shiny_gosling_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_shiny_gosling_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(shiny.gosling)
    library(GRanges)
    library(jsonlite)

    # --- View Composition and Arrangement [] ---
    # Key functions: compose_view, arrange_views
    composed_view <- compose_view(
        layout = "linear",
        tracks = track_1
    )
    arranged_view <- arrange_views(
        title = "Basic Marks: bar",
        subtitle = "Tutorial Examples",
        views = composed_view
    )


    # --- Shiny Application Integration [] ---
    # Key functions: use_gosling, goslingOutput, renderGosling, gosling
    ui <- shiny::fluidPage(
        use_gosling(clear_files = FALSE),
        goslingOutput("gosling_plot")
    )
    server <- function(input, output, session) {
        output$gosling_plot <- renderGosling({
            gosling(
                component_id = "component_1",
                arranged_view
            )
        })
    }

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_shiny_gosling_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_shiny_gosling_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_shiny_gosling_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SHINY_GOSLING:", paste0("    shiny_gosling: ", packageVersion("shiny.gosling"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_shiny_gosling_results.csv
    touch ${prefix}_shiny_gosling_output.rds
    echo "BIOC_SHINY_GOSLING:" > versions.yml
    echo "    shiny_gosling: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SHINY_GOSLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SHINY_GOSLING(ch_input)

    emit:
    results  = BIOC_SHINY_GOSLING.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SHINY_GOSLING.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SHINY_GOSLING.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SHINY_GOSLING.out.versions  // channel: path(versions.yml)
}
