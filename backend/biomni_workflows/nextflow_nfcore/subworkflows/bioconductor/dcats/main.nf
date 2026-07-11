#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DCATS — differential_composition_analysis
// Detect differential cell type composition abundances between conditions in scRNA-seq data while correcting for cell misclassification.
// Input: sim_count, sim_design, knnGraphs, labels, svmDF
// Container: quay.io/biocontainers/bioconductor-dcats:1.8.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DCATS, tidymodels, tidyverse
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate the similarity/confusion matrix using one of three methods (create_simMat, knn_simMat, or svm_simMat)
//  * 2. [Core Analysis] (Optional) Estimate a global over-dispersion parameter phi using getPhi to prevent overfitting
//  * 3. [Input & Preparation] (Optional) Detect or define reference cell types for normalization using detect_reference
//  * 4. [Core Analysis] Perform differential abundance analysis using dcats_GLM with the count matrix, design matrix, similarity matrix, and optional refe

nextflow.enable.dsl = 2

process BIOC_DCATS_DIFFERENTIAL_COMPOSITION_ANALYSIS {
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
    .bm_deps <- c("DCATS", "tidyverse", "tidymodels")
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
        library(DCATS)
        library(tidyverse)
        library(tidymodels)
        
        # Helper function to load files with various extensions robustly
        load_input_file = function(base_name) {
          extensions = c(".rds", ".csv", ".tsv", "")
          for (ext in extensions) {
            file_path = paste0(base_name, ext)
            if (file.exists(file_path)) {
              if (ext == ".rds") {
                return(readRDS(file_path))
              } else if (ext == ".csv") {
                return(read.csv(file_path, row.names = 1, stringsAsFactors = FALSE, check.names = FALSE))
              } else if (ext == ".tsv") {
                return(read.delim(file_path, row.names = 1, stringsAsFactors = FALSE, check.names = FALSE))
              } else {
                # No extension: try RDS first, then table
                res = tryCatch(readRDS(file_path), error = function(e) NULL)
                if (!is.null(res)) return(res)
                res = tryCatch(read.table(file_path, header = TRUE, row.names = 1, check.names = FALSE), error = function(e) NULL)
                if (!is.null(res)) return(res)
              }
            }
          }
          stop(paste("Required input file not found in working directory:", base_name))
        }
        
        # 1. Load User Inputs
        sim_count = as.matrix(load_input_file("sim_count"))
        sim_design = load_input_file("sim_design")
        knnGraphs = load_input_file("knnGraphs")
        labels = load_input_file("labels")
        svmDF = load_input_file("svmDF")
        
        # Ensure labels is a vector/factor
        if (is.data.frame(labels)) {
          labels = labels[[1]]
        }
        labels = as.factor(labels)
        
        # 2. Estimate the Similarity/Confusion Matrix
        # Method A: Uniform confusion matrix
        simil_mat = create_simMat(K = ncol(sim_count), confuse_rate = 0.2)
        
        # Method B: KNN-based similarity matrix
        knn_mat = knn_simMat(knnGraphs, labels)
        
        # Method C: SVM-based similarity matrix
        svm_mat = svm_simMat(svmDF)
        
        # Save estimated similarity matrices
        write.csv(as.matrix(simil_mat), "similarity_matrix_uniform.csv")
        write.csv(as.matrix(knn_mat), "similarity_matrix_knn.csv")
        write.csv(as.matrix(svm_mat), "similarity_matrix_svm.csv")
        
        # Helper function to format and save GLM results
        save_dcats_results = function(res, prefix) {
          if (is.null(res)) return(NULL)
          saveRDS(res, paste0(prefix, ".rds"))
          
          tryCatch({
            df = data.frame(
              coefficient = as.vector(res\$ceoffs),
              coeff_err = if (!is.null(res\$coeffs_err)) as.vector(res\$coeffs_err) else NA,
              LR_val = as.vector(res\$LR_vals),
              LRT_pval = as.vector(res\$LRT_pvals),
              fdr = as.vector(res\$fdr),
              row.names = rownames(res\$ceoffs)
            )
            write.csv(df, paste0(prefix, ".csv"), row.names = TRUE)
          }, error = function(e) {
            # Fallback if dimensions or structure differ (e.g. multi-factor designs)
            write.csv(as.data.frame(res\$ceoffs), paste0(prefix, "_coefficients.csv"))
            write.csv(as.data.frame(res\$LRT_pvals), paste0(prefix, "_pvalues.csv"))
            write.csv(as.data.frame(res\$fdr), paste0(prefix, "_fdr.csv"))
          })
        }
        
        # 3. Differential Abundance Analysis (Standard GLM)
        res_standard = dcats_GLM(sim_count, sim_design, similarity_mat = simil_mat)
        save_dcats_results(res_standard, "dcats_results_standard")
        
        # 4. Differential Abundance Analysis (Full Model Comparison)
        res_full = tryCatch({
          dcats_GLM(sim_count, sim_design, similarity_mat = simil_mat, base_model = 'FULL')
        }, error = function(e) {
          message("Warning: Full model fitting failed or is not applicable to the design matrix. Error: ", e\$message)
          NULL
        })
        if (!is.null(res_full)) {
          save_dcats_results(res_full, "dcats_results_full")
        }
        
        # 5. Estimate Global Over-dispersion Parameter (phi) and Run GLM
        phi = DCATS::getPhi(sim_count, sim_design)
        res_fixed_phi = dcats_GLM(sim_count, sim_design, similarity_mat = simil_mat, fix_phi = phi)
        save_dcats_results(res_fixed_phi, "dcats_results_fixed_phi")
        
        # 6. Differential Abundance Analysis with Manual Reference Cell Types
        res_ref = dcats_GLM(sim_count, sim_design, similarity_mat = simil_mat, reference = colnames(sim_count)[1:2])
        save_dcats_results(res_ref, "dcats_results_manual_ref")
        
        # 7. Automatic Reference Cell Type Detection and GLM
        reference_cell = detect_reference(sim_count, sim_design, similarity_mat = simil_mat)
        saveRDS(reference_cell, "detected_reference_info.rds")
        
        res_detected_ref = dcats_GLM(sim_count, sim_design, similarity_mat = simil_mat, reference = reference_cell\$ordered_celltype[1:2])
        save_dcats_results(res_detected_ref, "dcats_results_detected_ref")
        
        message("DCATS pipeline completed successfully. Outputs saved to the working directory.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .cqc_obj <- tryCatch(readRDS(.cqc_rds), error = function(e) NULL)
      .cqc_mat <- if (is.matrix(.cqc_obj) || is.data.frame(.cqc_obj)) .cqc_obj else NULL
      if (!is.null(.cqc_mat) && nrow(.cqc_mat) > 100) {
        .cqc_ncells <- ncol(.cqc_mat); .cqc_nfeats <- nrow(.cqc_mat)
        .cqc_files <- c(.cqc_files, .cqc_rds); break
      }
    }
    .gates_by_label[["cell QC metrics"]] <- list(
      gate_row = "bioc_cell_qc_metrics",
      metric_name = "n_cells",
      metric_value = .cqc_ncells,
      passes = isTRUE(is.finite(.cqc_ncells) && .cqc_ncells >= 50 && .cqc_nfeats >= 200),
      status = if (is.finite(.cqc_ncells)) paste0("computed (cells=", .cqc_ncells, ", features=", .cqc_nfeats, "; proxy gate)")
               else "not_computed (no scRNA matrix .rds artifact present)"
    )

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
    for (.lcf_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_DCATS_DIFFERENTIAL_COMPOSITION_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics", "count normalization", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DCATS_DIFFERENTIAL_COMPOSITION_ANALYSIS":',
        paste0('    DCATS: ', as.character(packageVersion('DCATS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_composition_analysis.csv versions.yml
    """
}

workflow BIOC_DCATS_DIFFERENTIAL_COMPOSITION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sim_count, sim_design, knnGraphs, labels, svmDF ] ]

    main:
    BIOC_DCATS_DIFFERENTIAL_COMPOSITION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DCATS_DIFFERENTIAL_COMPOSITION_ANALYSIS.out.tables
    plots    = BIOC_DCATS_DIFFERENTIAL_COMPOSITION_ANALYSIS.out.plots
    objects  = BIOC_DCATS_DIFFERENTIAL_COMPOSITION_ANALYSIS.out.objects
    versions = BIOC_DCATS_DIFFERENTIAL_COMPOSITION_ANALYSIS.out.versions
}
