#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Director
// Director is an R package designed to streamline the visualization of molecular effects in regulatory
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Director/inst/doc/vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Director")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DIRECTOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-director"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-director:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-director:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_director_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_director_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_director_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Director)
    library(jsonlite)

    # --- Data Preparation and List Creation [Step 1] ---
    # Key functions: createList
    table1 <- data.frame(
        source = c("DrugX", "DrugX", "miR-B", "miR-B", "miR-B",
                   "miR-A", "miR-A", "transc1", "transc2", "transc3", "transc4"),
        target = c("miR-B", "miR-A", "transc1", "transc2", "transc3", "transc2",
                   "transc4", "gene1", "gene2", "gene2", "gene3"),
        value = c(0.6, 0.8, -0.7, -0.4, -0.34, -0.8, -0.6, 0.8, 0.9, 0.88, 0.6),
        sourcefc = c(1, 1, 1.5, 1.5, 1.5, 2.6, 2.6, -1.7, -2.6, -1.5, -1.2),
        targetfc = c(1.5, 2.6, -1.7, -2.6, -1.5, -2.6, -1.2, -0.6, -2.2, -2.2, -0.7),
        stringsAsFactors = FALSE
    )
    tempList <- createList(table1)

    # --- Sankey Diagram Generation [Step 2] ---
    # Key functions: initSankey, makeSankey
    initSankey()
    sankey <- makeSankey(tempList)
    sankey_ref <- sankey$reference[, 1:6]

    # --- Rendering and Visualization [Step 3] ---
    # Key functions: drawSankey
    sankey_drawn <- drawSankey(
        sankey,
        caption = "Default Sankey Diagram",
        height = 400
    )

    # --- Path Averaging and Loop Handling [Step 4] ---
    # Key functions: makeSankey, drawSankey
    sankey_avg <- makeSankey(tempList, averagePath = TRUE)
    sankey_avg_drawn <- drawSankey(sankey_avg)
    avg_values <- sankey_avg$reference[, c("source", "target")]

    # --- Customizing Visual Parameters [Step 5] ---
    # Key functions: initSankey, makeSankey, drawSankey
    initSankey(
        pathOpacity = 0.3,
        pathHover = 0.6,
        fontsizeProportion = FALSE,
        fontsize = 20
    )
    sankey_custom <- makeSankey(
        tempList,
        averagePath = TRUE,
        nodeMin = "orange",
        nodeMax = "purple",
        pathMax = "#333333"
    )
    sankey_custom_drawn <- drawSankey(
        sankey_custom,
        caption = "Customized Figure",
        nodeValue = "Node colour scale",
        pathValue = "Path colour scale",
        legendsize = 14,
        height = 300
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_director_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_director_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_director_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DIRECTOR:", paste0("    director: ", packageVersion("Director"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_director_results.csv
    touch ${prefix}_director_output.rds
    echo "BIOC_DIRECTOR:" > versions.yml
    echo "    director: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DIRECTOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DIRECTOR(ch_input)

    emit:
    results  = BIOC_DIRECTOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DIRECTOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DIRECTOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DIRECTOR.out.versions  // channel: path(versions.yml)
}
