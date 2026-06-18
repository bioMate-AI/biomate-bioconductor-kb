#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MEDME — medme_methylation_prediction
// Predict absolute and relative DNA methylation levels from MeDIP-microarray data using a logistic model calibrated on fully-methylated DNA.
// Input: matrix.csv, coldata.csv
// Container: 1.70.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg18, MEDME
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MEDME_MEDME_METHYLATION_PREDICTION {
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
    .bm_deps <- c("MEDME", "BSgenome.Hsapiens.UCSC.hg18")
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
    library(MEDME)
    library(BSgenome.Hsapiens.UCSC.hg18)
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    
    message("Loading input data...")
    # Read the feature-by-sample matrix
    mat <- read.csv("matrix.csv", check.names = FALSE)
    if (!"feature_id" %in% colnames(mat)) {
      stop("Input matrix.csv must contain a 'feature_id' column.")
    }
    rownames(mat) <- mat\$feature_id
    feature_ids <- mat\$feature_id
    mat\$feature_id <- NULL
    
    # Read sample metadata
    coldata <- read.csv("coldata.csv")
    if (!all(c("sample", "condition") %in% colnames(coldata))) {
      stop("Input coldata.csv must contain 'sample' and 'condition' columns.")
    }
    
    # Align matrix columns with coldata samples
    common_samples <- intersect(colnames(mat), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("No matching samples found between matrix.csv columns and coldata.csv 'sample' column.")
    }
    mat <- mat[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), ]
    
    # Identify the calibration (fully-methylated) sample
    # Look for common keywords representing calibration/control
    calib_idx <- which(tolower(coldata\$condition) %in% c("fullymet", "calibration", "control", "reference", "calib"))
    if (length(calib_idx) == 0) {
      message("No explicit calibration sample found in 'condition'. Defaulting to the first sample.")
      calib_idx <- 1
    } else {
      calib_idx <- calib_idx[1]
      message(sprintf("Using sample '%s' as the calibration control.", coldata\$sample[calib_idx]))
    }
    
    # ==========================================
    # --- Parse and Validate Genomic Coordinates ---
    # ==========================================
    
    message("Parsing genomic coordinates...")
    # Initialize default coordinates on chrX of hg18 to prevent out-of-bounds errors
    chr_vec <- rep("chrX", length(feature_ids))
    pos_vec <- seq(from = 1000000, by = 1000, length.out = length(feature_ids))
    
    # Attempt to parse actual coordinates from feature_id (e.g., "chr1_10000" or "chr1:10000")
    parsed_chr <- gsub("^([Cc][Hh][Rr][0-9XYxy]+)[_:.].*\$", "\\1", feature_ids)
    parsed_pos <- as.integer(gsub("^.*[_:.]([0-9]+)\$", "\\1", feature_ids))
    
    valid_parse <- !is.na(parsed_pos) & grepl("^chr", parsed_chr, ignore.case = TRUE)
    if (any(valid_parse)) {
      chr_vec[valid_parse] <- parsed_chr[valid_parse]
      pos_vec[valid_parse] <- parsed_pos[valid_parse]
    }
    
    # Ensure chromosomes match hg18 naming style and positions are within bounds
    genome <- BSgenome.Hsapiens.UCSC.hg18
    chr_vec <- paste0("chr", gsub("^chr", "", chr_vec, ignore.case = TRUE))
    
    # Fallback for chromosomes not present in hg18
    invalid_chr <- !chr_vec %in% seqnames(genome)
    if (any(invalid_chr)) {
      chr_vec[invalid_chr] <- "chrX"
    }
    
    # Fallback for out-of-bounds positions
    chr_lens <- seqlengths(genome)[chr_vec]
    out_of_bounds <- is.na(pos_vec) | pos_vec < 1 | pos_vec > chr_lens
    if (any(out_of_bounds)) {
      pos_vec[out_of_bounds] <- 1000000 + (which(out_of_bounds) * 100) %% 10000000
    }
    
    # ==========================================
    # --- Create MEDMEset and Run Pipeline ---
    # ==========================================
    
    message("Initializing MEDMEset object...")
    medme_set <- new("MEDMEset",
                     logR = as.matrix(mat),
                     chr = chr_vec,
                     pos = as.integer(pos_vec),
                     org = "hsa")
    
    message("Smoothing MeDIP enrichment data...")
    medme_set <- smooth(data = medme_set, wsize = 1000, wFunction = "linear")
    
    message("Calculating probe-level CpG content...")
    medme_set <- CGcount(data = medme_set)
    
    message("Fitting logistic model on calibration data...")
    # Save the diagnostic model fit plot to PDF
    pdf("medme_model_fit.pdf", width = 7, height = 7)
    MEDMEmodel <- MEDME(data = medme_set, sample = calib_idx)
    dev.off()
    
    message("Predicting absolute and relative methylation levels...")
    medme_set <- MEDME.predict(data = medme_set,
                               MEDMEfit = MEDMEmodel,
                               MEDMEextremes = c(1, 32),
                               wsize = 1000,
                               wFunction = "linear")
    
    # ==========================================
    # --- Export Results ---
    # ==========================================
    
    message("Exporting results...")
    
    # Extract results
    smoothed_data <- smoothed(medme_set)
    ams_data <- AMS(medme_set)
    rms_data <- RMS(medme_set)
    
    # Add feature_id back as the first column
    smoothed_df <- data.frame(feature_id = feature_ids, smoothed_data, check.names = FALSE)
    ams_df <- data.frame(feature_id = feature_ids, ams_data, check.names = FALSE)
    rms_df <- data.frame(feature_id = feature_ids, rms_data, check.names = FALSE)
    
    # Write to CSV
    write.csv(smoothed_df, "smoothed_logR.csv", row.names = FALSE)
    write.csv(ams_df, "absolute_methylation_scores.csv", row.names = FALSE)
    write.csv(rms_df, "relative_methylation_scores.csv", row.names = FALSE)
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_MEDME_MEDME_METHYLATION_PREDICTION":',
        paste0('    MEDME: ', as.character(packageVersion('MEDME')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_medme_methylation_prediction.csv versions.yml
    """
}

workflow BIOC_MEDME_MEDME_METHYLATION_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_MEDME_MEDME_METHYLATION_PREDICTION(ch_input)

    emit:
    tables   = BIOC_MEDME_MEDME_METHYLATION_PREDICTION.out.tables
    plots    = BIOC_MEDME_MEDME_METHYLATION_PREDICTION.out.plots
    objects  = BIOC_MEDME_MEDME_METHYLATION_PREDICTION.out.objects
    versions = BIOC_MEDME_MEDME_METHYLATION_PREDICTION.out.versions
}
