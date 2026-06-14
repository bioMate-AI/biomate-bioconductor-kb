#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: aggregateBioVar — pseudobulk_aggregation_and_dge
// Aggregate single-cell RNA-seq counts by subject and cell type to perform subject-level pseudo-bulk differential gene expression analysis.
// Input: small_airway
// Container: quay.io/biocontainers/bioconductor-aggregatebiovar:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, RColorBrewer, SingleCellExperiment, SummarizedExperiment, aggregateBioVar, cowplot, dplyr, ggplot2, ggtext, magrittr, pheatmap, viridis
// Visualizations: heatmap, volcano plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Aggregate gene counts within subjects using countsBySubject()
//  * 2. [Visualization & Output] Summarize metadata to retain inter-subject variation using subjectMetaData()
//  * 3. [Visualization & Output] Combine aggregation and metadata summarization into a SummarizedExperiment using summarizedCounts()
//  * 4. [Core Analysis] Stratify and aggregate counts across all cell types using aggregateBioVar()
//  * 5. [Core Analysis] Perform downstream differential gene expression analysis on a specific cell type using DESeq2 (via DESeqDataSetFromMatrix() and DE

nextflow.enable.dsl = 2

process BIOC_AGGREGATEBIOVAR_PSEUDOBULK_AGGREGATION_AND_DGE {
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
    .bm_deps <- c("aggregateBioVar", "SummarizedExperiment", "SingleCellExperiment", "DESeq2", "magrittr", "dplyr", "ggplot2", "cowplot", "ggtext", "pheatmap", "viridis")
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
        library(aggregateBioVar)
        library(SummarizedExperiment)
        library(SummarizedExperiment, quietly = TRUE)
        library(SingleCellExperiment, quietly = TRUE)
        library(DESeq2, quietly = TRUE)
        library(magrittr, quietly = TRUE)
        library(dplyr, quietly = TRUE)
        library(ggplot2, quietly = TRUE)
        library(cowplot, quietly = TRUE)
        library(ggtext, quietly = TRUE)
        library(pheatmap, quietly = TRUE)
        library(viridis, quietly = TRUE)
        
        # ----------------------------------------------------------------------
        # 1. Read User Input
        # ----------------------------------------------------------------------
        if (file.exists("small_airway")) {
            small_airway <- readRDS("small_airway")
        } else if (file.exists("small_airway.rds")) {
            small_airway <- readRDS("small_airway.rds")
        } else {
            stop("Error: Input file 'small_airway' or 'small_airway.rds' not found in the working directory.")
        }
        
        # ----------------------------------------------------------------------
        # 2. Documented Workflow Steps
        # ----------------------------------------------------------------------
        
        # Step 2.1: Aggregate gene counts within subjects
        counts_by_sub <- countsBySubject(scExp = small_airway, subjectVar = "orig.ident")
        
        # Step 2.2: Summarize metadata to retain inter-subject variation
        sub_metadata <- subjectMetaData(scExp = small_airway, subjectVar = "orig.ident")
        
        # Step 2.3: Combine aggregation and metadata summarization into a SummarizedExperiment
        sum_counts <- summarizedCounts(scExp = small_airway, subjectVar = "orig.ident")
        
        # Step 2.4: Stratify and aggregate counts across all cell types
        agg_test <- aggregateBioVar(scExp = small_airway,
                                    subjectVar = "orig.ident", cellVar = "celltype")
        
        # Step 2.5: Perform downstream differential gene expression analysis
        aggregate_counts <-
            aggregateBioVar(
                scExp = small_airway,
                subjectVar = "orig.ident", cellVar = "celltype"
            )
        
        subj_dds_dataset <-
            DESeqDataSetFromMatrix(
                countData = assay(aggregate_counts\$`Secretory cell`, "counts"),
                colData = colData(aggregate_counts\$`Secretory cell`),
                design = ~ Genotype
            )
        
        subj_dds <- DESeq(subj_dds_dataset)
        
        subj_dds_results <-
            results(subj_dds, contrast = c("Genotype", "WT", "CFTRKO"))
        
        # ----------------------------------------------------------------------
        # 3. Cell-level DGE for Comparison
        # ----------------------------------------------------------------------
        cells_secretory <-
            small_airway[, which(
                as.character(small_airway\$celltype) == "Secretory cell")]
        cells_secretory\$Genotype <- as.factor(cells_secretory\$Genotype)
        
        cell_dds_dataset <-
            DESeqDataSetFromMatrix(
                countData = assay(cells_secretory, "counts"),
                colData = colData(cells_secretory),
                design = ~ Genotype
            )
        
        cell_dds <- DESeq(cell_dds_dataset)
        
        cell_dds_results <-
            results(cell_dds, contrast = c("Genotype", "WT", "CFTRKO"))
        
        # Transform results for plotting
        subj_dds_transf <- as.data.frame(subj_dds_results) %>%
            bind_cols(feature = rownames(subj_dds_results)) %>%
            mutate(log_padj = - log(.data\$padj, base = 10))
        
        cell_dds_transf <- as.data.frame(cell_dds_results) %>%
            bind_cols(feature = rownames(cell_dds_results)) %>%
            mutate(log_padj = - log(.data\$padj, base = 10))
        
        # ----------------------------------------------------------------------
        # 4. Visualization and Plotting
        # ----------------------------------------------------------------------
        
        # Define scPHeatmap function
        scPHeatmap <- function(sumExp, subjectVar, gtVar, logSample = 1:100, ...) {
            orderSumExp <- sumExp[, order(sumExp[[subjectVar]])]
            sumExpCounts <- as.matrix(
                SummarizedExperiment::assay(orderSumExp, "counts")
            )
            logcpm <- log2(
                1e6 * t(t(sumExpCounts) / colSums(sumExpCounts)) + 1
            )
            annotations <- data.frame(
                Genotype = orderSumExp[[gtVar]],
                Subject = orderSumExp[[subjectVar]]
            )
            rownames(annotations) <- colnames(orderSumExp)
        
            singleCellpHeatmap <- pheatmap::pheatmap(
                mat = logcpm[logSample, ], annotation_col = annotations,
                cluster_cols = FALSE, show_rownames = FALSE, show_colnames = FALSE,
                scale = "none", ...
            )
            return(singleCellpHeatmap)
        }
        
        # Setup annotation colors for heatmaps
        sumExp_sec <- small_airway[, small_airway\$celltype == "Secretory cell"]
        ann_colors <- list(
            Genotype = c(CFTRKO = "red", WT = "black"),
            Subject = c(RColorBrewer::brewer.pal(7, "Accent"))
        )
        ann_names <- unique(sumExp_sec[["orig.ident"]])
        names(ann_colors\$Subject) <- ann_names[order(ann_names)]
        
        # Save Heatmaps to PDF
        pdf("heatmaps_comparison.pdf", width = 10, height = 8)
        # Heatmap 1: Cell-level
        scPHeatmap(
            sumExp = sumExp_sec, logSample = 1:100,
            subjectVar = "orig.ident", gtVar = "Genotype",
            color = viridis::viridis(75), annotation_colors = ann_colors,
            treeheight_row = 0, treeheight_col = 0,
            main = "Gene-by-cell Count Matrix (Secretory Cells)"
        )
        # Heatmap 2: Subject-level (aggregated)
        scPHeatmap(
            sumExp = aggregate_counts\$`Secretory cell`, logSample = 1:100,
            subjectVar = "orig.ident", gtVar = "Genotype",
            color = viridis::viridis(75), annotation_colors = ann_colors,
            treeheight_row = 0, treeheight_col = 0,
            main = "Gene-by-subject Count Matrix (Secretory Cells)"
        )
        dev.off()
        
        # Define theme for volcano plots
        deseq_themes <- function() {
            list(
                theme_classic(),
                lims(x = c(-4, 5), y = c(0, 80)),
                labs(
                    x = "log<sub>2</sub> (fold change)",
                    y = "-log<sub>10</sub> (p<sub>adj</sub>)"
                ),
                ggplot2::theme(
                    axis.title.x = ggtext::element_markdown(),
                    axis.title.y = ggtext::element_markdown())
            )
        }
        
        # Build Volcano Plots
        ggplot_full <- ggplot(data = cell_dds_transf) +
            geom_point(aes(x = log2FoldChange, y = log_padj), na.rm = TRUE) +
            geom_point(
                data = filter(
                    .data = cell_dds_transf,
                    abs(.data\$log2FoldChange) > 1, .data\$padj < 0.05
                ),
                aes(x = log2FoldChange, y = log_padj), color = "red"
            ) +
            deseq_themes() +
            ggtitle("Cell-level DGE")
        
        ggplot_subj <- ggplot(data = subj_dds_transf) +
            geom_point(aes(x = log2FoldChange, y = log_padj), na.rm = TRUE) +
            geom_point(
                data = filter(
                    .data = subj_dds_transf,
                    abs(.data\$log2FoldChange) > 1, .data\$padj < 0.05
                ),
                aes(x = log2FoldChange, y = log_padj), color = "red"
            ) +
            geom_label(
                data = filter(
                    .data = subj_dds_transf,
                    abs(.data\$log2FoldChange) > 1, .data\$padj < 0.05
                ),
                aes(x = log2FoldChange + 0.5, y = log_padj + 5, label = feature)
            ) +
            deseq_themes() +
            ggtitle("Subject-level DGE (Pseudo-bulk)")
        
        # Save Volcano Plot to PDF
        pdf("volcano_plots.pdf", width = 12, height = 6)
        print(cowplot::plot_grid(ggplot_full, ggplot_subj, ncol = 2, labels = c("A", "B")))
        dev.off()
        
        # Define function to plot normalized counts
        ggplot_counts <- function(dds_obj, gene) {
            norm_counts <-
                counts(dds_obj, normalized = TRUE)[grepl(gene, rownames(dds_obj)), ]
            sc_counts <-
                data.frame(
                    norm_count = norm_counts,
                    subject = colData(dds_obj)[["orig.ident"]],
                    genotype = factor(
                        colData(dds_obj)[["Genotype"]],
                        levels = c("WT", "CFTRKO")
                    )
                )
        
            count_ggplot <- ggplot(data = sc_counts) +
                geom_jitter(
                    aes(x = genotype, y = norm_count, color = genotype),
                    height = 0, width = 0.05
                ) +
                scale_color_manual(
                    "Genotype", values = c("WT" = "blue", "CFTRKO" = "red")
                ) +
                lims(x = c("WT", "CFTRKO"), y = c(0, 350)) +
                labs(x = "Genotype", y = "Normalized Counts") +
                ggtitle(label = gene) +
                theme_classic()
            return(count_ggplot)
        }
        
        # Save Normalized Counts Plot to PDF
        pdf("normalized_gene_counts.pdf", width = 10, height = 5)
        print(cowplot::plot_grid(
            ggplot_counts(dds_obj = subj_dds, gene = "CFTR") +
                theme(legend.position = "FALSE"),
            ggplot_counts(dds_obj = subj_dds, gene = "CD36") +
                theme(legend.position = "FALSE"),
            cowplot::get_legend(
                plot = ggplot_counts(dds_obj = subj_dds, gene = "CD36")
            ),
            ncol = 3, rel_widths = c(4, 4, 1)
        ))
        dev.off()
        
        # ----------------------------------------------------------------------
        # 5. Save Outputs to Files
        # ----------------------------------------------------------------------
        # Save aggregated counts object
        saveRDS(aggregate_counts, "aggregate_counts.rds")
        
        # Save DGE results tables
        write.csv(as.data.frame(subj_dds_results), "subject_level_dge_results.csv", row.names = TRUE)
        write.csv(as.data.frame(cell_dds_results), "cell_level_dge_results.csv", row.names = TRUE)
        
        message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_AGGREGATEBIOVAR_PSEUDOBULK_AGGREGATION_AND_DGE":',
        paste0('    aggregateBioVar: ', as.character(packageVersion('aggregateBioVar')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pseudobulk_aggregation_and_dge.csv versions.yml
    """
}

workflow BIOC_AGGREGATEBIOVAR_PSEUDOBULK_AGGREGATION_AND_DGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ small_airway ] ]

    main:
    BIOC_AGGREGATEBIOVAR_PSEUDOBULK_AGGREGATION_AND_DGE(ch_input)

    emit:
    tables   = BIOC_AGGREGATEBIOVAR_PSEUDOBULK_AGGREGATION_AND_DGE.out.tables
    plots    = BIOC_AGGREGATEBIOVAR_PSEUDOBULK_AGGREGATION_AND_DGE.out.plots
    objects  = BIOC_AGGREGATEBIOVAR_PSEUDOBULK_AGGREGATION_AND_DGE.out.objects
    versions = BIOC_AGGREGATEBIOVAR_PSEUDOBULK_AGGREGATION_AND_DGE.out.versions
}
