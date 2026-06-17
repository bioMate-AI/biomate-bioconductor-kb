#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: qsmooth — gc_content_aware_smooth_quantile_normalization
// Perform smooth quantile normalization while accounting for sample-specific GC-content technical variability.
// Input: counts1, gcContent, pd1$organ
// Container: quay.io/biocontainers/bioconductor-qsmooth:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: qsmooth, quantro
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read User Input Files
//  * 2. [Core Analysis] Align and Filter GC-Content
//  * 3. [Core Analysis] Run GC-Content-Aware Smooth Quantile Normalization
//  * 4. [Core Analysis] Save Outputs and Generate Diagnostic Plots

nextflow.enable.dsl = 2

process BIOC_QSMOOTH_GC_CONTENT_AWARE_SMOOTH_QUANTILE_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("qsmooth", "quantro")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
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
    library(qsmooth)
    library(quantro)
    
    # ==========================================
    # --- Read User Input Files ---
    # ==========================================
    
    # Read counts1 (matrix or data frame of raw expression counts)
    if (file.exists("counts1.rds")) {
      counts1 <- readRDS("counts1.rds")
    } else if (file.exists("counts1.csv")) {
      counts1 <- as.matrix(read.csv("counts1.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("counts1.tsv")) {
      counts1 <- as.matrix(read.delim("counts1.tsv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: counts1 file not found. Please provide counts1.rds, counts1.csv, or counts1.tsv in the working directory.")
    }
    
    # Read gcContent (numeric vector of GC-content values)
    if (file.exists("gcContent.rds")) {
      gcContent <- readRDS("gcContent.rds")
    } else if (file.exists("gcContent.csv")) {
      gc_df <- read.csv("gcContent.csv", row.names = 1)
      gcContent <- gc_df[[1]]
      names(gcContent) <- rownames(gc_df)
    } else {
      stop("Error: gcContent file not found. Please provide gcContent.rds or gcContent.csv in the working directory.")
    }
    
    # Read pd1 (phenotypic data containing the organ factor/vector)
    if (file.exists("pd1.rds")) {
      pd1 <- readRDS("pd1.rds")
    } else if (file.exists("pd1.csv")) {
      pd1 <- read.csv("pd1.csv", row.names = 1)
    } else {
      stop("Error: pd1 file not found. Please provide pd1.rds or pd1.csv in the working directory.")
    }
    
    # Ensure pd1 is a data frame or list-like object so pd1\$organ is accessible
    pd1 <- as.data.frame(pd1)
    if (!"organ" %in% colnames(pd1)) {
      stop("Error: pd1 must contain an 'organ' column representing the biological group.")
    }
    
    # ==========================================
    # --- Align and Filter GC-Content ---
    # ==========================================
    
    # Ensure gcContent is named and aligned with counts1 rows
    if (is.null(names(gcContent))) {
      if (length(gcContent) == nrow(counts1)) {
        names(gcContent) <- rownames(counts1)
      } else {
        stop("Error: gcContent length does not match counts1 row count, and gcContent is not named.")
      }
    }
    
    # Align gcContent to counts1 rownames
    gcContent <- gcContent[rownames(counts1)]
    
    # Identify features with non-missing GC-content
    keep <- names(gcContent)[!is.na(gcContent)]
    
    # ==========================================
    # --- Run GC-Content-Aware Smooth Quantile Normalization ---
    # ==========================================
    
    # Perform smooth quantile normalization accounting for GC-content
    qs_norm_gc <- qsmoothGC(object = counts1[keep,], gc=gcContent[keep], group_factor = pd1\$organ)
    
    # Extract the normalized expression matrix
    normalized_data <- qsmoothData(qs_norm_gc)
    
    # ==========================================
    # --- Save Outputs and Generate Diagnostic Plots ---
    # ==========================================
    
    # Save the normalized expression matrix to CSV
    write.csv(normalized_data, file = "normalized_counts.csv", row.names = TRUE)
    
    # Save the complete qsmooth object to RDS
    saveRDS(qs_norm_gc, file = "qs_norm_gc.rds")
    
    # Generate diagnostic plots comparing raw and normalized data
    pdf("normalization_plots.pdf", width = 10, height = 10)
    par(mfrow=c(2,2))
    
    # Raw data boxplot
    quantro::matboxplot(log2(counts1[keep,] + 1), groupFactor = factor(pd1\$organ),
                        main = "Raw data", xaxt="n", 
                        ylab = "Expression (log2 scale)")
    axis(1, at=seq_len(length(as.character(pd1\$organ))), labels=FALSE)
    text(seq_len(length(pd1\$organ)), par("usr")[3] - 2, 
         labels = pd1\$organ, srt = 90, pos = 1, xpd = TRUE)
    
    # Raw data density plot
    quantro::matdensity(log2(counts1[keep,] + 1), groupFactor = pd1\$organ, 
                        main = "Raw data", ylab= "density",
                        xlab = "Expression (log2 scale)")
    legend('topright', levels(factor(pd1\$organ)), col = 1:2, lty = 1)
    
    # Normalized data boxplot
    quantro::matboxplot(log2(normalized_data + 1), groupFactor = factor(pd1\$organ), 
                        xaxt="n", main = "qsmoothGC normalized data", 
                        ylab = "Expression (log2 scale)")
    axis(1, at=seq_len(length(pd1\$organ)), labels=FALSE)
    text(seq_len(length(pd1\$organ)), par("usr")[3] - 2, 
         labels = pd1\$organ, srt = 90, pos = 1, xpd = TRUE)
    
    # Normalized data density plot
    quantro::matdensity(log2(normalized_data + 1), groupFactor = pd1\$organ,
                        main = "qsmoothGC normalized data",
                        xlab = "Expression (log2 scale)", ylab = "density")
    legend('topright', levels(factor(pd1\$organ)), col = 1:2, lty = 1)
    
    dev.off()
    
    cat("Pipeline completed successfully.\n")
    cat("Outputs saved:\n")
    cat("- normalized_counts.csv (Normalized expression matrix)\n")
    cat("- qs_norm_gc.rds (Full qsmoothGC object)\n")
    cat("- normalization_plots.pdf (Diagnostic plots)\n")

    writeLines(c(
        '"BIOC_QSMOOTH_GC_CONTENT_AWARE_SMOOTH_QUANTILE_NORMALIZATION":',
        paste0('    qsmooth: ', as.character(packageVersion('qsmooth')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gc_content_aware_smooth_quantile_normalization.csv versions.yml
    """
}

workflow BIOC_QSMOOTH_GC_CONTENT_AWARE_SMOOTH_QUANTILE_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts1, gcContent, pd1$organ ] ]

    main:
    BIOC_QSMOOTH_GC_CONTENT_AWARE_SMOOTH_QUANTILE_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_QSMOOTH_GC_CONTENT_AWARE_SMOOTH_QUANTILE_NORMALIZATION.out.tables
    plots    = BIOC_QSMOOTH_GC_CONTENT_AWARE_SMOOTH_QUANTILE_NORMALIZATION.out.plots
    objects  = BIOC_QSMOOTH_GC_CONTENT_AWARE_SMOOTH_QUANTILE_NORMALIZATION.out.objects
    versions = BIOC_QSMOOTH_GC_CONTENT_AWARE_SMOOTH_QUANTILE_NORMALIZATION.out.versions
}
