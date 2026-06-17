#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: decoupleR — pathway_activity_bulk_rnaseq
// Infer pathway activities from bulk RNA-seq differential expression statistics (t-values) or counts using the PROGENy model and a multivariate linear model (MLM)
// Input: bk_data.rds
// Container: quay.io/biocontainers/bioconductor-decoupler:2.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: decoupleR, dplyr, ggplot2, ggrepel, pheatmap, tibble, tidyr
// Visualizations: heatmap, pathway diagram, bar plot, scatter plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load bulk RNA-seq data
//  * 2. [Core Analysis] Extract normalized log-transformed counts and limma t-values
//  * 3. [Core Analysis] Retrieve PROGENy pathway-gene weights using get_progeny()
//  * 4. [Core Analysis] Run Multivariate Linear Model on counts or t-values using run_mlm()
//  * 5. [Visualization & Output] Visualize sample-specific or contrast-specific pathway activities

nextflow.enable.dsl = 2

process BIOC_DECOUPLER_PATHWAY_ACTIVITY_BULK_RNASEQ {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("decoupleR", "dplyr", "tibble", "tidyr", "ggplot2", "pheatmap", "ggrepel")
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
    
    # 1. Load required packages
    library(decoupleR)
    library(dplyr)
    library(tibble)
    library(tidyr)
    library(ggplot2)
    library(pheatmap)
    library(ggrepel)
    
    # 2. Load bulk RNA-seq data
    input_file <- "bk_data.rds"
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    data <- readRDS(input_file)
    
    # 3. Extract normalized log-transformed counts and limma t-values
    counts <- data\$counts %>% 
      dplyr::mutate_if(~ any(is.na(.x)), ~ if_else(is.na(.x), 0, .x)) %>% 
      column_to_rownames(var = "gene") %>% 
      as.matrix()
    
    deg <- data\$limma_ttop %>% 
      select(ID, t) %>% 
      filter(!is.na(t)) %>% 
      column_to_rownames(var = "ID") %>% 
      as.matrix()
    
    # 4. Retrieve PROGENy pathway-gene weights using get_progeny()
    net <- get_progeny(organism = 'human', top = 500)
    
    # 5. Run Multivariate Linear Model on counts and t-values using run_mlm()
    sample_acts <- run_mlm(mat=counts, net=net, .source='source', .target='target', .mor='weight', minsize = 5)
    contrast_acts <- run_mlm(mat=deg, net=net, .source='source', .target='target', .mor='weight', minsize = 5)
    
    # 6. Save meaningful results to files
    write.csv(sample_acts, "sample_pathway_activities.csv", row.names = FALSE)
    write.csv(contrast_acts, "contrast_pathway_activities.csv", row.names = FALSE)
    saveRDS(sample_acts, "sample_pathway_activities.rds")
    saveRDS(contrast_acts, "contrast_pathway_activities.rds")
    
    # 7. Visualize sample-specific and contrast-specific pathway activities
    
    # (a) Heatmap of sample-specific pathway activities
    sample_acts_mat <- sample_acts %>% 
      pivot_wider(id_cols = 'condition', names_from = 'source', values_from = 'score') %>% 
      column_to_rownames('condition') %>% 
      as.matrix()
    
    # Scale per feature
    sample_acts_mat <- scale(sample_acts_mat)
    
    palette_length <- 100
    my_color <- colorRampPalette(c("Darkblue", "white", "red"))(palette_length)
    my_breaks <- c(seq(-3, 0, length.out=ceiling(palette_length/2) + 1), 
                   seq(0.05, 3, length.out=floor(palette_length/2)))
    
    pdf("sample_pathway_activities_heatmap.pdf", width = 8, height = 6)
    pheatmap(sample_acts_mat, border_color = NA, color=my_color, breaks = my_breaks)
    dev.off()
    
    # (b) Barplot of contrast-specific pathway activities
    p_contrast <- ggplot(contrast_acts, aes(x = reorder(source, score), y = score)) +
      geom_bar(aes(fill = score), stat = "identity") +
      scale_fill_gradient2(low = "darkblue", high = "indianred", mid = "whitesmoke", midpoint = 0) +
      theme_minimal() +
      theme(axis.title = element_text(face = "bold", size = 12),
            axis.text.x = element_text(angle = 45, hjust = 1, size = 10, face = "bold"),
            axis.text.y = element_text(size = 10, face = "bold"),
            panel.grid.major = element_blank(),
            panel.grid.minor = element_blank()) +
      xlab("Pathways") +
      ylab("Activity Score (t-value)") +
      ggtitle("Contrast-specific Pathway Activities (KO vs WT)")
    
    ggsave("contrast_pathway_activities_barplot.pdf", plot = p_contrast, width = 8, height = 6)
    
    # (c) Scatter plot of the most responsive genes in the MAPK pathway
    pathway <- 'MAPK'
    df <- net %>% 
      filter(source == pathway) %>% 
      arrange(target) %>% 
      mutate(ID = target, color = "3") %>% 
      column_to_rownames('target')
    
    inter <- sort(intersect(rownames(deg), rownames(df)))
    df <- df[inter, ]
    df['t_value'] <- deg[inter, ]
    
    df <- df %>% 
      mutate(color = if_else(weight > 0 & t_value > 0, '1', color)) %>% 
      mutate(color = if_else(weight > 0 & t_value < 0, '2', color)) %>% 
      mutate(color = if_else(weight < 0 & t_value > 0, '2', color)) %>% 
      mutate(color = if_else(weight < 0 & t_value < 0, '1', color))
    
    p_mapk <- ggplot(df, aes(x = weight, y = t_value, color = color)) +
      geom_point() +
      scale_colour_manual(values = c("red", "royalblue3", "grey")) +
      geom_label_repel(aes(label = ID), max.overlaps = 20) +
      theme_minimal() +
      theme(legend.position = "none") +
      geom_vline(xintercept = 0, linetype = 'dotted') +
      geom_hline(yintercept = 0, linetype = 'dotted') +
      ggtitle(paste(pathway, "Pathway Target Genes & t-values")) +
      xlab("Interaction Weight") +
      ylab("Gene t-value (Contrast)")
    
    ggsave("mapk_pathway_targets_scatter.pdf", plot = p_mapk, width = 8, height = 6)
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
      process = "BIOC_DECOUPLER_PATHWAY_ACTIVITY_BULK_RNASEQ",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DECOUPLER_PATHWAY_ACTIVITY_BULK_RNASEQ":',
        paste0('    decoupleR: ', as.character(packageVersion('decoupleR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_activity_bulk_rnaseq.csv versions.yml
    """
}

workflow BIOC_DECOUPLER_PATHWAY_ACTIVITY_BULK_RNASEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bk_data.rds ] ]

    main:
    BIOC_DECOUPLER_PATHWAY_ACTIVITY_BULK_RNASEQ(ch_input)

    emit:
    tables   = BIOC_DECOUPLER_PATHWAY_ACTIVITY_BULK_RNASEQ.out.tables
    plots    = BIOC_DECOUPLER_PATHWAY_ACTIVITY_BULK_RNASEQ.out.plots
    objects  = BIOC_DECOUPLER_PATHWAY_ACTIVITY_BULK_RNASEQ.out.objects
    versions = BIOC_DECOUPLER_PATHWAY_ACTIVITY_BULK_RNASEQ.out.versions
}
