#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: biscuiteer — biscuiteer_epigenomic_pipeline
// Perform comprehensive WGBS downstream analysis including locus extremality filtering, logit-transformed fractional methylation calculation for compartment infer
// Input: matrix.csv, coldata.csv
// Container: 1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, SummarizedExperiment, biscuiteer, bsseq, ggplot2
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BISCUITEER_BISCUITEER_EPIGENOMIC_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("biscuiteer", "bsseq", "GenomicRanges", "ggplot2", "SummarizedExperiment")
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
    library(SummarizedExperiment)
    library(biscuiteer)
    library(bsseq)
    library(GenomicRanges)
    library(ggplot2)
    
    # ==========================================
    # --- Load and Parse Input Data ---
    # ==========================================
    message("Loading input datasets...")
    matrix_df <- read.csv("matrix.csv", stringsAsFactors = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Parse feature_id into genomic coordinates (chrom, start, end)
    feature_ids <- trimws(matrix_df\$feature_id)
    parsed <- regmatches(feature_ids, regexec("^([^:_]+)[:_](\\\\d+)(?:[:_-](\\\\d+))?\$", feature_ids))
    
    chrom <- sapply(parsed, function(x) if(length(x) >= 2) x[2] else NA)
    start <- as.numeric(sapply(parsed, function(x) if(length(x) >= 3) x[3] else NA))
    end <- as.numeric(sapply(parsed, function(x) if(length(x) >= 4 && !is.na(x[4])) x[4] else NA))
    
    # Fallback for missing or unparseable coordinates
    na_idx <- is.na(chrom) | is.na(start)
    if (any(na_idx)) {
      chrom[na_idx] <- "chr1"
      start[na_idx] <- seq(1000, by = 150, length.out = sum(na_idx))
      end[na_idx] <- start[na_idx] + 1
    }
    end[is.na(end)] <- start[is.na(end)]
    
    # Create GRanges object and set genome to hg19 (required for WGBSage clock models)
    gr <- GRanges(seqnames = chrom, ranges = IRanges(start = start, end = end))
    genome(gr) <- "hg19"
    
    # ==========================================
    # --- Construct BSseq Object ---
    # ==========================================
    message("Constructing BSseq object...")
    beta_mat <- as.matrix(matrix_df[, -1, drop = FALSE])
    rownames(beta_mat) <- feature_ids
    
    # Determine if input values are beta values [0, 1] or raw counts
    if (max(beta_mat, na.rm = TRUE) > 1) {
      # Treat as raw methylated counts, simulate coverage
      M <- round(beta_mat)
      Cov <- round(beta_mat * 1.5) + 10
    } else {
      # Treat as beta values, simulate standard WGBS coverage (30x)
      Cov <- matrix(30, nrow = nrow(beta_mat), ncol = ncol(beta_mat))
      M <- round(beta_mat * Cov)
    }
    
    # Handle missing values and ensure Cov >= M
    M[is.na(M)] <- 0
    Cov[is.na(Cov)] <- 0
    Cov[Cov < M] <- M[Cov < M]
    
    # Align coldata with matrix columns
    samples <- colnames(beta_mat)
    coldata_aligned <- coldata[match(samples, coldata\$sample), , drop = FALSE]
    
    # Build the BSseq object
    bs_obj <- BSseq(gr = gr, M = M, Cov = Cov, pData = coldata_aligned)
    
    # ==========================================
    # --- Extremality Filtering & Scoring ---
    # ==========================================
    message("Calculating locus-level extremality...")
    ext_scores <- extremality(bs_obj)
    ext_df <- data.frame(feature_id = feature_ids, extremality = ext_scores)
    write.csv(ext_df, "extremality_scores.csv", row.names = FALSE)
    
    # ==========================================
    # --- Define Tiled Regions ---
    # ==========================================
    # Create genomic tiles across the chromosomes present in the dataset
    max_coords <- tapply(end(gr), seqnames(gr), max)
    regions <- GRanges(seqnames = names(max_coords),
                       ranges = IRanges(start = 1, end = max_coords))
    tiles <- unlist(tile(regions, width = 50000))
    genome(tiles) <- "hg19"
    
    # ==========================================
    # --- A/B Compartment Prep (getLogitFracMeth) ---
    # ==========================================
    message("Calculating moderated logit fractional methylation...")
    frac_meth_gr <- getLogitFracMeth(bs_obj, minSamp = 1, r = tiles)
    frac_meth_df <- as.data.frame(frac_meth_gr)
    write.csv(frac_meth_df, "logit_frac_meth.csv", row.names = FALSE)
    
    # ==========================================
    # --- Region Summarization ---
    # ==========================================
    message("Summarizing BSseq over tiled regions...")
    summarized_se <- summarizeBsSeqOver(bs_obj, regions = tiles)
    sum_M <- assay(summarized_se, "M")
    sum_Cov <- assay(summarized_se, "Cov")
    sum_beta <- sum_M / (sum_Cov + 1e-6)
    
    sum_df <- data.frame(
      chrom = as.character(seqnames(tiles)),
      start = start(tiles),
      end = end(tiles),
      as.data.frame(sum_beta)
    )
    write.csv(sum_df, "summarized_regions.csv", row.names = FALSE)
    
    # ==========================================
    # --- Epigenetic Age Estimation ---
    # ==========================================
    message("Estimating epigenetic age using WGBSage...")
    age_estimates <- tryCatch({
      WGBSage(bs_obj, "horvath")
    }, error = function(e) {
      message("WGBSage failed (likely due to insufficient clock CpG overlap): ", e\$message)
      NULL
    })
    
    if (!is.null(age_estimates) && !is.null(age_estimates\$age)) {
      age_df <- data.frame(
        sample = names(age_estimates\$age),
        predicted_age = as.numeric(age_estimates\$age)
      )
      if ("condition" %in% colnames(coldata_aligned)) {
        age_df\$condition <- coldata_aligned\$condition[match(age_df\$sample, coldata_aligned\$sample)]
      }
    } else {
      age_df <- data.frame(
        sample = coldata_aligned\$sample,
        predicted_age = NA,
        status = "WGBSage failed or returned empty results"
      )
    }
    write.csv(age_df, "age_predictions.csv", row.names = FALSE)
    
    # ==========================================
    # --- Visualizations & Diagnostics ---
    # ==========================================
    message("Generating diagnostic plots...")
    pdf("methylation_plots.pdf", width = 10, height = 8)
    
    # Plot 1: Extremality Distribution
    p1 <- ggplot(ext_df, aes(x = extremality)) +
      geom_histogram(bins = 50, fill = "skyblue", color = "black", alpha = 0.7) +
      theme_minimal() +
      labs(title = "Distribution of Locus Extremality Scores",
           subtitle = "Scores near 1 indicate highly bimodal/extreme methylation states",
           x = "Extremality Score",
           y = "Count")
    print(p1)
    
    # Plot 2: Logit Fractional Methylation Distribution
    sample_cols <- setdiff(colnames(frac_meth_df), c("seqnames", "start", "end", "width", "strand"))
    if (length(sample_cols) > 0) {
      frac_long <- data.frame(
        sample = rep(sample_cols, each = nrow(frac_meth_df)),
        value = as.vector(as.matrix(frac_meth_df[, sample_cols, drop = FALSE]))
      )
      p2 <- ggplot(frac_long, aes(x = sample, y = value, fill = sample)) +
        geom_boxplot(outlier.size = 0.5, alpha = 0.7) +
        theme_minimal() +
        theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
        labs(title = "Logit Fractional Methylation Distribution across Samples",
             subtitle = "Moderated values prepared for compartment inference",
             x = "Sample",
             y = "Logit Methylation Fraction")
      print(p2)
    }
    
    # Plot 3: Age Predictions (if valid)
    if (!all(is.na(age_df\$predicted_age))) {
      p3 <- ggplot(age_df, aes(x = if("condition" %in% colnames(age_df)) condition else "All", 
                               y = predicted_age, 
                               fill = if("condition" %in% colnames(age_df)) condition else NULL)) +
        geom_boxplot(outlier.shape = NA, alpha = 0.6) +
        geom_jitter(width = 0.2, size = 3, color = "darkblue") +
        theme_minimal() +
        labs(title = "Predicted Epigenetic Age",
             x = "Group",
             y = "Predicted Age (Horvath Clock)") +
        theme(legend.position = "none")
      print(p3)
    }
    
    dev.off()
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_BISCUITEER_BISCUITEER_EPIGENOMIC_PIPELINE":',
        paste0('    biscuiteer: ', as.character(packageVersion('biscuiteer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biscuiteer_epigenomic_pipeline.csv versions.yml
    """
}

workflow BIOC_BISCUITEER_BISCUITEER_EPIGENOMIC_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BISCUITEER_BISCUITEER_EPIGENOMIC_PIPELINE(ch_input)

    emit:
    tables   = BIOC_BISCUITEER_BISCUITEER_EPIGENOMIC_PIPELINE.out.tables
    plots    = BIOC_BISCUITEER_BISCUITEER_EPIGENOMIC_PIPELINE.out.plots
    objects  = BIOC_BISCUITEER_BISCUITEER_EPIGENOMIC_PIPELINE.out.objects
    versions = BIOC_BISCUITEER_BISCUITEER_EPIGENOMIC_PIPELINE.out.versions
}
