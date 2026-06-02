#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: FindIT2
// This package implements functions to find influential TF and target based on different input type. I
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/FindIT2/inst/doc/FindIT2.R
// Upstream  : SummarizedExperiment, dplyr, ggplot2, sessioninfo
// Downstream: none
//
// Install: BiocManager::install("FindIT2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FINDIT2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-findit2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-findit2:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-findit2:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_findit2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_findit2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_findit2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FindIT2)
    library(jsonlite)

    # --- "install" [] ---
    # Key functions: valid

    # --- "start" [] ---
    # Key functions: seqlevels, genes
    library(FindIT2)
    library(TxDb.Athaliana.BioMart.plantsmart28)
    library(SummarizedExperiment)
    # --- "prepare data" [] ---
    # Key functions: loadPeakFile
    ChIP_peak_path <- system.file("extdata", "ChIP.bed.gz", package = "FindIT2")
    ChIP_peak_GR <- loadPeakFile(ChIP_peak_path)
    # --- "mm nearestgene" [] ---
    # Key functions: mm_nearestGene, plot_annoDistance, getAssocPairNumber, plot_peakGeneAlias_summary

    # --- "mm geneBound" [] ---
    # Key functions: mm_geneBound
    genes_Chr5 <- names(all_geneSet[seqnames(all_geneSet) == "Chr5"])
    genes_Chr5_notAnno <- genes_Chr5[!genes_Chr5 %in% unique(mmAnno_nearestgene$gene_id)]
    genes_Chr5_Anno <- unique(mmAnno_nearestgene$gene_id)
    # --- "mm geneScan" [] ---
    # Key functions: mm_geneScan, getAssocPairNumber, plot_peakGeneAlias_summary

    # --- "calcRP TFHit" [] ---
    # Key functions: calcRP_TFHit, metadata

    # --- "calcRP bw" [] ---
    # Key functions: calcRP_coverage
    bwFile <- system.file("extdata", "E50h_sampleChr5.bw", package = "FindIT2")
    # --- "calcRP region" [] ---
    # Key functions: loadPeakFile, mm_geneScan, calcRP_region, assays
    data("ATAC_normCount")
    ATAC_peak_path <- system.file("extdata", "ATAC.bed.gz", package = "FindIT2")
    ATAC_peak_GR <- loadPeakFile(ATAC_peak_path)
    # --- "findITarget" [] ---
    # Key functions: integrate_ChIP_RNA
    data("RNADiff_LEC2_GR")
    # --- "prepare for findIT" [] ---
    # Key functions: mm_geneBound, loadPeakFile

    # --- "findIT enrichWilcox" [] ---
    # Key functions: findIT_enrichWilcox

    # --- "findIT enrichFisher" [] ---
    # Key functions: findIT_enrichFisher, jaccard_findIT_enrichFisher, diag

    # --- "findIT TTPair" [] ---
    # Key functions: findIT_TTPair, jaccard_findIT_TTpair, diag
    result_TTpair <- findIT_TTPair(input_genes = input_genes,
    gene_background = names(all_geneSet))
    # --- "findIT TFHit" [] ---
    # Key functions: findIT_TFHit, findIT_regionRP, assays, heatmap, metadata
    set.seed(20160806)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_findit2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_findit2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_findit2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FINDIT2:", paste0("    findit2: ", packageVersion("FindIT2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_findit2_results.csv
    touch ${prefix}_findit2_output.rds
    echo "BIOC_FINDIT2:" > versions.yml
    echo "    findit2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FINDIT2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FINDIT2(ch_input)

    emit:
    results  = BIOC_FINDIT2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FINDIT2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FINDIT2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FINDIT2.out.versions  // channel: path(versions.yml)
}
