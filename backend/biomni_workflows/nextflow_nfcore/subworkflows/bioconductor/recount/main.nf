#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: recount
// Explore and download data from the recount project available at https://jhubiostatistics.shinyapps.i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/recount/inst/doc/SRP009615-results.R
// Upstream  : DESeq2, DT, GenomeInfoDb, GenomicRanges, RColorBrewer
// Downstream: none
//
// Install: BiocManager::install("recount")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RECOUNT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-recount"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-recount:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-recount:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_recount_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_recount_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_recount_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PrintBibliography)
    library(jsonlite)

    # --- 'PCA' [] ---
    # Key functions: plotPCA
    rld <- tryCatch(rlog(dds), error = function(e) { rlog(dds, fitType = 'mean') })
    plotPCA(rld, intgroup = intgroup)
    data_pca <- plotPCA(rld, intgroup = intgroup, returnData = TRUE)
    # --- 'sampleDist' [] ---
    # Key functions: dist, colorRampPalette, pheatmap
    sampleDists <- dist(t(assay(rld)))
    sampleDistMatrix <- as.matrix(sampleDists)
    # --- 'MAplotalpha' [] ---
    # Key functions: plotMA, metadata
    MA plot with alpha used in DESeq2::results()
    plotMA(res, alpha = metadata(res)$alpha, main = paste('MA plot with alpha =',
    metadata(res)$alpha))
    # --- 'MAplotalphaHalf' [] ---
    # Key functions: plotMA
    MA plot with alpha = 1/2 of the alpha used in DESeq2::results()
    plotMA(res, alpha = metadata(res)$alpha / 2,
    main = paste('MA plot with alpha =', metadata(res)$alpha / 2))
    # --- 'MAplotalpha [] ---
    # Key functions: plotMA
    nBest.actual <- min(nBest, nrow(head(res.df, n = nBest)))
    nBest.alpha <- head(res.df, n = nBest)$padj[nBest.actual]
    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_histogram, labs, xlab, xlim
    ggplot(res.df[!is.na(res.df$pvalue), ], aes(x = pvalue)) +
    geom_histogram(alpha=.5, position='identity', bins = 50) +
    labs(title='Histogram of unadjusted p-values') +
    # --- kable [] ---
    # Key functions: kable

    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_histogram, labs, xlab, xlim
    ggplot(res.df[!is.na(res.df$padj), ], aes(x = padj)) +
    geom_histogram(alpha=.5, position='identity', bins = 50) +
    labs(title=paste('Histogram of', elementMetadata(res)$description[grep('adjusted', elementMetadata(res)$description)])) +
    # --- kable [] ---
    # Key functions: kable

    # --- 'topFeatures' [] ---
    # Key functions: datatable

    # --- 'plotCounts' [] ---
    # Key functions: colData, droplevels, plotCounts

    # --- diff [] ---
    # Key functions: diff
    totalTime <- diff(c(startTime, Sys.time()))
    round(totalTime, digits=3)
    # --- session_info [] ---
    # Key functions: session_info
    options(width = 120)
    session_info()
    # --- Print Bibliography [] ---
    # Key functions: PrintBibliography
    PrintBibliography(bib, .opts = list(hyperlink = "to.doc", style = "html"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_recount_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_recount_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_recount_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RECOUNT:", paste0("    recount: ", packageVersion("recount"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_recount_results.csv
    touch ${prefix}_recount_output.rds
    echo "BIOC_RECOUNT:" > versions.yml
    echo "    recount: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RECOUNT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RECOUNT(ch_input)

    emit:
    results  = BIOC_RECOUNT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RECOUNT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RECOUNT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RECOUNT.out.versions  // channel: path(versions.yml)
}
