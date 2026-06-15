#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pqsfinder — custom_g4_detection
// Detect non-standard or customized G-quadruplex structures (such as interstrand G-quadruplexes) using custom scoring functions and regular expressions.
// Input: sequence.fa
// Container: quay.io/biocontainers/bioconductor-pqsfinder:2.26.0--r45ha27e39d_1
// R packages: Biostrings, pqsfinder, rtracklayer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PQSFINDER_CUSTOM_G4_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-pqsfinder:2.26.0--r45ha27e39d_1"

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
    .bm_deps <- c("Biostrings", "pqsfinder", "rtracklayer")
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
    library(pqsfinder)
    library(Biostrings)
    library(rtracklayer)
    
    # --- Read the user input FASTA file ---
    fasta_seqs <- readDNAStringSet("sequence.fa")
    seq <- fasta_seqs[[1]] # Extract the first sequence as a DNAString
    
    # --- Define a custom scoring function (c_loop_bonus) ---
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
    
    # --- Run pqsfinder with the custom scoring function ---
    pqs_custom1 <- pqsfinder(seq, custom_scoring_fn = c_loop_bonus)
    
    # --- Define an alternative scoring function (isG4) and regular ---
    # for complete replacement of the default scoring system
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
    
    # --- Run pqsfinder with default scoring disabled ---
    pqs_custom2 <- pqsfinder(seq, strand = "+",
              use_default_scoring = FALSE, run_re = "G{3,6}|C{3,6}",
              custom_scoring_fn = isG4)
    
    # --- Write named output files for the meaningful results ---
    saveRDS(pqs_custom1, "pqs_custom1.rds")
    saveRDS(pqs_custom2, "pqs_custom2.rds")
    
    # Convert to GRanges and export to GFF3
    gr1 <- as(pqs_custom1, "GRanges")
    export(gr1, "pqs_custom1.gff", version = "3")
    
    gr2 <- as(pqs_custom2, "GRanges")
    export(gr2, "pqs_custom2.gff", version = "3")
    
    # Convert to DNAStringSet and export to FASTA
    dss1 <- as(pqs_custom1, "DNAStringSet")
    writeXStringSet(dss1, file = "pqs_custom1_detected.fa", format = "fasta")
    
    dss2 <- as(pqs_custom2, "DNAStringSet")
    writeXStringSet(dss2, file = "pqs_custom2_detected.fa", format = "fasta")

    writeLines(c(
        '"BIOC_PQSFINDER_CUSTOM_G4_DETECTION":',
        paste0('        pqsfinder: ', as.character(packageVersion("pqsfinder")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_g4_detection.csv versions.yml
    """
}

workflow BIOC_PQSFINDER_CUSTOM_G4_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sequence.fa ] ]

    main:
    BIOC_PQSFINDER_CUSTOM_G4_DETECTION(ch_input)

    emit:
    tables   = BIOC_PQSFINDER_CUSTOM_G4_DETECTION.out.tables
    plots    = BIOC_PQSFINDER_CUSTOM_G4_DETECTION.out.plots
    objects  = BIOC_PQSFINDER_CUSTOM_G4_DETECTION.out.objects
    versions = BIOC_PQSFINDER_CUSTOM_G4_DETECTION.out.versions
}
