#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: zitools — zero_inflated_metagenomics_analysis
// Fit a zero-inflated mixture model to metagenomic count data, perform differential abundance testing with DESeq2, and conduct diversity and dimensionality reduct
// Input: phyloseq
// Container: quay.io/biocontainers/bioconductor-zitools:1.4.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, matrixStats, microbiome, phyloseq, tidyverse, zitools
// Visualizations: box plot, alpha diversity plot
// QC: prevalence/abundance filtering, missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Input
//  * 2. [Visualization & Output] Fit Zero-Inflated Mixture Model
//  * 3. [Visualization & Output] Visualizations & Resampling
//  * 4. [Visualization & Output] Differential Abundance Analysis with DESeq2
//  * 5. [Visualization & Output] Missing Value Heatmap
//  * 6. [Visualization & Output] Principal Component Analysis (PCA)
//  * 7. [Visualization & Output] Downstream Phyloseq Analysis

nextflow.enable.dsl = 2

process BIOC_ZITOOLS_ZERO_INFLATED_METAGENOMICS_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    .bm_deps <- c("zitools", "phyloseq", "DESeq2", "tidyverse", "microbiome", "matrixStats")
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
    library(zitools)
    library(phyloseq)
    library(DESeq2)
    library(tidyverse)
    library(microbiome)
    library(matrixStats)
    
    # ----------------------------------------------------------------------
    # --- Read User Input ---
    # ----------------------------------------------------------------------
    if (file.exists("phyloseq")) {
        phyloseq <- readRDS("phyloseq")
    } else if (file.exists("phyloseq.rds")) {
        phyloseq <- readRDS("phyloseq.rds")
    } else {
        stop("Input file 'phyloseq' or 'phyloseq.rds' not found in the working directory.")
    }
    
    # Ensure the time variable is a factor as required by the workflow
    if (!is.null(sample_data(phyloseq)\$time)) {
        sample_data(phyloseq)\$time <- factor(sample_data(phyloseq)\$time)
    } else {
        stop("The input phyloseq object must contain a 'time' variable in its sample_data.")
    }
    
    # ----------------------------------------------------------------------
    # --- Fit Zero-Inflated Mixture Model ---
    # ----------------------------------------------------------------------
    Zi <- ziMain(phyloseq)
    print(Zi)
    
    # Calculate basic statistics
    sink("basic_statistics.txt")
    cat("Mean:\n")
    print(mean(Zi))
    cat("\nSD:\n")
    print(sd(Zi))
    cat("\nVar:\n")
    print(var(Zi))
    cat("\nMedian:\n")
    print(median(Zi))
    cat("\nQuantile:\n")
    print(quantile(Zi))
    sink()
    
    # ----------------------------------------------------------------------
    # --- Visualizations & Resampling ---
    # ----------------------------------------------------------------------
    pdf("diagnostic_plots.pdf", width = 10, height = 8)
    
    # Boxplots comparing ZI considered vs not considered
    boxplot(log2p(Zi), xlab = "samples", ylab = "log2(count+1)", 
            main = "ZI considered")
    boxplot(log2p(inputcounts(Zi)), xlab = "samples", ylab = "log2(count+1)", 
            main = "ZI not considered")
    
    # Resampling loop
    i <- 1
    repeat {
        Zi <- resample_deinflatedcounts(Zi)
        boxplot(log2p(Zi), xlab = "samples", ylab = "log2(count+1)", 
            main = paste("Iteration", i))
        i = i+1
        if(i==6){
            break
        }
    } 
    
    # ----------------------------------------------------------------------
    # --- Differential Abundance Analysis with DESeq2 ---
    # ----------------------------------------------------------------------
    DDS <- zi2deseq2(Zi, ~time)
    
    # Robustly handle releveling in case the reference level "1" is absent
    tryCatch({
        DDS\$Subject <- relevel(DDS\$time, ref = "1")
    }, error = function(e) {
        warning("Could not relevel DDS\$time with ref = '1'. Proceeding with default levels.")
        DDS\$Subject <- DDS\$time
    })
    
    DDS <- DESeq(DDS, test = "Wald", fitType = "local", sfType = "poscounts")
    
    result <- results(DDS, cooksCutoff = FALSE)
    result <- as.data.frame(result)
    write.csv(result, "deseq2_results.csv", row.names = TRUE)
    
    # Volcano Plot Data Preparation
    result_df <- cbind(as(result, "data.frame"), 
        as(tax_table(phyloseq)[rownames(result), ], "matrix"))
    result_df <- result_df %>%
        rownames_to_column(var = "OTU") %>%
        arrange(padj)
    
    # Drop the rows with NA
    result_df <- result_df[complete.cases(result_df), ]
    
    # Initialize diffexpressed column safely
    result_df\$diffexpressed <- NA
    if (nrow(result_df) > 0 && "Genus" %in% colnames(result_df)) {
        up_regulated <- result_df\$log2FoldChange > 1 & result_df\$pvalue < 0.05
        down_regulated <- result_df\$log2FoldChange < -1 & result_df\$pvalue < 0.05
        
        result_df\$diffexpressed[up_regulated] <- as.character(result_df\$Genus[up_regulated])
        result_df\$diffexpressed[down_regulated] <- as.character(result_df\$Genus[down_regulated])
    }
    
    result_df <- data.frame("OTU" = result_df\$OTU, 
        "log2FoldChange" = result_df\$log2FoldChange, 
        "pvalue" = result_df\$pvalue, 
        "Genus" = result_df\$diffexpressed)
    
    # Plot Volcano Plot
    if (nrow(result_df) > 0) {
        print(ggplot(data=result_df, aes(x=log2FoldChange, 
            y=-log10(pvalue), 
            color = Genus)) +
            geom_point()+
            theme_minimal()+
            ylab("-log10(pvalue)\n")+
            xlab("\nLog2FoldChange")+
            geom_vline(xintercept=c(-1, 1), col="black") +
            geom_hline(yintercept=-log10(0.05), col="black")+
            theme(text = element_text(size = 20))+
            theme(panel.spacing.x = unit(2, "lines")))
    }
    
    # ----------------------------------------------------------------------
    # --- Missing Value Heatmap ---
    # ----------------------------------------------------------------------
    Zi2 <- Zi
    mat <- deinflatedcounts(Zi2)
    mat[mat > 500] <- 500
    deinflatedcounts(Zi2) <- mat
    
    MissingValueHeatmap(Zi2, xlab = "Sample")
    
    # ----------------------------------------------------------------------
    # --- Principal Component Analysis (PCA) ---
    # ----------------------------------------------------------------------
    PCA <- princomp(covmat = cor(t(Zi)), cor = FALSE)
    centered_data <- (inputcounts(t(Zi))-colMeans2(t(Zi)))/sqrt(colVars(t(Zi)))
    loadings <- PCA\$loadings
    scores <- centered_data %*% loadings
    PCA\$scores <- scores
    
    pc1_var <- round(PCA\$sdev[1]^2 / sum(PCA\$sdev^2) * 100, 1)
    pc2_var <- round(PCA\$sdev[2]^2 / sum(PCA\$sdev^2) * 100, 1)
    
    df_PCA <- data.frame("PC1" = PCA[["scores"]][,1], "PC2" = PCA[["scores"]][,2], 
        "time" = sample_data(Zi)\$time)
    
    print(ggplot(df_PCA, aes(x = PC1, y = PC2, color = time))+
        geom_point()+
        xlab(paste0("PC1 ", pc1_var, "%"))+
        ylab(paste0("PC2 ", pc2_var, "%")))
    
    # ----------------------------------------------------------------------
    # --- Downstream Phyloseq Analysis ---
    # ----------------------------------------------------------------------
    new_phyloseq <- zi2phyloseq(Zi)
    saveRDS(new_phyloseq, "new_phyloseq.rds")
    
    # Print structure of the new phyloseq object
    sink("new_phyloseq_structure.txt")
    str(otu_table(new_phyloseq), max.level = 3)
    sink()
    
    # Subset and Heatmap
    if (!is.null(tax_table(new_phyloseq, errorIfNULL = FALSE))) {
        tax_mat <- as(tax_table(new_phyloseq), "matrix")
        if ("Phylum" %in% colnames(tax_mat)) {
            keep_taxa <- rownames(tax_mat)[which(tax_mat[, "Phylum"] == "Firmicutes")]
            subset <- prune_taxa(keep_taxa, new_phyloseq)
        } else {
            subset <- new_phyloseq
            warning("Rank 'Phylum' not found in taxonomy table. Using all taxa.")
        }
    } else {
        subset <- new_phyloseq
    }
    
    if (ntaxa(subset) > 0) {
        n_taxa <- min(300, ntaxa(subset))
        subset <- prune_taxa(names(sort(taxa_sums(subset), TRUE)[1:n_taxa]), subset)
        print(plot_heatmap(subset))
    } else {
        warning("No taxa found for heatmap. Skipping heatmap.")
    }
    
    # Richness Plot
    print(plot_richness(new_phyloseq, measures = c("Chao1"), 
        color = "time")+
        theme(axis.text.x = element_blank()))
    
    dev.off()

    writeLines(c(
        '"BIOC_ZITOOLS_ZERO_INFLATED_METAGENOMICS_ANALYSIS":',
        paste0('    zitools: ', as.character(packageVersion('zitools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_zero_inflated_metagenomics_analysis.csv versions.yml
    """
}

workflow BIOC_ZITOOLS_ZERO_INFLATED_METAGENOMICS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ phyloseq ] ]

    main:
    BIOC_ZITOOLS_ZERO_INFLATED_METAGENOMICS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ZITOOLS_ZERO_INFLATED_METAGENOMICS_ANALYSIS.out.tables
    plots    = BIOC_ZITOOLS_ZERO_INFLATED_METAGENOMICS_ANALYSIS.out.plots
    objects  = BIOC_ZITOOLS_ZERO_INFLATED_METAGENOMICS_ANALYSIS.out.objects
    versions = BIOC_ZITOOLS_ZERO_INFLATED_METAGENOMICS_ANALYSIS.out.versions
}
