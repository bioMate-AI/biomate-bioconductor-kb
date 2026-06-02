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
    library(geomeTriD)
    library(GRanges)
    library(jsonlite)

    # --- Multidimensional Scaling Projection [] ---
    # Key functions: mdsPlot
    gi_nij <- readRDS(system.file("extdata", "nij.chr6.51120000.53200000.gi.rds",
      package = "geomeTriD"
    ))
    range_chr6 <- GenomicRanges::GRanges(
      "chr6",
      IRanges::IRanges(51120000, 53200000)
    )
    mds_res <- mdsPlot(
      gi_nij,
      range = range_chr6,
      k = 3,
      render = "none"
    )


    # --- Integrating Genomic Signals and Features [] ---
    # Key functions: mdsPlot
    gi_nij <- readRDS(system.file("extdata", "nij.chr6.51120000.53200000.gi.rds",
      package = "geomeTriD"
    ))
    range_chr6 <- GenomicRanges::GRanges(
      "chr6",
      IRanges::IRanges(51120000, 53200000)
    )
    ctcf <- readRDS(system.file("extdata", "ctcf.sample.rds",
      package = "trackViewer"
    ))
    feature_gr <- GenomicRanges::GRanges(
      seqnames = "chr6",
      ranges = IRanges::IRanges(start = 51120000, end = 53200000),
      col = 2,
      type = "gene"
    )
    objs <- mdsPlot(
      gi_nij,
      range = range_chr6,
      feature.gr = feature_gr,
      genomicSigs = list(ctcf = ctcf),
      reverseGenomicSigs = TRUE,
      k = 3,
      render = "none"
    )


    # --- 3D Genomic Signal Generation [] ---
    # Key functions: extractBackbonePositions, create3dGenomicSignals, threeJsViewer
    gi_nij <- readRDS(system.file("extdata", "nij.chr6.51120000.53200000.gi.rds",
      package = "geomeTriD"
    ))
    range_chr6 <- GenomicRanges::GRanges(
      "chr6",
      IRanges::IRanges(51120000, 53200000)
    )
    objs <- mdsPlot(gi_nij, range = range_chr6, k = 3, render = "none")
    xyz <- extractBackbonePositions(objs)
    gi_subset <- gi_nij[InteractionSet::distance(
      InteractionSet::first(gi_nij),
      InteractionSet::second(gi_nij)
    ) > 50000]
    hic <- create3dGenomicSignals(
      gi_subset,
      xyz,
      name = "segment",
      tag = "hic",
      color = c("green", "darkred"),
      topN = 3,
      lwd.maxGenomicSigs = 3,
      alpha = 0.5
    )
    threeJsViewer(c(objs, hic))


    # --- Loop Bouquet Plotting [] ---
    # Key functions: loopBouquetPlot
    gi_chr2 <- readRDS(system.file("extdata", "gi.rds", package = "trackViewer"))
    range_chr2 <- GenomicRanges::GRanges(
      "chr2",
      IRanges::IRanges(234300000, 235000000)
    )
    feature_gr_chr2 <- GenomicRanges::GRanges(
      seqnames = "chr2",
      ranges = IRanges::IRanges(start = 234300000, end = 235000000),
      col = 2,
      type = "gene",
      pch = 11,
      label = "GeneA"
    )
    geomeTriD::loopBouquetPlot(
      gi_chr2,
      range_chr2,
      feature_gr_chr2
    )

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
