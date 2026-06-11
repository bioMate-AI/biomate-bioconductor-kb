#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tfbstools — tfbs_sequence_scanning
// Scan a nucleotide sequence with a PWM to identify putative TFBSs, calculate empirical p-values, and export results to GFF format.
// Input: sequence.fasta, pfm_data.txt
// Container: quay.io/biocontainers/bioconductor-tfbstools:1.48.0--r45h01b2380_0
// R packages: Biostrings, CNEr, JASPAR2014, rtracklayer, TFBSTools
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TFBSTOOLS_TFBS_SEQUENCE_SCANNING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-tfbstools:1.48.0--r45h01b2380_0"

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
    .bm_deps <- c("Biostrings", "CNEr", "JASPAR2014", "rtracklayer", "TFBSTools")
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
    library(TFBSTools)
    library(Biostrings)
    
    # ==========================================
    # 1. Read User Input Files & Construct PFM
    # ==========================================
    
    # Read DNA sequence of interest
    if (!file.exists("sequence.fasta")) {
      stop("Error: 'sequence.fasta' not found in the working directory.")
    }
    seqs <- readDNAStringSet("sequence.fasta")
    if (length(seqs) == 0) {
      stop("Error: 'sequence.fasta' is empty.")
    }
    subject <- seqs[[1]]
    
    # Read PFM data or JASPAR ID
    if (!file.exists("pfm_data.txt")) {
      stop("Error: 'pfm_data.txt' not found in the working directory.")
    }
    pfm_lines <- readLines("pfm_data.txt")
    pfm_lines <- pfm_lines[nzchar(trimws(pfm_lines))]
    
    if (length(pfm_lines) == 0) {
      stop("Error: 'pfm_data.txt' is empty.")
    }
    
    # Determine if input is a JASPAR ID or a raw matrix
    if (length(pfm_lines) == 1 && grepl("^MA\\d", trimws(pfm_lines[1]))) {
      # Input is a JASPAR ID
      jaspar_id <- trimws(pfm_lines[1])
      message("Loading PFM from JASPAR2014 database for ID: ", jaspar_id)
      if (!requireNamespace("JASPAR2014", quietly = TRUE)) {
        stop("Error: JASPAR2014 package is required to fetch JASPAR IDs.")
      }
      library(JASPAR2014)
      opts <- list(ID = jaspar_id)
      pfm_list <- getMatrixSet(JASPAR2014, opts)
      if (length(pfm_list) == 0) {
        stop(paste("Error: JASPAR ID", jaspar_id, "not found in JASPAR2014."))
      }
      pfm <- pfm_list[[1]]
    } else {
      # Input is a raw matrix
      message("Parsing raw PFM matrix from pfm_data.txt")
      matrix_rows <- list()
      for (line in pfm_lines) {
        # Extract all integers from the line
        nums <- as.integer(regmatches(line, gregexpr("\\d+", line))[[1]])
        if (length(nums) > 0) {
          matrix_rows[[length(matrix_rows) + 1]] <- nums
        }
      }
      if (length(matrix_rows) != 4) {
        stop("Error: Raw PFM matrix must contain exactly 4 rows of counts (A, C, G, T).")
      }
      
      profile_mat <- do.call(rbind, matrix_rows)
      rownames(profile_mat) <- c("A", "C", "G", "T")
      
      # Construct PFMatrix object using documented arguments
      pfm <- PFMatrix(ID="User_PFM", name="User_Motif", 
                      matrixClass="Unknown", strand="+",
                      bg=c(A=0.25, C=0.25, G=0.25, T=0.25),
                      tags=list(family="Unknown", species="Unknown"),
                      profileMatrix=profile_mat)
    }
    
    # ==========================================
    # 2. Convert PFMatrix to PWMatrix
    # ==========================================
    pwm <- toPWM(pfm, type="log2probratio", pseudocounts=0.8,
                 bg=c(A=0.25, C=0.25, G=0.25, T=0.25))
    
    # ==========================================
    # 3. Scan Sequence with PWMatrix
    # ==========================================
    siteset <- searchSeq(pwm, subject, seqname="seq1", min.score="60%", strand="*")
    
    # ==========================================
    # 4. Calculate Empirical P-values
    # ==========================================
    p_tfm <- tryCatch({
      pvalues(siteset, type="TFMPvalue")
    }, error = function(e) {
      warning("Could not calculate TFMPvalue p-values: ", e\$message)
      rep(NA, length(siteset))
    })
    
    p_samp <- tryCatch({
      pvalues(siteset, type="sampling")
    }, error = function(e) {
      warning("Could not calculate sampling p-values: ", e\$message)
      rep(NA, length(siteset))
    })
    
    # ==========================================
    # 5. Export Results
    # ==========================================
    
    # Generate GFF3 and GFF2 data frames
    gff3_df <- writeGFF3(siteset)
    gff2_df <- writeGFF2(siteset)
    
    # Print head of GFF outputs to console as in documented code
    message("\n--- GFF3 Output Head ---")
    print(head(gff3_df))
    
    message("\n--- GFF2 Output Head ---")
    print(head(gff2_df))
    
    # Write GFF files
    write.table(gff3_df, "siteset.gff3", sep="\t", quote=FALSE, row.names=FALSE, col.names=TRUE)
    write.table(gff2_df, "siteset.gff2", sep="\t", quote=FALSE, row.names=FALSE, col.names=TRUE)
    
    # Create a comprehensive CSV summary table
    summary_df <- gff3_df
    summary_df\$relScore <- relScore(siteset)
    summary_df\$pvalue_TFMPvalue <- p_tfm
    summary_df\$pvalue_sampling <- p_samp
    
    write.csv(summary_df, "tfbs_scan_results.csv", row.names=FALSE)
    
    # Save R objects for downstream analysis
    saveRDS(pwm, "pwm.rds")
    saveRDS(siteset, "siteset.rds")
    
    message("\nPipeline completed successfully. Outputs saved:")
    message("- siteset.gff3 (GFF3 format predictions)")
    message("- siteset.gff2 (GFF2 format predictions)")
    message("- tfbs_scan_results.csv (Comprehensive CSV summary with scores and p-values)")
    message("- pwm.rds (Serialized PWMatrix object)")
    message("- siteset.rds (Serialized SiteSet object)")

    writeLines(c(
        '"BIOC_TFBSTOOLS_TFBS_SEQUENCE_SCANNING":',
        paste0('        tfbstools: ', as.character(packageVersion("tfbstools")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tfbs_sequence_scanning.csv versions.yml
    """
}

workflow BIOC_TFBSTOOLS_TFBS_SEQUENCE_SCANNING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sequence.fasta, pfm_data.txt ] ]

    main:
    BIOC_TFBSTOOLS_TFBS_SEQUENCE_SCANNING(ch_input)

    emit:
    tables   = BIOC_TFBSTOOLS_TFBS_SEQUENCE_SCANNING.out.tables
    plots    = BIOC_TFBSTOOLS_TFBS_SEQUENCE_SCANNING.out.plots
    objects  = BIOC_TFBSTOOLS_TFBS_SEQUENCE_SCANNING.out.objects
    versions = BIOC_TFBSTOOLS_TFBS_SEQUENCE_SCANNING.out.versions
}
