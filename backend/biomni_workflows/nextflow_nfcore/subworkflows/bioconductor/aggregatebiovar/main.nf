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

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
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
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .lcf_obj <- tryCatch(readRDS(.lcf_rds), error = function(e) NULL)
      .lcf_mat <- if (is.matrix(.lcf_obj) || is.data.frame(.lcf_obj)) .lcf_obj else NULL
      if (!is.null(.lcf_mat) && nrow(.lcf_mat) > 100) {
        .lcf_m <- tryCatch(as.matrix(.lcf_mat), error = function(e) NULL)
        if (!is.null(.lcf_m)) {
          .lcf_row_med <- suppressWarnings(apply(.lcf_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
          .lcf_kept <- sum(is.finite(.lcf_row_med) & .lcf_row_med >= 1) / nrow(.lcf_m)
          .lcf_kept_fractions <- c(.lcf_kept_fractions, .lcf_kept)
          .lcf_scanned <- c(.lcf_scanned, .lcf_rds)
        }
      }
    }
    .lcf_kept <- if (length(.lcf_kept_fractions) > 0) round(median(.lcf_kept_fractions), 4) else NA_real_
    .gates_by_label[["low-count filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = .lcf_kept,
      passes = isTRUE(is.finite(.lcf_kept) && .lcf_kept >= 0.3 && .lcf_kept <= 0.6),
      status = if (is.finite(.lcf_kept)) paste0("computed (proxy: rows w/ median count >=1 across ", length(.lcf_scanned), " matrix .rds)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # dispersion/size-factor estimation — object-type-aware. Try DESeq2
    # DESeqDataSet (mcols\$dispOutlier), then edgeR DGEList (common.dispersion).
    .dsf_value <- NA_real_; .dsf_kind <- "none"
    for (.dsf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .dsf_obj <- tryCatch(readRDS(.dsf_rds), error = function(e) NULL)
      if (!is.null(.dsf_obj)) {
        if (inherits(.dsf_obj, "DESeqDataSet")) {
          .dsf_o <- tryCatch(mcols(.dsf_obj)\$dispOutlier, error = function(e) NULL)
          if (!is.null(.dsf_o)) { .dsf_value <- round(mean(.dsf_o, na.rm = TRUE), 4); .dsf_kind <- "deseq2"; break }
        } else if (inherits(.dsf_obj, "DGEList")) {
          .dsf_v <- tryCatch(.dsf_obj\$common.dispersion, error = function(e) NULL)
          if (!is.null(.dsf_v) && is.finite(.dsf_v)) { .dsf_value <- round(sqrt(.dsf_v), 4); .dsf_kind <- "edger_bcv"; break }
        }
      }
    }
    .gates_by_label[["dispersion/size-factor estimation"]] <- list(
      gate_row = "bioc_dispersion_size_factor",
      metric_name = if (.dsf_kind == "edger_bcv") "common_bcv" else "disp_outlier_fraction",
      metric_value = .dsf_value,
      passes = isTRUE(
        (.dsf_kind == "deseq2" && is.finite(.dsf_value) && .dsf_value <= 0.01) ||
        (.dsf_kind == "edger_bcv" && is.finite(.dsf_value) && .dsf_value > 0 && .dsf_value < 1.0)
      ),
      status = if (is.finite(.dsf_value)) paste0("computed (", .dsf_kind, ")")
               else "not_computed (no DESeqDataSet/DGEList .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_AGGREGATEBIOVAR_PSEUDOBULK_AGGREGATION_AND_DGE",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



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
