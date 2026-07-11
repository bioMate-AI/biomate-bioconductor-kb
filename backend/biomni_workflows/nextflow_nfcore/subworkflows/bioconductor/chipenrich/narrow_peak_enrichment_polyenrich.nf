#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chipenrich — narrow_peak_enrichment_polyenrich
// Perform gene set enrichment testing for narrow genomic regions using a count-based model, suitable for high peak counts or enhancer-target gene definitions.
// Input: peaks_E2F4, vignette_genesets.txt
// Container: quay.io/biocontainers/bioconductor-chipenrich:2.34.0--r45hdfd78af_0
// R packages: chipenrich
// Bioconductor: 3.20 | R: 4.4
// Requires: chipenrich
// Visualizations: enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read User Inputs from Working Directory
//  * 2. [Input & Preparation] Run Poly-Enrich (Standard Count-Based Method)
//  * 3. [Input & Preparation] Run Poly-Enrich (Weighted Method & Enhancer Locus)
//  * 4. [Input & Preparation] Generate and Save QC Plots

nextflow.enable.dsl = 2

process BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_POLYENRICH {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("chipenrich")
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
    library(chipenrich)
    
    # ---------------------------------------------------------
    # --- Read User Inputs from Working Directory ---
    # ---------------------------------------------------------
    
    # Locate the peaks_E2F4 file (can be a path to .bed, .narrowPeak, or a text file)
    peaks_input = "peaks_E2F4"
    if (!file.exists(peaks_input)) {
      possible_extensions = c(".bed", ".narrowPeak", ".txt")
      found = FALSE
      for (ext in possible_extensions) {
        test_path = paste0("peaks_E2F4", ext)
        if (file.exists(test_path)) {
          peaks_input = test_path
          found = TRUE
          break
        }
      }
      if (!found) {
        stop("Error: Input file 'peaks_E2F4' (or with .bed/.narrowPeak/.txt extension) not found in the working directory.")
      }
    }
    
    # Assign to the variable name used in the documented code
    peaks_E2F4 = peaks_input
    
    # Define the path to the custom gene sets file
    gs_path = "vignette_genesets.txt"
    if (!file.exists(gs_path)) {
      stop("Error: Input file 'vignette_genesets.txt' not found in the working directory.")
    }
    
    # ---------------------------------------------------------
    # --- Run Poly-Enrich (Standard Count-Based Method) ---
    # ---------------------------------------------------------
    message("Running Poly-Enrich with standard count-based method...")
    
    results_std = polyenrich(
      peaks = peaks_E2F4, 
      genome = 'hg19', 
      genesets = gs_path, 
      method = 'polyenrich', 
      locusdef = "nearest_tss", 
      qc_plots = FALSE, 
      out_name = NULL, 
      n_cores = 1
    )
    results.pe = results_std\$results
    print(results.pe[1:5,1:5])
    
    # Save standard results
    write.csv(results.pe, file = "polyenrich_standard_results.csv", row.names = FALSE)
    saveRDS(results_std, file = "polyenrich_standard_full.rds")
    
    # ---------------------------------------------------------
    # --- Run Poly-Enrich (Weighted Method & Enhancer Locus) ---
    # ---------------------------------------------------------
    message("Running Poly-Enrich with weighted method and enhancer locus definition...")
    
    results_wt = polyenrich(
      peaks = peaks_E2F4, 
      genome = 'hg19', 
      genesets = gs_path, 
      method = "polyenrich_weighted", 
      locusdef = "enhancer_plus5kb", 
      qc_plots = FALSE, 
      out_name = NULL, 
      n_cores = 1
    )
    results.pe = results_wt\$results
    print(results.pe[1:5,1:5])
    
    # Save weighted results
    write.csv(results.pe, file = "polyenrich_weighted_results.csv", row.names = FALSE)
    saveRDS(results_wt, file = "polyenrich_weighted_full.rds")
    
    # ---------------------------------------------------------
    # --- Generate and Save QC Plots ---
    # ---------------------------------------------------------
    tryCatch({
      message("Generating QC plots...")
      pdf("polyenrich_qc_plots.pdf", width = 8, height = 6)
      
      # Peak distance to TSS distribution
      plot_dist_to_tss(peaks = peaks_E2F4, genome = 'hg19')
      
      # Number of peaks versus locus length spline
      plot_polyenrich_spline(peaks = peaks_E2F4, locusdef = 'nearest_tss', genome = 'hg19')
      
      dev.off()
      message("QC plots saved to 'polyenrich_qc_plots.pdf'")
    }, error = function(e) {
      warning("Could not generate QC plots: ", e\$message)
    })
    
    message("Pipeline completed successfully!")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # alignment/mapping QC — workflow-emitted artifact check for common log
    # files (.log, .summary, alignment metrics tables). Binary pass.
    .amqc_logs <- c(list.files(".", pattern = "(?i)(align|map|samtools|flagstat).*\\.(log|txt|summary)\$"),
                    list.files(".", pattern = "(?i)flagstat\\."))
    .amqc_passes <- length(.amqc_logs) > 0
    .gates_by_label[["alignment/mapping QC"]] <- list(
      gate_row = "bioc_alignment_mapping_qc",
      metric_name = "alignment_qc_artifacts",
      metric_value = length(.amqc_logs),
      passes = .amqc_passes,
      status = if (.amqc_passes) paste0("computed (", length(.amqc_logs), " alignment log(s) emitted)")
               else "not_computed (no alignment log/summary artifact present)"
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_POLYENRICH",
      domain  = "bioconductor",
      declared_qc_steps = c("alignment/mapping QC", "low-count filtering", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_POLYENRICH":',
        paste0('    chipenrich: ', as.character(packageVersion('chipenrich')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_narrow_peak_enrichment_polyenrich.csv versions.yml
    """
}

workflow BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_POLYENRICH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peaks_E2F4, vignette_genesets.txt ] ]

    main:
    BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_POLYENRICH(ch_input)

    emit:
    tables   = BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_POLYENRICH.out.tables
    plots    = BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_POLYENRICH.out.plots
    objects  = BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_POLYENRICH.out.objects
    versions = BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_POLYENRICH.out.versions
}
