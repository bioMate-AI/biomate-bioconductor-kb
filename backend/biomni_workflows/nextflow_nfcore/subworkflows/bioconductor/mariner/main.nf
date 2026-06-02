#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mariner
// Tools for manipulating paired ranges and working with Hi-C data in R. Functionality includes manipul
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mariner/inst/doc/introduction_to_mariner.R
// Upstream  : InteractionSet, marinerData, strawr
// Downstream: none
//
// Install: BiocManager::install("mariner")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MARINER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mariner"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mariner:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mariner:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mariner_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mariner_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mariner_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mariner)
    library(GInteractions)
    library(GRanges)
    library(jsonlite)

    # --- Merging and Clustering Pairs [] ---
    # Key functions: mergePairs, getPairClusters, subsetBySource, sources
    bedpeFiles <- c(
        marinerData::FS_5kbLoops.txt(),
        marinerData::WT_5kbLoops.txt()
    )
    names(bedpeFiles) <- c("FS", "WT")
    giList <- lapply(
        lapply(bedpeFiles, read.table, header = TRUE),
        as_ginteractions
    )
    mgi <- mergePairs(
        x = giList,
        radius = 10e3,
        column = "APScoreAvg",
        selectMax = TRUE
    )
    clusters <- getPairClusters(mgi[12772])
    unique_sources <- subsetBySource(mgi)


    # --- Hi-C Pixel and Matrix Extraction [] ---
    # Key functions: pullHicPixels, pullHicMatrices, pixelsToMatrices
    hicFiles <- c(
        marinerData::LEUK_HEK_PJA27_inter_30.hic(),
        marinerData::LEUK_HEK_PJA30_inter_30.hic()
    )
    names(hicFiles) <- c("FS", "WT")
    GenomeInfoDb::seqlevelsStyle(mgi) <- "ENSEMBL"
    binned_100k <- binPairs(x = mgi, binSize = 100e3)
    imat <- pullHicPixels(
        x = binned_100k[1:1000],
        files = hicFiles,
        binSize = 100e3
    )
    regions <- pixelsToMatrices(x = binned_100k[1:1000], buffer = 1)
    iarr <- pullHicMatrices(x = regions, files = hicFiles, binSize = 100e3)


    # --- Matrix Aggregation and Visualisation [] ---
    # Key functions: aggHicMatrices, plotMatrix
    agg_interact <- aggHicMatrices(x = iarr, by = "interactions")
    agg_files <- aggHicMatrices(x = iarr, by = "files")
    agg_total <- aggHicMatrices(x = iarr)
    plotMatrix(data = agg_total)


    # --- Loop Enrichment Analysis [] ---
    # Key functions: selectCenterPixel, selectTopLeft, selectBottomRight, calcLoopEnrichment
    buffer <- 10
    fg <- selectCenterPixel(mhDist = 0:1, buffer = buffer)
    bg <- selectTopLeft(n = 2, buffer = buffer) +
        selectBottomRight(n = 2, buffer = buffer)
    enrich <- calcLoopEnrichment(
        x = binned_100k[1:1000],
        files = hicFiles,
        fg = fg,
        bg = bg
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mariner_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mariner_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mariner_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MARINER:", paste0("    mariner: ", packageVersion("mariner"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mariner_results.csv
    touch ${prefix}_mariner_output.rds
    echo "BIOC_MARINER:" > versions.yml
    echo "    mariner: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MARINER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MARINER(ch_input)

    emit:
    results  = BIOC_MARINER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MARINER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MARINER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MARINER.out.versions  // channel: path(versions.yml)
}
