#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ctc — hierarchical_clustering_export
// Perform dual-hierarchical clustering on a feature-by-sample matrix and export the trees and data to Newick and TreeView-compatible formats (ATR, GTR, CDT).
// Input: input.csv
// Container: 1.84.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ctc
// Visualizations: heatmap, dendrogram
// QC: missing-value handling
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CTC_HIERARCHICAL_CLUSTERING_EXPORT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("ctc")
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
    library(ctc)
    
    # Define parameters
    linkage_method <- "complete"
    distance_metric <- "euclidean"
    
    # --- Read and preprocess the input data defensively ---
    if (!file.exists("input.csv")) {
      stop("Input file 'input.csv' not found.")
    }
    
    # Read CSV
    df <- read.csv("input.csv", row.names = NULL, check.names = FALSE)
    
    # Determine row names from 'feature_id' or the first column
    if ("feature_id" %in% colnames(df)) {
      rownames(df) <- df\$feature_id
      df\$feature_id <- NULL
    } else if (is.character(df[[1]]) || is.factor(df[[1]])) {
      rownames(df) <- df[[1]]
      df[[1]] <- NULL
    } else {
      rownames(df) <- paste0("Feature_", seq_len(nrow(df)))
    }
    
    # Convert to numeric matrix
    mat <- as.matrix(df)
    mat <- apply(mat, 2, as.numeric)
    rownames(mat) <- rownames(df)
    
    # Handle missing values and filter out zero-variance rows
    mat <- na.omit(mat)
    if (nrow(mat) < 3 || ncol(mat) < 2) {
      stop("Matrix is too small for meaningful clustering after removing NAs.")
    }
    
    row_vars <- apply(mat, 1, var, na.rm = TRUE)
    mat <- mat[row_vars > 1e-5 & !is.na(row_vars), , drop = FALSE]
    
    if (nrow(mat) < 3) {
      stop("Not enough features with non-zero variance for clustering.")
    }
    
    # --- Perform Hierarchical Clustering ---
    message("Performing hierarchical clustering on rows and columns...")
    # Row clustering (features)
    dist_rows <- dist(mat, method = distance_metric)
    hr <- hclust(dist_rows, method = linkage_method)
    
    # Column clustering (samples)
    dist_cols <- dist(t(mat), method = distance_metric)
    hc <- hclust(dist_cols, method = linkage_method)
    
    # --- Export to Newick Format ---
    message("Exporting trees to Newick format...")
    newick_rows <- ctc::hc2Newick(hr)
    newick_cols <- ctc::hc2Newick(hc)
    
    write(newick_rows, file = "dendrogram_rows.newick")
    write(newick_cols, file = "dendrogram_cols.newick")
    
    # --- Export to TreeView / Freeview Formats (ATR, GTR, CDT) ---
    message("Exporting trees to TreeView formats...")
    ctc::r2atr(hc, file = "treeview_cluster.atr")
    ctc::r2gtr(hr, file = "treeview_cluster.gtr")
    ctc::r2cdt(hr, hc, mat, file = "treeview_cluster.cdt")
    
    # --- Generate Diagnostic Heatmap Visualization ---
    message("Generating diagnostic heatmap...")
    pdf("heatmap_diagnostic.pdf", width = 10, height = 10)
    tryCatch({
      heatmap(
        mat, 
        Rowv = as.dendrogram(hr), 
        Colv = as.dendrogram(hc), 
        scale = "row",
        col = heat.colors(256),
        main = "Hierarchical Clustering Heatmap"
      )
    }, error = function(e) {
      warning("Standard heatmap plotting failed; plotting basic dendrograms instead.")
      par(mfrow = c(2, 1))
      plot(hr, main = "Row Dendrogram", sub = "", xlab = "")
      plot(hc, main = "Column Dendrogram", sub = "", xlab = "")
    })
    dev.off()
    
    message("Pipeline completed successfully.")
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_CTC_HIERARCHICAL_CLUSTERING_EXPORT",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_CTC_HIERARCHICAL_CLUSTERING_EXPORT":',
        paste0('    ctc: ', as.character(packageVersion('ctc')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hierarchical_clustering_export.csv versions.yml
    """
}

workflow BIOC_CTC_HIERARCHICAL_CLUSTERING_EXPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_CTC_HIERARCHICAL_CLUSTERING_EXPORT(ch_input)

    emit:
    tables   = BIOC_CTC_HIERARCHICAL_CLUSTERING_EXPORT.out.tables
    plots    = BIOC_CTC_HIERARCHICAL_CLUSTERING_EXPORT.out.plots
    objects  = BIOC_CTC_HIERARCHICAL_CLUSTERING_EXPORT.out.objects
    versions = BIOC_CTC_HIERARCHICAL_CLUSTERING_EXPORT.out.versions
}
