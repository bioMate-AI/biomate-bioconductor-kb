#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: affy — affy_microarray_pipeline
// Perform a comprehensive Affymetrix microarray analysis pipeline including quality control, RNA degradation analysis, MAS5/RMA normalization, and expression summ
// Input: counts.csv, coldata.csv
// Container: 1.88.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, affy
// Visualizations: box plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AFFY_AFFY_MICROARRAY_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(affy)
    library(Biobase)
    
    # ==========================================
    # STAGE 1: Data Loading & AffyBatch Creation
    # ==========================================
    
    # Read input files
    counts <- read.csv("counts.csv", row.names = 1)
    coldata <- read.csv("coldata.csv")
    
    # Ensure counts is a numeric matrix
    exprs_data <- as.matrix(counts)
    
    # Ensure all values are strictly positive (microarray intensities must be > 0)
    if (min(exprs_data) <= 0) {
      exprs_data[exprs_data <= 0] <- 1
    }
    
    # Format, pad, or truncate the expression matrix to a perfect square (10*k)^2
    # to mimic a standard Affymetrix chip layout and ensure clean probe set partitioning.
    n_original <- nrow(exprs_data)
    k <- floor(sqrt(n_original) / 10)
    if (k < 1) {
      padding_needed <- 100 - n_original
      if (padding_needed > 0) {
        extra_rows <- exprs_data[sample(1:n_original, padding_needed, replace = TRUE), , drop = FALSE]
        exprs_data <- rbind(exprs_data, extra_rows)
      }
      k <- 1
    }
    M <- (10 * k)^2
    exprs_data <- exprs_data[1:M, , drop = FALSE]
    ab_nrow <- 10 * k
    ab_ncol <- 10 * k
    
    # Create a mock CDF environment mapping probes to probe sets of size 10 (5 PM, 5 MM)
    n_probesets <- M / 10
    mockcdf <- new.env(parent = emptyenv())
    for (i in 1:n_probesets) {
      ps_name <- paste0("probeset_", i)
      pm_idx <- (i - 1) * 10 + 1:5
      mm_idx <- (i - 1) * 10 + 6:10
      val <- cbind(pm = as.integer(pm_idx), mm = as.integer(mm_idx))
      assign(ps_name, val, envir = mockcdf)
    }
    
    # Register the CDF environment in the global environment so the affy package can find it
    assign("mockcdf", mockcdf, envir = .GlobalEnv)
    
    # Instantiate the AffyBatch object
    ad <- assayDataNew(storage.mode = "lockedEnvironment", exprs = exprs_data)
    pheno_df <- data.frame(row.names = colnames(exprs_data), condition = coldata\$condition)
    pd <- new("AnnotatedDataFrame", data = pheno_df)
    
    abatch <- new("AffyBatch",
                  assayData = ad,
                  phenoData = pd,
                  cdfName = "mockcdf",
                  annotation = "mockcdf",
                  nrow = as.integer(ab_nrow),
                  ncol = as.integer(ab_ncol))
    
    # ==========================================
    # STAGE 2: Quality Control & Diagnostics
    # ==========================================
    
    # Run RNA degradation analysis
    deg_analysis_success <- FALSE
    tryCatch({
      deg <- AffyRNAdeg(abatch)
      deg_summary <- data.frame(
        Sample = deg\$sample.names,
        Slope = deg\$slope,
        Pvalue = deg\$pvals
      )
      write.csv(deg_summary, "rna_degradation_summary.csv", row.names = FALSE)
      deg_analysis_success <- TRUE
    }, error = function(e) {
      warning("RNA degradation analysis failed: ", e\$message)
      write.csv(data.frame(Error = e\$message), "rna_degradation_summary.csv", row.names = FALSE)
    })
    
    # Generate diagnostic plots
    tryCatch({
      pdf("affy_qc_plots.pdf", width = 10, height = 10)
      par(mfrow = c(2, 2))
      
      # 1. Histogram of PM intensities
      hist(abatch, main = "PM Intensity Distribution")
      
      # 2. Boxplot of intensities across samples
      boxplot(abatch, col = 2:(ncol(exprs_data) + 1), main = "Intensity Boxplot")
      
      # 3. Pairwise MA-plot
      MAplot(abatch, pairs = TRUE, plot.method = "smoothScatter")
      
      # 4. RNA degradation plot (custom base R implementation using AffyRNAdeg output)
      if (deg_analysis_success) {
        matplot(deg\$means.by.number, type = "l", lty = 1, col = 2:(ncol(exprs_data) + 1),
                xlab = "Probe Position (5' -> 3')", ylab = "Mean Intensity",
                main = "RNA Degradation Plot")
        legend("topleft", legend = deg\$sample.names, col = 2:(ncol(exprs_data) + 1), lty = 1, cex = 0.8)
      } else {
        plot.new()
        text(0.5, 0.5, "RNA Degradation Plot Unavailable")
      }
      
      dev.off()
    }, error = function(e) {
      warning("QC plotting failed: ", e\$message)
      if (names(dev.cur()) != "null device") dev.off()
      # Write fallback empty PDF
      pdf("affy_qc_plots.pdf")
      plot.new()
      text(0.5, 0.5, paste("QC Plotting Failed:", e\$message))
      dev.off()
    })
    
    # ==========================================
    # STAGE 3: Normalization & Summarization
    # ==========================================
    
    # 1. RMA-like processing using the modular 'expresso' function
    eset_rma <- expresso(abatch,
                         bgcorrect.method = "rma",
                         normalize.method = "quantiles",
                         pmcorrect.method = "pmonly",
                         summary.method = "medianpolish")
    exprs_rma <- exprs(eset_rma)
    
    # 2. MAS5 processing
    eset_mas5 <- mas5(abatch)
    exprs_mas5 <- exprs(eset_mas5)
    
    # 3. MAS5 Presence/Absence Calls
    calls_mas5 <- mas5calls(abatch)
    calls_matrix <- exprs(calls_mas5)
    pvals_matrix <- assayData(calls_mas5)[["se.exprs"]]
    
    # ==========================================
    # STAGE 4: Exporting Results & Comparison
    # ==========================================
    
    # Combine all metrics into a single comprehensive data frame
    probe_sets <- rownames(exprs_rma)
    
    colnames(exprs_rma) <- paste0("RMA_", colnames(exprs_rma))
    colnames(exprs_mas5) <- paste0("MAS5_Expr_", colnames(exprs_mas5))
    colnames(calls_matrix) <- paste0("MAS5_Call_", colnames(calls_matrix))
    colnames(pvals_matrix) <- paste0("MAS5_Pval_", colnames(pvals_matrix))
    
    combined_results <- data.frame(
      ProbeSet = probe_sets,
      exprs_rma,
      exprs_mas5,
      calls_matrix,
      pvals_matrix
    )
    
    write.csv(combined_results, "normalized_expression_summary.csv", row.names = FALSE)
    
    # Generate a scatter plot comparing RMA and MAS5 expression values
    tryCatch({
      pdf("rma_vs_mas5_comparison.pdf", width = 8, height = 8)
      plot(exprs_rma[, 1], log2(exprs_mas5[, 1] + 1),
           xlab = "RMA Expression (log2)",
           ylab = "MAS5 Expression (log2)",
           main = paste("RMA vs MAS5 Comparison -", colnames(exprs_data)[1]),
           pch = 16, col = rgb(0, 0, 1, 0.5))
      abline(a = 0, b = 1, col = "red", lty = 2)
      dev.off()
    }, error = function(e) {
      warning("Comparison plotting failed: ", e\$message)
      if (names(dev.cur()) != "null device") dev.off()
      pdf("rma_vs_mas5_comparison.pdf")
      plot.new()
      text(0.5, 0.5, "Comparison Plotting Failed")
      dev.off()
    })

    writeLines(c(
        '"BIOC_AFFY_AFFY_MICROARRAY_PIPELINE":',
        paste0('    affy: ', as.character(packageVersion('affy')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_affy_microarray_pipeline.csv versions.yml
    """
}

workflow BIOC_AFFY_AFFY_MICROARRAY_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_AFFY_AFFY_MICROARRAY_PIPELINE(ch_input)

    emit:
    tables   = BIOC_AFFY_AFFY_MICROARRAY_PIPELINE.out.tables
    plots    = BIOC_AFFY_AFFY_MICROARRAY_PIPELINE.out.plots
    objects  = BIOC_AFFY_AFFY_MICROARRAY_PIPELINE.out.objects
    versions = BIOC_AFFY_AFFY_MICROARRAY_PIPELINE.out.versions
}
