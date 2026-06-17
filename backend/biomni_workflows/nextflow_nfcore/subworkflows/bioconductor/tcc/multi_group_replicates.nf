#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TCC — multi_group_replicates
// Perform robust differential expression analysis on multi-group RNA-seq count data with replicates.
// Input: hypoData_mg, group
// Container: quay.io/biocontainers/bioconductor-tcc:1.50.0--r45hdfd78af_0
// R packages: TCC
// Bioconductor: 3.20 | R: 4.4
// Requires: TCC
// Visualizations: MA plot
// QC: TMM normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct a TCC class object
//  * 2. [Input & Preparation] Calculate robust normalization factors using DEGES/edgeR
//  * 3. [Input & Preparation] Perform multi-group differential expression analysis
//  * 4. [Input & Preparation] Retrieve the results table

nextflow.enable.dsl = 2

process BIOC_TCC_MULTI_GROUP_REPLICATES {
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
    .bm_deps <- c("TCC")
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
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read hypoData_mg (matrix of raw integer counts)
    if (file.exists("hypoData_mg.rds")) {
      hypoData_mg <- readRDS("hypoData_mg.rds")
    } else if (file.exists("hypoData_mg.csv")) {
      hypoData_mg <- as.matrix(read.csv("hypoData_mg.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("hypoData_mg.tsv")) {
      hypoData_mg <- as.matrix(read.delim("hypoData_mg.tsv", row.names = 1, check.names = FALSE))
    } else if (file.exists("hypoData_mg.txt")) {
      hypoData_mg <- as.matrix(read.table("hypoData_mg.txt", header = TRUE, row.names = 1, check.names = FALSE))
    } else {
      stop("Error: hypoData_mg file (RDS, CSV, TSV, or TXT) not found in the working directory.")
    }
    
    # Read group (numeric vector indicating group membership)
    if (file.exists("group.rds")) {
      group <- readRDS("group.rds")
    } else if (file.exists("group.csv")) {
      group_df <- read.csv("group.csv", header = FALSE)
      if (ncol(group_df) > 1) {
        group <- as.vector(t(group_df))
      } else {
        group <- group_df[[1]]
      }
    } else if (file.exists("group.txt")) {
      group <- scan("group.txt", quiet = TRUE)
    } else {
      stop("Error: group file (RDS, CSV, or TXT) not found in the working directory.")
    }
    
    # Ensure count matrix contains integer values
    if (!is.integer(hypoData_mg)) {
      hypoData_mg <- round(hypoData_mg)
    }
    
    # ==========================================
    # 2. TCC Workflow Execution
    # ==========================================
    
    # --- Construct a TCC class object ---
    tcc <- new("TCC", hypoData_mg, group)
    
    # --- Calculate robust normalization factors using DEGES/edgeR ---
    tcc <- calcNormFactors(tcc, norm.method = "tmm", test.method = "edger",
                           iteration = 1)
    
    # --- Perform multi-group differential expression analysis ---
    tcc <- estimateDE(tcc, test.method = "edger", FDR = 0.1)
    
    # --- Retrieve the results table ---
    result <- getResult(tcc, sort = TRUE)
    
    # Print summary results to console
    cat("=== HEAD OF RESULTS ===\n")
    print(head(result))
    cat("\n=== ESTIMATED DEG SUMMARY ===\n")
    print(table(tcc\$estimatedDEG))
    
    # ==========================================
    # 3. Write Output Files
    # ==========================================
    
    # Save the full results table
    write.csv(result, "tcc_results.csv", row.names = FALSE)
    
    # Save the normalized count matrix
    normalized_counts <- getNormalizedData(tcc)
    write.csv(normalized_counts, "normalized_counts.csv", row.names = TRUE)
    
    # Save the final TCC object as an RDS file
    saveRDS(tcc, "tcc_object.rds")
    
    # Generate and save the MA plot
    pdf("ma_plot.pdf")
    plot(tcc)
    dev.off()
    
    cat("\nPipeline completed successfully. Outputs written to:\n")
    cat("- tcc_results.csv\n")
    cat("- normalized_counts.csv\n")
    cat("- tcc_object.rds\n")
    cat("- ma_plot.pdf\n")
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_TCC_MULTI_GROUP_REPLICATES",
      domain  = "bioconductor",
      declared_qc_steps = c("TMM normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_TCC_MULTI_GROUP_REPLICATES":',
        paste0('    TCC: ', as.character(packageVersion('TCC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_group_replicates.csv versions.yml
    """
}

workflow BIOC_TCC_MULTI_GROUP_REPLICATES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hypoData_mg, group ] ]

    main:
    BIOC_TCC_MULTI_GROUP_REPLICATES(ch_input)

    emit:
    tables   = BIOC_TCC_MULTI_GROUP_REPLICATES.out.tables
    plots    = BIOC_TCC_MULTI_GROUP_REPLICATES.out.plots
    objects  = BIOC_TCC_MULTI_GROUP_REPLICATES.out.objects
    versions = BIOC_TCC_MULTI_GROUP_REPLICATES.out.versions
}
