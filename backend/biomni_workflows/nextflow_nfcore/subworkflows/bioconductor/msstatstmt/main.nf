#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MSstatsTMT — tmt_differential_abundance_analysis
// Preprocess, normalize, summarize, and perform differential abundance testing on TMT proteomics data.
// Input: raw.pd, annotation.pd
// Container: quay.io/biocontainers/bioconductor-msstatstmt:2.18.0--r45hdfd78af_0
// R packages: MSstatsTMT
// Bioconductor: 3.20 | R: 4.4
// Requires: MSstatsTMT
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read user input files from the working directory
//  * 2. [Visualization & Output] Convert raw search engine output and annotation into
//  * 3. [Visualization & Output] Perform protein-level summarization, missing value
//  * 4. [Visualization & Output] Generate diagnostic profile plots
//  * 5. [Visualization & Output] Test for significant changes in protein abundance
//  * 6. [Visualization & Output] Test for significant changes using a custom contrast

nextflow.enable.dsl = 2

process BIOC_MSSTATSTMT_TMT_DIFFERENTIAL_ABUNDANCE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("MSstatsTMT")
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
    
    # Load required package
    library(MSstatsTMT)
    
    # --- Read user input files from the working directory ---
    # raw.pd is typically a tab-separated Proteome Discoverer PSM export
    raw.pd <- read.delim("raw.pd", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    annotation.pd <- read.csv("annotation.pd", header = TRUE, stringsAsFactors = FALSE)
    
    # --- Convert raw search engine output and annotation into ---
    input.pd <- PDtoMSstatsTMTFormat(raw.pd, annotation.pd, 
                                     which.proteinid = "Protein.Accessions")
    
    # --- Perform protein-level summarization, missing value ---
    quant.msstats <- proteinSummarization(input.pd,
                                          method="msstats",
                                          global_norm=TRUE,
                                          reference_norm=TRUE,
                                          remove_norm_channel = TRUE,
                                          remove_empty_channel = TRUE)
    
    # Save summarization results
    saveRDS(quant.msstats, "quant_msstats.rds")
    if (!is.null(quant.msstats\$ProteinLevelData)) {
      write.csv(quant.msstats\$ProteinLevelData, "quant_msstats_protein_level.csv", row.names = FALSE)
    }
    
    # --- Generate diagnostic profile plots ---
    # This function automatically saves PDF files (e.g., "ProfilePlot.pdf") in the working directory
    dataProcessPlotsTMT(data=quant.msstats,
                         type = 'ProfilePlot',
                         width = 21, # adjust the figure width since there are 15 TMT runs.
                         height = 7)
    
    # --- Test for significant changes in protein abundance ---
    test.pairwise <- groupComparisonTMT(quant.msstats, moderated = TRUE)
    
    # Save pairwise comparison results
    if (!is.null(test.pairwise\$ComparisonResult)) {
      write.csv(test.pairwise\$ComparisonResult, "test_pairwise_results.csv", row.names = FALSE)
    }
    
    # --- Test for significant changes using a custom contrast ---
    # Note: This specific contrast matrix assumes conditions "0.125", "0.5", "0.667", and "1" are present.
    # We wrap this in a tryCatch block to ensure the pipeline remains robust if the user's annotation
    # contains different condition names, while strictly preserving the documented code.
    tryCatch({
      comparison<-matrix(c(-1,0,0,1),nrow=1)
      row.names(comparison)<-"1-0.125"
      colnames(comparison)<- c("0.125", "0.5", "0.667", "1")
    
      test.contrast <- groupComparisonTMT(data = quant.msstats, contrast.matrix = comparison, moderated = TRUE)
      
      if (!is.null(test.contrast\$ComparisonResult)) {
        write.csv(test.contrast\$ComparisonResult, "test_contrast_results.csv", row.names = FALSE)
      }
    }, error = function(e) {
      warning("Custom contrast comparison could not be completed. Check if condition names match '0.125', '0.5', '0.667', '1'. Error: ", e\$message)
    })
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
      process = "BIOC_MSSTATSTMT_TMT_DIFFERENTIAL_ABUNDANCE_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling", "count normalization", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MSSTATSTMT_TMT_DIFFERENTIAL_ABUNDANCE_ANALYSIS":',
        paste0('    MSstatsTMT: ', as.character(packageVersion('MSstatsTMT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tmt_differential_abundance_analysis.csv versions.yml
    """
}

workflow BIOC_MSSTATSTMT_TMT_DIFFERENTIAL_ABUNDANCE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw.pd, annotation.pd ] ]

    main:
    BIOC_MSSTATSTMT_TMT_DIFFERENTIAL_ABUNDANCE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MSSTATSTMT_TMT_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.tables
    plots    = BIOC_MSSTATSTMT_TMT_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.plots
    objects  = BIOC_MSSTATSTMT_TMT_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.objects
    versions = BIOC_MSSTATSTMT_TMT_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.versions
}
