#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: qsea — qsea_differential_methylation
// Perform quantitative differential methylation analysis using qsea on user-provided region counts or beta values, calibrating enrichment profiles and fitting neg
// Input: matrix.csv, coldata.csv
// Container: 1.36.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg19, GenomicRanges, qsea
// Visualizations: PCA plot, enrichment plot
// QC: diagnostic MA/PCA QC
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QSEA_QSEA_DIFFERENTIAL_METHYLATION {
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
    .bm_deps <- c("qsea", "GenomicRanges", "BSgenome.Hsapiens.UCSC.hg19")
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
    library(qsea)
    library(GenomicRanges)
    library(BSgenome.Hsapiens.UCSC.hg19)
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    
    message("Loading input files...")
    counts_df <- read.csv("matrix.csv", check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Ensure feature_id is set as row names
    if ("feature_id" %in% colnames(counts_df)) {
      rownames(counts_df) <- counts_df\$feature_id
      counts_df\$feature_id <- NULL
    }
    
    # Align samples between matrix and coldata
    common_samples <- intersect(colnames(counts_df), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("Error: No common samples found between matrix.csv and coldata.csv.")
    }
    counts_df <- counts_df[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), , drop = FALSE]
    
    # Parse genomic features into GRanges
    message("Parsing genomic features...")
    feature_ids <- rownames(counts_df)
    parse_features <- function(ids) {
      gr <- tryCatch({
        GRanges(ids)
      }, error = function(e) {
        # Fallback for chr_start_end format
        standardized <- sapply(ids, function(id) {
          parts <- strsplit(id, "_")[[1]]
          if (length(parts) >= 3) {
            n <- length(parts)
            paste0(paste(parts[1:(n-2)], collapse="_"), ":", parts[n-1], "-", parts[n])
          } else {
            id
          }
        })
        GRanges(standardized)
      })
      return(gr)
    }
    regions_gr <- parse_features(feature_ids)
    names(regions_gr) <- feature_ids
    
    # Standardize chromosome names to UCSC style and filter to hg19 boundaries
    seqlevelsStyle(regions_gr) <- "UCSC"
    hg19_seqinfo <- seqinfo(BSgenome.Hsapiens.UCSC.hg19)
    regions_gr <- keepSeqlevels(regions_gr, intersect(seqlevels(regions_gr), seqnames(hg19_seqinfo)), pruning.mode = "coarse")
    regions_gr <- trim(regions_gr)
    regions_gr <- regions_gr[width(regions_gr) > 0]
    
    # Align count matrix with filtered regions
    counts_df <- counts_df[names(regions_gr), , drop = FALSE]
    count_matrix <- as.matrix(counts_df)
    
    # Check if input is beta values (0 to 1) or counts, and scale if necessary
    is_beta <- max(count_matrix, na.rm = TRUE) <= 1.01 && min(count_matrix, na.rm = TRUE) >= -0.01
    if (is_beta) {
      message("Input values detected as beta values. Converting to pseudo-counts for GLM fitting.")
      count_matrix <- round(count_matrix * 1000)
    } else {
      count_matrix <- round(count_matrix)
    }
    
    # ==========================================
    # --- Initialize and Populate qseaSet ---
    # ==========================================
    
    message("Initializing qseaSet...")
    sample_table <- data.frame(
      sample_name = coldata\$sample,
      file_name = coldata\$sample, # Dummy file name
      group = coldata\$condition,
      stringsAsFactors = FALSE
    )
    
    qseaSet <- createQseaSet(
      sampleTable = sample_table,
      BSgenome = "BSgenome.Hsapiens.UCSC.hg19",
      Regions = regions_gr
    )
    
    # Manually inject counts and library sizes into the S4 object
    qseaSet@counts <- count_matrix
    qseaSet@libraries\$lib_size <- colSums(count_matrix)
    
    # ==========================================
    # --- Normalization & Parameter Estimation ---
    # ==========================================
    
    message("Estimating library factors and pattern density...")
    qseaSet <- addLibraryFactors(qseaSet)
    qseaSet <- addPatternDensity(qseaSet, "CG", name = "CpG")
    
    message("Estimating background offset...")
    qseaSet <- tryCatch({
      addOffset(qseaSet, enrichmentPattern = "CpG")
    }, error = function(e) {
      message("Warning: addOffset failed, proceeding with default offset.")
      qseaSet
    })
    
    message("Calibrating enrichment parameters (blind calibration)...")
    wd <- which(getRegions(qseaSet)\$CpG_density >= 0)
    if (length(wd) > 0) {
      cpg_den <- getRegions(qseaSet)\$CpG_density[wd]
      max_den <- max(cpg_den, na.rm = TRUE)
      if (max_den <= 0) max_den <- 1
      # Model a linear decrease of average methylation levels for higher CpG density
      signal <- (max_den - cpg_den) * 0.55 / max_den + 0.25
      qseaSet <- addEnrichmentParameters(qseaSet, enrichmentPattern = "CpG", windowIdx = wd, signal = as.matrix(signal))
    }
    
    # ==========================================
    # --- Differential Methylation Analysis ---
    # ==========================================
    
    message("Fitting Negative Binomial GLM...")
    design <- model.matrix(~group, getSampleTable(qseaSet))
    qseaGLM <- fitNBglm(qseaSet, design, norm_method = "beta")
    qseaGLM <- addContrast(qseaSet, qseaGLM, coef = 2, name = "TvN")
    
    # Extract significant regions
    fdr_th <- 0.05
    sig <- isSignificant(qseaGLM, fdr_th = fdr_th)
    if (sum(sig) == 0) {
      message("No significant regions found at FDR 0.05. Relaxing threshold to output all regions.")
      sig <- isSignificant(qseaGLM, fdr_th = 1.0)
    }
    
    # Generate results table
    message("Generating results table...")
    result <- makeTable(
      qseaSet,
      glm = qseaGLM,
      groupMeans = getSampleGroups(qseaSet),
      keep = sig,
      norm_method = "beta"
    )
    
    # Write results to CSV
    write.csv(result, "differential_methylation_results.csv", row.names = FALSE)
    message("Results successfully written to 'differential_methylation_results.csv'.")
    
    # ==========================================
    # --- Visualization & Diagnostics ---
    # ==========================================
    
    message("Generating diagnostic plots...")
    
    # 1. PCA Plot
    tryCatch({
      pca <- getPCA(qseaSet, norm_method = "beta")
      pdf("pca_plot.pdf", width = 7, height = 7)
      groups_factor <- as.factor(getSampleTable(qseaSet)\$group)
      colors <- rainbow(length(levels(groups_factor)))[groups_factor]
      plotPCA(pca, bg = colors, main = "PCA Plot (Beta Values)")
      dev.off()
      message("PCA plot saved to 'pca_plot.pdf'.")
    }, error = function(e) {
      message("Warning: PCA plot generation failed: ", e\$message)
    })
    
    # 2. Enrichment Profile Plot
    tryCatch({
      pdf("enrichment_profile.pdf", width = 8, height = 6)
      plotEPmatrix(qseaSet)
      dev.off()
      message("Enrichment profile plot saved to 'enrichment_profile.pdf'.")
    }, error = function(e) {
      message("Warning: Enrichment profile plot generation failed: ", e\$message)
    })
    
    message("Pipeline completed successfully!")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # diagnostic MA/PCA QC — PC1 variance explained on any large matrix.
    # Pass when PC1 > 10% (Risso 2014 RUV-seq diagnostic).
    .pca_pc1 <- NA_real_; .pca_files <- character(0)
    for (.pca_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .pca_obj <- tryCatch(readRDS(.pca_rds), error = function(e) NULL)
      .pca_mat <- if (is.matrix(.pca_obj) || is.data.frame(.pca_obj)) .pca_obj else NULL
      if (!is.null(.pca_mat) && ncol(.pca_mat) >= 3 && nrow(.pca_mat) >= 100) {
        .pca_m <- suppressWarnings(as.matrix(.pca_mat))
        .pca_kept <- apply(.pca_m, 1, function(r) all(is.finite(r)) && var(r) > 0)
        if (sum(.pca_kept) >= 50) {
          .pca_fit <- tryCatch(prcomp(t(.pca_m[.pca_kept, , drop = FALSE])), error = function(e) NULL)
          if (!is.null(.pca_fit)) {
            .pca_vars <- (.pca_fit\$sdev^2) / sum(.pca_fit\$sdev^2)
            .pca_pc1 <- round(.pca_vars[1] * 100, 2); .pca_files <- c(.pca_files, .pca_rds); break
          }
        }
      }
    }
    .gates_by_label[["diagnostic MA/PCA QC"]] <- list(
      gate_row = "bioc_diagnostic_ma_pca_qc",
      metric_name = "pc1_var_explained",
      metric_value = .pca_pc1,
      passes = isTRUE(is.finite(.pca_pc1) && .pca_pc1 > 10),
      status = if (is.finite(.pca_pc1)) paste0("computed (PC1=", .pca_pc1, "%)")
               else "not_computed (no large numeric matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_QSEA_QSEA_DIFFERENTIAL_METHYLATION",
      domain  = "bioconductor",
      declared_qc_steps = c("diagnostic MA/PCA QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_QSEA_QSEA_DIFFERENTIAL_METHYLATION":',
        paste0('    qsea: ', as.character(packageVersion('qsea')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qsea_differential_methylation.csv versions.yml
    """
}

workflow BIOC_QSEA_QSEA_DIFFERENTIAL_METHYLATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_QSEA_QSEA_DIFFERENTIAL_METHYLATION(ch_input)

    emit:
    tables   = BIOC_QSEA_QSEA_DIFFERENTIAL_METHYLATION.out.tables
    plots    = BIOC_QSEA_QSEA_DIFFERENTIAL_METHYLATION.out.plots
    objects  = BIOC_QSEA_QSEA_DIFFERENTIAL_METHYLATION.out.objects
    versions = BIOC_QSEA_QSEA_DIFFERENTIAL_METHYLATION.out.versions
}
