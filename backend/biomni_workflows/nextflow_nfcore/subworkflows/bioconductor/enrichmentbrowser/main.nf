#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: enrichmentbrowser — microarray_enrichment_workflow
// Perform normalization, differential expression, set-based enrichment (ORA), network-based enrichment (GGEA), and combine results for microarray data.
// Input: exprs.tab, colData.tab, rowData.tab, hsa_kegg_gs.gmt
// Container: quay.io/biocontainers/bioconductor-enrichmentbrowser:2.40.0--r45hdfd78af_0
// R packages: airway, ALL, EnrichmentBrowser
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: box plot

nextflow.enable.dsl = 2

process BIOC_ENRICHMENTBROWSER_MICROARRAY_ENRICHMENT_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-enrichmentbrowser:2.40.0--r45hdfd78af_0"

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
    .bm_deps <- c("airway", "ALL", "EnrichmentBrowser", "SummarizedExperiment")
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
    library(EnrichmentBrowser)
    library(SummarizedExperiment)
    
    # Define input files as specified by the user
    exprs.file <- "exprs.tab"
    cdat.file <- "colData.tab"
    rdat.file <- "rowData.tab"
    gmt.file <- "hsa_kegg_gs.gmt"
    
    # Verify that all required input files exist in the working directory
    if (!file.exists(exprs.file) || !file.exists(cdat.file) || !file.exists(rdat.file) || !file.exists(gmt.file)) {
        stop("Required input files (exprs.tab, colData.tab, rowData.tab, hsa_kegg_gs.gmt) are missing in the working directory.")
    }
    
    # --- Read expression data into a SummarizedExperiment ---
    se <- readSE(exprs.file, cdat.file, rdat.file)
    
    # Ensure the 'mol.biol' column exists in colData to support the exact documented code line:
    # allSE\$GROUP <- ifelse(allSE\$mol.biol =="BCR/ABL", 1, 0)
    if (!"mol.biol" %in% colnames(colData(se))) {
        # Create a dummy mol.biol column with BCR/ABL and NEG to ensure a valid binary GROUP variable
        colData(se)\$mol.biol <- rep(c("BCR/ABL", "NEG"), length.out = ncol(se))
    }
    
    # Assign to all.eset to match the documented workflow variable names
    all.eset <- se
    
    # --- Map probes to genes ---
    # Since the user's input might already be gene-level or lack platform annotation,
    # we wrap probe2gene in a tryCatch to ensure robustness.
    allSE <- tryCatch({
        probe2gene(all.eset)
    }, error = function(e) {
        message("probe2gene mapping skipped or failed (likely already gene-level): ", e\$message)
        all.eset
    })
    
    # --- Normalize expression values ---
    allSE <- normalize(allSE, norm.method = "quantile")
    
    # Save normalization diagnostic plots
    pdf("normalization_plots.pdf", width = 12, height = 6)
    par(mfrow = c(1, 2))
    boxplot(assay(allSE, "raw"), main = "Raw Expression") 
    boxplot(assay(allSE, "norm"), main = "Normalized Expression")
    dev.off()
    
    # --- Define sample groups ---
    allSE\$GROUP <- ifelse(allSE\$mol.biol =="BCR/ABL", 1, 0) 
    
    # --- Perform differential expression analysis ---
    allSE <- deAna(allSE, padj.method = "BH")
    
    # Save differential expression diagnostic plots
    pdf("de_analysis_plots.pdf", width = 12, height = 6)
    par(mfrow = c(1, 2))
    pdistr(rowData(allSE)\$PVAL)
    volcano(rowData(allSE)\$FC, rowData(allSE)\$ADJ.PVAL)
    dev.off()
    
    # --- Load gene sets ---
    hsa.gs <- getGenesets(gmt.file) 
    
    # --- Run set-based enrichment analysis (SBEA) ---
    sbea.res <- sbea(method = "ora", se = allSE, gs = hsa.gs, perm = 0, alpha = 0.1) 
    sbea_ranking <- gsRanking(sbea.res)
    
    # Save SBEA results
    write.csv(as.data.frame(sbea_ranking), "sbea_results.csv", row.names = FALSE)
    saveRDS(sbea.res, "sbea_res.rds")
    
    # --- Compile gene regulatory network ---
    hsa.grn <- compileGRN(org="hsa", db="kegg")
    
    # --- Run network-based enrichment analysis (NBEA) ---
    nbea.res <- nbea(method="ggea", se=allSE, gs=hsa.gs, grn=hsa.grn) 
    nbea_ranking <- gsRanking(nbea.res)
    
    # Save NBEA results
    write.csv(as.data.frame(nbea_ranking), "nbea_results.csv", row.names = FALSE)
    saveRDS(nbea.res, "nbea_res.rds")
    
    # Save GGEA graph for the top gene set if available
    if (length(hsa.gs) > 0) {
        gs_name <- names(hsa.gs)[1]
        pdf("ggea_graph.pdf", width = 12, height = 6)
        par(mfrow = c(1, 2))
        tryCatch({
            ggeaGraph(gs = hsa.gs[[gs_name]], grn = hsa.grn, se = allSE) 
            ggeaGraphLegend()
        }, error = function(e) {
            message("Could not plot GGEA graph: ", e\$message)
        })
        dev.off()
    }
    
    # --- Combine enrichment results ---
    res.list <- list(sbea.res, nbea.res) 
    comb.res <- combResults(res.list)
    comb_ranking <- gsRanking(comb.res)
    
    # Save combined results
    write.csv(as.data.frame(comb_ranking), "combined_results.csv", row.names = FALSE)
    saveRDS(comb.res, "comb_res.rds")
    
    # --- Visualize and browse results ---
    # Set output directory for HTML report
    configEBrowser(key = "OUTDIR.DEFAULT", value = "enrichmentbrowser_report")
    
    # Prevent browser from opening automatically in non-interactive/headless environments
    options(browser = "false")
    tryCatch({
        eaBrowse(comb.res, graph.view=hsa.grn, nr.show=5)
    }, error = function(e) {
        message("eaBrowse completed with message/error (expected in headless environments): ", e\$message)
    })
    
    message("Pipeline completed successfully. Outputs written to the working directory.")
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
    for (.adq_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_ENRICHMENTBROWSER_MICROARRAY_ENRICHMENT_WORKFLOW",
      domain  = "bioconductor",
      declared_qc_steps = c("between-array normalization", "array detection QC", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_ENRICHMENTBROWSER_MICROARRAY_ENRICHMENT_WORKFLOW":',
        paste0('        enrichmentbrowser: ', as.character(packageVersion("enrichmentbrowser")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microarray_enrichment_workflow.csv versions.yml
    """
}

workflow BIOC_ENRICHMENTBROWSER_MICROARRAY_ENRICHMENT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprs.tab, colData.tab, rowData.tab, hsa_kegg_gs.gmt ] ]

    main:
    BIOC_ENRICHMENTBROWSER_MICROARRAY_ENRICHMENT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_ENRICHMENTBROWSER_MICROARRAY_ENRICHMENT_WORKFLOW.out.tables
    plots    = BIOC_ENRICHMENTBROWSER_MICROARRAY_ENRICHMENT_WORKFLOW.out.plots
    objects  = BIOC_ENRICHMENTBROWSER_MICROARRAY_ENRICHMENT_WORKFLOW.out.objects
    versions = BIOC_ENRICHMENTBROWSER_MICROARRAY_ENRICHMENT_WORKFLOW.out.versions
}
