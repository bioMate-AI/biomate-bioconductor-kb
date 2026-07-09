#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: knowyourcg — feature_aggregation_and_annotation
// Aggregate CpG-level beta values into database-level summary statistics (e.g., mean) for downstream modeling, or annotate an arbitrary probe set.
// Input: betas, query
// Container: quay.io/biocontainers/bioconductor-knowyourcg:1.6.3--r45h01b2380_0
// R packages: SummarizedExperiment, knowYourCG, sesameData, wheatmap
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: heatmap

nextflow.enable.dsl = 2

process BIOC_KNOWYOURCG_FEATURE_AGGREGATION_AND_ANNOTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-knowyourcg:1.6.3--r45h01b2380_0"

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
    .bm_deps <- c("SummarizedExperiment", "knowYourCG", "sesameData", "wheatmap")
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
    library(knowYourCG)
    library(sesameData)
    library(SummarizedExperiment)
    
    # -------------------------------------------------------------------------
    # --- Read User Input Files ---
    # -------------------------------------------------------------------------
    
    # Read betas matrix
    if (file.exists("betas.rds")) {
      betas <- readRDS("betas.rds")
    } else if (file.exists("betas.csv")) {
      betas <- as.matrix(read.csv("betas.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("betas.tsv")) {
      betas <- as.matrix(read.delim("betas.tsv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: betas file (betas.rds, betas.csv, or betas.tsv) not found in the working directory.")
    }
    
    # Ensure betas is a numeric matrix
    if (!is.matrix(betas)) {
      betas <- as.matrix(betas)
    }
    storage.mode(betas) <- "numeric"
    
    # Read query probe IDs
    if (file.exists("query.rds")) {
      query <- readRDS("query.rds")
    } else if (file.exists("query.txt")) {
      query <- readLines("query.txt")
    } else if (file.exists("query.csv")) {
      query_df <- read.csv("query.csv", header = FALSE)
      query <- as.character(query_df[[1]])
    } else {
      stop("Error: query file (query.rds, query.txt, or query.csv) not found in the working directory.")
    }
    
    # Ensure query is a character vector
    query <- as.character(query)
    
    # -------------------------------------------------------------------------
    # --- Feature Aggregation (dbStats) ---
    # -------------------------------------------------------------------------
    # Calculate summary statistics (e.g., mean) across database sets
    stats <- dbStats(betas, 'MM285.chromHMM')
    
    # Save the aggregated statistics
    write.csv(stats, "db_stats.csv", row.names = TRUE)
    saveRDS(stats, "db_stats.rds")
    
    # -------------------------------------------------------------------------
    # --- Feature Annotation (annoProbes) ---
    # -------------------------------------------------------------------------
    # Annotate the arbitrary probe set
    anno <- annoProbes(query, "designGroup", silent = TRUE)
    
    # Save the annotations
    anno_df <- data.frame(Probe_ID = names(anno), Annotation = as.character(anno), row.names = NULL)
    write.csv(anno_df, "probe_annotations.csv", row.names = FALSE)
    saveRDS(anno, "probe_annotations.rds")
    
    # -------------------------------------------------------------------------
    # --- Visualization (Optional Heatmap of dbStats) ---
    # -------------------------------------------------------------------------
    pdf("db_stats_heatmap.pdf", width = 10, height = 8)
    tryCatch({
      library(wheatmap)
      WHeatmap(both.cluster(stats)\$mat, xticklabels = TRUE, cmp = CMPar(stop.points = c("blue", "yellow")))
    }, error = function(e) {
      # Fallback to base R heatmap if wheatmap is not fully configured or fails
      heatmap(as.matrix(stats), Colv = NA, scale = "none", margins = c(10, 5))
    })
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_KNOWYOURCG_FEATURE_AGGREGATION_AND_ANNOTATION",
      domain  = "bioconductor",
      declared_qc_steps = c("array detection QC", "alignment/mapping QC", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_KNOWYOURCG_FEATURE_AGGREGATION_AND_ANNOTATION":',
        paste0('        knowyourcg: ', as.character(packageVersion("knowyourcg")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_feature_aggregation_and_annotation.csv versions.yml
    """
}

workflow BIOC_KNOWYOURCG_FEATURE_AGGREGATION_AND_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ betas, query ] ]

    main:
    BIOC_KNOWYOURCG_FEATURE_AGGREGATION_AND_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_KNOWYOURCG_FEATURE_AGGREGATION_AND_ANNOTATION.out.tables
    plots    = BIOC_KNOWYOURCG_FEATURE_AGGREGATION_AND_ANNOTATION.out.plots
    objects  = BIOC_KNOWYOURCG_FEATURE_AGGREGATION_AND_ANNOTATION.out.objects
    versions = BIOC_KNOWYOURCG_FEATURE_AGGREGATION_AND_ANNOTATION.out.versions
}
