#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: StabMap
// StabMap performs single cell mosaic data integration by first building a mosaic data topology, and f
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/StabMap/inst/doc/stabMap_PBMC_Multiome.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("StabMap")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_STABMAP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-stabmap"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-stabmap:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-stabmap:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_stabmap_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_stabmap_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_stabmap_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(StabMap)
    library(jsonlite)

    # --- Upsetsamples [] ---
    # Key functions: upsetSamples, colData, experiments
    ---------------------------------------------------------------------
    mae
    upsetSamples(mae)
    head(colData(mae))
    dim(experiments(mae)[["rna"]])
    # --- Experiments [] ---
    # Key functions: experiments, logNormCounts, modelGeneVar
    ---------------------------------------------------------------------
    sce.rna <- experiments(mae)[["rna"]]
    # Normalisation
    sce.rna <- logNormCounts(sce.rna)
    # Feature selection
    # --- Dim [] ---
    # Key functions: experiments, logNormCounts, modelGeneVar
    ---------------------------------------------------------------------
    dim(experiments(mae)[["atac"]])
    sce.atac <- experiments(mae)[["atac"]]
    # Normalise
    sce.atac <- logNormCounts(sce.atac)
    # --- Setnames [] ---
    # Key functions: setNames, sample
    ---------------------------------------------------------------------
    # --- Mosaicdataupset [] ---
    # Key functions: mosaicDataUpSet
    ---------------------------------------------------------------------
    mosaicDataUpSet(assay_list, plot = FALSE)
    # --- Mosaicdatatopology [] ---
    # Key functions: mosaicDataTopology
    ---------------------------------------------------------------------
    mdt <- mosaicDataTopology(assay_list)
    mdt
    plot(mdt)
    # --- Stabmap [] ---
    # Key functions: stabMap
    ---------------------------------------------------------------------
    stab <- stabMap(assay_list,
      reference_list = c("Multiome"),
      plot = FALSE
    )
    # --- Calculateumap [] ---
    # Key functions: calculateUMAP, factor
    ---------------------------------------------------------------------
    stab_umap <- calculateUMAP(t(stab))
    dim(stab_umap)
    plot(stab_umap, pch = 16, cex = 0.3, col = factor(dataType[rownames(stab)]))
    # --- Imputeembedding [] ---
    # Key functions: imputeEmbedding
    ---------------------------------------------------------------------
    # --- Coldata [] ---
    # Key functions: colData, experiments
    ---------------------------------------------------------------------
    annotation <- "celltype"
    referenceLabels <- colData(
      experiments(mae)[["rna"]]
    )[colnames(assay_list$Multiome), annotation]
    # --- Classifyembedding [] ---
    # Key functions: classifyEmbedding
    ---------------------------------------------------------------------
    knn_out <- classifyEmbedding(
      stab,
      referenceLabels,
    )
    # --- Coldata [] ---
    # Key functions: colData, experiments
    ---------------------------------------------------------------------
    # Extract query labels
    queryLabels <- colData(
      experiments(mae)[["rna"]]
    )[colnames(assay_list$RNA), annotation]
    # --- Colnames [] ---
    # Key functions: frame, ggplot, aes, geom_point, ggtitle, arrange
    ---------------------------------------------------------------------
    # Extract reference and query cells from UMAP embedding
    stab_umap_ref <- stab_umap[colnames(assay_list$Multiome), ]
    stab_umap_query <- stab_umap[colnames(assay_list$RNA), ]
    # Create UMAP for reference cells
    # --- Setnames [] ---
    # Key functions: setNames, sample
    ---------------------------------------------------------------------
    # --- Mosaicdataupset [] ---
    # Key functions: mosaicDataUpSet
    ---------------------------------------------------------------------
    mosaicDataUpSet(assay_list_indirect, plot = FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_stabmap_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_stabmap_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_stabmap_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_STABMAP:", paste0("    stabmap: ", packageVersion("StabMap"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_stabmap_results.csv
    touch ${prefix}_stabmap_output.rds
    echo "BIOC_STABMAP:" > versions.yml
    echo "    stabmap: 0.0.0" >> versions.yml
    """
}


workflow BIOC_STABMAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_STABMAP(ch_input)

    emit:
    results  = BIOC_STABMAP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_STABMAP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_STABMAP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_STABMAP.out.versions  // channel: path(versions.yml)
}
