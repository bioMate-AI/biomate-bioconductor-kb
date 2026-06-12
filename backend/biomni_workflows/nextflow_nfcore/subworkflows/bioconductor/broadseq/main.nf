#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: broadSeq — rnaseq_analysis_and_comparison
// Perform a complete RNA-seq analysis workflow including normalization, transformation, QC visualization, and comparative differential expression analysis using m
// Input: expression_data.rds
// Container: quay.io/biocontainers/bioconductor-broadseq:1.0.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, broadSeq, dplyr, ggplot2, ggpubr
// Visualizations: plot (ggplot/base)
// QC: low-count filtering, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and filter low-expression genes
//  * 2. [Core Analysis] Normalize counts (CPM, TMM) using normalizeEdgerCPM
//  * 3. [Core Analysis] Transform counts (VST, normTransform) using transformDESeq2
//  * 4. [Visualization & Output] Visualize sample assays and gene expression using sampleAssay_plot, assay_plot, and genes_plot
//  * 5. [Visualization & Output] Perform QC clustering (MDS, Heatmap, PCA) using plot_MDS, plotHeatmapCluster, prcompTidy, plotAnyPC, and biplotAnyPC
//  * 6. [Core Analysis] Perform single-method differential expression using use_NOIseq
//  * 7. [Visualization & Output] Perform multi-method differential expression comparison using use_multDE and visualize results using volcanoPlot

nextflow.enable.dsl = 2

