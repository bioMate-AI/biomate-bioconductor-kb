#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: proDA — differential_abundance_analysis
// Identify differentially abundant proteins in label-free mass spectrometry data by fitting a probabilistic dropout model without imputation.
// Input: proteinGroups.txt
// Container: quay.io/biocontainers/bioconductor-proda:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: pheatmap, proDA
// Visualizations: heatmap, heatmap (ComplexHeatmap), box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the protein intensity data and convert zero values to NA
//  * 2. [Core Analysis] Log2-transform the intensities
//  * 3. [Core Analysis] Perform median normalization using median_normalization()
//  * 4. [Core Analysis] Estimate sample distances using dist_approx()
//  * 5. [Core Analysis] Fit the probabilistic dropout model using proDA()
//  * 6. [Core Analysis] Test for differential abundance using test_diff()

nextflow.enable.dsl = 2

process BIOC_PRODA_DIFFERENTIAL_ABUNDANCE_ANALYSIS {
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
    .bm_deps <- c("proDA")
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
        library(proDA)
        
        # 1. Load the protein intensity data from the working directory
        # The user input file 'proteinGroups.txt' must be present in the working directory.
        maxquant_protein_table <- read.delim(
            "proteinGroups.txt",
            stringsAsFactors = FALSE
        )
        
        # Extract the intensity columns
        intensity_colnames <- grep("^LFQ\\\\.intensity\\\\.", colnames(maxquant_protein_table), value=TRUE)
        abundance_matrix <- as.matrix(maxquant_protein_table[, intensity_colnames])
        colnames(abundance_matrix) <- sub("^LFQ\\\\.intensity\\\\.", "", intensity_colnames)
        rownames(abundance_matrix) <- maxquant_protein_table\$Protein.IDs
        
        # Convert zero values to NA
        abundance_matrix[abundance_matrix == 0] <- NA
        
        # 2. Log2-transform the intensities
        abundance_matrix <- log2(abundance_matrix)
        
        # 3. Perform median normalization using median_normalization()
        normalized_abundance_matrix <- median_normalization(abundance_matrix)
        
        # 4. Estimate sample distances using dist_approx()
        da <- dist_approx(normalized_abundance_matrix)
        
        # Create sample information data frame
        sample_info_df <- data.frame(name = colnames(normalized_abundance_matrix),
                                     stringsAsFactors = FALSE)
        sample_info_df\$condition <- sub("\\\\.\\\\d+\$", "", sample_info_df\$name)
        sample_info_df\$replicate <- suppressWarnings(as.numeric(sub("^.*\\\\.", "", sample_info_df\$name)))
        
        # Determine reference and test conditions dynamically
        unique_conditions <- unique(sample_info_df\$condition)
        ref_condition <- unique_conditions[1]
        
        # 5. Fit the probabilistic dropout model using proDA()
        fit <- proDA(normalized_abundance_matrix, design = ~ condition, 
                     col_data = sample_info_df, reference_level = ref_condition)
        
        # 6. Test for differential abundance using test_diff()
        if (length(unique_conditions) > 1) {
          test_condition <- unique_conditions[2]
          contrast_name <- paste0("condition", test_condition)
          test_res <- test_diff(fit, contrast_name)
        } else {
          test_res <- test_diff(fit, "(Intercept)")
        }
        
        # --- Write Output Files ---
        
        # Save the differential abundance test results as a CSV table
        write.csv(test_res, "differential_abundance_results.csv", row.names = FALSE)
        
        # Save the normalized abundance matrix as a CSV table
        write.csv(normalized_abundance_matrix, "normalized_abundance_matrix.csv", row.names = TRUE)
        
        # Save the fitted proDA model object as an RDS file
        saveRDS(fit, "proda_fit.rds")
        
        # Save the estimated sample distances as an RDS file
        saveRDS(da, "sample_distances.rds")
        
        # Generate and save a diagnostic plot of the sample distances
        pdf("sample_distance_heatmap.pdf", width = 8, height = 8)
        tryCatch({
          if (requireNamespace("pheatmap", quietly = TRUE)) {
            plot_mat <- as.matrix(da\$mean)
            diag(plot_mat) <- NA
            pheatmap::pheatmap(plot_mat, 
                               cluster_rows = FALSE, 
                               cluster_cols = FALSE, 
                               main = "Sample Distance Heatmap (Expected Distance)")
          } else {
            plot_mat <- as.matrix(da\$mean)
            diag(plot_mat) <- NA
            heatmap(plot_mat, Rowv = NA, Colv = NA, main = "Sample Distance Heatmap")
          }
        }, error = function(e) {
          warning("Could not generate heatmap plot: ", e\$message)
        })
        dev.off()
        
        # Generate and save a boxplot of the normalized intensity distributions
        pdf("normalized_intensity_boxplot.pdf", width = 10, height = 6)
        boxplot(normalized_abundance_matrix, 
                las = 2, 
                main = "Normalized Intensity Distribution per Sample", 
                ylab = "Log2 Intensity")
        dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # missing-value handling — scan .rds matrix/data.frame artifacts for max NA fraction
    .mv_na_fracs <- numeric(0)
    .mv_scanned <- character(0)
    for (.mv_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .mv_obj <- tryCatch(readRDS(.mv_rds), error = function(e) NULL)
      .mv_mat <- if (is.matrix(.mv_obj) || is.data.frame(.mv_obj)) .mv_obj else NULL
      if (!is.null(.mv_mat)) {
        .mv_vals <- suppressWarnings(as.numeric(as.matrix(.mv_mat)))
        if (length(.mv_vals) > 0) {
          .mv_na_fracs <- c(.mv_na_fracs, mean(is.na(.mv_vals)))
          .mv_scanned <- c(.mv_scanned, .mv_rds)
        }
      }
    }
    .mv_max <- if (length(.mv_na_fracs) > 0) round(max(.mv_na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .mv_max,
      passes = isTRUE(is.finite(.mv_max) && .mv_max < 0.05),
      status = if (is.finite(.mv_max)) paste0("computed (scanned ", length(.mv_scanned), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_PRODA_DIFFERENTIAL_ABUNDANCE_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling", "count normalization", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_PRODA_DIFFERENTIAL_ABUNDANCE_ANALYSIS":',
        paste0('    proDA: ', as.character(packageVersion('proDA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_abundance_analysis.csv versions.yml
    """
}

workflow BIOC_PRODA_DIFFERENTIAL_ABUNDANCE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ proteinGroups.txt ] ]

    main:
    BIOC_PRODA_DIFFERENTIAL_ABUNDANCE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PRODA_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.tables
    plots    = BIOC_PRODA_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.plots
    objects  = BIOC_PRODA_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.objects
    versions = BIOC_PRODA_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.versions
}
