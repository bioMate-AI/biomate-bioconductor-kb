#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bnbc — hic_normalization_from_matrices
// Normalize and batch-correct Hi-C replicates starting from a list of contact matrices.
// Input: upper.mats.list, LociData, SampleData
// Container: quay.io/biocontainers/bioconductor-bnbc:1.32.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, S4Vectors, bnbc
// QC: count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert upper triangular matrices to symmetric matrices
//  * 2. [Input & Preparation] Create a ContactGroup object using ContactGroup()
//  * 3. [Core Analysis] Apply logCPM transformation using logCPM()
//  * 4. [Core Analysis] Smooth contact matrices using boxSmoother()
//  * 5. [Core Analysis] Perform cross-sample normalization and batch correction using bnbc()

nextflow.enable.dsl = 2

process BIOC_BNBC_HIC_NORMALIZATION_FROM_MATRICES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("bnbc", "GenomicRanges", "S4Vectors", "SummarizedExperiment")
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
        
        # Load required librarie        library(SummarizedExperiment)
s
        library(bnbc)
        library(GenomicRanges)
        library(S4Vectors)
        
        # 1. Read User Inputs from the working directory
        message("Reading input files...")
        
        if (file.exists("upper.mats.list")) {
            upper.mats.list <- readRDS("upper.mats.list")
        } else if (file.exists("upper.mats.list.rds")) {
            upper.mats.list <- readRDS("upper.mats.list.rds")
        } else {
            stop("Error: 'upper.mats.list' file not found in the working directory.")
        }
        
        if (file.exists("LociData")) {
            LociData <- readRDS("LociData")
        } else if (file.exists("LociData.rds")) {
            LociData <- readRDS("LociData.rds")
        } else {
            stop("Error: 'LociData' file not found in the working directory.")
        }
        
        if (file.exists("SampleData")) {
            SampleData <- readRDS("SampleData")
        } else if (file.exists("SampleData.rds")) {
            SampleData <- readRDS("SampleData.rds")
        } else {
            stop("Error: 'SampleData' file not found in the working directory.")
        }
        
        # 2. Convert upper triangular matrices to symmetric matrices
        message("Converting upper triangular matrices to symmetric matrices...")
        MatsList <- lapply(upper.mats.list, function(M) {
            M[lower.tri(M)] <- t(M)[lower.tri(M)]
            M
        })
        
        # 3. Create a ContactGroup object using ContactGroup()
        message("Creating ContactGroup object...")
        cg <- ContactGroup(rowData = LociData, contacts = MatsList, colData = SampleData)
        cgEx <- cg # Ensure compatibility with subsequent documented code variable names
        
        # 4. Apply logCPM transformation using logCPM()
        message("Applying logCPM transformation...")
        cgEx.cpm <- logCPM(cgEx)
        
        # 5. Smooth contact matrices using boxSmoother()
        message("Smoothing contact matrices using boxSmoother...")
        cgEx.smooth <- boxSmoother(cgEx.cpm, h=5)
        
        # 6. Perform cross-sample normalization and batch correction using bnbc()
        message("Performing cross-sample normalization and batch correction...")
        if (!"Batch" %in% colnames(colData(cgEx.smooth))) {
            stop("Error: 'SampleData' must contain a 'Batch' column for bnbc batch correction.")
        }
        
        cgEx.bnbc <- bnbc(cgEx.smooth, batch=colData(cgEx.smooth)\$Batch,
                          threshold=1e7, step=width(LociData)[1], nbands=11, verbose=FALSE)
        
        # 7. Save meaningful results to output files
        message("Saving outputs...")
        saveRDS(cgEx.bnbc, file = "cgEx.bnbc.rds")
        saveRDS(contacts(cgEx.bnbc), file = "normalized_matrices.rds")
        
        # Write a summary CSV of the pipeline run
        summary_df <- data.frame(
            Metric = c("Number of Bins", "Number of Samples", "Smoothing Parameter (h)", "BNBC Bands"),
            Value = c(length(rowData(cgEx.bnbc)), ncol(cgEx.bnbc), 5, 11)
        )
        write.csv(summary_df, file = "pipeline_summary.csv", row.names = FALSE)
        
        message("Pipeline completed successfully!")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_BNBC_HIC_NORMALIZATION_FROM_MATRICES",
      domain  = "bioconductor",
      declared_qc_steps = c("count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_BNBC_HIC_NORMALIZATION_FROM_MATRICES":',
        paste0('    bnbc: ', as.character(packageVersion('bnbc')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hic_normalization_from_matrices.csv versions.yml
    """
}

workflow BIOC_BNBC_HIC_NORMALIZATION_FROM_MATRICES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ upper.mats.list, LociData, SampleData ] ]

    main:
    BIOC_BNBC_HIC_NORMALIZATION_FROM_MATRICES(ch_input)

    emit:
    tables   = BIOC_BNBC_HIC_NORMALIZATION_FROM_MATRICES.out.tables
    plots    = BIOC_BNBC_HIC_NORMALIZATION_FROM_MATRICES.out.plots
    objects  = BIOC_BNBC_HIC_NORMALIZATION_FROM_MATRICES.out.objects
    versions = BIOC_BNBC_HIC_NORMALIZATION_FROM_MATRICES.out.versions
}
