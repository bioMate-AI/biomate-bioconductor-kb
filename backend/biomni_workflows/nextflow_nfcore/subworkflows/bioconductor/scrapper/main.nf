#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scrapper
// Implements R bindings to C++ code for analyzing single-cell (expression) data, mostly from various l
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scrapper/inst/doc/userguide.R
// Upstream  : BiocStyle, DelayedArray, knitr, scRNAseq
// Downstream: none
//
// Install: BiocManager::install("scrapper")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCRAPPER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scrapper"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scrapper:1.0.3--r44_0' :
        'quay.io/biocontainers/bioconductor-scrapper:1.0.3--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scrapper_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scrapper_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scrapper_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scrapper)
    library(DelayedArray)
    library(StoeckiusHashingData)
    library(TasicBrainData)
    library(ZeiselBrainData)
    library(jsonlite)

    # --- Normalisation and Feature Selection [] ---
    # Key functions: centerSizeFactors, normalizeCounts, modelGeneVariances, chooseHighlyVariableGenes
    size.factors <- centerSizeFactors(rna.qc.metrics$sum[rna.qc.filter])
    normalized <- normalizeCounts(filtered, size.factors)
    gene.var <- modelGeneVariances(normalized, num.threads = 2)
    top.hvgs <- chooseHighlyVariableGenes(gene.var$statistics$residuals)


    # --- Dimensionality Reduction and Clustering [] ---
    # Key functions: runPca, runUmap, runTsne, buildSnnGraph, clusterGraph
    pca <- runPca(normalized[top.hvgs, ], num.threads = 2)
    umap.out <- runUmap(pca$components, num.threads = 2)
    tsne.out <- runTsne(pca$components, num.threads = 2)
    snn.graph <- buildSnnGraph(pca$components, num.threads = 2)
    clust.out <- clusterGraph(snn.graph)


    # --- Marker Gene Detection [] ---
    # Key functions: scoreMarkers
    markers <- scoreMarkers(
        normalized,
        groups = clust.out$membership,
        num.threads = 2
    )
    top.markers <- lapply(markers$auc, function(x) {
        head(rownames(x)[order(x$median, decreasing = TRUE)], 10)
    })


    # --- Batch Correction [] ---
    # Key functions: correctMnn
    corrected <- correctMnn(
        pca$components,
        block = filtered.block,
        num.threads = 2
    )
    corrected.umap <- runUmap(corrected$corrected, num.threads = 2)


    # --- Multi-modal Integration [] ---
    # Key functions: computeAdtQcMetrics, computeClrm1Factors, scaleByNeighbors
    adt.qc.metrics <- computeAdtQcMetrics(adt.counts, num.threads = 2)
    adt.size.factors <- computeClrm1Factors(adt.counts, num.threads = 2)
    adt.size.factors <- centerSizeFactors(adt.size.factors)
    adt.normalized <- normalizeCounts(adt.counts, adt.size.factors)
    combined <- scaleByNeighbors(
        list(pca$components, as.matrix(adt.normalized)),
        num.threads = 2
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scrapper_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scrapper_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scrapper_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCRAPPER:", paste0("    scrapper: ", packageVersion("scrapper"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scrapper_results.csv
    touch ${prefix}_scrapper_output.rds
    echo "BIOC_SCRAPPER:" > versions.yml
    echo "    scrapper: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCRAPPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCRAPPER(ch_input)

    emit:
    results  = BIOC_SCRAPPER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCRAPPER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCRAPPER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCRAPPER.out.versions  // channel: path(versions.yml)
}
