#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: geomeTriD
// geomeTriD (Three Dimensional Geometry Package) create interactive 3D plots using the GL library with
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/geomeTriD/inst/doc/geomeTriD.R
// Upstream  : GenomicRanges, InteractionSet, manipulateWidget, rgl, trackViewer
// Downstream: none
//
// Install: BiocManager::install("geomeTriD")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GEOMETRID {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-geometrid"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-geometrid:1.0.1--r44_0' :
        'quay.io/biocontainers/bioconductor-geometrid:1.0.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_geometrid_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_geometrid_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_geometrid_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(jsonlite)

    # --- Load saved R data object [] ---
    # Key functions: view3dStructure, threeJsViewer
    library(geomeTriD)
    # --- Load saved R data object [] ---
    # Key functions: GRanges, mdsPlot
    library(trackViewer)
    library(InteractionSet)
    # --- mget [] ---
    # Key functions: mget, unlist, mdsPlot
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    library(org.Hs.eg.db)
    feature.gr <- genes(TxDb.Hsapiens.UCSC.hg19.knownGene)
    # --- Load saved R data object [] ---
    # Key functions: mdsPlot

    # --- mds Plot [] ---
    # Key functions: mdsPlot, threeJsViewer
    set.seed(1)
    randomSig <- randomSig[sort(sample(seq_along(randomSig), 50))]
    randomSig$score <- randomSig$score * 2 * runif(50)
    # --- clear3d [] ---
    # Key functions: clear3d, rglViewer, rglwidget, toggleWidget, asRow
    library(rgl)
    library(manipulateWidget)
    rgl::clear3d() # Remove the earlier display
    # --- extract Backbone Positions [] ---
    # Key functions: extractBackbonePositions, create3dGenomicSignals, width, threeJsViewer
    xyz <- extractBackbonePositions(objs)
    gi.subset <- gi_nij[distance(first(gi_nij), second(gi_nij))>50000]
    # --- Load saved R data object [] ---
    # Key functions: GRanges, mget, unlist
    gi_chr2 <- readRDS(system.file("extdata", "gi.rds", package = "trackViewer"))
    range_chr2 <- GRanges("chr2", IRanges(234300000, 235000000))
    gene_hg19 <- suppressMessages(genes(TxDb.Hsapiens.UCSC.hg19.knownGene))
    # --- distance [] ---
    # Key functions: distance, regions, start, end
    keep <- distance(first(gi_nij), second(gi_nij)) > 5e5 & gi_nij$score > 35
    reg <- regions(gi_nij)
    wr <- floor(width(reg) / 4)
    # --- Create GenomicRanges object [] ---
    # Key functions: threeJsViewer, view3dCells, GRanges
    threeJsViewer(cellobjs)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_geometrid_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_geometrid_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_geometrid_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GEOMETRID:", paste0("    geometrid: ", packageVersion("geomeTriD"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_geometrid_results.csv
    touch ${prefix}_geometrid_output.rds
    echo "BIOC_GEOMETRID:" > versions.yml
    echo "    geometrid: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GEOMETRID_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GEOMETRID(ch_input)

    emit:
    results  = BIOC_GEOMETRID.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GEOMETRID.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GEOMETRID.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GEOMETRID.out.versions  // channel: path(versions.yml)
}
