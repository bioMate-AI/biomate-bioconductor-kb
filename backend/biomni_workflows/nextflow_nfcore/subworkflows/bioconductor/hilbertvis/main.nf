#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HilbertVis
// Functions to visualize long vectors of integer data by means of Hilbert curves
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HilbertVis/inst/doc/HilbertVis.R
// Upstream  : grid
// Downstream: HilbertVisGUI
//
// Install: BiocManager::install("HilbertVis")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HILBERTVIS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hilbertvis"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hilbertvis:1.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hilbertvis:1.64.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hilbertvis_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hilbertvis_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hilbertvis_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HilbertVis)
    library(jsonlite)

    # --- Makerandomtestdata [] ---
    # Key functions: makeRandomTestData
    library( HilbertVis )
    vec <- makeRandomTestData( )
    # --- Plotlongvector [] ---
    # Key functions: plotLongVector
    plotLongVector( vec )
    # --- Zoomin [] ---
    # Key functions: plotLongVector
    start <- 1500000
    plotLongVector( vec[ start + 0:100000 ], offset=start )
    # --- Hilbertcurves [] ---
    # Key functions: pushViewport, viewport, plotHilbertCurve, popViewport
    library( grid )
    pushViewport( viewport( layout=grid.layout( 2, 2 ) ) )
    for( i in 1:4 ) {
       pushViewport( viewport(
           layout.pos.row=1+(i-1)%/%2, layout.pos.col=1+(i-1)%%2 ) )
    # --- Hilbertimage [] ---
    # Key functions: hilbertImage
    hMat <- hilbertImage( vec )
    # --- Showhilbertimage [] ---
    # Key functions: showHilbertImage
    ## showHilbertImage( hMat )
    # --- Hilberttest [] ---
    # Key functions: show, showHilbertImage
    show( showHilbertImage( hMat ) )
    # --- Showhilbertimage [] ---
    # Key functions: showHilbertImage
    ## showHilbertImage( hMat, mode="EBImage" )
    # --- Hilbertdisplay [] ---
    # Key functions: hilbertDisplay
    ## hilbertDisplay( vec )
    # --- Function [] ---
    # Key functions: hilbertDisplay
    ## dumpDataInsteadOfPlotting <- function( data, info ) {
    ##    str( data )
    ##    print( info )
    ## }
    ## hilbertDisplay( vec, plotFunc=dumpDataInsteadOfPlotting )
    # --- Hilbertdisplay [] ---
    # Key functions: hilbertDisplay
    ## hilbertDisplay( vec, vec2 )
    # --- Hilbertdisplaythreechannel [] ---
    # Key functions: hilbertDisplayThreeChannel
    ## hilbertDisplayThreeChannel(
    ##    vec / max(vec), vec2 / max(vec), rep( 0, length(vec) ) )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hilbertvis_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hilbertvis_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hilbertvis_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HILBERTVIS:", paste0("    hilbertvis: ", packageVersion("HilbertVis"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hilbertvis_results.csv
    touch ${prefix}_hilbertvis_output.rds
    echo "BIOC_HILBERTVIS:" > versions.yml
    echo "    hilbertvis: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HILBERTVIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HILBERTVIS(ch_input)

    emit:
    results  = BIOC_HILBERTVIS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HILBERTVIS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HILBERTVIS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HILBERTVIS.out.versions  // channel: path(versions.yml)
}
