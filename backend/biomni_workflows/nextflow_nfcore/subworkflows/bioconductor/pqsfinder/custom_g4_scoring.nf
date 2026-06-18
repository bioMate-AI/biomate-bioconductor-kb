#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pqsfinder — custom_g4_scoring
// Detect non-standard or custom G-quadruplexes (like interstrand G-quadruplexes) using custom scoring functions and regular expressions.
// Input: sequence.fasta
// Container: quay.io/biocontainers/bioconductor-pqsfinder:2.26.0--r45ha27e39d_1
// R packages: Biostrings, GenomicRanges, pqsfinder
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, GenomicRanges, pqsfinder
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define a custom scoring function
//  * 2. [Core Analysis] Run pqsfinder with custom_scoring_fn, and optionally disable default scoring (use_default_scoring = FALSE) and provide a custom ru

nextflow.enable.dsl = 2

process BIOC_PQSFINDER_CUSTOM_G4_SCORING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("Biostrings", "GenomicRanges", "pqsfinder")
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
    library(pqsfinder)
    library(Biostrings)
    library(GenomicRanges)
    
    # -----------------------------------------------------------------------------
    # Stage 1: Read User Input
    # -----------------------------------------------------------------------------
    # Read the DNA sequence from the required sequence.fasta file
    fasta_file <- "sequence.fasta"
    if (!file.exists(fasta_file)) {
      stop(paste("Required input file", fasta_file, "not found in the working directory."))
    }
    
    dna_seqs <- readDNAStringSet(fasta_file)
    if (length(dna_seqs) == 0) {
      stop("The input FASTA file is empty.")
    }
    
    # Extract the first sequence as a DNAString object
    seq <- dna_seqs[[1]]
    
    # -----------------------------------------------------------------------------
    # Stage 2: Define Custom Scoring Functions
    # -----------------------------------------------------------------------------
    
    # Custom scoring function 1: c_loop_bonus
    c_loop_bonus <- function(subject, score, start, width, loop_1,
                             run_2, loop_2, run_3, loop_3, run_4) {
      l1 <- run_2 - loop_1
      l2 <- run_3 - loop_2
      l3 <- run_4 - loop_3
      if (l1 == l2 && l1 == l3 && subject[loop_1] == DNAString("C") &&
          subject[loop_1] == subject[loop_2] &&
          subject[loop_1] == subject[loop_3]) {
        score <- score + 20
      }
      return(score)
    }
    
    # Custom scoring function 2: isG4 (for interstrand G-quadruplexes)
    isG4 <- function(subject, score, start, width, loop_1,
                     run_2, loop_2, run_3, loop_3, run_4) {
      r1 <- loop_1 - start
      r2 <- loop_2 - run_2
      r3 <- loop_3 - run_3
      r4 <- start + width - run_4
      
      if (!(r1 == r2 && r1 == r3 && r1 == r4))
        return(0)
      
      run_1_s <- subject[start:start+r1-1]
      run_2_s <- subject[run_2:run_2+r2-1]
      run_3_s <- subject[run_3:run_3+r3-1]
      run_4_s <- subject[run_4:run_4+r4-1]
      
      if (length(grep("^G+\$", run_1_s)) && length(grep("^C+\$", run_2_s)) &&
          length(grep("^G+\$", run_3_s)) && length(grep("^C+\$", run_4_s)))
        return(r1 * 20)
      else
        return(0)
    }
    
    # -----------------------------------------------------------------------------
    # Stage 3: Run pqsfinder with Custom Scoring Functions
    # -----------------------------------------------------------------------------
    
    # Run 1: Using c_loop_bonus custom scoring function
    pqs_c_loop <- pqsfinder(seq, custom_scoring_fn = c_loop_bonus)
    
    # Run 2: Using isG4 custom scoring function with custom run regex and disabled default scoring
    pqs_isG4 <- pqsfinder(seq, strand = "+",
                          use_default_scoring = FALSE, run_re = "G{3,6}|C{3,6}",
                          custom_scoring_fn = isG4)
    
    # -----------------------------------------------------------------------------
    # Stage 4: Export Results
    # -----------------------------------------------------------------------------
    
    # Save the raw PQSViews objects as RDS
    saveRDS(pqs_c_loop, "pqs_c_loop_results.rds")
    saveRDS(pqs_isG4, "pqs_isG4_results.rds")
    
    # Convert results to GRanges and export to CSV
    tryCatch({
      gr_c_loop <- as(pqs_c_loop, "GRanges")
      df_c_loop <- as.data.frame(gr_c_loop)
      write.csv(df_c_loop, "pqs_c_loop_annotations.csv", row.names = FALSE)
    }, error = function(e) {
      warning("Failed to export c_loop_bonus results to CSV: ", e\$message)
    })
    
    tryCatch({
      gr_isG4 <- as(pqs_isG4, "GRanges")
      df_isG4 <- as.data.frame(gr_isG4)
      write.csv(df_isG4, "pqs_isG4_annotations.csv", row.names = FALSE)
    }, error = function(e) {
      warning("Failed to export isG4 results to CSV: ", e\$message)
    })
    
    # Export to FASTA format
    tryCatch({
      dss_c_loop <- as(pqs_c_loop, "DNAStringSet")
      writeXStringSet(dss_c_loop, file = "pqs_c_loop_sequences.fa", format = "fasta")
    }, error = function(e) {
      warning("Failed to export c_loop_bonus sequences to FASTA: ", e\$message)
    })
    
    tryCatch({
      dss_isG4 <- as(pqs_isG4, "DNAStringSet")
      writeXStringSet(dss_isG4, file = "pqs_isG4_sequences.fa", format = "fasta")
    }, error = function(e) {
      warning("Failed to export isG4 sequences to FASTA: ", e\$message)
    })
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_PQSFINDER_CUSTOM_G4_SCORING":',
        paste0('    pqsfinder: ', as.character(packageVersion('pqsfinder')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_g4_scoring.csv versions.yml
    """
}

workflow BIOC_PQSFINDER_CUSTOM_G4_SCORING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sequence.fasta ] ]

    main:
    BIOC_PQSFINDER_CUSTOM_G4_SCORING(ch_input)

    emit:
    tables   = BIOC_PQSFINDER_CUSTOM_G4_SCORING.out.tables
    plots    = BIOC_PQSFINDER_CUSTOM_G4_SCORING.out.plots
    objects  = BIOC_PQSFINDER_CUSTOM_G4_SCORING.out.objects
    versions = BIOC_PQSFINDER_CUSTOM_G4_SCORING.out.versions
}
