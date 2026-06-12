#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MCbiclust — single_bicluster_analysis
// Find and analyze a single bicluster from a gene expression matrix using a specific gene set of interest.
// Input: CCLE_small, Mitochondrial_genes
// Container: quay.io/biocontainers/bioconductor-mcbiclust:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MCbiclust, dplyr, ggplot2, gplots
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Subset gene expression matrix to the gene set of interest
//  * 2. [Core Analysis] Find a bicluster seed using FindSeed
//  * 3. [Core Analysis] Select highly correlated genes using HclustGenesHiCor
//  * 4. [Core Analysis] Calculate the correlation vector using CVEval
//  * 5. [Core Analysis] Perform gene set enrichment analysis using GOEnrichmentAnalysis
//  * 6. [Core Analysis] Sort samples using SampleSort
//  * 7. [Core Analysis] Calculate PC1 values using PC1VecFun
//  * 8. [Core Analysis] Threshold the bicluster using ThresholdBic and align PC1 using PC1Align
//  * 9. [Core Analysis] Classify samples using ForkClassifier

nextflow.enable.dsl = 2

process BIOC_MCBICLUST_SINGLE_BICLUSTER_ANALYSIS {
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
    .bm_deps <- c("MCbiclust", "ggplot2", "gplots", "dplyr", "MASS")
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
    library(MCbiclust)
    library(ggplot2)
    library(gplots)
    library(dplyr)
    library(MASS)
    
    # -----------------------------------------------------------------------------
    # Stage 0: Read User Input Files
    # -----------------------------------------------------------------------------
    
    # Robustly read CCLE_small (gene expression matrix)
    if (file.exists("CCLE_small.rds")) {
      CCLE_small <- readRDS("CCLE_small.rds")
    } else if (file.exists("CCLE_small")) {
      CCLE_small <- readRDS("CCLE_small")
    } else {
      stop("Error: CCLE_small file not found in the working directory.")
    }
    
    # Robustly read Mitochondrial_genes (character vector of gene names of interest)
    if (file.exists("Mitochondrial_genes.rds")) {
      Mitochondrial_genes <- readRDS("Mitochondrial_genes.rds")
    } else if (file.exists("Mitochondrial_genes")) {
      Mitochondrial_genes <- readRDS("Mitochondrial_genes")
    } else {
      stop("Error: Mitochondrial_genes file not found in the working directory.")
    }
    
    # Ensure CCLE_small is a matrix
    CCLE_small <- as.matrix(CCLE_small)
    
    # -----------------------------------------------------------------------------
    # Stage 1: Subset gene expression matrix to the gene set of interest
    # -----------------------------------------------------------------------------
    mito.loc <- which(row.names(CCLE_small) %in% Mitochondrial_genes)
    CCLE.mito <- CCLE_small[mito.loc,]
    
    # -----------------------------------------------------------------------------
    # Stage 2: Find a bicluster seed using FindSeed
    # -----------------------------------------------------------------------------
    set.seed(102)
    CCLE.seed <- FindSeed(gem = CCLE.mito,
                          seed.size = 10,
                          iterations = 10000,
                          messages = 1000)
    
    # -----------------------------------------------------------------------------
    # Stage 3: Select highly correlated genes using HclustGenesHiCor
    # -----------------------------------------------------------------------------
    CCLE.hicor.genes <- as.numeric(HclustGenesHiCor(CCLE.mito,
                                                    CCLE.seed,
                                                    cuts = 8))
    
    # -----------------------------------------------------------------------------
    # Stage 4: Calculate the correlation vector using CVEval
    # -----------------------------------------------------------------------------
    CCLE.cor.vec <- CVEval(gem.part = CCLE.mito,
                            gem.all = CCLE_small,
                            seed = CCLE.seed, splits = 10)
    
    # -----------------------------------------------------------------------------
    # Stage 5: Perform gene set enrichment analysis using GOEnrichmentAnalysis
    # -----------------------------------------------------------------------------
    GSE.MW <- GOEnrichmentAnalysis(gene.names = row.names(CCLE_small),
                                   gene.values = CCLE.cor.vec,
                                   sig.rate = 0.05)
    
    # Save GO Enrichment results
    write.csv(GSE.MW, file = "GSE_MW_results.csv", row.names = FALSE)
    
    # -----------------------------------------------------------------------------
    # Stage 6: Sort samples using SampleSort
    # -----------------------------------------------------------------------------
    CCLE.samp.sort <- SampleSort(CCLE.mito[as.numeric(CCLE.hicor.genes),],
                                 seed = CCLE.seed)
    
    # -----------------------------------------------------------------------------
    # Stage 7: Calculate PC1 values using PC1VecFun
    # -----------------------------------------------------------------------------
    top.mat <- CCLE.mito[as.numeric(CCLE.hicor.genes),]
    pc1.vec <- PC1VecFun(top.gem = top.mat,
                         seed.sort = CCLE.samp.sort, n = 10)
    
    # -----------------------------------------------------------------------------
    # Stage 8: Threshold the bicluster using ThresholdBic and align PC1 using PC1Align
    # -----------------------------------------------------------------------------
    CCLE.bic <- ThresholdBic(cor.vec = CCLE.cor.vec,
                             sort.order = CCLE.samp.sort,
                             pc1 = pc1.vec, samp.sig = 0.05)
    
    pc1.vec <- PC1Align(gem = CCLE_small, pc1 = pc1.vec,
                        sort.order = CCLE.samp.sort,
                        cor.vec = CCLE.cor.vec, bic = CCLE.bic)
    
    # Save thresholded bicluster object
    saveRDS(CCLE.bic, file = "CCLE_bic_thresholds.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 9: Classify samples using ForkClassifier and Plot Results
    # -----------------------------------------------------------------------------
    fork.status <- ForkClassifier(pc1.vec, samp.num = length(CCLE.bic[[2]]))
    
    # Create a summary data frame of the sorted samples and their classifications
    CCLE.names <- colnames(CCLE_small)[CCLE.samp.sort]
    CCLE.df <- data.frame(CCLE.name = CCLE.names,
                          PC1 = pc1.vec,
                          Fork = fork.status,
                          Order = seq_along(pc1.vec))
    
    # Save classification table
    write.csv(CCLE.df, file = "fork_classification.csv", row.names = FALSE)
    
    # Generate and save the Fork Plot
    p <- ggplot(CCLE.df, aes(Order, PC1)) +
      geom_point(aes(colour = Fork)) +
      ylab("PC1") +
      ggtitle("Sample Ordering and Fork Classification") +
      theme_minimal()
    
    ggsave("fork_plot.pdf", plot = p, width = 7, height = 5)

    writeLines(c(
        '"BIOC_MCBICLUST_SINGLE_BICLUSTER_ANALYSIS":',
        paste0('    MCbiclust: ', as.character(packageVersion('MCbiclust')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_bicluster_analysis.csv versions.yml
    """
}

workflow BIOC_MCBICLUST_SINGLE_BICLUSTER_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CCLE_small, Mitochondrial_genes ] ]

    main:
    BIOC_MCBICLUST_SINGLE_BICLUSTER_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MCBICLUST_SINGLE_BICLUSTER_ANALYSIS.out.tables
    plots    = BIOC_MCBICLUST_SINGLE_BICLUSTER_ANALYSIS.out.plots
    objects  = BIOC_MCBICLUST_SINGLE_BICLUSTER_ANALYSIS.out.objects
    versions = BIOC_MCBICLUST_SINGLE_BICLUSTER_ANALYSIS.out.versions
}
