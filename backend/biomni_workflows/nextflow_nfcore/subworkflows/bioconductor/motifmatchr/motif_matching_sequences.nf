#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: motifmatchr — motif_matching_sequences
// Find motif matches directly within biological sequences (DNAStringSet or character vectors).
// Input: example_DNAStringSet, example_character, example_motifs
// Container: quay.io/biocontainers/bioconductor-motifmatchr:1.32.0--r45ha27e39d_0
// R packages: BSgenome.Hsapiens.UCSC.hg19, Biostrings, motifmatchr
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg19, Biostrings, motifmatchr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the Biostrings and genome libraries
//  * 2. [Core Analysis] Extract sequences from the genome using genomic ranges
//  * 3. [Core Analysis] Find motif matches using a DNAStringSet input
//  * 4. [Core Analysis] Convert sequences to a character vector and find motif matches

nextflow.enable.dsl = 2

process BIOC_MOTIFMATCHR_MOTIF_MATCHING_SEQUENCES {
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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "Biostrings", "motifmatchr")
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
        
    # Stage 1: Load the Biostrings and genome libraries
    library(motifmatchr)
    library(Biostrings)
    library(BSgenome.Hsapiens.UCSC.hg19)
    
    # Helper function to safely read user inputs (supporting exact name or .rds extension)
    read_input <- function(name) {
      if (file.exists(name)) {
        return(readRDS(name))
      } else if (file.exists(paste0(name, ".rds"))) {
        return(readRDS(paste0(name, ".rds")))
      } else {
        stop(paste("Required input file not found:", name))
      }
    }
    
    # Read the declared user inputs
    example_DNAStringSet <- read_input("example_DNAStringSet")
    example_character_input <- read_input("example_character")
    example_motifs <- read_input("example_motifs")
    
    # Stage 2: Extract sequences from the genome using genomic ranges
    # (Adapted: The sequence data is read directly from the user-provided example_DNAStringSet)
    # example_DNAStringSet <- getSeq(BSgenome.Hsapiens.UCSC.hg19, peaks)
    
    # Stage 3: Find motif matches using a DNAStringSet input
    motif_ix_DNAStringSet <- matchMotifs(example_motifs, example_DNAStringSet) 
    
    # Stage 4: Convert sequences to a character vector and find motif matches
    motif_ix_character <- matchMotifs(example_motifs, example_character_input)
    
    # Write named output files for the meaningful results
    saveRDS(motif_ix_DNAStringSet, "motif_ix_DNAStringSet.rds")
    saveRDS(motif_ix_character, "motif_ix_character.rds")
    
    # Export boolean match matrices as CSV tables
    matches_ds <- as.matrix(motifMatches(motif_ix_DNAStringSet))
    write.csv(matches_ds, "motif_matches_DNAStringSet.csv", row.names = TRUE)
    
    matches_char <- as.matrix(motifMatches(motif_ix_character))
    write.csv(matches_char, "motif_matches_character.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_MOTIFMATCHR_MOTIF_MATCHING_SEQUENCES":',
        paste0('    motifmatchr: ', as.character(packageVersion('motifmatchr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_motif_matching_sequences.csv versions.yml
    """
}

workflow BIOC_MOTIFMATCHR_MOTIF_MATCHING_SEQUENCES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example_DNAStringSet, example_character, example_motifs ] ]

    main:
    BIOC_MOTIFMATCHR_MOTIF_MATCHING_SEQUENCES(ch_input)

    emit:
    tables   = BIOC_MOTIFMATCHR_MOTIF_MATCHING_SEQUENCES.out.tables
    plots    = BIOC_MOTIFMATCHR_MOTIF_MATCHING_SEQUENCES.out.plots
    objects  = BIOC_MOTIFMATCHR_MOTIF_MATCHING_SEQUENCES.out.objects
    versions = BIOC_MOTIFMATCHR_MOTIF_MATCHING_SEQUENCES.out.versions
}
