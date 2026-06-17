#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TargetScore — target_score_via_targetscoredata
// Retrieve precomputed sequence scores and validated targets for a specific miRNA and compute target scores.
// Input: miRNA ID, logFC.imputed matrix
// Container: quay.io/biocontainers/bioconductor-targetscore:1.48.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: TargetScore, TargetScoreData, gplots
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load TargetScoreData and gplots libraries
//  * 2. [Core Analysis] Run getTargetScores with miRNA ID
//  * 3. [Core Analysis] (Optional) Retrieve precomputed logFC matrix for multiple miRNAs

nextflow.enable.dsl = 2

process BIOC_TARGETSCORE_TARGET_SCORE_VIA_TARGETSCOREDATA {
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
    .bm_deps <- c("TargetScore", "TargetScoreData", "gplots")
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
            
            # 1. Load TargetScoreData and gplots libraries
            library(TargetScore)
            library(TargetScoreData)
            library(gplots)
            
            # ---------------------------------------------------------
            # Read User Inputs from Working Directory
            # ---------------------------------------------------------
            # Read miRNA ID (default to "hsa-miR-1" if file does not exist)
            if (file.exists("mirna_id.txt")) {
              mirna_id <- trimws(readLines("mirna_id.txt", warn = FALSE)[1])
            } else {
              mirna_id <- "hsa-miR-1"
              writeLines(mirna_id, "mirna_id.txt")
            }
            
            # Read logFC.imputed matrix (optional, precomputed or user-supplied logFC)
            if (file.exists("logFC_imputed.csv")) {
              logFC.imputed <- as.matrix(read.csv("logFC_imputed.csv", row.names = 1, check.names = FALSE))
            } else {
              # Retrieve precomputed logFC matrix using the package function and save it
              logFC.imputed <- get_precomputed_logFC()
              write.csv(as.data.frame(logFC.imputed), "logFC_imputed.csv", row.names = TRUE)
            }
            
            # ---------------------------------------------------------
            # Run Documented Workflow
            # ---------------------------------------------------------
            # 2. Run getTargetScores with miRNA ID and logFC matrix
            myTargetScores <- getTargetScores(mirna_id, logFC.imputed[, mirna_id, drop = FALSE], tol=1e-3, maxiter=200)
            
            # Print validation table
            val_table <- table((myTargetScores\$targetScore > 0.1), myTargetScores\$validated)
            print(val_table)
            
            # 3. Retrieve precomputed logFC matrix for multiple miRNAs
            # (We already loaded/read logFC.imputed above, now we extract the unique miRNA IDs)
            mirIDs <- unique(colnames(logFC.imputed))
            
            # ---------------------------------------------------------
            # Save Outputs
            # ---------------------------------------------------------
            # Save target scores to CSV
            write.csv(as.data.frame(myTargetScores), "target_scores.csv", row.names = TRUE)
            
            # Save validation table to CSV
            write.csv(as.data.frame(val_table), "validation_table.csv", row.names = TRUE)
            
            # Save unique miRNA IDs to a text file
            writeLines(mirIDs, "mir_ids.txt")
            
            message("Pipeline completed successfully. Outputs saved to 'target_scores.csv', 'validation_table.csv', and 'mir_ids.txt'.")
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_TARGETSCORE_TARGET_SCORE_VIA_TARGETSCOREDATA",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_TARGETSCORE_TARGET_SCORE_VIA_TARGETSCOREDATA":',
        paste0('    TargetScore: ', as.character(packageVersion('TargetScore')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_target_score_via_targetscoredata.csv versions.yml
    """
}

workflow BIOC_TARGETSCORE_TARGET_SCORE_VIA_TARGETSCOREDATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ miRNA ID, logFC.imputed matrix ] ]

    main:
    BIOC_TARGETSCORE_TARGET_SCORE_VIA_TARGETSCOREDATA(ch_input)

    emit:
    tables   = BIOC_TARGETSCORE_TARGET_SCORE_VIA_TARGETSCOREDATA.out.tables
    plots    = BIOC_TARGETSCORE_TARGET_SCORE_VIA_TARGETSCOREDATA.out.plots
    objects  = BIOC_TARGETSCORE_TARGET_SCORE_VIA_TARGETSCOREDATA.out.objects
    versions = BIOC_TARGETSCORE_TARGET_SCORE_VIA_TARGETSCOREDATA.out.versions
}
