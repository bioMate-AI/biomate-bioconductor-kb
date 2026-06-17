#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fishpond — allelic_imbalance_seesaw
// Test for global, differential, or dynamic allelic imbalance using diploid-quantified Salmon bootstrap replicates.
// Input: coldata.csv, Diploid Salmon quantification directories
// Container: quay.io/biocontainers/bioconductor-fishpond:2.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EnsDb.Hsapiens.v86, SummarizedExperiment, dplyr, ensembldb, fishpond, plyranges
// Visualizations: plot (ggplot/base)
// QC: low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read user input coldata.csv
//  * 2. [Input & Preparation] Build transcript-to-TSS mapping using ensembldb
//  * 3. [Input & Preparation] Import allelic counts
//  * 4. [Input & Preparation] Filter out features with low expression or no allelic
//  * 5. [Input & Preparation] Run paired differential testing using Swish (skipping
//  * 6. [Input & Preparation] Generate Diagnostic and Results Plots

nextflow.enable.dsl = 2

process BIOC_FISHPOND_ALLELIC_IMBALANCE_SEESAW {
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
    .bm_deps <- c("ensembldb", "plyranges", "EnsDb.Hsapiens.v86", "fishpond", "dplyr", "SummarizedExperiment")
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
           library(SummarizedExperiment)
     library(ensembldb)
        library(plyranges)
        library(EnsDb.Hsapiens.v86)
        library(fishpond)
        library(dplyr)
        
        # Set random seed for reproducibility
        set.seed(1)
        
        # --- Read user input coldata.csv ---
        if (!file.exists("coldata.csv")) {
          stop("Error: 'coldata.csv' not found in the working directory.")
        }
        coldata <- read.csv("coldata.csv")
        
        # Ensure 'files' column exists and points to valid paths
        if (!"files" %in% colnames(coldata)) {
          if ("names" %in% colnames(coldata)) {
            coldata\$files <- file.path(coldata\$names, "quant.sf")
          } else if ("sample" %in% colnames(coldata)) {
            coldata\$files <- file.path(coldata\$sample, "quant.sf")
          } else {
            stop("Error: coldata.csv must contain a 'files' column pointing to the Salmon quantification files.")
          }
        }
        
        # Verify that the quantification files exist
        missing_files <- coldata\$files[!file.exists(coldata\$files)]
        if (length(missing_files) > 0) {
          warning(paste("The following quantification files were not found:", paste(missing_files, collapse = ", ")))
        }
        
        # --- Build transcript-to-TSS mapping using ensembldb ---
        edb <- EnsDb.Hsapiens.v86
        tx2gene <- makeTx2Tss(edb, maxgap=50) %>%
          select(tx_id, gene_id, group_id, tss)
        
        # --- Import allelic counts ---
        # We assume the alleles are labeled "alt" and "ref" as per the documented code.
        # If the user's coldata uses different names, they should match these arguments.
        y <- importAllelicCounts(
          coldata, a1="alt", a2="ref",
          format="wide", tx2gene=tx2gene
        )
        
        # --- Filter out features with low expression or no allelic ---
        # Standard Swish filtering:
        y <- labelKeep(y)
        y <- y[mcols(y)\$keep,]
        
        # Manual filtering for features with no allelic information (from SEESAW vignette):
        # Dynamically determine allele names from the imported object to prevent crashes
        allele_levels <- levels(y\$allele)
        if (is.null(allele_levels)) {
          allele_levels <- unique(y\$allele)
        }
        if (length(allele_levels) >= 2) {
          a1_name <- allele_levels[2] # typically the effect allele (alt)
          a2_name <- allele_levels[1] # typically the reference allele (ref)
        } else {
          a1_name <- "alt"
          a2_name <- "ref"
        }
        
        n <- ncol(y) / 2
        rep1a1 <- assay(y, "infRep1")[, y\$allele == a1_name]
        rep1a2 <- assay(y, "infRep1")[, y\$allele == a2_name]
        mcols(y)\$someInfo <- rowSums(abs(rep1a1 - rep1a2) < 1) < n
        y <- y[mcols(y)\$someInfo, ]
        
        # --- Run paired differential testing using Swish (skipping ---
        
        # Test A: Global Allelic Imbalance (always run)
        message("Running Global Allelic Imbalance test...")
        y_global <- swish(y, x="allele", pair="sample", fast=1)
        
        # Save Global AI results
        saveRDS(y_global, "y_global.rds")
        write.csv(as.data.frame(mcols(y_global)), "global_ai_results.csv", row.names=TRUE)
        
        # Test B: Differential Allelic Imbalance (run if 'condition' is in coldata)
        if ("condition" %in% colnames(coldata)) {
          message("Running Differential Allelic Imbalance test across conditions...")
          y_diff <- swish(y, x="allele", pair="sample",
                          cov="condition", interaction=TRUE)
          saveRDS(y_diff, "y_diff.rds")
          write.csv(as.data.frame(mcols(y_diff)), "diff_ai_results.csv", row.names=TRUE)
        } else {
          message("Skipping Differential Allelic Imbalance: 'condition' column not found in coldata.csv")
        }
        
        # Test C: Dynamic Allelic Imbalance (run if 'time' is in coldata)
        if ("time" %in% colnames(coldata)) {
          message("Running Dynamic Allelic Imbalance test across time...")
          y_dynamic <- swish(y, x="allele", pair="sample", cov="time", cor="pearson")
          saveRDS(y_dynamic, "y_dynamic.rds")
          write.csv(as.data.frame(mcols(y_dynamic)), "dynamic_ai_results.csv", row.names=TRUE)
        } else {
          message("Skipping Dynamic Allelic Imbalance: 'time' column not found in coldata.csv")
        }
        
        # --- Generate Diagnostic and Results Plots ---
        pdf("allelic_imbalance_plots.pdf", width=10, height=8)
        
        # Plot 1: P-value distribution for Global AI
        if (any(!is.na(mcols(y_global)\$pvalue))) {
          hist(mcols(y_global)\$pvalue, col="grey", main="Global AI P-value Distribution", xlab="p-value")
        }
        
        # Plot 2: MA Plot for Global AI
        plotMASwish(y_global, alpha=0.05, main="Global Allelic Imbalance MA Plot")
        
        # Plot 3: Top significant feature visualization (if any pass FDR)
        sig_idx <- which(mcols(y_global)\$qvalue < 0.05)
        if (length(sig_idx) > 0) {
          top_idx <- sig_idx[which.min(mcols(y_global)\$qvalue[sig_idx])]
          
          # Plot inferential replicates for the top feature
          plotInfReps(y_global, idx=top_idx, x="allele", cov="sample", 
                      main=paste("Top Global AI Feature:", rownames(y_global)[top_idx]))
          
          # Plot Allelic Heatmap for the gene containing the top feature
          top_gene <- mcols(y_global)\$gene_id[top_idx]
          if (!is.null(top_gene) && !is.na(top_gene)) {
            gene_features <- which(mcols(y_global)\$gene_id == top_gene)
            if (length(gene_features) > 0) {
              y_global <- computeInfRV(y_global)
              plotAllelicHeatmap(y_global, idx=gene_features, 
                                 main=paste("Allelic Heatmap for Gene:", top_gene))
            }
          }
        }
        
        dev.off()
        
        message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_FISHPOND_ALLELIC_IMBALANCE_SEESAW":',
        paste0('    fishpond: ', as.character(packageVersion('fishpond')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_allelic_imbalance_seesaw.csv versions.yml
    """
}

workflow BIOC_FISHPOND_ALLELIC_IMBALANCE_SEESAW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ coldata.csv, Diploid Salmon quantification directories ] ]

    main:
    BIOC_FISHPOND_ALLELIC_IMBALANCE_SEESAW(ch_input)

    emit:
    tables   = BIOC_FISHPOND_ALLELIC_IMBALANCE_SEESAW.out.tables
    plots    = BIOC_FISHPOND_ALLELIC_IMBALANCE_SEESAW.out.plots
    objects  = BIOC_FISHPOND_ALLELIC_IMBALANCE_SEESAW.out.objects
    versions = BIOC_FISHPOND_ALLELIC_IMBALANCE_SEESAW.out.versions
}
