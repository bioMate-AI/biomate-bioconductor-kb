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

    # --- Gene Model Construction [] ---
    # Key functions: geneModelFromTxdb
    gr <- GRanges("chr11", IRanges(122929275, 122930122), strand = "-")
    trs <- geneModelFromTxdb(
        TxDb.Hsapiens.UCSC.hg19.knownGene,
        org.Hs.eg.db,
        gr = gr
    )


    # --- Style Optimization [] ---
    # Key functions: optimizeStyle, trackList
    optSty <- optimizeStyle(trackList(repA, trs), theme = "col")
    track_list <- optSty$tracks
    viewer_style <- optSty$style


    # --- Track Visualization [] ---
    # Key functions: viewTracks, setTrackViewerStyleParam, setTrackStyleParam
    setTrackViewerStyleParam(viewer_style, "xaxis", TRUE)
    setTrackStyleParam(track_list[[1]], "color", c("green", "black"))
    viewTracks(track_list, gr = gr, viewerStyle = viewer_style)

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
