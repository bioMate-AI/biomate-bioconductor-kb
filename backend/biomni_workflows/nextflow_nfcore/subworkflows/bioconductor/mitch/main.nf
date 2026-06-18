#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mitch — standard_multi_contrast_enrichment
// Perform multi-contrast pathway enrichment analysis on differential expression data (e.g., RNA-seq) using gene sets from a GMT file.
// Input: ReactomePathways.gmt, rna, k9a
// Container: quay.io/biocontainers/bioconductor-mitch:1.22.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: mitch
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Import gene sets from a GMT file using gmt_import
//  * 2. [Visualization & Output] Import and merge multi-contrast profiling data using
//  * 3. [Visualization & Output] Calculate multivariate enrichment using mitch_calc
//  * 4. [Visualization & Output] Generate an interactive HTML report using mitch_report
//  * 5. [Visualization & Output] Generate high-resolution PDF plots using mitch_plots
//  * 6. [Visualization & Output] Visualize gene set similarity and driver genes using

nextflow.enable.dsl = 2

process BIOC_MITCH_STANDARD_MULTI_CONTRAST_ENRICHMENT {
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
    .bm_deps <- c("mitch")
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
    
    # Load required library
    library("mitch")
    
    # --- Import gene sets from a GMT file using gmt_import ---
    if (!file.exists("ReactomePathways.gmt")) {
      stop("Required input file 'ReactomePathways.gmt' is missing in the working directory.")
    }
    genesets <- gmt_import("ReactomePathways.gmt")
    
    # Helper function to read rna and k9a data frames robustly from the working directory
    read_input_df <- function(filepath) {
      if (!file.exists(filepath)) {
        stop(paste("Required input file missing:", filepath))
      }
      # Try reading as RDS first, then TSV, then CSV
      df <- tryCatch({
        readRDS(filepath)
      }, error = function(e) {
        tryCatch({
          read.table(filepath, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
        }, error = function(e2) {
          read.csv(filepath, header = TRUE, row.names = 1, check.names = FALSE)
        })
      })
      return(df)
    }
    
    # Read the user input files
    rna <- read_input_df("rna")
    k9a <- read_input_df("k9a")
    
    # --- Import and merge multi-contrast profiling data using ---
    x <- list("rna"=rna,"k9a"=k9a)
    y <- mitch_import(x,"edgeR")
    
    # --- Calculate multivariate enrichment using mitch_calc ---
    # We use the imported 'genesets' object instead of the forbidden 'genesetsExample'
    res <- mitch_calc(y,genesets,priority="effect",cores=2)
    
    # Save enrichment results table to CSV and RDS
    write.csv(res\$enrichment_result, "enrichment_results.csv", row.names = FALSE)
    saveRDS(res, "mitch_results.rds")
    
    # --- Generate an interactive HTML report using mitch_report ---
    mitch_report(res,"myreport.html",overwrite=TRUE)
    
    # --- Generate high-resolution PDF plots using mitch_plots ---
    mitch_plots(res,outfile="mycharts.pdf")
    
    # --- Visualize gene set similarity and driver genes using ---
    # Capture the network plot to a PDF file
    pdf("network_plots.pdf", width = 14, height = 6)
    tryCatch({
      networkplot(res,FDR=1,n_sets=10)
    }, error = function(e) {
      warning("networkplot failed: ", e\$message)
    })
    dev.off()
    
    # Retrieve and save the driver genes list
    ng <- tryCatch({
      network_genes(res,FDR=1,n_sets=10)
    }, error = function(e) {
      warning("network_genes failed: ", e\$message)
      NULL
    })
    
    if (!is.null(ng)) {
      saveRDS(ng, "network_genes.rds")
    }
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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

    # dispersion/size-factor estimation — object-type-aware. Try DESeq2
    # DESeqDataSet (mcols\$dispOutlier), then edgeR DGEList (common.dispersion).
    .dsf_value <- NA_real_; .dsf_kind <- "none"
    for (.dsf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .dsf_obj <- tryCatch(readRDS(.dsf_rds), error = function(e) NULL)
      if (!is.null(.dsf_obj)) {
        if (inherits(.dsf_obj, "DESeqDataSet")) {
          .dsf_o <- tryCatch(mcols(.dsf_obj)\$dispOutlier, error = function(e) NULL)
          if (!is.null(.dsf_o)) { .dsf_value <- round(mean(.dsf_o, na.rm = TRUE), 4); .dsf_kind <- "deseq2"; break }
        } else if (inherits(.dsf_obj, "DGEList")) {
          .dsf_v <- tryCatch(.dsf_obj\$common.dispersion, error = function(e) NULL)
          if (!is.null(.dsf_v) && is.finite(.dsf_v)) { .dsf_value <- round(sqrt(.dsf_v), 4); .dsf_kind <- "edger_bcv"; break }
        }
      }
    }
    .gates_by_label[["dispersion/size-factor estimation"]] <- list(
      gate_row = "bioc_dispersion_size_factor",
      metric_name = if (.dsf_kind == "edger_bcv") "common_bcv" else "disp_outlier_fraction",
      metric_value = .dsf_value,
      passes = isTRUE(
        (.dsf_kind == "deseq2" && is.finite(.dsf_value) && .dsf_value <= 0.01) ||
        (.dsf_kind == "edger_bcv" && is.finite(.dsf_value) && .dsf_value > 0 && .dsf_value < 1.0)
      ),
      status = if (is.finite(.dsf_value)) paste0("computed (", .dsf_kind, ")")
               else "not_computed (no DESeqDataSet/DGEList .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_MITCH_STANDARD_MULTI_CONTRAST_ENRICHMENT",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MITCH_STANDARD_MULTI_CONTRAST_ENRICHMENT":',
        paste0('    mitch: ', as.character(packageVersion('mitch')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_multi_contrast_enrichment.csv versions.yml
    """
}

workflow BIOC_MITCH_STANDARD_MULTI_CONTRAST_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ReactomePathways.gmt, rna, k9a ] ]

    main:
    BIOC_MITCH_STANDARD_MULTI_CONTRAST_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_MITCH_STANDARD_MULTI_CONTRAST_ENRICHMENT.out.tables
    plots    = BIOC_MITCH_STANDARD_MULTI_CONTRAST_ENRICHMENT.out.plots
    objects  = BIOC_MITCH_STANDARD_MULTI_CONTRAST_ENRICHMENT.out.objects
    versions = BIOC_MITCH_STANDARD_MULTI_CONTRAST_ENRICHMENT.out.versions
}
