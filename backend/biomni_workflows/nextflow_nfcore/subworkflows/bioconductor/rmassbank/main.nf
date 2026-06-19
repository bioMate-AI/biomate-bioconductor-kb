#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rmassbank — msms_spectral_processing
// Extract, analyze, recalibrate, and filter MS/MS spectra from raw LC-MS data files.
// Input: mysettings.ini, Compoundlist.csv, raw_spectra.mzML
// Container: quay.io/biocontainers/bioconductor-rmassbank:3.20.0--r45ha27e39d_0
// R packages: RMassBank
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_RMASSBANK_MSMS_SPECTRAL_PROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rmassbank:3.20.0--r45ha27e39d_0"

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
    .bm_deps <- c("RMassBank")
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
    library(RMassBank)
    
    # --- Generate and load settings ---
    # If mysettings.ini exists, we back it up, run the template generator as documented,
    # then restore it to use the user's settings.
    user_settings_exist <- file.exists("mysettings.ini")
    if (user_settings_exist) {
      file.copy("mysettings.ini", "mysettings.ini.bak", overwrite = TRUE)
    }
    
    RmbSettingsTemplate("mysettings.ini")
    
    if (user_settings_exist) {
      file.copy("mysettings.ini.bak", "mysettings.ini", overwrite = TRUE)
      file.remove("mysettings.ini.bak")
    }
    
    loadRmbSettings("mysettings.ini")
    
    # --- Initialize workspace and load compound list ---
    w <- newMsmsWorkspace()
    
    # Read the user's raw_spectra.mzML file from the working directory
    files <- list.files(".", "raw_spectra.mzML", full.names = TRUE)
    if (length(files) == 0) {
      files <- "raw_spectra.mzML"
    }
    basename(files)
    
    # Ensure we have at least 2 elements to satisfy files[1:2] without NA
    if (length(files) < 2) {
      files <- rep(files, 2)
    }
    w@files <- files[1:2]
    
    loadList("./Compoundlist.csv")
    
    # --- Run msmsWorkflow steps 1 to 4 ---
    w <- msmsWorkflow(w, mode="pH", steps=c(1:4), archivename = 
    				"pH_narcotics")
    
    # --- Plot and inspect the recalibration curve ---
    pdf("recalibration_curve.pdf")
    plotRecalibration(w)
    dev.off()
    
    # Save the current workspace to act as the stored workspace for the next steps
    save(w, file = "pH_narcotics_RF.RData")
    
    # Load the stored workspace (replacing system.file with local file)
    storedW <- loadMsmsWorkspace("pH_narcotics_RF.RData")
    
    storedW <- msmsWorkflow(storedW, mode="pH", steps=4)
    
    w@rc <- storedW@parent@rc
    w@rc.ms1 <- storedW@parent@rc.ms1
    
    w <- msmsWorkflow(w, mode="pH", steps=4, archivename = 
    	"pH_narcotics", newRecalibration = FALSE)
    
    # --- Run msmsWorkflow steps 5 to 8 ---
    w <- msmsWorkflow(w, mode="pH", steps=c(5:8), archivename = 
    		"pH_narcotics")
    
    # Save final results
    saveRDS(w, "final_workspace.rds")
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
      process = "BIOC_RMASSBANK_MSMS_SPECTRAL_PROCESSING",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling", "count normalization", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_RMASSBANK_MSMS_SPECTRAL_PROCESSING":',
        paste0('        rmassbank: ', as.character(packageVersion("rmassbank")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msms_spectral_processing.csv versions.yml
    """
}

workflow BIOC_RMASSBANK_MSMS_SPECTRAL_PROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mysettings.ini, Compoundlist.csv, raw_spectra.mzML ] ]

    main:
    BIOC_RMASSBANK_MSMS_SPECTRAL_PROCESSING(ch_input)

    emit:
    tables   = BIOC_RMASSBANK_MSMS_SPECTRAL_PROCESSING.out.tables
    plots    = BIOC_RMASSBANK_MSMS_SPECTRAL_PROCESSING.out.plots
    objects  = BIOC_RMASSBANK_MSMS_SPECTRAL_PROCESSING.out.objects
    versions = BIOC_RMASSBANK_MSMS_SPECTRAL_PROCESSING.out.versions
}
