#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DRIMSeq — transcript_usage_qtl
// Identify genetic variants (SNPs) associated with changes in transcript usage (tuQTLs) using a Dirichlet-multinomial model.
// Input: geuv_counts, geuv_genotypes, geuv_gene_ranges, geuv_snp_ranges, geuv_samples
// Container: quay.io/biocontainers/bioconductor-drimseq:1.38.0--r45hdfd78af_0
// R packages: DRIMSeq, GenomicRanges, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: DRIMSeq, GenomicRanges, ggplot2
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Format counts, genotypes, and sample data frames
//  * 2. [Input & Preparation] Create a dmSQTLdata object using dmSQTLdata() with a specified genomic window
//  * 3. [Core Analysis] Filter out lowly expressed features and low-frequency alleles using dmFilter()
//  * 4. [Core Analysis] Estimate precision parameters using dmPrecision()
//  * 5. [Core Analysis] Fit the model proportions using dmFit()
//  * 6. [Core Analysis] Test for tuQTL associations using dmTest()
//  * 7. [Visualization & Output] Extract results using results() and visualize proportions using plotProportions()

nextflow.enable.dsl = 2

process BIOC_DRIMSEQ_TRANSCRIPT_USAGE_QTL {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("DRIMSeq", "GenomicRanges", "ggplot2")
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
    library(DRIMSeq)
    library(GenomicRanges)
    library(ggplot2)
    
    # Read user input files from the working directory
    geuv_counts <- readRDS("geuv_counts.rds")
    geuv_genotypes <- readRDS("geuv_genotypes.rds")
    geuv_gene_ranges <- readRDS("geuv_gene_ranges.rds")
    geuv_snp_ranges <- readRDS("geuv_snp_ranges.rds")
    geuv_samples <- readRDS("geuv_samples.rds")
    
    # 2. Create a dmSQTLdata object using dmSQTLdata() with a specified genomic window
    d <- dmSQTLdata(counts = geuv_counts, gene_ranges = geuv_gene_ranges,
      genotypes = geuv_genotypes, snp_ranges = geuv_snp_ranges, 
      samples = geuv_samples, window = 5e3)
    d
    
    # Save diagnostic data plots
    pdf("plot_data_features.pdf")
    plotData(d, plot_type = "features")
    dev.off()
    
    pdf("plot_data_snps.pdf")
    plotData(d, plot_type = "snps")
    dev.off()
    
    pdf("plot_data_blocks.pdf")
    plotData(d, plot_type = "blocks")
    dev.off()
    
    # 3. Filter out lowly expressed features and low-frequency alleles using dmFilter()
    d <- dmFilter(d, min_samps_gene_expr = 70, min_samps_feature_expr = 5,
      minor_allele_freq = 5, min_gene_expr = 10, min_feature_expr = 10)
    
    # 4. Estimate precision parameters using dmPrecision()
    set.seed(123)
    d <- dmPrecision(d)
    
    pdf("plot_precision.pdf")
    plotPrecision(d)
    dev.off()
    
    # 5. Fit the model proportions using dmFit()
    d <- dmFit(d)
    
    # 6. Test for tuQTL associations using dmTest()
    d <- dmTest(d)
    
    pdf("plot_pvalues.pdf")
    plotPValues(d)
    dev.off()
    
    head(results(d))
    
    # 7. Extract results using results() and visualize proportions using plotProportions()
    res <- results(d)
    write.csv(res, "tuQTL_results.csv", row.names = FALSE)
    
    res <- res[order(res\$pvalue, decreasing = FALSE), ]
    
    top_gene_id <- res\$gene_id[1]
    top_snp_id <- res\$snp_id[1]
    
    pdf("plot_proportions_default.pdf")
    plotProportions(d, gene_id = top_gene_id, snp_id = top_snp_id)
    dev.off()
    
    pdf("plot_proportions_boxplot2.pdf")
    plotProportions(d, gene_id = top_gene_id, snp_id = top_snp_id,
      plot_type = "boxplot2")
    dev.off()
    
    # Save the final processed DRIMSeq object
    saveRDS(d, "drimseq_tuQTL_object.rds")

    writeLines(c(
        '"BIOC_DRIMSEQ_TRANSCRIPT_USAGE_QTL":',
        paste0('    DRIMSeq: ', as.character(packageVersion('DRIMSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_transcript_usage_qtl.csv versions.yml
    """
}

workflow BIOC_DRIMSEQ_TRANSCRIPT_USAGE_QTL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ geuv_counts, geuv_genotypes, geuv_gene_ranges, geuv_snp_ranges, geuv_samples ] ]

    main:
    BIOC_DRIMSEQ_TRANSCRIPT_USAGE_QTL(ch_input)

    emit:
    tables   = BIOC_DRIMSEQ_TRANSCRIPT_USAGE_QTL.out.tables
    plots    = BIOC_DRIMSEQ_TRANSCRIPT_USAGE_QTL.out.plots
    objects  = BIOC_DRIMSEQ_TRANSCRIPT_USAGE_QTL.out.objects
    versions = BIOC_DRIMSEQ_TRANSCRIPT_USAGE_QTL.out.versions
}
