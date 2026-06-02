#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SpaceMarkers
// Spatial transcriptomic technologies have helped to resolve the connection between gene expression an
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SpaceMarkers/inst/doc/SpaceMarkers_vignette.R
// Upstream  : Matrix, RColorBrewer, cowplot, dplyr, ggplot2
// Downstream: none
//
// Install: BiocManager::install("SpaceMarkers")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPACEMARKERS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spacemarkers"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spacemarkers:1.2.1--r44_0' :
        'quay.io/biocontainers/bioconductor-spacemarkers:1.2.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spacemarkers_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spacemarkers_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spacemarkers_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SpaceMarkers)
    library(jsonlite)

    # --- Load Spatial Data ---
    # Key functions: load10XExpr, load10XCoords
    counts_matrix <- load10XExpr(
        visiumDir = ".",
        h5filename = "Visium_Human_Breast_Cancer_filtered_feature_bc_matrix.h5"
    )
    good_gene_threshold <- 3
    goodGenes <- rownames(counts_matrix)[
        apply(counts_matrix, 1, function(x) sum(x > 0) >= good_gene_threshold)
    ]
    counts_matrix <- counts_matrix[goodGenes, ]
    spCoords <- load10XCoords(visiumDir = ".", version = "1.0")
    rownames(spCoords) <- spCoords$barcode

    # --- Integrate Spatial Patterns ---
    # Key functions: None
    cogaps_result <- readRDS(system.file(
        "extdata", "CoGAPS_result.rds",
        package = "SpaceMarkers", mustWork = TRUE
    ))
    features <- intersect(
        rownames(counts_matrix),
        rownames(slot(cogaps_result, "featureLoadings"))
    )
    barcodes <- intersect(
        colnames(counts_matrix),
        rownames(slot(cogaps_result, "sampleFactors"))
    )
    counts_matrix <- counts_matrix[features, barcodes]
    cogaps_matrix <- slot(cogaps_result, "featureLoadings")[features, ] %*%
        t(slot(cogaps_result, "sampleFactors")[barcodes, ])
    spCoords <- spCoords[barcodes, ]
    spPatterns <- cbind(
        spCoords,
        slot(cogaps_result, "sampleFactors")[barcodes, ]
    )

    # --- Residual Mode Analysis ---
    # Key functions: getInteractingGenes
    data("curated_genes")
    data("optParams")
    spPatterns_sub <- spPatterns[
        c("barcode", "y", "x", "Pattern_1", "Pattern_5")
    ]
    counts_sub <- counts_matrix[curated_genes, ]
    cogaps_sub <- cogaps_matrix[curated_genes, ]
    SpaceMarkers_res <- getInteractingGenes(
        data = counts_sub,
        reconstruction = cogaps_sub,
        optParams = optParams,
        spPatterns = spPatterns_sub,
        refPattern = "Pattern_1",
        mode = "residual",
        analysis = "overlap"
    )

    # --- Differential Expression Mode Analysis ---
    # Key functions: getInteractingGenes
    data("curated_genes")
    data("optParams")
    spPatterns_sub <- spPatterns[
        c("barcode", "y", "x", "Pattern_1", "Pattern_5")
    ]
    counts_sub <- counts_matrix[curated_genes, ]
    SpaceMarkers_DE <- getInteractingGenes(
        data = counts_sub,
        reconstruction = NULL,
        optParams = optParams,
        spPatterns = spPatterns_sub,
        refPattern = "Pattern_1",
        mode = "DE",
        analysis = "overlap"
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spacemarkers_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spacemarkers_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spacemarkers_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPACEMARKERS:", paste0("    spacemarkers: ", packageVersion("SpaceMarkers"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spacemarkers_results.csv
    touch ${prefix}_spacemarkers_output.rds
    echo "BIOC_SPACEMARKERS:" > versions.yml
    echo "    spacemarkers: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPACEMARKERS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPACEMARKERS(ch_input)

    emit:
    results  = BIOC_SPACEMARKERS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPACEMARKERS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPACEMARKERS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPACEMARKERS.out.versions  // channel: path(versions.yml)
}
