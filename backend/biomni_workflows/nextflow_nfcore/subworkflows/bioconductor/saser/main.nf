#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: saseR
// saseR is a highly performant and fast framework for aberrant expression and splicing analyses. The m
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/saseR/inst/doc/saseR-vignette.R
// Upstream  : ASpli, BiocParallel, DESeq2, DEXSeq, GenomicAlignments
// Downstream: none
//
// Install: BiocManager::install("saseR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SASER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-saser"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-saser:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-saser:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_saser_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_saser_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_saser_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(saseR)
    library(BamtoAspliCounts)
    library(DESeqDataSetFromMatrix)
    library(DGEList)
    library(MulticoreParam)
    library(jsonlite)

    # --- Filtering and Normalisation [] ---
    # Key functions: filterByExpr, calculateOffsets
    filtergenes <- filterByExpr(SEgenes)
    SEgenes <- SEgenes[filtergenes, ]
    SEgenes <- calculateOffsets(SEgenes, method = "TMM")
    filterbins <- filterByExpr(SEbins)
    SEbins <- SEbins[filterbins, ]
    SEbins <- calculateOffsets(SEbins, method = "AS", aggregation = "locus")


    # --- Encoding Dimension Estimation [] ---
    # Key functions: saseRfindEncodingDim
    SEgenes <- saseRfindEncodingDim(SEgenes, method = "GD")
    SEbins <- saseRfindEncodingDim(SEbins, method = "GD")
    SEjunctions <- saseRfindEncodingDim(SEjunctions, method = "GD")


    # --- Model Fitting and Splicing Analysis [] ---
    # Key functions: saseRfit
    SEgenes <- saseRfit(SEgenes, analysis = "AE", padjust = "BH", fit = "fast")
    SEbins <- saseRfit(SEbins, analysis = "AS", padjust = "BH", fit = "fast")
    SEjunctions <- saseRfit(SEjunctions, analysis = "AS", padjust = "BH",
                            fit = "fast")


    # --- Result Extraction [] ---
    # Key functions: assays, metadata
    gene_pvals <- assays(SEgenes)$pValue
    bin_pvals <- assays(SEbins)$pValue
    sig_genes <- lapply(seq_len(ncol(SEgenes)), function(x) {
        rownames(SEgenes)[assays(SEgenes)$pValueAdjust[, x] < 0.05]
    })
    sig_bins <- lapply(seq_len(ncol(SEbins)), function(x) {
        rownames(SEbins)[assays(SEbins)$pValueAdjust[, x] < 0.05]
    })

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_saser_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_saser_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_saser_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SASER:", paste0("    saser: ", packageVersion("saseR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_saser_results.csv
    touch ${prefix}_saser_output.rds
    echo "BIOC_SASER:" > versions.yml
    echo "    saser: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SASER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SASER(ch_input)

    emit:
    results  = BIOC_SASER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SASER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SASER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SASER.out.versions  // channel: path(versions.yml)
}
