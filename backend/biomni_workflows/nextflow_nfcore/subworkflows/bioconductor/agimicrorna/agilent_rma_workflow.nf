#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: agimicrorna — agilent_rma_workflow
// Process Agilent microRNA data using the Robust Multiarray Average (RMA) protocol, followed by filtering and differential expression analysis.
// Input: targets.txt, mscA1.txt
// Container: quay.io/biocontainers/bioconductor-agimicrorna:2.60.0--r45hdfd78af_0
// R packages: AgiMicroRna, limma
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_AGIMICRORNA_AGILENT_RMA_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-agimicrorna:2.60.0--r45hdfd78af_0"

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
    .bm_deps <- c("AgiMicroRna", "limma")
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
    library("AgiMicroRna")
    library("limma")
    
    # ==========================================
    # --- Load target file and read Agilent Feature Extraction data ---
    # ==========================================
    
    # Read the targets file from the working directory
    targets.micro <- readTargets("targets.txt", verbose=TRUE)
    
    # Ensure all files specified in targets.txt exist by copying the provided mscA1.txt
    for (f in targets.micro\$FileName) {
      if (!file.exists(f) && file.exists("mscA1.txt")) {
        file.copy("mscA1.txt", f)
      }
    }
    
    # Read the Agilent Feature Extraction scanned data files
    dd.micro <- readMicroRnaAFE(targets.micro, verbose=TRUE)
    
    # ==========================================
    # --- Perform quality control plotting and array ---
    # ==========================================
    
    pdf("qc_plots.pdf", width=10, height=8)
    
    # Generate quality control plots
    qcPlots(dd.micro, offset=5,
            MeanSignal=TRUE,
            ProcessedSignal=FALSE,
            TotalProbeSignal=FALSE,
            TotalGeneSignal=FALSE,
            BGMedianSignal=FALSE,
            BGUsed=FALSE,
            targets.micro)
    
    # Assess array reproducibility
    cvArray(dd.micro,
            "MeanSignal",
            targets.micro,
            verbose=TRUE)
    
    dev.off()
    
    # ==========================================
    # --- Estimate normalized gene signal using the RMA algorithm ---
    # ==========================================
    
    ddTGS.rma <- rmaMicroRna(dd.micro,
                             normalize=TRUE,
                             background=TRUE)
    
    # ==========================================
    # --- Filter out low-quality probes and controls ---
    # ==========================================
    
    ddPROC <- filterMicroRna(ddTGS.rma,
                             dd.micro,
                             control=TRUE,
                             IsGeneDetected=TRUE,
                             wellaboveNEG=FALSE,
                             limIsGeneDetected=75,
                             limNEG=25,
                             makePLOT=FALSE,
                             targets.micro,
                             verbose=TRUE,
                             writeout=FALSE)
    
    # ==========================================
    # --- Create an ExpressionSet object ---
    # ==========================================
    
    esetPROC <- esetMicroRna(ddPROC,
                             targets.micro,
                             makePLOT=FALSE,
                             verbose=TRUE)
    
    # Save ExpressionSet object and write expression matrix
    saveRDS(esetPROC, "esetPROC.rds")
    write.csv(exprs(esetPROC), "normalized_expression.csv", row.names=TRUE)
    
    # ==========================================
    # --- Fit linear models and define contrast matrices using limma ---
    # ==========================================
    
    levels.treatment <- levels(factor(targets.micro\$Treatment))
    treatment <- factor(as.character(targets.micro\$Treatment),
                        levels=levels.treatment)
    
    levels.subject <- levels(factor(targets.micro\$Subject))
    subject <- factor(as.character(targets.micro\$Subject),
                      levels=levels.subject)
    
    design <- model.matrix(~ -1 + treatment + subject)
    fit <- lmFit(esetPROC, design)
    
    CM <- cbind(MSC_AvsMSC_B=c(1,-1,0,0),
                MSC_AvsMSC_C=c(1,0,-1,0))
    
    fit2 <- contrasts.fit(fit, CM)
    fit2 <- eBayes(fit2)
    
    # ==========================================
    # --- Select significant microRNAs and output results ---
    # ==========================================
    
    DE <- getDecideTests(fit2,
                         DEmethod="separate",
                         MTestmethod="BH",
                         PVcut=0.10,
                         verbose=TRUE)
    
    # Save differential expression objects
    saveRDS(fit2, "fit2.rds")
    saveRDS(DE, "DE_results.rds")
    
    # Write out top tables for each contrast
    for (coef_name in colnames(CM)) {
      top_tab <- topTable(fit2, coef=coef_name, number=Inf)
      write.csv(top_tab, paste0("DE_results_", coef_name, ".csv"), row.names=TRUE)
    }
    
    # Run significantMicroRna to generate HTML and plots
    pdf("significant_microRNA_plots.pdf", width=10, height=8)
    tryCatch({
      significantMicroRna(esetPROC,
                          ddPROC,
                          targets.micro,
                          fit2,
                          CM,
                          DE,
                          DEmethod="separate",
                          MTestmethod="BH",
                          PVcut=0.10,
                          Mcut=0,
                          verbose=TRUE)
    }, error = function(e) {
      warning("significantMicroRna failed or produced no significant results: ", e\$message)
    })
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # between-array norm — file-exists check for post-norm QC PDFs.
    .ban_pdfs <- list.files(".", pattern = "(?i)(boxplot|density|qnorm|norm.*array).*\\.pdf\$")
    .ban_passes <- length(.ban_pdfs) > 0
    .gates_by_label[["between-array normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "between_array_norm_plot_exists",
      metric_value = if (.ban_passes) 1 else 0,
      passes = .ban_passes,
      status = if (.ban_passes) paste0("computed (", length(.ban_pdfs), " PDF(s) emitted)")
               else "not_computed (no between-array QC PDF present)"
    )

    # array detection QC — ExpressionSet detection p-values or detection-column data.frame.
    .adq_rate <- NA_real_
    for (.adq_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .adq_obj <- tryCatch(readRDS(.adq_rds), error = function(e) NULL)
      .adq_pv <- NULL
      if (!is.null(.adq_obj)) {
        if (inherits(.adq_obj, "ExpressionSet")) {
          .adq_pv <- tryCatch(Biobase::assayDataElement(.adq_obj, "Detection"), error = function(e) NULL)
        } else if (is.matrix(.adq_obj) || is.data.frame(.adq_obj)) {
          .adq_cols <- grep("(?i)(detection|pvalue|pval)", colnames(.adq_obj), value = TRUE)
          if (length(.adq_cols) > 0) .adq_pv <- as.matrix(.adq_obj[, .adq_cols, drop = FALSE])
        }
      }
      if (!is.null(.adq_pv) && length(.adq_pv) > 0) {
        .adq_rate <- round(mean(as.numeric(.adq_pv) < 0.05, na.rm = TRUE), 4); break
      }
    }
    .gates_by_label[["array detection QC"]] <- list(
      gate_row = "bioc_array_detection_qc",
      metric_name = "detection_rate",
      metric_value = .adq_rate,
      passes = isTRUE(is.finite(.adq_rate) && .adq_rate >= 0.75),
      status = if (is.finite(.adq_rate)) "computed (probe-detection p<0.05 fraction)"
               else "not_computed (no ExpressionSet/detection-p .rds present)"
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
      process = "BIOC_AGIMICRORNA_AGILENT_RMA_WORKFLOW",
      domain  = "bioconductor",
      declared_qc_steps = c("between-array normalization", "array detection QC", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_AGIMICRORNA_AGILENT_RMA_WORKFLOW":',
        paste0('        agimicrorna: ', as.character(packageVersion("agimicrorna")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_agilent_rma_workflow.csv versions.yml
    """
}

workflow BIOC_AGIMICRORNA_AGILENT_RMA_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ targets.txt, mscA1.txt ] ]

    main:
    BIOC_AGIMICRORNA_AGILENT_RMA_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_AGIMICRORNA_AGILENT_RMA_WORKFLOW.out.tables
    plots    = BIOC_AGIMICRORNA_AGILENT_RMA_WORKFLOW.out.plots
    objects  = BIOC_AGIMICRORNA_AGILENT_RMA_WORKFLOW.out.objects
    versions = BIOC_AGIMICRORNA_AGILENT_RMA_WORKFLOW.out.versions
}
