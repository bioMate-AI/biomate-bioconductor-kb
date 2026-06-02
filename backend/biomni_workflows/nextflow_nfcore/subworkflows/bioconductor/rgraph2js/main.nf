#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RGraph2js
// Generator of web pages which display interactive network/graph visualizations with D3js, jQuery and 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RGraph2js/inst/doc/RGraph2js.R
// Upstream  : graph, sna, xtable
// Downstream: none
//
// Install: BiocManager::install("RGraph2js")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RGRAPH2JS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rgraph2js"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rgraph2js:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rgraph2js:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rgraph2js_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rgraph2js_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rgraph2js_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RGraph2js)
    library(jsonlite)

    # --- Layout Configuration [] ---
    # Key functions: graph2js
    v <- c(0, 0, 1, 1, 0, 0, 0, 0, 0, 0, -1, 0, 0, 1, 0)
    a35 <- matrix(v, 3, 5)
    colnames(a35) <- LETTERS[1:5]
    rownames(a35) <- LETTERS[1:3]
    r <- 100
    sector <- 2 * pi / 5
    n_prop <- data.frame(
        x=c(r*cos(1*sector), r*cos(2*sector), r*cos(3*sector),
            r*cos(4*sector), r*cos(5*sector)),
        y=c(r*sin(1*sector), r*sin(2*sector), r*sin(3*sector),
            r*sin(4*sector), r*sin(5*sector)),
        fixed=c(TRUE, TRUE, TRUE, TRUE, TRUE)
    )
    rownames(n_prop) <- c("A", "B", "C", "D", "E")
    out_dir <- file.path(tempdir(), "RGraph2js_fixedNodes")
    g <- graph2js(a35, nodesProp=n_prop, outputDir=out_dir)


    # --- Visual Customization [] ---
    # Key functions: graph2js, getDefaultOptions
    v <- c(0, 0, 1, 1, 0, 0, 0, 0, 0, 0, -1, 0, 0, 1, 0)
    a35 <- matrix(v, 3, 5)
    colnames(a35) <- LETTERS[1:5]
    rownames(a35) <- LETTERS[1:3]
    numnodes <- 5
    inner_values <- matrix(runif(numnodes * 8), numnodes, 8)
    rownames(inner_values) <- LETTERS[1:5]
    inner_colors <- matrix(rainbow(numnodes * 8), numnodes, 8)
    rownames(inner_colors) <- LETTERS[1:5]
    opts <- getDefaultOptions()
    opts$displayBarPlotsInsideNodes <- FALSE
    opts$barplotInNodeTooltips <- TRUE
    out_dir <- file.path(tempdir(), "RGraph2js_barplots")
    g <- graph2js(
        a35,
        opts=opts,
        innerValues=inner_values,
        innerColors=inner_colors,
        outputDir=out_dir
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rgraph2js_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rgraph2js_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rgraph2js_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RGRAPH2JS:", paste0("    rgraph2js: ", packageVersion("RGraph2js"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rgraph2js_results.csv
    touch ${prefix}_rgraph2js_output.rds
    echo "BIOC_RGRAPH2JS:" > versions.yml
    echo "    rgraph2js: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RGRAPH2JS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RGRAPH2JS(ch_input)

    emit:
    results  = BIOC_RGRAPH2JS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RGRAPH2JS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RGRAPH2JS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RGRAPH2JS.out.versions  // channel: path(versions.yml)
}
