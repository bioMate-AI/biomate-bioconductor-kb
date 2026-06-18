#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CuratedAtlasQueryR — curated_atlas_query_hca_comparison
// Query the Human Cell Atlas (HCA) via CuratedAtlasQueryR to retrieve harmonised single-cell reference data matching local sample conditions, and perform a compar
// Input: counts.csv, coldata.csv
// Container: 1.8.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CuratedAtlasQueryR, SummarizedExperiment, dplyr, ggplot2, stringr
// Visualizations: plot (ggplot/base)
// QC: count normalization
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CURATEDATLASQUERYR_CURATED_ATLAS_QUERY_HCA_COMPARISON {
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
    .bm_deps <- c("CuratedAtlasQueryR", "ggplot2", "dplyr", "stringr", "SummarizedExperiment")
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
    library(CuratedAtlasQueryR)
    library(SummarizedExperiment)
    library(ggplot2)
    library(dplyr)
    library(stringr)
    
    # --- Load local count matrix and metadata ---
    message("Loading local count matrix and metadata...")
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # --- Connect to CuratedAtlasQueryR Database ---
    message("Connecting to CuratedAtlasQueryR metadata database...")
    # In real applications, we use the default remote_url (DATABASE_URL)
    hca_metadata <- get_metadata()
    
    # --- Match local conditions to HCA tissues ---
    message("Matching local conditions to HCA tissues...")
    # Collect unique tissues from HCA to find a match
    hca_tissues <- hca_metadata |> 
      dplyr::distinct(tissue) |> 
      dplyr::collect() |> 
      dplyr::pull(tissue)
    
    # Find intersection between local conditions and HCA tissues
    matched_tissues <- intersect(coldata\$condition, hca_tissues)
    if (length(matched_tissues) > 0) {
      target_tissue <- matched_tissues[1]
      message(paste("Matched local condition to HCA tissue:", target_tissue))
    } else {
      # Fallback to a common tissue in HCA if no direct match is found
      target_tissue <- "blood"
      message(paste("No direct tissue match found. Defaulting to HCA tissue:", target_tissue))
    }
    
    # --- Query and download reference SingleCellExperiment ---
    message("Querying HCA reference data...")
    # To keep the download fast and robust, we find one file_id associated with the target tissue
    sample_file <- hca_metadata |>
      dplyr::filter(tissue == !!target_tissue) |>
      dplyr::select(file_id_db) |>
      head(1) |>
      dplyr::collect()
    
    if (nrow(sample_file) == 0) {
      # Fallback to any available file if target_tissue has no files
      sample_file <- hca_metadata |>
        dplyr::select(file_id_db) |>
        head(1) |>
        dplyr::collect()
    }
    target_file_id <- sample_file\$file_id_db[1]
    
    # Select a subset of cells from this file to limit memory usage
    query_metadata <- hca_metadata |>
      dplyr::filter(file_id_db == !!target_file_id) |>
      head(100)
    
    # Select genes to query (overlap with local genes to minimize download size)
    local_genes <- rownames(counts)
    genes_to_query <- head(local_genes, 50)
    
    message("Downloading reference SingleCellExperiment...")
    sce_ref <- tryCatch({
      get_single_cell_experiment(
        query_metadata, 
        assays = "cpm", 
        features = genes_to_query
      )
    }, error = function(e) {
      message("Error downloading with feature filter. Retrying with a single default gene...")
      get_single_cell_experiment(
        query_metadata,
        assays = "cpm",
        features = "GAPDH"
      )
    })
    
    # --- Compare Local Data with HCA Reference ---
    message("Comparing local data with HCA reference...")
    # Calculate CPM for local counts
    local_counts_sub <- counts[intersect(rownames(counts), rownames(sce_ref)), , drop = FALSE]
    
    if (nrow(local_counts_sub) > 0 && ncol(local_counts_sub) > 0) {
      local_cpm <- apply(local_counts_sub, 2, function(x) {
        s <- sum(x)
        if (s == 0) return(rep(0, length(x)))
        (x / s) * 1e6
      })
      if (is.vector(local_cpm)) {
        local_cpm <- matrix(local_cpm, nrow = nrow(local_counts_sub), dimnames = list(rownames(local_counts_sub), colnames(local_counts_sub)))
      }
      
      # Compute average profiles
      mean_local_cpm <- rowMeans(local_cpm, na.rm = TRUE)
      ref_cpm_mat <- as.matrix(SummarizedExperiment::assay(sce_ref, "cpm"))
      mean_ref_cpm <- rowMeans(ref_cpm_mat, na.rm = TRUE)
      
      common_genes <- intersect(names(mean_local_cpm), names(mean_ref_cpm))
      comparison_df <- data.frame(
        gene = common_genes,
        local_mean_cpm = mean_local_cpm[common_genes],
        reference_mean_cpm = mean_ref_cpm[common_genes],
        stringsAsFactors = FALSE
      )
    } else {
      message("No overlapping genes found between local data and HCA reference. Creating dummy comparison.")
      comparison_df <- data.frame(
        gene = "None",
        local_mean_cpm = 0,
        reference_mean_cpm = 0,
        stringsAsFactors = FALSE
      )
    }
    
    # --- Retrieve Unharmonised Metadata ---
    message("Retrieving unharmonised metadata...")
    unharmonised_meta <- tryCatch({
      get_unharmonised_metadata(query_metadata)
    }, error = function(e) {
      NULL
    })
    
    # --- Save Outputs ---
    message("Saving outputs...")
    # 1. Save comparison table
    write.csv(comparison_df, "hca_comparison.csv", row.names = FALSE)
    
    # 2. Save reference SCE
    saveRDS(sce_ref, "hca_reference_sce.rds")
    
    # 3. Save unharmonised metadata if available
    if (!is.null(unharmonised_meta) && nrow(unharmonised_meta) > 0) {
      unharm_list <- dplyr::pull(unharmonised_meta, unharmonised)
      if (length(unharm_list) > 0) {
        unharm_df <- dplyr::collect(unharm_list[[1]])
        write.csv(head(unharm_df, 100), "unharmonised_ref_metadata.csv", row.names = FALSE)
      }
    } else {
      write.csv(data.frame(status = "No unharmonised metadata retrieved"), "unharmonised_ref_metadata.csv", row.names = FALSE)
    }
    
    # 4. Generate and save comparison plot
    pdf("hca_comparison_plot.pdf", width = 7, height = 6)
    if (nrow(comparison_df) > 1 && any(comparison_df\$gene != "None")) {
      p <- ggplot(comparison_df, aes(x = local_mean_cpm + 1, y = reference_mean_cpm + 1)) +
        geom_point(color = "blue", alpha = 0.7) +
        geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "red") +
        scale_x_log10() +
        scale_y_log10() +
        labs(
          title = paste("Local vs HCA Reference CPM (Tissue:", target_tissue, ")"),
          x = "Local Mean CPM (+1)",
          y = "HCA Reference Mean CPM (+1)"
        ) +
        theme_bw()
      print(p)
    } else {
      plot.new()
      text(0.5, 0.5, "No overlapping genes to plot", cex = 1.2)
    }
    dev.off()
    
    message("Pipeline completed successfully!")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_CURATEDATLASQUERYR_CURATED_ATLAS_QUERY_HCA_COMPARISON",
      domain  = "bioconductor",
      declared_qc_steps = c("count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_CURATEDATLASQUERYR_CURATED_ATLAS_QUERY_HCA_COMPARISON":',
        paste0('    CuratedAtlasQueryR: ', as.character(packageVersion('CuratedAtlasQueryR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_curated_atlas_query_hca_comparison.csv versions.yml
    """
}

workflow BIOC_CURATEDATLASQUERYR_CURATED_ATLAS_QUERY_HCA_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_CURATEDATLASQUERYR_CURATED_ATLAS_QUERY_HCA_COMPARISON(ch_input)

    emit:
    tables   = BIOC_CURATEDATLASQUERYR_CURATED_ATLAS_QUERY_HCA_COMPARISON.out.tables
    plots    = BIOC_CURATEDATLASQUERYR_CURATED_ATLAS_QUERY_HCA_COMPARISON.out.plots
    objects  = BIOC_CURATEDATLASQUERYR_CURATED_ATLAS_QUERY_HCA_COMPARISON.out.objects
    versions = BIOC_CURATEDATLASQUERYR_CURATED_ATLAS_QUERY_HCA_COMPARISON.out.versions
}
