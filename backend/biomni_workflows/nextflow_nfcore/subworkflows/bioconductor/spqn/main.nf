#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spqn — spatial_quantile_normalization
// Filter and normalize gene expression data, compute the correlation matrix, diagnose mean-correlation bias, apply spatial quantile normalization (SpQN), and veri
// Input: gtex
// Container: quay.io/biocontainers/bioconductor-spqn:1.22.0--r45hdfd78af_0
// R packages: WGCNA, ggplot2, matrixStats, spqn, spqndata, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, ggplot2, matrixStats, spqn
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter genes by type and expression level
//  * 2. [Core Analysis] Normalize counts to log2RPKM and compute average expression
//  * 3. [Core Analysis] Center, scale, and remove principal components from the expression matrix
//  * 4. [Core Analysis] Compute the gene correlation matrix
//  * 5. [Visualization & Output] Diagnose mean-correlation bias using signal, IQR, and Q-Q plots
//  * 6. [Core Analysis] Normalize the correlation matrix using normalize_correlation
//  * 7. [Visualization & Output] Assess the normalized correlation matrix using the same diagnostic plots

nextflow.enable.dsl = 2

process BIOC_SPQN_SPATIAL_QUANTILE_NORMALIZATION {
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
    .bm_deps <- c("WGCNA", "ggplot2", "matrixStats", "spqn", "spqndata", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(spqn)
    library(SummarizedExperiment)
    library(matrixStats)
    library(WGCNA)
    library(ggplot2)
    
    # Read user input from the working directory
    if (file.exists("gtex.rds")) {
        gtex <- readRDS("gtex.rds")
    } else {
        stop("Required input file 'gtex.rds' not found in the working directory.")
    }
    
    # 1. Filter genes by type and expression level
    gtex <- gtex[rowData(gtex)\$gene_type %in% c("lincRNA", "protein_coding"), ]
    cSums <- colSums(assay(gtex))
    logrpkm <- sweep(log2(assay(gtex) + 0.5), 2, FUN = "-", STATS = log2(cSums / 10^6))
    logrpkm <- logrpkm - log2(rowData(gtex)\$gene_length / 1000)
    
    wh.expressed <- which(rowMedians(logrpkm) > 0)
    
    # To ensure the pipeline runs successfully and matches the vignette's design (4000 genes),
    # we subset to at most 4000 genes so that ngrp * size_grp (20 * 300 = 6000) is >= number of genes.
    if (length(wh.expressed) > 4000) {
        set.seed(123)
        wh.expressed <- sample(wh.expressed, 4000)
    }
    
    gtex.0pcs <- gtex[wh.expressed,]
    logrpkm.0pcs <- logrpkm[wh.expressed,]
    ave_logrpkm <- rowMeans(logrpkm.0pcs)
    
    # Align logrpkm dimensions to avoid subtraction mismatch
    logrpkm <- logrpkm[wh.expressed, ]
    logrpkm <- logrpkm - ave_logrpkm
    logrpkm  <- logrpkm / matrixStats::rowSds(logrpkm)
    
    assays(gtex.0pcs) <- SimpleList(logrpkm = logrpkm.0pcs)
    rowData(gtex.0pcs)\$ave_logrpkm <- ave_logrpkm
    
    # 2. Center, scale, and remove principal components from the expression matrix
    gtex.4pcs <- gtex.0pcs
    assay(gtex.4pcs) <- removePrincipalComponents(t(scale(t(logrpkm.0pcs))), n = 4)
    
    # Define gtex.4k to match the vignette's variable name
    gtex.4k <- gtex.4pcs
    
    # 3. Compute the gene correlation matrix
    cor_m <- cor(t(assay(gtex.4k)))
    ave_logrpkm <- rowData(gtex.4k)\$ave_logrpkm
    
    # Open PDF device to save all diagnostic plots
    pdf("spqn_diagnostic_plots.pdf", width = 11, height = 8.5)
    
    # 4. Diagnose mean-correlation bias (Before Correction)
    p1 <- plot_signal_condition_exp(cor_m, ave_logrpkm, signal=0)
    print(p1)
    
    p2 <- plot_signal_condition_exp(cor_m, ave_logrpkm, signal=0.001)
    print(p2)
    
    IQR_list <- get_IQR_condition_exp(cor_m, rowData(gtex.4k)\$ave_logrpkm)
    p3 <- plot_IQR_condition_exp(IQR_list)
    print(p3)
    
    IQR_unlist <- unlist(lapply(1:10, function(ii) IQR_list\$IQR_cor_mat[ii, ii:10]))
    plot(rep(IQR_list\$grp_mean, times = 1:10), IQR_unlist, xlab="min(average(log2RPKM))", ylab="IQR", cex.lab=1.5, cex.axis=1.2, col="blue", main="Before SpQN: IQR vs Expression")
    
    par(mfrow = c(3,3))
    for(j in c(1:8,10)){
        qqplot_condition_exp(cor_m, ave_logrpkm, j, j)
    }
    
    # 5. Normalize the correlation matrix using normalize_correlation (SpQN)
    cor_m_spqn <- normalize_correlation(cor_m, ave_exp=ave_logrpkm, ngrp=20, size_grp=300, ref_grp=18)
    
    # Reset layout for subsequent plots
    par(mfrow = c(1,1))
    
    # 6. Assess the normalized correlation matrix using the same diagnostic plots
    p4 <- plot_signal_condition_exp(cor_m_spqn, ave_logrpkm, signal=0)
    print(p4)
    
    p5 <- plot_signal_condition_exp(cor_m_spqn, ave_logrpkm, signal=0.001)
    print(p5)
    
    IQR_spqn_list <- get_IQR_condition_exp(cor_m_spqn, rowData(gtex.4k)\$ave_logrpkm)
    p6 <- plot_IQR_condition_exp(IQR_spqn_list)
    print(p6)
    
    par(mfrow = c(3,3))
    for(j in c(1:8,10)){
        qqplot_condition_exp(cor_m_spqn, ave_logrpkm, j, j)
    }
    
    par(mfrow = c(1,1))
    IQR_unlist_spqn <- unlist(lapply(1:10, function(ii) IQR_spqn_list\$IQR_cor_mat[ii, ii:10]))
    plot(rep(IQR_spqn_list\$grp_mean, times = 1:10), IQR_unlist_spqn, xlab="min(average(log2RPKM))", ylab="IQR", cex.lab=1.5, cex.axis=1.2, col="blue", main="After SpQN: IQR vs Expression")
    
    dev.off()
    
    # Save outputs to the working directory
    saveRDS(cor_m_spqn, "cor_m_spqn.rds")
    saveRDS(IQR_list, "IQR_list_before.rds")
    saveRDS(IQR_spqn_list, "IQR_list_after.rds")
    
    write.csv(data.frame(
        gene = rownames(gtex.4k),
        ave_logrpkm = ave_logrpkm
    ), "gene_expression_summary.csv", row.names = FALSE)
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_SPQN_SPATIAL_QUANTILE_NORMALIZATION":',
        paste0('    spqn: ', as.character(packageVersion('spqn')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_quantile_normalization.csv versions.yml
    """
}

workflow BIOC_SPQN_SPATIAL_QUANTILE_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gtex ] ]

    main:
    BIOC_SPQN_SPATIAL_QUANTILE_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_SPQN_SPATIAL_QUANTILE_NORMALIZATION.out.tables
    plots    = BIOC_SPQN_SPATIAL_QUANTILE_NORMALIZATION.out.plots
    objects  = BIOC_SPQN_SPATIAL_QUANTILE_NORMALIZATION.out.objects
    versions = BIOC_SPQN_SPATIAL_QUANTILE_NORMALIZATION.out.versions
}
