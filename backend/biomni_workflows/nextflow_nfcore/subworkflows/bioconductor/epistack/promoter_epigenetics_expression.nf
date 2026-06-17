#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epistack — promoter_epigenetics_expression
// Visualize DNA methylation and ChIP-seq coverage at gene promoters (TSS) sorted and binned by gene expression levels.
// Input: genes, rpkm, meth, H3K4me3
// Container: quay.io/biocontainers/bioconductor-epistack:1.16.0--r45hdfd78af_0
// R packages: EnrichedHeatmap, GenomicRanges, SummarizedExperiment, epistack
// Bioconductor: 3.20 | R: 4.4
// Requires: EnrichedHeatmap, GenomicRanges, SummarizedExperiment, epistack
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read the declared user input files from the working
//  * 2. [Visualization & Output] Extract TSS coordinates using GenomicRanges::promoters
//  * 3. [Visualization & Output] Merge expression data with TSS coordinates and sort them
//  * 4. [Visualization & Output] Partition the genes into expression bins
//  * 5. [Visualization & Output] Extract DNA methylation and ChIP-seq signals around TSS
//  * 6. [Visualization & Output] Assemble the data into a SummarizedExperiment object
//  * 7. [Visualization & Output] Plot the multi-track stacked profiles and save to PDF
//  * 8. [Visualization & Output] Save meaningful output files

nextflow.enable.dsl = 2

process BIOC_EPISTACK_PROMOTER_EPIGENETICS_EXPRESSION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("EnrichedHeatmap", "GenomicRanges", "SummarizedExperiment", "epistack")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(GenomicRanges)
    library(SummarizedExperiment)
    library(epistack)
    library(EnrichedHeatmap)
    
    # --- Read the declared user input files from the working ---
    if (!file.exists("genes.rds") || !file.exists("rpkm.rds") || !file.exists("meth.rds") || !file.exists("H3K4me3.rds")) {
        stop("Required input files (genes.rds, rpkm.rds, meth.rds, H3K4me3.rds) are missing from the working directory.")
    }
    
    genes <- readRDS("genes.rds")
    rpkm <- readRDS("rpkm.rds")
    meth <- readRDS("meth.rds")
    H3K4me3 <- readRDS("H3K4me3.rds")
    
    # --- Extract TSS coordinates using GenomicRanges::promoters ---
    tss <- promoters(genes, upstream = 0, downstream = 1)
    tss\$gene_id <- names(tss)
    
    # --- Merge expression data with TSS coordinates and sort them ---
    expr <- data.frame(
        gene_id = names(rpkm),
        expr = rpkm
    )
    
    epidata <- addMetricAndArrangeGRanges(
        tss, expr,
        gr_key = "gene_id",
        order_key = "gene_id", order_value = "expr"
    )
    
    # --- Partition the genes into expression bins ---
    epidata <- addBins(epidata, nbins = 5)
    
    # --- Extract DNA methylation and ChIP-seq signals around TSS ---
    methstack <- normalizeToMatrix(
        meth, epidata, value_column = "meth",
        extend = 5000, w = 250, mean_mode = "absolute"
    )
    
    h3k4me3stack <- normalizeToMatrix(
        H3K4me3, epidata, value_column = "coverage",
        extend = 5000, w = 250, mean_mode = "coverage"
    )
    
    # --- Assemble the data into a SummarizedExperiment object ---
    epidata <- SummarizedExperiment(
        rowRanges = epidata,
        assays = list(DNAme = methstack, H3K4me3 = h3k4me3stack)
    )
    
    # --- Plot the multi-track stacked profiles and save to PDF ---
    pdf("epistack_promoter_plot.pdf", width = 8, height = 10)
    plotEpistack(
        epidata,
        tints = c("dodgerblue", "orange"),
        zlim = list(c(0, 1), c(0, 25)), ylim = list(c(0, 1), c(0, 50)),
        x_labels = c("-5kb", "TSS", "+5kb"),
        legends = c("%mCpG", "Coverage"),
        metric_col = "expr", metric_title = "Gene expression",
        metric_label = "log10(RPKM+1)",
        metric_transfunc = function(x) log10(x + 1),
        npix_height = 300
    )
    dev.off()
    
    # --- Save meaningful output files ---
    saveRDS(epidata, "epidata_summarized_experiment.rds")
    
    # Export metadata as a CSV table
    metadata_df <- as.data.frame(rowRanges(epidata))
    write.csv(metadata_df, "epidata_metadata.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_EPISTACK_PROMOTER_EPIGENETICS_EXPRESSION":',
        paste0('    epistack: ', as.character(packageVersion('epistack')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_promoter_epigenetics_expression.csv versions.yml
    """
}

workflow BIOC_EPISTACK_PROMOTER_EPIGENETICS_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genes, rpkm, meth, H3K4me3 ] ]

    main:
    BIOC_EPISTACK_PROMOTER_EPIGENETICS_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_EPISTACK_PROMOTER_EPIGENETICS_EXPRESSION.out.tables
    plots    = BIOC_EPISTACK_PROMOTER_EPIGENETICS_EXPRESSION.out.plots
    objects  = BIOC_EPISTACK_PROMOTER_EPIGENETICS_EXPRESSION.out.objects
    versions = BIOC_EPISTACK_PROMOTER_EPIGENETICS_EXPRESSION.out.versions
}
