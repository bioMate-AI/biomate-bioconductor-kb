#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scater — sc_rnaseq_qc_and_visualization
// Perform quality control, normalization, dimensionality reduction, and visualization of single-cell RNA-seq expression data.
// Input: example_sce
// Container: quay.io/biocontainers/bioconductor-scater:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, scater
// Visualizations: PCA plot, sample metadata plot, ordination plot, t-SNE plot, expression plot, highest-expression plot, scatter plot, box plot, density plot, violin plot
// QC: per-cell QC metrics, diagnostic MA/PCA QC, cell QC metrics, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute quality control metrics using addPerCellQC
//  * 2. [Visualization & Output] Visualize QC metrics using plotColData and plotHighestExprs
//  * 3. [Core Analysis] Normalize counts using logNormCounts
//  * 4. [Visualization & Output] Calculate and plot variance explained by experimental variables using getVarianceExplained and plotExplanatoryVariables
//  * 5. [Visualization & Output] Visualize gene expression profiles using plotExpression
//  * 6. [Core Analysis] Perform dimensionality reduction using runPCA, runTSNE, and runUMAP
//  * 7. [Visualization & Output] Visualize reduced dimensions using plotReducedDim, plotTSNE, and plotPCA
//  * 8. [Visualization & Output] Create custom plots using ggcells and ggfeatures

nextflow.enable.dsl = 2

