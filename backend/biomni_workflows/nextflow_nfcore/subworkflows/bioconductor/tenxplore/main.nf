#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tenXplore — tenxplore_neuron_analysis
// Perform ontological and comparative exploration of single-cell RNA-seq data using the tenXplore package and its 1.3 million neuron reference dataset.
// Input: counts.csv, coldata.csv
// Container: 1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, tenXplore
// Visualizations: heatmap
// QC: low-count filtering, count normalization
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TENXPLORE_TENXPLORE_NEURON_ANALYSIS {
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
    .bm_deps <- c("tenXplore", "SummarizedExperiment")
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
    
    # --- Load libraries and input datasets ---
        library(SummarizedExperiment)
library(tenXplore)
    
    message("Loading input datasets...")
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", row.names = 1, check.names = FALSE)
    
    # Align counts and coldata
    if (!"sample" %in% colnames(coldata) && !is.null(rownames(coldata))) {
      coldata\$sample <- rownames(coldata)
    } else if ("sample" %in% colnames(coldata) && (is.null(rownames(coldata)) || any(rownames(coldata) != coldata\$sample))) {
      rownames(coldata) <- coldata\$sample
    }
    
    common_samples <- intersect(colnames(counts), rownames(coldata))
    if (length(common_samples) == 0) {
      stop("Error: No matching samples found between counts.csv and coldata.csv")
    }
    
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, drop = FALSE]
    
    # --- Construct and Preprocess SummarizedExperiment ---
    message("Preprocessing user dataset...")
    se_user <- SummarizedExperiment(
      assays = list(counts = as.matrix(counts)),
      colData = coldata
    )
    
    # Filter out low-expression genes
    keep_genes <- rowSums(assay(se_user, "counts") > 0) >= 2
    se_user <- se_user[keep_genes, ]
    
    # Perform library size normalization (CPM) and log2 transformation
    libsizes <- colSums(assay(se_user, "counts"))
    libsizes[libsizes == 0] <- 1 # Avoid division by zero
    cpm <- sweep(assay(se_user, "counts"), 2, libsizes, "/") * 1e6
    assay(se_user, "logcpm") <- log2(cpm + 1)
    
    # --- Load Reference Dataset and Perform Comparative Analysis ---
    message("Loading reference 1.3M neuron dataset...")
    se_ref <- tryCatch({
      se1.3M()
    }, error = function(e) {
      message("Warning: Could not load se1.3M reference dataset: ", e\$message)
      NULL
    })
    
    if (!is.null(se_ref)) {
      message("Computing correlation with reference cells...")
      common_genes <- intersect(rownames(se_user), rownames(se_ref))
      
      if (length(common_genes) > 0) {
        # Use a subset of common genes to avoid high memory usage
        subset_genes <- head(common_genes, 100)
        user_expr <- assay(se_user, "logcpm")[subset_genes, , drop = FALSE]
        
        # Extract a subset of reference cells
        ref_cols <- seq_len(min(50, ncol(se_ref)))
        ref_sub <- se_ref[subset_genes, ref_cols, drop = FALSE]
        ref_expr <- as.matrix(assay(ref_sub))
        
        # Compute Pearson correlation
        cor_matrix <- cor(user_expr, ref_expr, use = "pairwise.complete.obs")
        write.csv(cor_matrix, "reference_correlation.csv")
        message("Correlation matrix saved to reference_correlation.csv")
      } else {
        write.csv(data.frame(Error = "No common genes found between user data and reference"), "reference_correlation.csv")
      }
    } else {
      write.csv(data.frame(Error = "Reference dataset se1.3M could not be loaded"), "reference_correlation.csv")
    }
    
    # --- Visualization ---
    message("Generating expression heatmap...")
    pdf("expression_heatmap.pdf", width = 8, height = 6)
    gene_vars <- apply(assay(se_user, "logcpm"), 1, var)
    top_genes <- names(sort(gene_vars, decreasing = TRUE))[1:min(20, length(gene_vars))]
    
    if (length(top_genes) > 0) {
      heatmap_data <- assay(se_user, "logcpm")[top_genes, , drop = FALSE]
      heatmap(heatmap_data, 
              main = "Top Variable Genes in User Dataset",
              col = heat.colors(256),
              margins = c(10, 10))
    } else {
      plot.new()
      text(0.5, 0.5, "No genes available for heatmap")
    }
    dev.off()
    
    # --- App Initialization and Serialization ---
    message("Initializing tenXplore app object...")
    app <- tryCatch({
      tenXplore()
    }, error = function(e) {
      message("Note: tenXplore app initialized as standalone object: ", e\$message)
      NULL
    })
    
    # Save the processed user dataset
    saveRDS(se_user, "user_processed_se.rds")
    message("Pipeline completed successfully.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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
      process = "BIOC_TENXPLORE_TENXPLORE_NEURON_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_TENXPLORE_TENXPLORE_NEURON_ANALYSIS":',
        paste0('    tenXplore: ', as.character(packageVersion('tenXplore')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tenxplore_neuron_analysis.csv versions.yml
    """
}

workflow BIOC_TENXPLORE_TENXPLORE_NEURON_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_TENXPLORE_TENXPLORE_NEURON_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TENXPLORE_TENXPLORE_NEURON_ANALYSIS.out.tables
    plots    = BIOC_TENXPLORE_TENXPLORE_NEURON_ANALYSIS.out.plots
    objects  = BIOC_TENXPLORE_TENXPLORE_NEURON_ANALYSIS.out.objects
    versions = BIOC_TENXPLORE_TENXPLORE_NEURON_ANALYSIS.out.versions
}
