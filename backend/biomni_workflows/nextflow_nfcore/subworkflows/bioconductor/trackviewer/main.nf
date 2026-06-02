#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: trackViewer
// Visualize mapped reads along with annotation as track layers for NGS dataset such as ChIP-seq, RNA-s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/trackViewer/inst/doc/changeTracksStyles.R
// Upstream  : VariantAnnotation, httr, motifStack, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("trackViewer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRACKVIEWER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-trackviewer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-trackviewer:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-trackviewer:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_trackviewer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_trackviewer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_trackviewer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(trackViewer)
    library(jsonlite)


    # --- Browse Track [] ---
    # Key functions: browseTracks, setTrackViewerStyleParam, setTrackXscaleParam, viewTracks, xaxis, margin, draw, position
    browseTracks(trackList, gr=gr)
    setTrackViewerStyleParam(viewerStyle, "xaxis", FALSE)
    setTrackViewerStyleParam(viewerStyle, "margin", c(.01, .05, .01, .01))
    setTrackXscaleParam(trackList[[1]], "draw", TRUE)
    setTrackXscaleParam(trackList[[1]], "gp", list(cex=0.8))
    viewTracks(trackList, gr=gr, viewerStyle=viewerStyle)
    setTrackXscaleParam(trackList[[1]], attr="position", 
                        value=list(x=122929700, y=3, label=200))
    viewTracks(trackList, gr=gr, viewerStyle=viewerStyle)

    # --- View Tracks Yaxis [] ---
    # Key functions: setTrackViewerStyleParam, for, setTrackYaxisParam, setTrackStyleParam, viewTracks, margin, main, ylim
    setTrackViewerStyleParam(viewerStyle, "margin", c(.01, .05, .01, .05))
    for(i in 1:2){
        setTrackYaxisParam(trackList[[i]], "main", FALSE)
    }
    ## Adjust the limit of y-axis
    setTrackStyleParam(trackList[[1]], "ylim", c(0, 25))
    setTrackStyleParam(trackList[[2]], "ylim", c(-25, 0))
    ## The y-axis tick labels can be turn off/on by setting the 'label' to FALSE/TRUE
    #setTrackYaxisParam(trackList[[1]], 'label', TRUE)
    viewTracks(trackList, gr=gr, viewerStyle=viewerStyle)
    ## change the 
    setTrackYaxisParam(trackList[[1]], "gp", list(cex=.8, col="green"))
    setTrackYaxisParam(trackList[[2]], "gp", list(cex=.8, col="blue"))
    viewTracks(trackList, gr=gr, viewerStyle=viewerStyle)

    # --- View Tracks Ylab [] ---
    # Key functions: setTrackStyleParam, viewTracks, ylabgp, green, blue, marginBottom, ylabpos, bottomleft
    setTrackStyleParam(trackList[[1]], "ylabgp", list(cex=.8, col="green"))
    ## set cex to avoid automatic adjust
    setTrackStyleParam(trackList[[2]], "ylabgp", list(cex=.8, col="blue"))
    setTrackStyleParam(trackList[[2]], "marginBottom", .2)
    viewTracks(trackList, gr=gr, viewerStyle=viewerStyle)
    setTrackStyleParam(trackList[[1]], "ylabpos", "bottomleft")
    setTrackStyleParam(trackList[[2]], "ylabpos", "topright")
    setTrackStyleParam(trackList[[2]], "marginTop", .2)
    viewTracks(trackList, gr=gr, viewerStyle=viewerStyle)

    # --- View Tracks Ylab Ups Down [] ---
    # Key functions: setTrackStyleParam, unname, unlist, GRangesList, function, start, end, viewTracks
    trackListN <- trackList
    setTrackStyleParam(trackListN[[3]], "ylabpos", "upstream")
    setTrackStyleParam(trackListN[[4]], "ylabpos", "downstream")
    ## set cex to avoid automatic adjust
    setTrackStyleParam(trackListN[[3]], "ylabgp", list(cex=.6))
    setTrackStyleParam(trackListN[[4]], "ylabgp", list(cex=.6))
    gr1 <- range(unname(unlist(GRangesList(sapply(trs, function(.ele) .ele$dat)))))
    start(gr1) <- start(gr1) - 2000
    end(gr1) <- end(gr1) + 2000
    viewTracks(trackListN, gr=gr1, viewerStyle=viewerStyle)
    setTrackStyleParam(trackList[[1]], "color", c("green", "black"))
    setTrackStyleParam(trackList[[2]], "color", c("black", "blue"))
    for(i in 3:length(trackList)) 
        setTrackStyleParam(trackList[[i]], "color", "black")
    viewTracks(trackList, gr=gr, viewerStyle=viewerStyle)

    # --- View Tracks Height [] ---
    # Key functions: setTrackStyleParam, for, viewTracks, height, rep, cpsf160, fox2
    trackListH <- trackList
    setTrackStyleParam(trackListH[[1]], "height", .1)
    setTrackStyleParam(trackListH[[2]], "height", .44)
    for(i in 3:length(trackListH)){
        setTrackStyleParam(trackListH[[i]], "height", 
                           (1-(0.1+0.44))/(length(trackListH)-2))
    }
    viewTracks(trackListH, gr=gr, viewerStyle=viewerStyle)
    names(trackList) <- c("cpsf160", "fox2", rep("HSPA8", 5))
    viewTracks(trackList, gr=gr, viewerStyle=viewerStyle)

    # --- View Tracks Paired [] ---
    # Key functions: importScore, strand, setTrackStyleParam, viewTracks, trackList, color, black, red
    cpsf160 <- importScore(file.path(extdata, "cpsf160.repA_-.wig"),
                           file.path(extdata, "cpsf160.repB_-.wig"),
                           format="WIG")
    strand(cpsf160$dat) <- strand(cpsf160$dat2) <- "-"
    setTrackStyleParam(cpsf160, "color", c("black", "red"))
    viewTracks(trackList(trs, cpsf160), gr=gr, viewerStyle=viewerStyle)
    viewerStyleF <- viewerStyle
    setTrackViewerStyleParam(viewerStyleF, "flip", TRUE)
    setTrackViewerStyleParam(viewerStyleF, "xaxis", TRUE)
    setTrackViewerStyleParam(viewerStyleF, "margin", c(.1, .05, .01, .01))
    vp <- viewTracks(trackList, gr=gr, viewerStyle=viewerStyleF)
    addGuideLine(c(122929767, 122929969), vp=vp)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_trackviewer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_trackviewer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_trackviewer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TRACKVIEWER:", paste0("    trackviewer: ", packageVersion("trackViewer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_trackviewer_results.csv
    touch ${prefix}_trackviewer_output.rds
    echo "BIOC_TRACKVIEWER:" > versions.yml
    echo "    trackviewer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TRACKVIEWER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TRACKVIEWER(ch_input)

    emit:
    results  = BIOC_TRACKVIEWER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TRACKVIEWER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TRACKVIEWER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TRACKVIEWER.out.versions  // channel: path(versions.yml)
}
