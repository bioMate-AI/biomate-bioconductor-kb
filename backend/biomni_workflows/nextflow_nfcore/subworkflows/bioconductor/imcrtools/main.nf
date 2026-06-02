#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: imcRtools
// This R package supports the handling and analysis of imaging mass cytometry and other highly multipl
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/imcRtools/inst/doc/imcRtools.R
// Upstream  : CATALYST, cytomapper, ggplot2, ggraph
// Downstream: none
//
// Install: BiocManager::install("imcRtools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IMCRTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-imcrtools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-imcrtools:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-imcrtools:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_imcrtools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_imcrtools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_imcrtools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(imcRtools)
    library(jsonlite)

    # --- Spillover Analysis [] ---
    # Key functions: readSCEfromTXT, binAcrossPixels, plotSpotHeatmap
    spill_path <- system.file("extdata/spillover", package = "imcRtools")
    sce_spill <- readSCEfromTXT(spill_path)
    sce_binned <- binAcrossPixels(sce_spill, bin_size = 5)
    heatmap_plot <- plotSpotHeatmap(sce_binned, log = FALSE, threshold = 200)


    # --- Spillover Correction [] ---
    # Key functions: filterPixels, computeSpillmat
    spill_path <- system.file("extdata/spillover", package = "imcRtools")
    sce_spill <- readSCEfromTXT(spill_path)
    sce_spill$bc_id <- "191Ir"
    sce_spill$sample_mass <- 191
    sce_filtered <- filterPixels(sce_spill)
    sce_corrected <- computeSpillmat(sce_filtered)
    spill_matrix <- metadata(sce_corrected)$spillover_matrix


    # --- Spatial Graph Construction [] ---
    # Key functions: buildSpatialGraph
    data("pancreasSCE", package = "cytomapper")
    pancreasSCE <- buildSpatialGraph(pancreasSCE, img_id = "ImageNb",
                                     type = "expansion", threshold = 20)
    pancreasSCE <- buildSpatialGraph(pancreasSCE, img_id = "ImageNb",
                                     type = "knn", k = 5)
    pancreasSCE <- buildSpatialGraph(pancreasSCE, img_id = "ImageNb",
                                     type = "delaunay")


    # --- Spatial Visualization [] ---
    # Key functions: plotSpatial
    data("pancreasSCE", package = "cytomapper")
    pancreas_g <- buildSpatialGraph(pancreasSCE, img_id = "ImageNb",
                                    type = "knn", k = 5)
    spatial_plot <- plotSpatial(pancreas_g,
                                img_id = "ImageNb",
                                node_color_by = "CellType",
                                node_size_by = "Area",
                                draw_edges = TRUE,
                                colPairName = "knn_interaction_graph",
                                directed = FALSE,
                                scales = "free")


    # --- Neighborhood Aggregation [] ---
    # Key functions: aggregateNeighbors
    data("pancreasSCE", package = "cytomapper")
    pancreas_g <- buildSpatialGraph(pancreasSCE, img_id = "ImageNb",
                                    type = "knn", k = 5)
    pancreas_g <- aggregateNeighbors(pancreas_g,
                                     colPairName = "knn_interaction_graph",
                                     aggregate_by = "metadata",
                                     count_by = "CellType")
    pancreas_g <- aggregateNeighbors(pancreas_g,
                                     colPairName = "knn_interaction_graph",
                                     aggregate_by = "expression",
                                     assay_type = "exprs")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_imcrtools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_imcrtools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_imcrtools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IMCRTOOLS:", paste0("    imcrtools: ", packageVersion("imcRtools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_imcrtools_results.csv
    touch ${prefix}_imcrtools_output.rds
    echo "BIOC_IMCRTOOLS:" > versions.yml
    echo "    imcrtools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IMCRTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IMCRTOOLS(ch_input)

    emit:
    results  = BIOC_IMCRTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IMCRTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IMCRTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IMCRTOOLS.out.versions  // channel: path(versions.yml)
}
