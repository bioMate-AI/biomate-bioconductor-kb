#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: msqrob2 — dda_maxquant_peptide_workflow
// Analyze MaxQuant DDA peptide-level data to identify differentially abundant proteins.
// Input: peptides.txt, experimental_design.csv
// Container: quay.io/biocontainers/bioconductor-msqrob2:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ExploreModelMatrix, QFeatures, data.table, dplyr, ggplot2, msqrob2, stringr, tidyr
// Visualizations: volcano plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import peptide table and sample annotations
//  * 2. [Core Analysis] Convert to QFeatures object using readQFeatures
//  * 3. [Core Analysis] Replace zeros with NA using zeroIsNA
//  * 4. [Core Analysis] Log2-transform intensities using logTransform
//  * 5. [Core Analysis] Filter out failed protein inferences, shared peptides, decoys, and contaminants using filterFeatures
//  * 6. [Core Analysis] Filter out highly missing peptides using filterNA
//  * 7. [Core Analysis] Normalize intensities using sweep and nfLogMedian
//  * 8. [Visualization & Output] Summarize peptide intensities to protein level using aggregateFeatures
//  * 9. [Core Analysis] Fit robust linear models using msqrob
//  * 10. [Input & Preparation] Define contrasts using makeContrast and perform hypothesis testing using hypothesisTest
//  * 11. [Visualization & Output] Collect results using msqrobCollect and visualize using plotVolcano

nextflow.enable.dsl = 2

process BIOC_MSQROB2_DDA_MAXQUANT_PEPTIDE_WORKFLOW {
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
    .bm_deps <- c("QFeatures", "dplyr", "tidyr", "ggplot2", "msqrob2", "stringr", "ExploreModelMatrix", "SummarizedExperiment")
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
     library(QFeatures)
            library(dplyr)
            library(tidyr)
            library(ggplot2)
            library(msqrob2)
            library(stringr)
            library(ExploreModelMatrix)
            
            # 1. Import peptide table and sample annotations
            peptides <- data.table::fread("peptides.txt", check.names = TRUE, integer64 = "double")
            annot <- read.csv("experimental_design.csv", stringsAsFactors = FALSE)
            
            # Identify the column in annot that maps to the peptide quantification columns
            # and rename it to "quantCols" as expected by readQFeatures
            quant_col_idx <- which.max(sapply(annot, function(x) sum(as.character(x) %in% colnames(peptides))))
            colnames(annot)[quant_col_idx] <- "quantCols"
            
            # 2. Convert to QFeatures object using readQFeatures
            qf <- readQFeatures(assayData = peptides, colData = annot, name = "peptides", fnames = "Sequence")
            
            # 3. Replace zeros with NA using zeroIsNA
            qf <- zeroIsNA(qf, "peptides")
            
            # 4. Log2-transform intensities using logTransform
            qf <- logTransform(qf, base = 2, i = "peptides", name = "peptides_log")
            
            # 5. Filter out failed protein inferences, shared peptides, decoys, and contaminants using filterFeatures
            qf <- filterFeatures(
              qf, ~ Proteins != "" &
              !grepl(";", Proteins)
            )
            qf <- filterFeatures(
              qf, ~ Reverse != "+" &
              Potential.contaminant != "+"
            )
            
            # 6. Filter out highly missing peptides using filterNA
            nObs <- 3
            n <- ncol(qf[["peptides_log"]])
            qf <- filterNA(qf, i = "peptides_log", pNA = (n - nObs) / n)
            
            # 7. Normalize intensities using sweep and nfLogMedian
            qf <- sweep(
              qf, MARGIN = 2, STATS = nfLogMedian(qf, "peptides_log"), i = "peptides_log", name = "peptides_norm"
            )
            
            # 8. Summarize peptide intensities to protein level using aggregateFeatures
            qf <- aggregateFeatures(
              qf, i = "peptides_norm", fcol = "Proteins", na.rm = TRUE, name = "proteins"
            )
            
            # 9. Fit robust linear models using msqrob
            model <- ~ condition
            qf <- msqrob(
              qf, i = "proteins", formula = model, robust = TRUE
            )
            
            # Visualize design to get parameter names for contrast
            vd <- ExploreModelMatrix::VisualizeDesign(
              sampleData = colData(qf),
              designFormula = model
            )
            
            # 10. Define contrasts using makeContrast and perform hypothesis testing using hypothesisTest
            params <- colnames(vd\$designmatrix)
            contrast_param <- params[params != "(Intercept)"][1]
            contrast_formula <- paste0(contrast_param, " = 0")
            
            L <- makeContrast(
              contrast_formula, parameterNames = params
            )
            qf <- hypothesisTest(qf, i = "proteins", contrast = L)
            
            # 11. Collect results using msqrobCollect and visualize using plotVolcano
            inferences <- msqrobCollect(qf[["proteins"]], L)
            
            # Write outputs
            write.csv(inferences, "msqrob2_results.csv", row.names = TRUE)
            saveRDS(qf, "qf_results.rds")
            
            pdf("volcano_plot.pdf")
            print(inferences |> plotVolcano())
            dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # missing-value handling — scan .rds matrix/data.frame artifacts for max NA fraction
    .mv_na_fracs <- numeric(0)
    .mv_scanned <- character(0)
    for (.mv_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_MSQROB2_DDA_MAXQUANT_PEPTIDE_WORKFLOW",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling", "count normalization", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MSQROB2_DDA_MAXQUANT_PEPTIDE_WORKFLOW":',
        paste0('    msqrob2: ', as.character(packageVersion('msqrob2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dda_maxquant_peptide_workflow.csv versions.yml
    """
}

workflow BIOC_MSQROB2_DDA_MAXQUANT_PEPTIDE_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peptides.txt, experimental_design.csv ] ]

    main:
    BIOC_MSQROB2_DDA_MAXQUANT_PEPTIDE_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_MSQROB2_DDA_MAXQUANT_PEPTIDE_WORKFLOW.out.tables
    plots    = BIOC_MSQROB2_DDA_MAXQUANT_PEPTIDE_WORKFLOW.out.plots
    objects  = BIOC_MSQROB2_DDA_MAXQUANT_PEPTIDE_WORKFLOW.out.objects
    versions = BIOC_MSQROB2_DDA_MAXQUANT_PEPTIDE_WORKFLOW.out.versions
}