process BIOC_SCATER_SC_RNASEQ_QC_AND_VISUALIZATION {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load required libraries
        library(scater)
        library(ggplot2)
        
        # Read the user input SingleCellExperiment object from the working directory
        if (file.exists("example_sce")) {
            example_sce <- readRDS("example_sce")
        } else if (file.exists("example_sce.rds")) {
            example_sce <- readRDS("example_sce.rds")
        } else {
            stop("Error: Input file 'example_sce' or 'example_sce.rds' not found in the working directory.")
        }
        
        # Extract generic names to avoid hardcoded metadata and feature names
        orig_meta_cols <- colnames(colData(example_sce))
        meta1 <- if (length(orig_meta_cols) > 0) orig_meta_cols[1] else "sum"
        meta2 <- if (length(orig_meta_cols) > 1) orig_meta_cols[2] else meta1
        meta_all <- if (length(orig_meta_cols) > 0) head(orig_meta_cols, 4) else c("sum", "detected")
        
        gene1 <- rownames(example_sce)[1]
        gene2 <- if (nrow(example_sce) >= 2) rownames(example_sce)[2] else gene1
        gene3 <- if (nrow(example_sce) >= 3) rownames(example_sce)[3] else gene1
        
        # 1. Compute quality control metrics using addPerCellQC
        example_sce <- addPerCellQC(example_sce, 
            subsets=list(Mito=grep("mt-", rownames(example_sce))))
        
        # 2. Visualize QC metrics using plotColData and plotHighestExprs
        pdf("plot_coldata_sum_detected.pdf")
        p1 <- plotColData(example_sce, x = "sum", y="detected", colour_by=meta1) 
        print(p1)
        dev.off()
        
        pdf("plot_coldata_mito_facet.pdf")
        p2 <- plotColData(example_sce, x = "sum", y="subsets_Mito_percent", 
            other_fields=meta1) + facet_wrap(as.formula(paste0("~`", meta1, "`")))
        print(p2)
        dev.off()
        
        pdf("plot_highest_exprs.pdf")
        p3 <- plotHighestExprs(example_sce, exprs_values = "counts")
        print(p3)
        dev.off()
        
        # 3. Normalize counts using logNormCounts
        example_sce <- logNormCounts(example_sce)
        
        # 4. Calculate and plot variance explained by experimental variables using getVarianceExplained and plotExplanatoryVariables
        tryCatch({
            vars <- getVarianceExplained(example_sce,
                variables=meta_all)
            write.csv(head(vars), "variance_explained_head.csv", row.names=TRUE)
            write.csv(vars, "variance_explained_all.csv", row.names=TRUE)
        
            pdf("plot_explanatory_variables.pdf")
            p4 <- plotExplanatoryVariables(vars)
            print(p4)
            dev.off()
        }, error = function(e) {
            warning("Skipping variance explained calculation: ", e\$message)
        })
        
        # 5. Visualize gene expression profiles using plotExpression
        tryCatch({
            pdf("plot_expression_level1class.pdf")
            p5 <- plotExpression(example_sce, rownames(example_sce)[1:6], x = meta1)
            print(p5)
            dev.off()
        }, error = function(e) { warning("plotExpression 1 failed: ", e\$message) })
        
        tryCatch({
            pdf("plot_expression_scatter.pdf")
            p6 <- plotExpression(example_sce, rownames(example_sce)[1:6],
                x = rownames(example_sce)[10])
            print(p6)
            dev.off()
        }, error = function(e) { warning("plotExpression 2 failed: ", e\$message) })
        
        tryCatch({
            pdf("plot_expression_colour_by_tissue.pdf")
            p7 <- plotExpression(example_sce, rownames(example_sce)[1:6],
                x = meta1, colour_by=meta2)
            print(p7)
            dev.off()
        }, error = function(e) { warning("plotExpression 3 failed: ", e\$message) })
        
        tryCatch({
            pdf("plot_expression_default.pdf")
            p8 <- plotExpression(example_sce, rownames(example_sce)[1:6])
            print(p8)
            dev.off()
        }, error = function(e) { warning("plotExpression 4 failed: ", e\$message) })
        
        # 6. Perform dimensionality reduction using runPCA, runTSNE, and runUMAP
        n_comps_default <- max(1, min(50, ncol(example_sce) - 1, nrow(example_sce) - 1))
        example_sce <- runPCA(example_sce, ncomponents=n_comps_default)
        pca_str <- capture.output(str(reducedDim(example_sce, "PCA")))
        writeLines(pca_str, "pca_structure.txt")
        
        n_genes <- min(1000, nrow(example_sce))
        n_comps25 <- max(1, min(25, ncol(example_sce) - 1, nrow(example_sce) - 1))
        example_sce <- runPCA(example_sce, name="PCA2",
            subset_row=rownames(example_sce)[1:n_genes],
            ncomponents=n_comps25)
        pca2_str <- capture.output(str(reducedDim(example_sce, "PCA2")))
        writeLines(pca2_str, "pca2_structure.txt")
        
        set.seed(1000)
        perp10 <- floor((ncol(example_sce) - 1) / 3)
        if (perp10 * 3 >= ncol(example_sce) - 1) perp10 <- perp10 - 1
        perp10 <- max(1, min(10, perp10))
        example_sce <- runTSNE(example_sce, perplexity=perp10)
        write.csv(head(reducedDim(example_sce, "TSNE")), "tsne_perplexity10_head.csv")
        
        set.seed(1000)
        perp50 <- floor((ncol(example_sce) - 1) / 3)
        if (perp50 * 3 >= ncol(example_sce) - 1) perp50 <- perp50 - 1
        perp50 <- max(1, min(50, perp50))
        n_dimred10 <- max(1, min(10, ncol(reducedDim(example_sce, "PCA"))))
        example_sce <- runTSNE(example_sce, perplexity=perp50, 
            dimred="PCA", n_dimred=n_dimred10)
        write.csv(head(reducedDim(example_sce, "TSNE")), "tsne_perplexity50_head.csv")
        
        example_sce <- runUMAP(example_sce)
        write.csv(head(reducedDim(example_sce, "UMAP")), "umap_head.csv")
        
        # 7. Visualize reduced dimensions using plotReducedDim, plotTSNE, and plotPCA
        tryCatch({
            pdf("plot_reduced_dim_pca.pdf")
            p9 <- plotReducedDim(example_sce, dimred = "PCA", colour_by = meta1)
            print(p9)
            dev.off()
        }, error = function(e) { warning("plotReducedDim failed: ", e\$message) })
        
        tryCatch({
            pdf("plot_tsne_snap25.pdf")
            p10 <- plotTSNE(example_sce, colour_by = gene1)
            print(p10)
            dev.off()
        }, error = function(e) { warning("plotTSNE failed: ", e\$message) })
        
        tryCatch({
            pdf("plot_pca_mog.pdf")
            p11 <- plotPCA(example_sce, colour_by=gene2)
            print(p11)
            dev.off()
        }, error = function(e) { warning("plotPCA Mog failed: ", e\$message) })
        
        n_comps20 <- max(1, min(20, ncol(example_sce) - 1, nrow(example_sce) - 1))
        example_sce <- runPCA(example_sce, ncomponents=n_comps20)
        
        tryCatch({
            pdf("plot_pca_4comp.pdf")
            p12 <- plotPCA(example_sce, ncomponents = min(4, n_comps20), colour_by = meta1)
            print(p12)
            dev.off()
        }, error = function(e) { warning("plotPCA 4comp failed: ", e\$message) })
        
        # 8. Create custom plots using ggcells and ggfeatures
        tryCatch({
            pdf("ggcells_boxplot_snap25.pdf")
            p13 <- ggcells(example_sce, mapping=aes(x=.data[[meta1]], y=.data[[gene1]])) + 
                geom_boxplot() +
                facet_wrap(as.formula(paste0("~`", meta2, "`")))
            print(p13)
            dev.off()
        }, error = function(e) { warning("ggcells boxplot failed: ", e\$message) })
        
        tryCatch({
            pdf("ggcells_tsne_density.pdf")
            p14 <- ggcells(example_sce, mapping=aes(x=TSNE.1, y=TSNE.2, colour=.data[[gene1]])) +
                geom_point() +
                stat_density_2d() +
                facet_wrap(as.formula(paste0("~`", meta2, "`"))) +
                scale_colour_distiller(direction=1)
            print(p14)
            dev.off()
        }, error = function(e) { warning("ggcells tsne density failed: ", e\$message) })
        
        tryCatch({
            pdf("ggcells_smooth_actb.pdf")
            p15 <- ggcells(example_sce, mapping=aes(x=sizeFactor, y=.data[[gene3]])) +
                geom_point() +
                geom_smooth()
            print(p15)
            dev.off()
        }, error = function(e) { warning("ggcells smooth failed: ", e\$message) })
        
        colnames(example_sce) <- make.names(colnames(example_sce))
        cell1 <- colnames(example_sce)[1]
        row_meta_cols <- colnames(rowData(example_sce))
        
        tryCatch({
            pdf("ggfeatures_violin.pdf")
            if (length(row_meta_cols) > 0) {
                row_meta1 <- row_meta_cols[1]
                p16 <- ggfeatures(example_sce, mapping=aes(x=.data[[row_meta1]], y=.data[[cell1]])) + 
                    geom_violin()
            } else {
                p16 <- ggfeatures(example_sce, mapping=aes(x="All", y=.data[[cell1]])) + 
                    geom_violin()
            }
            print(p16)
            dev.off()
        }, error = function(e) { warning("ggfeatures violin failed: ", e\$message) })
        
        # Save the final processed SingleCellExperiment object
        saveRDS(example_sce, "processed_example_sce.rds")
        
        # Output session info
        writeLines(capture.output(sessionInfo()), "session_info.txt")

    writeLines(c(
        '"BIOC_SCATER_SC_RNASEQ_QC_AND_VISUALIZATION":',
        paste0('    scater: ', as.character(packageVersion('scater')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sc_rnaseq_qc_and_visualization.csv versions.yml
    """
}

workflow BIOC_SCATER_SC_RNASEQ_QC_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example_sce ] ]

    main:
    BIOC_SCATER_SC_RNASEQ_QC_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_SCATER_SC_RNASEQ_QC_AND_VISUALIZATION.out.tables
    plots    = BIOC_SCATER_SC_RNASEQ_QC_AND_VISUALIZATION.out.plots
    objects  = BIOC_SCATER_SC_RNASEQ_QC_AND_VISUALIZATION.out.objects
    versions = BIOC_SCATER_SC_RNASEQ_QC_AND_VISUALIZATION.out.versions
}