process BIOC_BROADSEQ_RNASEQ_ANALYSIS_AND_COMPARISON {
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
    .bm_deps <- c("broadSeq", "ggplot2", "ggpubr", "dplyr")
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
        library(broadSeq)
        library(ggplot2)
        library(ggpubr)
        library(dplyr)
        
        # ==========================================
        # 1. Load and filter low-expression genes
        # ==========================================
        
        # Read the user-provided expression data
        if (!file.exists("expression_data.rds")) {
          stop("Error: 'expression_data.rds' not found in the working directory.")
        }
        se <- readRDS("expression_data.rds")
        
        # Dynamically determine metadata columns to avoid hardcoding
        col_names <- colnames(colData(se))
        if (length(col_names) == 0) stop("Error: No colData found in SummarizedExperiment.")
        group_col <- col_names[1]
        color_col <- if (length(col_names) > 1) col_names[2] else col_names[1]
        
        row_names <- colnames(rowData(se))
        if (length(row_names) == 0) stop("Error: No rowData found in SummarizedExperiment.")
        symbol_col <- if ("symbol" %in% row_names) "symbol" else row_names[1]
        class_col <- if ("Class" %in% row_names) "Class" else if (length(row_names) > 1) row_names[2] else row_names[1]
        biotype_col <- if ("gene_biotype" %in% row_names) "gene_biotype" else if (length(row_names) > 2) row_names[3] else row_names[1]
        
        # Set factor levels for the primary grouping column
        se[[group_col]] <- as.factor(se[[group_col]])
        
        # Get gene symbols for plotting
        gene_symbols <- head(rownames(se), 2)
        gene1 <- gene_symbols[1]
        gene2 <- if (length(gene_symbols) > 1) gene_symbols[2] else gene_symbols[1]
        
        # Filter out low expression genes
        keep <- (assays(se)[["counts"]] >= 3) %>% rowSums() >= 5
        se <- se[keep, ]
        
        # ==========================================
        # 2. Normalize counts (CPM, TMM)
        # ==========================================
        
        se <- broadSeq::normalizeEdgerCPM(se, method = "none", cpm.log = TRUE)
        se <- broadSeq::normalizeEdgerCPM(se, method = "TMM", cpm.log = FALSE)
        
        # ==========================================
        # 3. Transform counts (VST, normTransform)
        # ==========================================
        
        se <- broadSeq::transformDESeq2(se, method = "vst")
        se <- broadSeq::transformDESeq2(se, method = "normTransform")
        
        # Save the normalized and transformed SummarizedExperiment object
        saveRDS(se, "normalized_transformed_se.rds")
        
        # ==========================================
        # 4. Visualize sample assays and gene expression
        # ==========================================
        
        # Open PDF device to save all plots
        pdf("broadSeq_qc_and_expression_plots.pdf", width = 11, height = 8.5)
        
        # Determine subset for plotting
        if (length(col_names) > 1) {
          subset_val <- unique(as.character(se[[color_col]]))[1]
          se_plot <- se[, se[[color_col]] == subset_val]
        } else {
          se_plot <- se
        }
        
        # Sample assay plots
        p <- broadSeq::sampleAssay_plot(se_plot, assayName = "counts", fill = group_col, yscale = "log2") + ggpubr::rremove("x.text")
        p1 <- broadSeq::sampleAssay_plot(se_plot, assayName = "vst", fill = group_col) + ggpubr::rremove("x.text")
        p2 <- broadSeq::sampleAssay_plot(se_plot, assayName = "TMM", fill = group_col, yscale = "log10") + ggpubr::rremove("x.text")
        p3 <- broadSeq::sampleAssay_plot(se_plot, assayName = "logCPM", fill = group_col) + ggpubr::rremove("x.text")
        
        p_arrange <- ggpubr::ggarrange(p, p1, p2, p3, common.legend = TRUE, labels = c("A", "B", "C"))
        print(p_arrange)
        
        # Multiple assay plot of a single gene
        p_assay <- broadSeq::assay_plot(se, feature = c(gene1), assayNames = c("counts", "logCPM", "vst", "TMM"), x = group_col, fill = color_col, add = "dotplot", palette = "npg")
        print(p_assay)
        
        # Expression of multiple genes from a single assay
        p_genes <- broadSeq::genes_plot(se, features = c(gene1, gene2), facet.by = symbol_col, x = group_col, assayName = "vst", color = color_col, palette = "jco")
        print(p_genes)
        
        # ==========================================
        # 5. Perform QC clustering (MDS, Heatmap, PCA)
        # ==========================================
        
        # MDS Plot
        p_mds <- broadSeq::plot_MDS(se, scaledAssay = "vst", ntop = 500, color = color_col, shape = group_col, ellipse = TRUE, legend = "bottom")
        print(p_mds)
        
        # Hierarchical clustering and Heatmap
        p_vst <- broadSeq::plotHeatmapCluster(
          se, 
          scaledAssay = "vst", 
          annotation_col = unique(c(color_col, group_col)), 
          annotation_row = unique(c(class_col, biotype_col)), 
          ntop = 30, 
          show_geneAs = symbol_col, 
          cluster_cols = TRUE, 
          cluster_rows = FALSE, 
          show_rownames = TRUE, 
          show_colnames = FALSE, 
          main = "Top 30 variable gene vst"
        )
        print(p_vst)
        
        # PCA Analysis
        computedPCA_logCPM <- broadSeq::prcompTidy(se, scaledAssay = "logCPM", ntop = 500)
        computedPCA_vst <- broadSeq::prcompTidy(se, scaledAssay = "vst", ntop = 500)
        
        # Plot PCA
        p_pca_logcpm <- broadSeq::plotAnyPC(computedPCA = computedPCA_logCPM, x = 1, y = 2, color = color_col, shape = group_col, legend = "bottom")
        print(p_pca_logcpm)
        
        pca_vst_2_3 <- broadSeq::plotAnyPC(computedPCA = computedPCA_vst, x = 2, y = 3, color = color_col, shape = group_col, legend = "bottom")
        print(pca_vst_2_3)
        
        # Get Feature Loadings and save to CSV
        loadings_df <- computedPCA_vst %>% broadSeq::getFeatureLoadRanking(keep = unique(c(symbol_col, class_col)))
        write.csv(loadings_df, "pca_vst_loadings.csv", row.names = FALSE)
        
        # Biplot
        pca_vst_bi <- broadSeq::biplotAnyPC(computedPCA = computedPCA_vst, x = 1, y = 2, genesLabel = symbol_col, color = color_col, shape = group_col, legend = "bottom")
        print(pca_vst_bi)
        
        # ==========================================
        # 6. Perform single-method differential expression
        # ==========================================
        
        # Subset for differential expression comparison
        if (length(col_names) > 1) {
          subset_val <- unique(as.character(se[[color_col]]))[1]
          se_de <- se[, se[[color_col]] == subset_val]
          if (length(unique(as.character(se_de[[group_col]]))) < 2) {
            se_de <- se
          }
        } else {
          se_de <- se
        }
        
        group_levels <- unique(as.character(se_de[[group_col]]))
        if (length(group_levels) < 2) {
          stop("Error: Not enough levels in the grouping column for differential expression.")
        }
        control_level <- group_levels[1]
        treatment_level <- group_levels[2]
        
        # Run NOISeq
        result_Noiseq <- broadSeq::use_NOIseq(se = se_de, colData_id = group_col, control = control_level, treatment = treatment_level, rank = TRUE, r = 10)
        write.csv(result_Noiseq, "de_noiseq_results.csv")
        
        # ==========================================
        # 7. Perform multi-method differential expression comparison
        # ==========================================
        
        # Define named list of DE functions
        funs <- list(
          limma_trend = broadSeq::use_limma_trend, 
          limma_voom = broadSeq::use_limma_voom, 
          edgeR_exact = broadSeq::use_edgeR_exact, 
          edgeR_glm = broadSeq::use_edgeR_GLM, 
          deseq2 = broadSeq::use_deseq2, 
          DELocal = broadSeq::use_DELocal, 
          noiseq = broadSeq::use_NOIseq, 
          EBSeq = broadSeq::use_EBSeq
        ) 
        
        # Run multi-method DE analysis
        multi_result <- broadSeq::use_multDE(
          se = se_de, 
          deFun_list = funs, 
          return.df = TRUE, 
          colData_id = group_col, 
          control = control_level, 
          treatment = treatment_level, 
          rank = TRUE
        )
        write.csv(multi_result, "de_multi_method_results.csv", row.names = TRUE)
        
        # Cluster DE methods based on gene rankings
        clusters <- multi_result %>% dplyr::select(ends_with("rank")) %>% t() %>% dist() %>% hclust()
        plot(clusters, main = "distance: Euclidean")
        
        # Volcano Plot of multi-method results (using DESeq2 statistics)
        p_volcano <- multi_result %>% broadSeq::volcanoPlot(
          pValName = "deseq2_padj", 
          lFCName = "deseq2_log2FoldChange", 
          labelName = symbol_col, 
          palette = "lancet", 
          selectedLabel = multi_result %>% dplyr::arrange(deseq2_padj) %>% .[[symbol_col]] %>% head()
        )
        print(p_volcano)
        
        # Close PDF device
        dev.off()
        
        message("Pipeline completed successfully. Outputs generated:
        - normalized_transformed_se.rds
        - broadSeq_qc_and_expression_plots.pdf
        - pca_vst_loadings.csv
        - de_noiseq_results.csv
        - de_multi_method_results.csv")

    writeLines(c(
        '"BIOC_BROADSEQ_RNASEQ_ANALYSIS_AND_COMPARISON":',
        paste0('    broadSeq: ', as.character(packageVersion('broadSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnaseq_analysis_and_comparison.csv versions.yml
    """
}

workflow BIOC_BROADSEQ_RNASEQ_ANALYSIS_AND_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.rds ] ]

    main:
    BIOC_BROADSEQ_RNASEQ_ANALYSIS_AND_COMPARISON(ch_input)

    emit:
    tables   = BIOC_BROADSEQ_RNASEQ_ANALYSIS_AND_COMPARISON.out.tables
    plots    = BIOC_BROADSEQ_RNASEQ_ANALYSIS_AND_COMPARISON.out.plots
    objects  = BIOC_BROADSEQ_RNASEQ_ANALYSIS_AND_COMPARISON.out.objects
    versions = BIOC_BROADSEQ_RNASEQ_ANALYSIS_AND_COMPARISON.out.versions
}
