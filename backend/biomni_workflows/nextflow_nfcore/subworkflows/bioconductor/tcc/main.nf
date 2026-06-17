#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TCC — two_group_replicates
// Perform robust differential expression analysis on two-group RNA-seq count data with biological replicates using iterative iDEGES/edgeR normalization.
// Input: hypoData, group
// Container: quay.io/biocontainers/bioconductor-tcc:1.50.0--r45hdfd78af_0
// R packages: roc, TCC
// Bioconductor: 3.20 | R: 4.4
// Requires: TCC
// Visualizations: plot (ggplot/base)
// QC: TMM normalization, low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Input Files
//  * 2. [Visualization & Output] Execute TCC Workflow
//  * 3. [Visualization & Output] Write Output Files

nextflow.enable.dsl = 2

process BIOC_TCC_TWO_GROUP_REPLICATES {
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
    .bm_deps <- c("roc", "TCC")
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
    
    # Load required library
    library(TCC)
    
    # ---------------------------------------------------------
    # --- Read User Input Files ---
    # ---------------------------------------------------------
    # Locate and read the raw count matrix (hypoData)
    hypoData_file <- NULL
    for (f in c("hypoData", "hypoData.csv", "hypoData.tsv", "hypoData.txt", "hypoData.rds")) {
      if (file.exists(f)) {
        hypoData_file <- f
        break
      }
    }
    if (is.null(hypoData_file)) {
      stop("Error: hypoData file not found in the working directory.")
    }
    
    if (grepl("\\\\.rds\$", hypoData_file, ignore.case = TRUE)) {
      hypoData <- readRDS(hypoData_file)
    } else if (grepl("\\\\.csv\$", hypoData_file, ignore.case = TRUE)) {
      hypoData <- as.matrix(read.csv(hypoData_file, row.names = 1, check.names = FALSE))
    } else {
      hypoData <- as.matrix(read.table(hypoData_file, header = TRUE, row.names = 1, check.names = FALSE))
    }
    
    # Locate and read the group membership vector (group)
    group_file <- NULL
    for (f in c("group", "group.csv", "group.tsv", "group.txt", "group.rds")) {
      if (file.exists(f)) {
        group_file <- f
        break
      }
    }
    if (is.null(group_file)) {
      stop("Error: group file not found in the working directory.")
    }
    
    if (grepl("\\\\.rds\$", group_file, ignore.case = TRUE)) {
      group <- readRDS(group_file)
    } else {
      lines <- readLines(group_file)
      lines <- lines[lines != ""]
      if (length(lines) == 1 && grepl(",", lines)) {
        group <- as.numeric(strsplit(lines, ",")[[1]])
      } else {
        group <- as.numeric(lines)
      }
    }
    
    # ---------------------------------------------------------
    # --- Execute TCC Workflow ---
    # ---------------------------------------------------------
    # Construct TCC class object
    tcc <- new("TCC", hypoData, group)
    
    # Filter out low-count genes
    tcc <- filterLowCountGenes(tcc)
    
    # Calculate robust normalization factors using iterative iDEGES/edgeR
    tcc <- calcNormFactors(tcc, norm.method = "tmm", test.method = "edger", 
                           iteration = 3, FDR = 0.1, floorPDEG = 0.05)
    
    # Perform differential expression analysis using edgeR
    tcc <- estimateDE(tcc, test.method = "edger", FDR = 0.1)
    
    # Retrieve results table
    result <- getResult(tcc, sort = TRUE)
    head(result)
    
    # Print DEG summary to console
    print(table(tcc\$estimatedDEG))
    
    # Retrieve normalized count data
    normalized.count <- getNormalizedData(tcc)
    
    # ---------------------------------------------------------
    # --- Write Output Files ---
    # ---------------------------------------------------------
    # Save DE results table
    write.csv(result, "tcc_de_results.csv", row.names = FALSE)
    
    # Save DEG summary table
    deg_summary <- table(tcc\$estimatedDEG)
    write.table(deg_summary, "tcc_deg_summary.txt", col.names = FALSE, quote = FALSE)
    
    # Save M-A plot as PDF
    pdf("tcc_ma_plot.pdf")
    plot(tcc)
    dev.off()
    
    # Save normalized count data
    write.csv(normalized.count, "tcc_normalized_counts.csv")
    
    # Save the complete TCC object
    saveRDS(tcc, "tcc_object.rds")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # TMM normalization — DGEList\$samples\$norm.factors set (Robinson & Oshlack 2010).
    .tmm_factors <- NULL; .tmm_n_nontrivial <- NA_real_
    for (.tmm_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .tmm_obj <- tryCatch(readRDS(.tmm_rds), error = function(e) NULL)
      if (!is.null(.tmm_obj) && inherits(.tmm_obj, "DGEList")) {
        .tmm_f <- tryCatch(.tmm_obj\$samples\$norm.factors, error = function(e) NULL)
        if (!is.null(.tmm_f) && length(.tmm_f) > 0) {
          .tmm_factors <- .tmm_f; .tmm_n_nontrivial <- sum(abs(.tmm_f - 1.0) > 1e-6); break
        }
      }
    }
    .gates_by_label[["TMM normalization"]] <- list(
      gate_row = "bioc_tmm_normalization",
      metric_name = "n_nontrivial_norm_factors",
      metric_value = .tmm_n_nontrivial,
      passes = isTRUE(is.finite(.tmm_n_nontrivial) && .tmm_n_nontrivial > 0),
      status = if (is.finite(.tmm_n_nontrivial)) paste0("computed (n=", length(.tmm_factors), ", nontrivial=", .tmm_n_nontrivial, ")")
               else "not_computed (no DGEList .rds artifact present)"
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
      process = "BIOC_TCC_TWO_GROUP_REPLICATES",
      domain  = "bioconductor",
      declared_qc_steps = c("TMM normalization", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_TCC_TWO_GROUP_REPLICATES":',
        paste0('    TCC: ', as.character(packageVersion('TCC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_group_replicates.csv versions.yml
    """
}

workflow BIOC_TCC_TWO_GROUP_REPLICATES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hypoData, group ] ]

    main:
    BIOC_TCC_TWO_GROUP_REPLICATES(ch_input)

    emit:
    tables   = BIOC_TCC_TWO_GROUP_REPLICATES.out.tables
    plots    = BIOC_TCC_TWO_GROUP_REPLICATES.out.plots
    objects  = BIOC_TCC_TWO_GROUP_REPLICATES.out.objects
    versions = BIOC_TCC_TWO_GROUP_REPLICATES.out.versions
}
