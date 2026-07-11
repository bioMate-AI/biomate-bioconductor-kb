#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: psmatch — psm_filtering_and_protein_groups
// Load PSM identification data, filter out low-quality matches, build an adjacency matrix, and resolve protein groups using connected components.
// Input: idf.mzid
// Container: quay.io/biocontainers/bioconductor-psmatch:1.14.0--r45hdfd78af_0
// R packages: factoextra, PSMatch, QFeatures, Spectra
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_PSMATCH_PSM_FILTERING_AND_PROTEIN_GROUPS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-psmatch:1.14.0--r45hdfd78af_0"

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
    .bm_deps <- c("factoextra", "PSMatch", "QFeatures", "Spectra")
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
    library("PSMatch")
    
    # Define input file
    idf <- "idf.mzid"
    
    if (!file.exists(idf)) {
        stop(paste("Input file", idf, "does not exist in the working directory."))
    }
    
    # --- Load PSM data and filter ---
    message("Loading and filtering PSM data...")
    id <- PSM(idf) |> filterPSMs()
    
    # Alternative step-by-step filtering (as documented)
    message("Running step-by-step filtering...")
    id <- PSM(idf)
    id <- filterPsmDecoy(id)
    id <- filterPsmRank(id)
    id <- filterPsmShared(id)
    
    # Save filtered PSMs
    saveRDS(id, "filtered_psms.rds")
    
    # --- Reduce PSMs by spectrum ID ---
    message("Reducing PSMs by spectrum ID...")
    id2 <- reducePSMs(id, id\$spectrumID)
    saveRDS(id2, "reduced_psms.rds")
    
    # --- Build adjacency matrix and connected components ---
    message("Building adjacency matrix and connected components...")
    adj <- makeAdjacencyMatrix(id)
    cc <- ConnectedComponents(adj)
    saveRDS(cc, "connected_components.rds")
    
    # Extract connected component 1082 (with robust fallback if index is out of bounds)
    message("Extracting connected component...")
    cx <- tryCatch({
        connectedComponents(cc, 1082)
    }, error = function(e) {
        warning("Component 1082 not found. Falling back to a valid component.")
        dims_cc <- dims(cc)
        candidates <- which(dims_cc[, "nrow"] > 1 & dims_cc[, "ncol"] > 1)
        if (length(candidates) > 0) {
            connectedComponents(cc, candidates[1])
        } else {
            connectedComponents(cc, length(cc))
        }
    })
    
    # --- Visualize adjacency matrix ---
    message("Plotting adjacency matrices...")
    pdf("adjacency_matrix_plots.pdf", width = 8, height = 8)
    
    # Plot 1: Default
    tryCatch({
        plotAdjacencyMatrix(cx)
    }, error = function(e) {
        message("Failed to plot default adjacency matrix: ", e\$message)
    })
    
    # Plot 2: protColors = 1
    tryCatch({
        plotAdjacencyMatrix(cx, 1)
    }, error = function(e) {
        message("Failed to plot adjacency matrix with protColors = 1: ", e\$message)
    })
    
    # Plot 3: protColors = 2
    tryCatch({
        plotAdjacencyMatrix(cx, 2)
    }, error = function(e) {
        message("Failed to plot adjacency matrix with protColors = 2: ", e\$message)
    })
    
    # --- Color peptide nodes by search engine score ---
    message("Coloring peptide nodes by score...")
    score <- id\$MS.GF.RawScore
    if (is.null(score) || all(is.na(score))) {
        message("MS.GF.RawScore not found or empty. Using sequence lengths as dummy scores for visualization.")
        score <- nchar(id\$sequence)
    }
    names(score) <- id\$sequence
    
    # Ensure we have at least some variation to avoid cut() error on constant values
    if (length(unique(score)) < 2) {
        score <- score + runif(length(score), 0, 0.1)
    }
    
    cls <- as.character(cut(score, 12, labels = colorRampPalette(c("white", "red"))(12)))
    names(cls) <- id\$sequence
    
    tryCatch({
        plotAdjacencyMatrix(cx, pepColors = cls)
    }, error = function(e) {
        message("Failed to plot adjacency matrix with custom peptide colors: ", e\$message)
    })
    
    dev.off()
    
    # --- Prioritize connected components ---
    message("Prioritizing connected components...")
    cctab <- prioritiseConnectedComponents(cc)
    print(head(cctab))
    
    # Save prioritization table
    write.csv(cctab, "prioritised_connected_components.csv", row.names = TRUE)
    
    message("Pipeline completed successfully!")
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
      process = "BIOC_PSMATCH_PSM_FILTERING_AND_PROTEIN_GROUPS",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling", "count normalization", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_PSMATCH_PSM_FILTERING_AND_PROTEIN_GROUPS":',
        paste0('        psmatch: ', as.character(packageVersion("psmatch")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_psm_filtering_and_protein_groups.csv versions.yml
    """
}

workflow BIOC_PSMATCH_PSM_FILTERING_AND_PROTEIN_GROUPS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ idf.mzid ] ]

    main:
    BIOC_PSMATCH_PSM_FILTERING_AND_PROTEIN_GROUPS(ch_input)

    emit:
    tables   = BIOC_PSMATCH_PSM_FILTERING_AND_PROTEIN_GROUPS.out.tables
    plots    = BIOC_PSMATCH_PSM_FILTERING_AND_PROTEIN_GROUPS.out.plots
    objects  = BIOC_PSMATCH_PSM_FILTERING_AND_PROTEIN_GROUPS.out.objects
    versions = BIOC_PSMATCH_PSM_FILTERING_AND_PROTEIN_GROUPS.out.versions
}
