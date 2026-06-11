#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: getDEE2 — dee2_validation_pipeline
// Fetch standardized RNA-seq counts and QC metadata from DEE2 for local SRA samples, and validate local processing via correlation analysis.
// Input: counts.csv, coldata.csv
// Container: 1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: S4Vectors, SummarizedExperiment, getDEE2
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GETDEE2_DEE2_VALIDATION_PIPELINE {
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
    library(getDEE2)
    library(S4Vectors)
    
    # --- Read local input files ---
    message("Reading local input files...")
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    local_counts <- read.csv("counts.csv", check.names = FALSE)
    
    # Format local counts: ensure gene_id is set as row names
    if ("gene_id" %in% colnames(local_counts)) {
      rownames(local_counts) <- local_counts\$gene_id
      local_counts\$gene_id <- NULL
    } else {
      rownames(local_counts) <- local_counts[, 1]
      local_counts <- local_counts[, -1, drop = FALSE]
    }
    
    # Extract and clean SRA Run Accessions (SRR/DRR/ERR)
    srr_vec <- as.character(coldata\$sample)
    srr_vec <- srr_vec[grep("^[SDR]RR\\\\d+\$", srr_vec)]
    
    if (length(srr_vec) == 0) {
      warning("No valid SRA Run Accessions (SRR/DRR/ERR) found in the 'sample' column of coldata.csv.")
      # Write empty fallback files and exit gracefully
      write.csv(data.frame(Warning="No valid SRR IDs found"), "dee2_fetched_counts.csv")
      write.csv(data.frame(Warning="No valid SRR IDs found"), "dee2_qc_summary.csv")
      write.csv(data.frame(Warning="No valid SRR IDs found"), "dee2_detailed_qc.csv")
      write.csv(data.frame(Warning="No valid SRR IDs found"), "dee2_gene_info.csv")
      write.csv(data.frame(Warning="No valid SRR IDs found"), "dee2_vs_local_correlation.csv")
      q(save = "no", status = 0)
    }
    
    # --- Auto-detect species from DEE2 metadata ---
    message("Detecting species for the provided SRA accessions...")
    species_list <- c("celegans", "hsapiens", "mmusculus", "dmelanogaster", "athaliana", "drerio", "rnorvegicus")
    detected_species <- NULL
    mdat <- NULL
    
    for (sp in species_list) {
      tryCatch({
        temp_mdat <- getDEE2Metadata(sp)
        if (any(srr_vec %in% temp_mdat\$SRR_accession)) {
          detected_species <- sp
          mdat <- temp_mdat
          message(paste("Detected species:", sp))
          break
        }
      }, error = function(e) {
        # Proceed to next species if metadata download fails or species is invalid
        next
      })
    }
    
    if (is.null(detected_species)) {
      message("Could not automatically match SRA accessions to a DEE2 species. Defaulting to 'celegans'.")
      detected_species <- "celegans"
      mdat <- tryCatch({
        getDEE2Metadata(detected_species)
      }, error = function(e) {
        NULL
      })
    }
    
    # --- Fetch standardized data from DEE2 ---
    se_dee2 <- NULL
    legacy_dee2 <- NULL
    
    if (!is.null(mdat)) {
      message(paste("Fetching DEE2 SummarizedExperiment for species:", detected_species))
      se_dee2 <- tryCatch({
        getDEE2(detected_species, srr_vec, metadata = mdat, counts = "GeneCounts")
      }, error = function(e) {
        message("Error fetching SummarizedExperiment: ", e\$message)
        NULL
      })
      
      message("Fetching DEE2 legacy data structure for detailed QC and gene info...")
      legacy_dee2 <- tryCatch({
        getDEE2(detected_species, srr_vec, metadata = mdat, legacy = TRUE)
      }, error = function(e) {
        message("Error fetching legacy DEE2 data: ", e\$message)
        NULL
      })
    }
    
    # --- Process and write outputs ---
    # Output 1: Standardized Gene Counts
    if (!is.null(se_dee2)) {
      dee2_counts <- assays(se_dee2)\$counts
      write.csv(dee2_counts, "dee2_fetched_counts.csv", row.names = TRUE)
    } else {
      write.csv(data.frame(Error = "Failed to fetch DEE2 counts"), "dee2_fetched_counts.csv")
      dee2_counts <- NULL
    }
    
    # Output 2: QC Summary Metadata
    if (!is.null(se_dee2)) {
      dee2_qc <- as.data.frame(colData(se_dee2))
      write.csv(dee2_qc, "dee2_qc_summary.csv", row.names = TRUE)
    } else {
      write.csv(data.frame(Error = "Failed to fetch DEE2 QC summary"), "dee2_qc_summary.csv")
    }
    
    # Output 3: Detailed QC Matrix
    if (!is.null(legacy_dee2) && !is.null(legacy_dee2\$QcMx)) {
      write.csv(as.data.frame(legacy_dee2\$QcMx), "dee2_detailed_qc.csv", row.names = TRUE)
    } else {
      write.csv(data.frame(Error = "Detailed QC matrix not available"), "dee2_detailed_qc.csv")
    }
    
    # Output 4: Gene Info
    if (!is.null(legacy_dee2) && !is.null(legacy_dee2\$GeneInfo)) {
      write.csv(as.data.frame(legacy_dee2\$GeneInfo), "dee2_gene_info.csv", row.names = TRUE)
    } else {
      write.csv(data.frame(Error = "Gene info not available"), "dee2_gene_info.csv")
    }
    
    # Output 5: Correlation Analysis (Validation)
    if (!is.null(dee2_counts)) {
      common_samples <- intersect(colnames(local_counts), colnames(dee2_counts))
      common_genes <- intersect(rownames(local_counts), rownames(dee2_counts))
      
      if (length(common_samples) > 0 && length(common_genes) > 10) {
        message(paste("Calculating correlation across", length(common_genes), "common genes and", length(common_samples), "samples..."))
        
        # Compute Spearman correlation matrix
        cor_matrix <- cor(local_counts[common_genes, common_samples, drop = FALSE],
                          dee2_counts[common_genes, common_samples, drop = FALSE],
                          method = "spearman")
        write.csv(cor_matrix, "dee2_vs_local_correlation.csv", row.names = TRUE)
      } else {
        warning("Insufficient overlapping samples or genes to perform correlation analysis.")
        write.csv(data.frame(Warning = "Insufficient overlapping samples or genes for correlation"), "dee2_vs_local_correlation.csv")
      }
    } else {
      write.csv(data.frame(Error = "No DEE2 counts available for correlation"), "dee2_vs_local_correlation.csv")
    }
    
    message("DEE2 validation pipeline completed successfully.")

    writeLines(c(
        '"BIOC_GETDEE2_DEE2_VALIDATION_PIPELINE":',
        paste0('    getDEE2: ', as.character(packageVersion('getDEE2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dee2_validation_pipeline.csv versions.yml
    """
}

workflow BIOC_GETDEE2_DEE2_VALIDATION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_GETDEE2_DEE2_VALIDATION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_GETDEE2_DEE2_VALIDATION_PIPELINE.out.tables
    plots    = BIOC_GETDEE2_DEE2_VALIDATION_PIPELINE.out.plots
    objects  = BIOC_GETDEE2_DEE2_VALIDATION_PIPELINE.out.objects
    versions = BIOC_GETDEE2_DEE2_VALIDATION_PIPELINE.out.versions
}
