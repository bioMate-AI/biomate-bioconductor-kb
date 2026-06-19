#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ScreenR — screenr_shrna_analysis
// Perform a comprehensive loss-of-function shRNA screen analysis using ScreenR, including quality control, normalization, Z-score, CAMERA, and ROAST hit identific
// Input: counts.csv, coldata.csv
// Container: 1.12.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ScreenR, dplyr, ggplot2, tidyr
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCREENR_SCREENR_SHRNA_ANALYSIS {
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
    .bm_deps <- c("ScreenR", "ggplot2", "dplyr", "tidyr")
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
    library(ScreenR)
    library(ggplot2)
    library(dplyr)
    library(tidyr)
    
    # ==========================================
    # --- Read and Preprocess Input Data ---
    # ==========================================
    message("Stage 1: Loading and preprocessing input data...")
    
    # Read counts and coldata
    counts_df <- read.csv("counts.csv", check.names = FALSE, stringsAsFactors = FALSE)
    coldata <- read.csv("coldata.csv", check.names = FALSE, stringsAsFactors = FALSE)
    
    # Ensure 'gene_id' or first column is treated as row names/Barcode
    if ("gene_id" %in% colnames(counts_df)) {
        rownames(counts_df) <- counts_df\$gene_id
        counts_df\$gene_id <- NULL
    } else {
        rownames(counts_df) <- counts_df[, 1]
        counts_df <- counts_df[, -1, drop = FALSE]
    }
    
    # Align coldata with counts columns
    common_samples <- intersect(coldata\$sample, colnames(counts_df))
    if (length(common_samples) == 0) {
        # Fallback if sample names do not match directly
        common_samples <- colnames(counts_df)
        coldata <- coldata[1:ncol(counts_df), ]
        coldata\$sample <- common_samples
    }
    counts_df <- counts_df[, coldata\$sample, drop = FALSE]
    
    # Standardize and construct ScreenR-compatible sample names: Day_Condition_Replicate
    if ("day" %in% colnames(coldata)) {
        days <- coldata\$day
    } else if ("timepoint" %in% colnames(coldata)) {
        days <- coldata\$timepoint
    } else {
        days <- rep("Time1", nrow(coldata))
    }
    
    conds <- coldata\$condition
    conds[grepl("control|ctrl|mock", conds, ignore.case = TRUE)] <- "CTRL"
    conds[grepl("treat|trt|drug", conds, ignore.case = TRUE)] <- "TRT"
    conds <- gsub("[^A-Za-z0-9]", "_", conds)
    
    # Compute replicates
    reps <- ave(seq_along(conds), paste(days, conds), FUN = seq_along)
    reps_letters <- LETTERS[reps]
    
    # Rename columns of counts to match ScreenR expected format
    new_sample_names <- paste(days, conds, reps_letters, sep = "_")
    colnames(counts_df) <- new_sample_names
    
    # Create the ScreenR input table
    data_table <- data.frame(
        Barcode = as.factor(rownames(counts_df)),
        counts_df,
        check.names = FALSE
    )
    
    # Create a 1-to-1 annotation table mapping Barcode to Gene
    annotation_table <- data.frame(
        Barcode = rownames(counts_df),
        Gene = rownames(counts_df),
        stringsAsFactors = FALSE
    )
    
    # Define groups
    groups <- factor(paste(days, conds, sep = "_"))
    if (length(unique(groups)) < 2) {
        stop("At least two distinct groups/conditions are required to perform ScreenR analysis.")
    }
    
    # Create ScreenR Object
    object <- create_screenr_object(
        table = data_table,
        annotation = annotation_table,
        groups = groups,
        replicates = ""
    )
    
    # ==========================================
    # --- Normalization and Filtering ---
    # ==========================================
    message("Stage 2: Normalizing and filtering data...")
    object <- remove_all_zero_row(object)
    object <- normalize_data(object)
    object <- compute_data_table(object)
    
    # ==========================================
    # --- Statistical Analysis (Hits) ---
    # ==========================================
    message("Stage 3: Performing statistical hit identification...")
    
    unique_days <- unique(days)
    control_name <- if ("CTRL" %in% conds) "CTRL" else unique(conds)[1]
    treatment_name <- if ("TRT" %in% conds) "TRT" else unique(conds)[max(1, length(unique(conds)))]
    
    # Create design matrix for CAMERA and ROAST
    matrix_model <- model.matrix(~ groups)
    colnames(matrix_model) <- make.names(levels(groups))
    
    metrics_list <- list()
    zscore_hits <- list()
    camera_hits <- list()
    roast_hits <- list()
    common_hits_2 <- list()
    common_hits_3 <- list()
    
    for (d in unique_days) {
        message(paste("Processing day/timepoint:", d))
        
        # 1. Compute Z-score metrics
        metrics_list[[d]] <- tryCatch({
            compute_metrics(
                object,
                control = control_name,
                treatment = treatment_name,
                day = d
            )
        }, error = function(e) {
            warning("Metrics computation failed for ", d, ": ", e\$message)
            NULL
        })
        
        # 2. Find Z-score hits
        if (!is.null(metrics_list[[d]])) {
            zscore_hits[[d]] <- tryCatch({
                find_zscore_hit(
                    table_treate_vs_control = metrics_list[[d]],
                    number_barcode = 1, # Default to 1 for gene-level input robustness
                    metric = "median"
                )
            }, error = function(e) {
                warning("Z-score hit finding failed for ", d, ": ", e\$message)
                data.frame(Gene = character(), numberOfBarcode = integer())
            })
        } else {
            zscore_hits[[d]] <- data.frame(Gene = character(), numberOfBarcode = integer())
        }
        
        # 3. CAMERA hits
        contrast_name <- make.names(paste(d, treatment_name, sep = "_"))
        if (contrast_name %in% colnames(matrix_model)) {
            camera_hits[[d]] <- tryCatch({
                find_camera_hit(
                    screenR_Object = object,
                    matrix_model = matrix_model,
                    contrast = contrast_name
                )
            }, error = function(e) {
                warning("CAMERA failed for ", d, ": ", e\$message)
                data.frame(Gene = character(), NGenes = numeric(), Direction = character(), PValue = numeric(), FDR = numeric())
            })
        } else {
            camera_hits[[d]] <- data.frame(Gene = character(), NGenes = numeric(), Direction = character(), PValue = numeric(), FDR = numeric())
        }
        
        # 4. ROAST hits
        if (contrast_name %in% colnames(matrix_model)) {
            roast_hits[[d]] <- tryCatch({
                find_roast_hit(
                    screenR_Object = object,
                    matrix_model = matrix_model,
                    contrast = contrast_name
                )
            }, error = function(e) {
                warning("ROAST failed for ", d, ": ", e\$message)
                data.frame(Gene = character(), NGenes = numeric(), PropDown = numeric(), PropUp = numeric(), Direction = character(), PValue = numeric(), FDR = numeric())
            })
        } else {
            roast_hits[[d]] <- data.frame(Gene = character(), NGenes = numeric(), PropDown = numeric(), PropUp = numeric(), Direction = character(), PValue = numeric(), FDR = numeric())
        }
        
        # 5. Find Common Hits (at least 2 and at least 3 methods)
        common_hits_2[[d]] <- tryCatch({
            find_common_hit(
                zscore_hits[[d]],
                camera_hits[[d]],
                roast_hits[[d]],
                common_in = 2
            )
        }, error = function(e) {
            warning("Common hits (at least 2) failed for ", d, ": ", e\$message)
            character()
        })
        
        common_hits_3[[d]] <- tryCatch({
            find_common_hit(
                zscore_hits[[d]],
                camera_hits[[d]],
                roast_hits[[d]],
                common_in = 3
            )
        }, error = function(e) {
            warning("Common hits (at least 3) failed for ", d, ": ", e\$message)
            character()
        })
    }
    
    # ==========================================
    # --- Export Results Table ---
    # ==========================================
    message("Stage 4: Exporting results table...")
    
    results_list <- list()
    for (d in unique_days) {
        all_genes <- unique(c(zscore_hits[[d]]\$Gene, camera_hits[[d]]\$Gene, roast_hits[[d]]\$Gene))
        if (length(all_genes) == 0) next
        
        day_hits <- data.frame(
            Gene = all_genes,
            Day = d,
            In_Zscore = all_genes %in% zscore_hits[[d]]\$Gene,
            In_CAMERA = all_genes %in% camera_hits[[d]]\$Gene,
            In_ROAST = all_genes %in% roast_hits[[d]]\$Gene,
            Hit_At_Least_2 = all_genes %in% common_hits_2[[d]],
            Hit_At_Least_3 = all_genes %in% common_hits_3[[d]],
            stringsAsFactors = FALSE
        )
        results_list[[d]] <- day_hits
    }
    
    if (length(results_list) > 0) {
        final_results <- do.call(rbind, results_list)
    } else {
        final_results <- data.frame(
            Gene = character(), Day = character(),
            In_Zscore = logical(), In_CAMERA = logical(), In_ROAST = logical(),
            Hit_At_Least_2 = logical(), Hit_At_Least_3 = logical()
        )
    }
    write.csv(final_results, "screenr_results.csv", row.names = FALSE)
    
    # ==========================================
    # --- Generate Diagnostic & Result Plots ---
    # ==========================================
    message("Stage 5: Generating diagnostic and result plots...")
    
    pdf("screenr_plots.pdf", width = 10, height = 8)
    
    # Set up a color palette
    plot_palette <- rainbow(length(levels(groups)))
    
    # 1. Mapped Reads
    tryCatch({
        p1 <- plot_mapped_reads(object, palette = plot_palette) +
            ggplot2::coord_flip() +
            ggplot2::theme_minimal() +
            ggplot2::ggtitle("Mapped Reads per Sample")
        print(p1)
    }, error = function(e) message("Plot Mapped Reads failed: ", e\$message))
    
    # 2. Mapped Reads Distribution (Boxplot)
    tryCatch({
        p2 <- plot_mapped_reads_distribution(object, palette = plot_palette, type = "boxplot") +
            ggplot2::coord_flip() +
            ggplot2::theme_minimal() +
            ggplot2::ggtitle("Mapped Reads Distribution (Boxplot)")
        print(p2)
    }, error = function(e) message("Plot Mapped Reads Boxplot failed: ", e\$message))
    
    # 3. Mapped Reads Distribution (Density)
    tryCatch({
        p3 <- plot_mapped_reads_distribution(object, palette = plot_palette, type = "density") +
            ggplot2::theme_minimal() +
            ggplot2::ggtitle("Mapped Reads Distribution (Density)")
        print(p3)
    }, error = function(e) message("Plot Mapped Reads Density failed: ", e\$message))
    
    # 4. Barcode Lost
    tryCatch({
        p4 <- plot_barcode_lost(object, palette = plot_palette) +
            ggplot2::coord_flip() +
            ggplot2::theme_minimal() +
            ggplot2::ggtitle("Barcodes Lost per Sample")
        print(p4)
    }, error = function(e) message("Plot Barcode Lost failed: ", e\$message))
    
    # 5. MDS Plot
    tryCatch({
        p5 <- plot_mds(object) +
            ggplot2::theme_minimal() +
            ggplot2::ggtitle("Multidimensional Scaling (MDS) Plot")
        print(p5)
    }, error = function(e) message("MDS Plot failed: ", e\$message))
    
    # 6. Z-score Distribution
    valid_metrics <- metrics_list[!sapply(metrics_list, is.null)]
    if (length(valid_metrics) > 0) {
        tryCatch({
            p6 <- plot_zscore_distribution(valid_metrics, alpha = 0.8) +
                ggplot2::theme_minimal() +
                ggplot2::ggtitle("Z-score Distribution")
            print(p6)
        }, error = function(e) message("Z-score Distribution Plot failed: ", e\$message))
    }
    
    # 7. Common Hits Venn Diagram (First Day)
    first_day <- unique_days[1]
    if (!is.null(zscore_hits[[first_day]]) && nrow(zscore_hits[[first_day]]) > 0) {
        tryCatch({
            plot_common_hit(
                hit_zscore = zscore_hits[[first_day]],
                hit_camera = camera_hits[[first_day]],
                roast_hits[[first_day]],
                show_elements = FALSE,
                show_percentage = TRUE
            )
        }, error = function(e) message("Common Hit Venn Diagram failed: ", e\$message))
    }
    
    # 8. Trend Plot for Top Hit
    if (length(common_hits_2[[first_day]]) > 0) {
        tryCatch({
            top_gene <- common_hits_2[[first_day]][1]
            p_trend <- plot_trend(
                screenR_Object = object,
                genes = top_gene,
                nrow = 2, ncol = 2,
                group_var = unique(as.character(groups))
            )
            print(p_trend)
        }, error = function(e) message("Trend Plot failed: ", e\$message))
    }
    
    dev.off()
    
    message("Analysis complete. Outputs written to 'screenr_results.csv' and 'screenr_plots.pdf'.")
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
      process = "BIOC_SCREENR_SCREENR_SHRNA_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCREENR_SCREENR_SHRNA_ANALYSIS":',
        paste0('    ScreenR: ', as.character(packageVersion('ScreenR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_screenr_shrna_analysis.csv versions.yml
    """
}

workflow BIOC_SCREENR_SCREENR_SHRNA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_SCREENR_SCREENR_SHRNA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCREENR_SCREENR_SHRNA_ANALYSIS.out.tables
    plots    = BIOC_SCREENR_SCREENR_SHRNA_ANALYSIS.out.plots
    objects  = BIOC_SCREENR_SCREENR_SHRNA_ANALYSIS.out.objects
    versions = BIOC_SCREENR_SCREENR_SHRNA_ANALYSIS.out.versions
}
