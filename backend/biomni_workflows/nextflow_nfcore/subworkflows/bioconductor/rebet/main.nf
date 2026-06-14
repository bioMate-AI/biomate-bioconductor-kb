#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: REBET — rebet_subregion_burden_test
// Perform a subregion-based burden test (REBET) to identify rare variant associations and pinpoint susceptible sub-regions using VCF genotype data and sample meta
// Input: input.vcf, coldata.csv
// Container: 1.28.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: REBET
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REBET_REBET_SUBREGION_BURDEN_TEST {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    .bm_deps <- c("REBET")
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
    library(REBET)
    
    # ==========================================
    # --- Read and Parse Input Files ---
    # ==========================================
    message("Stage 1: Reading input VCF and metadata...")
    
    vcf_path <- "input.vcf"
    coldata_path <- "coldata.csv"
    
    if (!file.exists(vcf_path)) {
      stop("Required input file 'input.vcf' not found.")
    }
    if (!file.exists(coldata_path)) {
      stop("Required input file 'coldata.csv' not found.")
    }
    
    # Read sample metadata
    pheno <- read.csv(coldata_path, stringsAsFactors = FALSE)
    message(sprintf("Loaded metadata for %d samples.", nrow(pheno)))
    
    # Parse VCF file using robust base R parsing
    vcf_lines <- readLines(vcf_path)
    header_idx <- grep("^#CHROM", vcf_lines)
    if (length(header_idx) == 0) {
      stop("Invalid VCF: No '#CHROM' header line found.")
    }
    
    header_line <- vcf_lines[header_idx]
    header_cols <- strsplit(substring(header_line, 2), "\t")[[1]] # Remove leading '#'
    
    variant_lines <- vcf_lines[(header_idx + 1):length(vcf_lines)]
    variant_lines <- variant_lines[variant_lines != ""] # Remove empty lines
    
    if (length(variant_lines) == 0) {
      stop("No variants found in the VCF file.")
    }
    
    message(sprintf("Parsing %d variants from VCF...", length(variant_lines)))
    vcf_data <- do.call(rbind, strsplit(variant_lines, "\t"))
    colnames(vcf_data) <- header_cols
    
    # Extract positions and variant IDs
    locs <- as.numeric(vcf_data[, "POS"])
    snps <- vcf_data[, "ID"]
    missing_ids <- snps == "." | is.na(snps)
    if (any(missing_ids)) {
      snps[missing_ids] <- paste0(vcf_data[missing_ids, "CHROM"], "_", vcf_data[missing_ids, "POS"])
    }
    
    # Extract genotype columns (from column 10 onwards)
    sample_cols <- header_cols[10:length(header_cols)]
    geno_matrix <- vcf_data[, sample_cols, drop = FALSE]
    
    # Convert genotype strings (e.g., "0/1", "1/1") to numeric dosages (0, 1, 2)
    dosage_matrix <- matrix(NA_real_, nrow = nrow(geno_matrix), ncol = ncol(geno_matrix))
    colnames(dosage_matrix) <- colnames(geno_matrix)
    rownames(dosage_matrix) <- snps
    
    for (i in seq_len(nrow(geno_matrix))) {
      for (j in seq_len(ncol(geno_matrix))) {
        cell <- geno_matrix[i, j]
        gt <- strsplit(cell, ":")[[1]][1] # Extract GT field
        if (gt == "0/0" || gt == "0|0") {
          dosage_matrix[i, j] <- 0
        } else if (gt == "0/1" || gt == "1/0" || gt == "0|1" || gt == "1|0") {
          dosage_matrix[i, j] <- 1
        } else if (gt == "1/1" || gt == "1|1") {
          dosage_matrix[i, j] <- 2
        } else {
          dosage_matrix[i, j] <- NA
        }
      }
    }
    
    # Transpose genotype matrix: rows = subjects, columns = variants
    G <- t(dosage_matrix)
    
    # ==========================================
    # --- Align Genotype and Phenotype Data ---
    # ==========================================
    message("Stage 2: Aligning genotype and phenotype data...")
    
    common_samples <- intersect(rownames(G), pheno\$sample)
    if (length(common_samples) == 0) {
      stop("No overlapping samples found between VCF and coldata.csv")
    }
    
    G <- G[common_samples, , drop = FALSE]
    pheno <- pheno[match(common_samples, pheno\$sample), , drop = FALSE]
    message(sprintf("Aligned dataset contains %d samples and %d variants.", nrow(G), ncol(G)))
    
    # Define response variable Y
    if (is.character(pheno\$condition) || is.factor(pheno\$condition)) {
      Y <- as.numeric(as.factor(pheno\$condition)) - 1
    } else {
      Y <- as.numeric(pheno\$condition)
    }
    
    # Define covariates X if additional columns exist
    cov_cols <- setdiff(colnames(pheno), c("sample", "condition"))
    if (length(cov_cols) > 0) {
      X_list <- list()
      for (col in cov_cols) {
        val <- pheno[[col]]
        if (is.character(val) || is.factor(val)) {
          X_list[[col]] <- as.numeric(as.factor(val))
        } else {
          X_list[[col]] <- as.numeric(val)
        }
      }
      X <- as.matrix(as.data.frame(X_list))
    } else {
      X <- NULL
    }
    
    # ==========================================
    # --- Define Sub-regions ---
    # ==========================================
    message("Stage 3: Defining sub-regions for variants...")
    
    # Dynamically partition the variant positions into 4 equal sub-regions
    min_pos <- min(locs)
    max_pos <- max(locs)
    if (max_pos == min_pos) {
      max_pos <- min_pos + 4
    }
    breaks <- seq(min_pos, max_pos, length.out = 5)
    
    E <- rep("", length(locs))
    for (i in 1:4) {
      if (i == 4) {
        idx <- (locs >= breaks[i]) & (locs <= breaks[i+1])
      } else {
        idx <- (locs >= breaks[i]) & (locs < breaks[i+1])
      }
      E[idx] <- paste0("SR", i)
    }
    E[E == ""] <- "SR1" # Fallback assignment
    
    # ==========================================
    # --- Run REBET Analysis ---
    # ==========================================
    message("Stage 4: Running REBET subregion-based burden test...")
    
    ret <- tryCatch({
      rebet(Y, G, E, covariates = X)
    }, error = function(e) {
      message("REBET failed with error: ", e\$message)
      NULL
    })
    
    # ==========================================
    # --- Summarize and Export Results ---
    # ==========================================
    message("Stage 5: Exporting results...")
    
    if (!is.null(ret)) {
      # Extract summary tables
      summary_list <- h.summary(ret)
      
      meta_df <- as.data.frame(summary_list\$Meta)
      onesided_df <- as.data.frame(summary_list\$Subset.1sided)
      twosided_df <- as.data.frame(summary_list\$Subset.2sided)
      
      write.csv(meta_df, "rebet_meta_summary.csv", row.names = FALSE)
      write.csv(onesided_df, "rebet_onesided_summary.csv", row.names = FALSE)
      write.csv(twosided_df, "rebet_twosided_summary.csv", row.names = FALSE)
      
      message("Analysis completed successfully. Results written to CSV files.")
    } else {
      # Fallback empty outputs in case of execution failure
      write.csv(data.frame(Status = "REBET failed or returned NULL"), "rebet_meta_summary.csv", row.names = FALSE)
      write.csv(data.frame(Status = "REBET failed or returned NULL"), "rebet_onesided_summary.csv", row.names = FALSE)
      write.csv(data.frame(Status = "REBET failed or returned NULL"), "rebet_twosided_summary.csv", row.names = FALSE)
      message("Fallback empty files written due to analysis failure.")
    }

    writeLines(c(
        '"BIOC_REBET_REBET_SUBREGION_BURDEN_TEST":',
        paste0('    REBET: ', as.character(packageVersion('REBET')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rebet_subregion_burden_test.csv versions.yml
    """
}

workflow BIOC_REBET_REBET_SUBREGION_BURDEN_TEST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_REBET_REBET_SUBREGION_BURDEN_TEST(ch_input)

    emit:
    tables   = BIOC_REBET_REBET_SUBREGION_BURDEN_TEST.out.tables
    plots    = BIOC_REBET_REBET_SUBREGION_BURDEN_TEST.out.plots
    objects  = BIOC_REBET_REBET_SUBREGION_BURDEN_TEST.out.objects
    versions = BIOC_REBET_REBET_SUBREGION_BURDEN_TEST.out.versions
}
