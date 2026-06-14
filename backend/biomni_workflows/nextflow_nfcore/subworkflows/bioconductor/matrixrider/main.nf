#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MatrixRider — tf_sequence_occupancy
// Calculate the total binding affinity or occupancy of single or multiple transcription factors on a target DNA sequence.
// Input: sequence.fasta, jaspar_db
// Container: quay.io/biocontainers/bioconductor-matrixrider:1.42.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, MatrixRider, TFBSTools
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the target DNA sequence into a DNAString object
//  * 2. [Input & Preparation] Retrieve or define the transcription factor PFMatrix or PFMatrixList
//  * 3. [Core Analysis] Calculate the sequence occupancy or total affinity using getSeqOccupancy with a specified cutoff

nextflow.enable.dsl = 2

process BIOC_MATRIXRIDER_TF_SEQUENCE_OCCUPANCY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("MatrixRider", "TFBSTools", "Biostrings")
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
    library(MatrixRider)
    library(TFBSTools)
    library(Biostrings)
    
    # 1. Load the target DNA sequence into a DNAString object
    if (!file.exists("sequence.fasta")) {
      stop("Required input file 'sequence.fasta' not found.")
    }
    sequence_set <- readDNAStringSet("sequence.fasta")
    if (length(sequence_set) == 0) {
      stop("The sequence.fasta file is empty.")
    }
    sequence <- sequence_set[[1]] # Extract first sequence as DNAString
    
    # 2. Retrieve or define the transcription factor PFMatrix or PFMatrixList
    if (!file.exists("jaspar_db")) {
      stop("Required input file 'jaspar_db' not found.")
    }
    
    # Attempt to read jaspar_db as RDS first, then as JASPAR format
    raw_pfms <- tryCatch({
      readRDS("jaspar_db")
    }, error = function(e) {
      tryCatch({
        readJASPARMatrix("jaspar_db", matrixClass = "PFM")
      }, error = function(e2) {
        stop("Failed to read 'jaspar_db' as RDS or JASPAR format. Error: ", e2\$message)
      })
    })
    
    # Extract pfm and pfm2 to match the documented workflow
    if (inherits(raw_pfms, "PFMatrix")) {
      pfm <- raw_pfms
      pfm2 <- raw_pfms # Fallback if only one matrix is provided
    } else if (inherits(raw_pfms, "PFMatrixList")) {
      if (length(raw_pfms) == 0) {
        stop("The loaded PFMatrixList is empty.")
      }
      pfm <- raw_pfms[[1]]
      if (length(raw_pfms) >= 2) {
        pfm2 <- raw_pfms[[2]]
      } else {
        pfm2 <- raw_pfms[[1]] # Fallback
      }
    } else {
      stop("The loaded 'jaspar_db' must be a PFMatrix or PFMatrixList object.")
    }
    
    # 3. Calculate the sequence occupancy or total affinity using getSeqOccupancy
    # Single PFM occupancy calculations
    occ_01 <- getSeqOccupancy(sequence, pfm, 0.1)
    occ_1 <- getSeqOccupancy(sequence, pfm, 1)
    
    # Multiple PFMs occupancy calculations
    pfms <- PFMatrixList(pfm, pfm2)
    names(pfms) <- c(name(pfm), name(pfm2))
    occ_multi_0 <- getSeqOccupancy(sequence, pfms, 0)
    
    # Save results to output files
    results <- list(
      single_pfm_occupancy_0.1 = occ_01,
      single_pfm_occupancy_1.0 = occ_1,
      multi_pfm_occupancy_0 = occ_multi_0
    )
    saveRDS(results, "occupancy_results.rds")
    
    # Create a summary data frame and write to CSV
    summary_df <- data.frame(
      Metric = c("Single_PFM_0.1", "Single_PFM_1.0", paste0("Multi_PFM_0_", names(occ_multi_0))),
      Value = c(occ_01, occ_1, occ_multi_0),
      stringsAsFactors = FALSE
    )
    write.csv(summary_df, "occupancy_summary.csv", row.names = FALSE)
    
    cat("Workflow completed successfully. Results saved to 'occupancy_results.rds' and 'occupancy_summary.csv'.\n")

    writeLines(c(
        '"BIOC_MATRIXRIDER_TF_SEQUENCE_OCCUPANCY":',
        paste0('    MatrixRider: ', as.character(packageVersion('MatrixRider')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tf_sequence_occupancy.csv versions.yml
    """
}

workflow BIOC_MATRIXRIDER_TF_SEQUENCE_OCCUPANCY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sequence.fasta, jaspar_db ] ]

    main:
    BIOC_MATRIXRIDER_TF_SEQUENCE_OCCUPANCY(ch_input)

    emit:
    tables   = BIOC_MATRIXRIDER_TF_SEQUENCE_OCCUPANCY.out.tables
    plots    = BIOC_MATRIXRIDER_TF_SEQUENCE_OCCUPANCY.out.plots
    objects  = BIOC_MATRIXRIDER_TF_SEQUENCE_OCCUPANCY.out.objects
    versions = BIOC_MATRIXRIDER_TF_SEQUENCE_OCCUPANCY.out.versions
}
