#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: saser — aberrant_expression_analysis
// Detect aberrant gene expression from BAM files and GTF annotation.
// Input: BAMFiles, gtfFileName
// Container: quay.io/biocontainers/bioconductor-saser:1.6.0--r45hdfd78af_0
// R packages: GenomicFeatures, PRROC, ASpli, BiocParallel, data.table, DESeq2, DEXSeq, dplyr, edgeR, GenomicAlignments, igraph, limma, saseR, txdbmaker
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SASER_ABERRANT_EXPRESSION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-saser:1.6.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicFeatures", "PRROC", "ASpli", "BiocParallel", "data.table", "DESeq2", "DEXSeq", "dplyr", "edgeR", "GenomicAlignments", "igraph", "limma", "saseR", "txdbmaker", "SummarizedExperiment")
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
    
    # Load required libra    library(SummarizedExperiment)
ries
    library(saseR)
    suppressWarnings(library(ASpli))
    library(edgeR)
    library(DESeq2)
    library(limma)
    library(GenomicFeatures)
    library(dplyr)
    library(PRROC)
    library(BiocParallel)
    library(data.table)
    library(igraph)
    library(txdbmaker)
    
    # -----------------------------------------------------------------------------
    # --- USER INPUTS ---
    # Read GTF and BAM files from the working directory
    # -----------------------------------------------------------------------------
    gtfFileName <- list.files(pattern = "\\\\.gtf\$", full.names = TRUE)[1]
    BAMFiles <- list.files(pattern = "\\\\.bam\$", full.names = TRUE)
    
    if (is.na(gtfFileName)) {
      stop("Error: No GTF file (.gtf) found in the working directory.")
    }
    if (length(BAMFiles) == 0) {
      stop("Error: No BAM files (.bam) found in the working directory.")
    }
    
    # Construct targets data frame dynamically based on the input BAM files
    targets <- data.frame( 
      row.names = paste0('Sample', seq_along(BAMFiles)),
      bam = BAMFiles,
      f1 = rep("A", length(BAMFiles)),
      stringsAsFactors = FALSE
    )
    
    # -----------------------------------------------------------------------------
    # --- GENOME ANNOTATION & FEATURE EXTRACTION ---
    # -----------------------------------------------------------------------------
    genomeTxDb <- txdbmaker::makeTxDbFromGFF(gtfFileName)
    features <- binGenome(genomeTxDb, logTo = NULL)
    
    # -----------------------------------------------------------------------------
    # --- READ COUNTING ---
    # -----------------------------------------------------------------------------
    ASpliSE <- BamtoAspliCounts(
      features = features,
      targets = targets,
      minReadLength = 100,
      libType = "SE",
      BPPARAM = MulticoreParam(1L)
    )
    
    # -----------------------------------------------------------------------------
    # --- ABERRANT EXPRESSION ANALYSIS PIPELINE ---
    # -----------------------------------------------------------------------------
    # Extract gene counts
    SEgenes <- convertASpli(ASpliSE, type = "gene")
    
    # Define design formula in metadata
    metadata(SEgenes)\$design <- ~1
    
    # Filter low-count genes
    filtergenes <- filterByExpr(SEgenes)
    SEgenes <- SEgenes[filtergenes,]
    
    # Calculate normalization offsets
    SEgenes <- calculateOffsets(SEgenes, method = "TMM")
    
    # Estimate latent confounders
    SEgenes <- saseRfindEncodingDim(SEgenes, method = "GD")
    
    # Fit the regression model and calculate p-values
    SEgenes <- saseRfit(
      SEgenes,
      analysis = "AE",
      padjust = "BH",
      fit = "fast"
    )
    
    # -----------------------------------------------------------------------------
    # --- WRITE OUTPUTS ---
    # -----------------------------------------------------------------------------
    # Save the complete SummarizedExperiment object
    saveRDS(SEgenes, file = "aberrant_expression_results.rds")
    
    # Extract and save p-values and adjusted p-values
    pvals <- assays(SEgenes)\$pValue
    pvals_adj <- assays(SEgenes)\$pValueAdjust
    
    write.csv(as.data.frame(pvals), file = "p_values.csv", row.names = TRUE)
    write.csv(as.data.frame(pvals_adj), file = "adjusted_p_values.csv", row.names = TRUE)
    
    # Generate and save diagnostic plot
    pdf("p_value_distribution.pdf", width = 8, height = 6)
    hist(
      pvals, 
      col = "skyblue", 
      border = "white", 
      main = "Distribution of Aberrant Expression p-values", 
      xlab = "p-value", 
      ylab = "Frequency"
    )
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_SASER_ABERRANT_EXPRESSION_ANALYSIS":',
        paste0('        saser: ', as.character(packageVersion("saser")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_aberrant_expression_analysis.csv versions.yml
    """
}

workflow BIOC_SASER_ABERRANT_EXPRESSION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BAMFiles, gtfFileName ] ]

    main:
    BIOC_SASER_ABERRANT_EXPRESSION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SASER_ABERRANT_EXPRESSION_ANALYSIS.out.tables
    plots    = BIOC_SASER_ABERRANT_EXPRESSION_ANALYSIS.out.plots
    objects  = BIOC_SASER_ABERRANT_EXPRESSION_ANALYSIS.out.objects
    versions = BIOC_SASER_ABERRANT_EXPRESSION_ANALYSIS.out.versions
}
