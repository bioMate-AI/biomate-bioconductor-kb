#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: messina — binary_classification_messina
// Construct optimal single-gene threshold classifiers to distinguish between two distinct sample classes (e.g., normal vs. tumor).
// Input: expression_matrix.csv, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-messina:1.46.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: messina
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the expression data and class labels
//  * 2. [Core Analysis] Subset the data to the two classes of interest
//  * 3. [Core Analysis] Fit the Messina classification model using the messina function with specified sensitivity and specificity thresholds
//  * 4. [Core Analysis] Inspect the S4 result object to identify features passing performance requirements
//  * 5. [Visualization & Output] Plot the classifier fits, thresholds, and margins using the plot function

nextflow.enable.dsl = 2

process BIOC_MESSINA_BINARY_CLASSIFICATION_MESSINA {
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
    .bm_deps <- c("messina")
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
    library(messina)
    
    # 1. Load the expression data and class labels from user input files
    x_raw = as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
    metadata_raw = read.csv("sample_metadata.csv", check.names = FALSE)
    
    # Align metadata to expression matrix columns
    sample_ids = colnames(x_raw)
    match_idx = match(sample_ids, metadata_raw[[1]])
    if (all(is.na(match_idx))) {
      match_idx = match(sample_ids, rownames(metadata_raw))
    }
    
    # Filter to matched samples
    valid_samples = !is.na(match_idx)
    x_raw = x_raw[, valid_samples, drop = FALSE]
    match_idx = match_idx[valid_samples]
    aligned_metadata = metadata_raw[match_idx, ]
    
    # Extract class labels
    if ("SubType" %in% colnames(aligned_metadata)) {
      raw_class = aligned_metadata\$SubType
    } else {
      raw_class = aligned_metadata[[2]]
    }
    
    # Map the user's binary classes to "normal" and "tumor" to ensure compatibility with the documented code
    unique_classes = unique(na.omit(raw_class))
    if (length(unique_classes) < 2) {
      stop("Metadata must contain at least two distinct classes for binary classification.")
    }
    
    mapped_class = rep(NA, length(raw_class))
    mapped_class[raw_class == unique_classes[1]] = "normal"
    mapped_class[raw_class == unique_classes[2]] = "tumor"
    
    x = x_raw
    y = mapped_class
    
    # 2. Subset the data to the two classes of interest
    sel = y %in% c("normal", "tumor")
    x = x[,sel]
    y = y[sel]
    
    # 3. Fit the Messina classification model using the messina function
    fit.apColon = messina(x, y == "tumor", min_sens = 0.95, min_spec = 0.85, seed = 1234, silent = TRUE)
    
    # 4. Inspect the S4 result object to identify features passing performance requirements
    print(fit.apColon)
    
    # Save the S4 result object and top results table
    saveRDS(fit.apColon, "messina_fit.rds")
    top_results = messinaTopResults(fit.apColon)
    write.csv(top_results, "messina_top_results.csv", row.names = TRUE)
    
    # 5. Plot the classifier fits, thresholds, and margins using the plot function
    pdf("messina_best_feature_plot.pdf")
    plot(fit.apColon, i = 1, plot_type = "point")
    dev.off()
    
    pdf("messina_multiple_features_plot.pdf")
    plot(fit.apColon, i = c(1, 2, 10, 50)[c(1, 2, 10, 50) <= nrow(x)], plot_type = "point")
    dev.off()
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
      process = "BIOC_MESSINA_BINARY_CLASSIFICATION_MESSINA",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MESSINA_BINARY_CLASSIFICATION_MESSINA":',
        paste0('    messina: ', as.character(packageVersion('messina')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_binary_classification_messina.csv versions.yml
    """
}

workflow BIOC_MESSINA_BINARY_CLASSIFICATION_MESSINA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, sample_metadata.csv ] ]

    main:
    BIOC_MESSINA_BINARY_CLASSIFICATION_MESSINA(ch_input)

    emit:
    tables   = BIOC_MESSINA_BINARY_CLASSIFICATION_MESSINA.out.tables
    plots    = BIOC_MESSINA_BINARY_CLASSIFICATION_MESSINA.out.plots
    objects  = BIOC_MESSINA_BINARY_CLASSIFICATION_MESSINA.out.objects
    versions = BIOC_MESSINA_BINARY_CLASSIFICATION_MESSINA.out.versions
}
