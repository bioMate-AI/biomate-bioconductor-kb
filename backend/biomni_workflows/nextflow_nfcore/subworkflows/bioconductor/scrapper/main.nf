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
    library(DelayedArray)
    library(StoeckiusHashingData)
    library(TasicBrainData)
    library(ZeiselBrainData)
    library(jsonlite)

    # --- Zeiselbraindata [] ---
    # Key functions: ZeiselBrainData
    ---------------------------------------------------------------------
    library(scRNAseq)
    sce.z <- ZeiselBrainData()
    sce.z
    # --- Delayedarray [] ---
    # Key functions: DelayedArray, assay, computeRnaQcMetrics, suggestRnaQcThresholds
    ---------------------------------------------------------------------
    # Wrapping it in a DelayedArray to avoid making unnecessary copies when we
    # do the various subsetting steps.
    library(DelayedArray)
    counts <- DelayedArray(assay(sce.z))
    # --- Tasicbraindata [] ---
    # Key functions: TasicBrainData, intersect, DelayedArray, assay
    ---------------------------------------------------------------------
    sce.t <- TasicBrainData()
    common <- intersect(rownames(sce.z), rownames(sce.t))
    combined <- cbind(
        DelayedArray(assay(sce.t))[common,],
    # --- Computernaqcmetrics [] ---
    # Key functions: computeRnaQcMetrics, suggestRnaQcThresholds, filterRnaQcMetrics, centerSizeFactors, normalizeCounts, modelGeneVariances
    ---------------------------------------------------------------------
    # No mitochondrial genes in the combined set, so we'll just skip it.
    library(scrapper)
    rna.qc.metrics <- computeRnaQcMetrics(combined, subsets=list(), num.threads=nthreads)
    rna.qc.thresholds <- suggestRnaQcThresholds(rna.qc.metrics, block=block)
    # --- Plot [] ---
    # Key functions: factor
    ---------------------------------------------------------------------
    plot(tsne.out[,1], tsne.out[,2], pch=16, col=factor(filtered.block))
    # --- Aggregateacrosscells [] ---
    # Key functions: aggregateAcrossCells
    ---------------------------------------------------------------------
    aggregates <- aggregateAcrossCells(filtered, list(cluster=clust.out$membership, dataset=filtered.block))
    # --- Stoeckiushashingdata [] ---
    # Key functions: StoeckiusHashingData
    ---------------------------------------------------------------------
    sce.s <- StoeckiusHashingData(mode=c("human", "adt1", "adt2"))
    sce.s <- sce.s[,1:5000]
    sce.s
    # --- Delayedarray [] ---
    # Key functions: DelayedArray, assay, altExp
    ---------------------------------------------------------------------
    rna.counts <- DelayedArray(assay(sce.s))
    adt.counts <- DelayedArray(rbind(
        assay(altExp(sce.s, "adt1")),
        assay(altExp(sce.s, "adt2"))
    # --- Grepl [] ---
    # Key functions: computeRnaQcMetrics, suggestRnaQcThresholds, filterRnaQcMetrics, computeAdtQcMetrics
    ---------------------------------------------------------------------
    # QC in both modalities, only keeping the cells that pass in both.
    library(scrapper)
    is.mito <- grepl("^MT-", rownames(rna.counts))
    rna.qc.metrics <- computeRnaQcMetrics(rna.counts, subsets=list(MT=is.mito), num.threads=nthreads)

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
