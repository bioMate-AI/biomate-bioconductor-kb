#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: illuminaio — illumina_microarray_pipeline
// Parse raw Illumina IDAT files using illuminaio, align with sample metadata, perform quality control, and conduct differential expression analysis.
// Input: counts.csv, coldata.csv
// Container: 0.52.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, illuminaio
// Visualizations: box plot, image plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ILLUMINAIO_ILLUMINA_MICROARRAY_PIPELINE {
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
    library(illuminaio)
    
    # ==========================================
    # Stage 1: Load Metadata and Discover Files
    # ==========================================
    message("Stage 1: Loading metadata and discovering files...")
    
    if (!file.exists("coldata.csv")) {
      stop("Error: coldata.csv is required but was not found in the working directory.")
    }
    
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    if (!all(c("sample", "condition") %in% colnames(coldata))) {
      stop("Error: coldata.csv must contain 'sample' and 'condition' columns.")
    }
    
    # Search for raw Illumina files in the working directory
    idat_files <- list.files(pattern = "\\\\.idat\$", ignore.case = TRUE)
    bgx_files <- list.files(pattern = "\\\\.bgx\$", ignore.case = TRUE)
    bpm_files <- list.files(pattern = "\\\\.bpm\$", ignore.case = TRUE)
    
    # ==========================================
    # Stage 2: Parse Illumina Files (if present)
    # ==========================================
    message("Stage 2: Parsing Illumina files...")
    
    # Helper function to safely read and extract intensities from IDAT files
    read_idat_safe <- function(file_path) {
      tryCatch({
        data <- illuminaio::readIDAT(file_path)
        if ("Quants" %in% names(data)) {
          quants <- data\$Quants
          if ("MeanBinData" %in% colnames(quants) && "CodesBinData" %in% colnames(quants)) {
            # Expression IDAT format
            df <- data.frame(
              ProbeID = as.character(quants[, "CodesBinData"]),
              Intensity = as.numeric(quants[, "MeanBinData"]),
              stringsAsFactors = FALSE
            )
            return(df)
          } else if ("Mean" %in% colnames(quants)) {
            # Genotyping IDAT format
            df <- data.frame(
              ProbeID = rownames(quants),
              Intensity = as.numeric(quants[, "Mean"]),
              stringsAsFactors = FALSE
            )
            return(df)
          }
        }
        return(NULL)
      }, error = function(e) {
        warning("Error reading IDAT file ", file_path, ": ", e\$message)
        return(NULL)
      })
    }
    
    expression_matrix <- NULL
    parsed_from_idat <- FALSE
    
    # Attempt to parse IDAT files matching the samples in coldata
    if (length(idat_files) > 0) {
      message("Found IDAT files. Attempting to match with coldata...")
      sample_data_list <- list()
      
      for (i in seq_len(nrow(coldata))) {
        s_name <- coldata\$sample[i]
        # Find matching IDAT file (e.g., SampleName_Grn.idat or SampleName.idat)
        matching_files <- idat_files[grep(s_name, idat_files, fixed = TRUE)]
        if (length(matching_files) > 0) {
          file_to_read <- matching_files[1]
          message("Parsing IDAT for sample: ", s_name)
          parsed <- read_idat_safe(file_to_read)
          if (!is.null(parsed)) {
            sample_data_list[[s_name]] <- parsed
          }
        }
      }
      
      if (length(sample_data_list) > 0) {
        # Merge all parsed samples by ProbeID
        merged <- Reduce(function(x, y) merge(x, y, by = "ProbeID", all = TRUE), sample_data_list)
        rownames(merged) <- merged\$ProbeID
        expression_matrix <- as.matrix(merged[, -1, drop = FALSE])
        colnames(expression_matrix) <- names(sample_data_list)
        parsed_from_idat <- TRUE
        message("Successfully parsed and assembled expression matrix from IDAT files.")
      }
    }
    
    # Parse BGX annotation file if present
    if (length(bgx_files) > 0) {
      message("Found BGX file: ", bgx_files[1], ". Parsing annotation...")
      tryCatch({
        bgx_data <- illuminaio::readBGX(bgx_files[1])
        message("Successfully parsed BGX file.")
      }, error = function(e) {
        warning("Failed to parse BGX file: ", e\$message)
      })
    }
    
    # Parse BPM manifest file if present
    if (length(bpm_files) > 0) {
      message("Found BPM file: ", bpm_files[1], ". Parsing manifest...")
      tryCatch({
        bpm_data <- illuminaio::readBPM(bpm_files[1])
        message("Successfully parsed BPM file.")
      }, error = function(e) {
        warning("Failed to parse BPM file: ", e\$message)
      })
    }
    
    # ==========================================
    # Stage 3: Fallback to Pre-processed Matrix
    # ==========================================
    if (!parsed_from_idat) {
      message("No matching IDAT files found or parsing failed. Falling back to counts.csv...")
      if (file.exists("counts.csv")) {
        expression_matrix <- as.matrix(read.csv("counts.csv", row.names = 1, check.names = FALSE))
      } else {
        stop("Error: Neither IDAT files nor counts.csv found in the working directory.")
      }
    }
    
    # Align expression matrix with coldata
    common_samples <- intersect(colnames(expression_matrix), coldata\$sample)
    if (length(common_samples) == 0) {
      warning("Sample names in coldata do not match column names in expression matrix. Aligning by order.")
      common_samples <- colnames(expression_matrix)[1:min(ncol(expression_matrix), nrow(coldata))]
      coldata <- coldata[1:length(common_samples), , drop = FALSE]
      colnames(expression_matrix)[1:length(common_samples)] <- coldata\$sample
      common_samples <- coldata\$sample
    }
    
    expression_matrix <- expression_matrix[, common_samples, drop = FALSE]
    coldata <- coldata[coldata\$sample %in% common_samples, , drop = FALSE]
    coldata <- coldata[match(colnames(expression_matrix), coldata\$sample), , drop = FALSE]
    
    # Handle missing values if any
    if (any(is.na(expression_matrix))) {
      message("Imputing missing values with row means...")
      row_means <- rowMeans(expression_matrix, na.rm = TRUE)
      row_means[is.na(row_means)] <- 0
      for (col in seq_len(ncol(expression_matrix))) {
        na_idx <- is.na(expression_matrix[, col])
        expression_matrix[na_idx, col] <- row_means[na_idx]
      }
    }
    
    # ==========================================
    # Stage 4: Build SummarizedExperiment & QC
    # ==========================================
    message("Stage 4: Building SummarizedExperiment and performing QC...")
    
    se <- SummarizedExperiment(
      assays = list(exprs = expression_matrix),
      colData = DataFrame(coldata)
    )
    
    # Open PDF device for QC plots
    pdf("qc_report.pdf", width = 8, height = 6)
    
    # Plot 1: Boxplot of Intensities
    boxplot(assay(se, "exprs"), main = "Expression Intensity Distribution",
            col = "lightblue", las = 2, ylab = "Intensity")
    
    # Plot 2: Density Plot of Intensities
    plot(density(assay(se, "exprs")[, 1]), main = "Density of Expression Intensities",
         xlab = "Intensity", ylab = "Density", col = 1, type = "l",
         ylim = c(0, max(apply(assay(se, "exprs"), 2, function(x) max(density(x)\$y))) * 1.1))
    if (ncol(se) > 1) {
      for (j in 2:ncol(se)) {
        lines(density(assay(se, "exprs")[, j]), col = j)
      }
    }
    legend("topright", legend = colnames(se), col = 1:ncol(se), lty = 1, cex = 0.8)
    
    # Plot 3: Sample Correlation Heatmap
    cor_matrix <- cor(assay(se, "exprs"), method = "pearson", use = "pairwise.complete.obs")
    image(1:ncol(cor_matrix), 1:nrow(cor_matrix), cor_matrix,
          main = "Sample Correlation Heatmap", xlab = "", ylab = "", axes = FALSE)
    axis(1, at = 1:ncol(cor_matrix), labels = colnames(cor_matrix), las = 2)
    axis(2, at = 1:nrow(cor_matrix), labels = rownames(cor_matrix), las = 2)
    for (x in 1:ncol(cor_matrix)) {
      for (y in 1:nrow(cor_matrix)) {
        text(x, y, round(cor_matrix[x, y], 2), col = "black")
      }
    }
    
    # ==========================================
    # Stage 5: Differential Expression Analysis
    # ==========================================
    message("Stage 5: Performing differential expression analysis...")
    
    conds <- colData(se)\$condition
    unique_conds <- unique(conds)
    de_results <- data.frame(ProbeID = rownames(se), stringsAsFactors = FALSE)
    
    if (length(unique_conds) >= 2 && all(table(conds) >= 1)) {
      g1 <- which(conds == unique_conds[1])
      g2 <- which(conds == unique_conds[2])
      
      p_vals <- apply(assay(se, "exprs"), 1, function(row) {
        tryCatch({
          t.test(row[g1], row[g2])\$p.value
        }, error = function(e) NA)
      })
      
      mean_g1 <- rowMeans(assay(se, "exprs")[, g1, drop = FALSE], na.rm = TRUE)
      mean_g2 <- rowMeans(assay(se, "exprs")[, g2, drop = FALSE], na.rm = TRUE)
      
      # Calculate Log2 Fold Change safely
      if (max(assay(se, "exprs"), na.rm = TRUE) > 50) {
        # Raw intensities: log2 transform first
        log2FC <- log2(mean_g1 + 1) - log2(mean_g2 + 1)
      } else {
        # Already log-transformed
        log2FC <- mean_g1 - mean_g2
      }
      
      de_results\$Mean_Group1 <- mean_g1
      de_results\$Mean_Group2 <- mean_g2
      de_results\$Log2FC <- log2FC
      de_results\$PValue <- p_vals
      de_results\$AdjPValue <- p.adjust(p_vals, method = "BH")
      
      # Plot 4: Volcano Plot
      plot(de_results\$Log2FC, -log10(de_results\$PValue),
           main = paste("Volcano Plot:", unique_conds[1], "vs", unique_conds[2]),
           xlab = "Log2 Fold Change", ylab = "-log10(P-value)",
           pch = 20, col = ifelse(de_results\$AdjPValue < 0.05, "red", "black"))
      abline(h = -log10(0.05), col = "blue", lty = 2)
    } else {
      message("Insufficient groups or replicates for differential analysis. Calculating basic statistics...")
      de_results\$Mean <- rowMeans(assay(se, "exprs"), na.rm = TRUE)
      de_results\$SD <- apply(assay(se, "exprs"), 1, sd, na.rm = TRUE)
      
      # Plot 4: SD vs Mean Plot
      plot(de_results\$Mean, de_results\$SD,
           main = "Standard Deviation vs Mean Expression",
           xlab = "Mean Intensity", ylab = "Standard Deviation",
           pch = 20, col = "darkgreen")
    }
    
    dev.off()
    
    # ==========================================
    # Stage 6: Save Outputs
    # ==========================================
    message("Stage 6: Saving output files...")
    
    write.csv(assay(se, "exprs"), "processed_expression.csv", row.names = TRUE)
    write.csv(de_results, "differential_analysis.csv", row.names = FALSE)
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_ILLUMINAIO_ILLUMINA_MICROARRAY_PIPELINE":',
        paste0('    illuminaio: ', as.character(packageVersion('illuminaio')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_illumina_microarray_pipeline.csv versions.yml
    """
}

workflow BIOC_ILLUMINAIO_ILLUMINA_MICROARRAY_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ILLUMINAIO_ILLUMINA_MICROARRAY_PIPELINE(ch_input)

    emit:
    tables   = BIOC_ILLUMINAIO_ILLUMINA_MICROARRAY_PIPELINE.out.tables
    plots    = BIOC_ILLUMINAIO_ILLUMINA_MICROARRAY_PIPELINE.out.plots
    objects  = BIOC_ILLUMINAIO_ILLUMINA_MICROARRAY_PIPELINE.out.objects
    versions = BIOC_ILLUMINAIO_ILLUMINA_MICROARRAY_PIPELINE.out.versions
}
