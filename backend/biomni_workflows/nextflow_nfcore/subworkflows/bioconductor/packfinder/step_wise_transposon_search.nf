#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: packFinder — step_wise_transposon_search
// Run the individual step-wise functions of the packSearch pipeline to identify TIRs, obtain TSDs, and filter potential elements.
// Input: genome_sequence.fasta, tir_query.txt
// Container: quay.io/biocontainers/bioconductor-packfinder:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, packFinder
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Identify potential forward and reverse TIR matches using identifyTirMatches
//  * 2. [Core Analysis] Obtain TSD sequences using getTsds
//  * 3. [Core Analysis] Filter and identify potential pack elements using identifyPotentialPackElements
//  * 4. [Core Analysis] Retrieve transposon sequences using getPackSeqs

nextflow.enable.dsl = 2

process BIOC_PACKFINDER_STEP_WISE_TRANSPOSON_SEARCH {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    library(packFinder)
    library(Biostrings)
    
    # ==========================================
    # 1. READ USER INPUT FILES
    # ==========================================
    
    # Read the genomic DNA sequence (FASTA format)
    genome_seqs <- Biostrings::readDNAStringSet("genome_sequence.fasta", format = "fasta")
    
    # Read the TIR query sequence of interest from tir_query.txt
    tir_raw <- readLines("tir_query.txt", warn = FALSE)
    tir_clean <- trimws(tir_raw[1])
    tir_query <- Biostrings::DNAString(tir_clean)
    
    # ==========================================
    # 2. STEP-WISE TRANSPOSON SEARCH PIPELINE
    # ==========================================
    
    # Step 2.1: Identify potential forward and reverse TIR matches
    message("Identifying forward TIR matches...")
    forwardMatches <- identifyTirMatches(
        tir_query,
        genome_seqs,
        strand = "+",
        tsdLength = 3
    )
    message(paste("Forward matches found:", nrow(forwardMatches)))
    
    message("Identifying reverse TIR matches...")
    reverseMatches <- identifyTirMatches(
        Biostrings::reverseComplement(tir_query),
        genome_seqs,
        strand = "-",
        tsdLength = 3
    )
    message(paste("Reverse matches found:", nrow(reverseMatches)))
    
    # Step 2.2: Obtain TSD sequences for forward and reverse matches
    message("Obtaining TSD sequences for forward matches...")
    forwardMatches\$TSD <- getTsds(
        forwardMatches,
        genome_seqs,
        3,
        strand = "+"
    )
    
    message("Obtaining TSD sequences for reverse matches...")
    reverseMatches\$TSD <- getTsds(
        reverseMatches,
        genome_seqs,
        3,
        strand = "-"
    )
    
    # Step 2.3: Filter and identify potential pack elements
    message("Filtering and identifying potential pack elements...")
    packMatches <- identifyPotentialPackElements(
        forwardMatches,
        reverseMatches,
        genome_seqs,
        c(300, 3500)
    )
    message(paste("Potential pack elements identified:", nrow(packMatches)))
    
    # Step 2.4: Retrieve transposon sequences
    message("Retrieving transposon sequences...")
    packSeqs <- getPackSeqs(packMatches, genome_seqs)
    
    # ==========================================
    # 3. WRITE OUTPUT FILES
    # ==========================================
    
    # Save the identified pack elements as a CSV table
    packsToCsv(packMatches, "potential_pack_elements.csv")
    message("Saved potential pack elements table to 'potential_pack_elements.csv'")
    
    # Save the identified pack element sequences as a FASTA file
    packsToFasta(packMatches, "potential_pack_elements.fasta", genome_seqs)
    message("Saved potential pack element sequences to 'potential_pack_elements.fasta'")
    
    # Save the R objects for downstream analysis
    saveRDS(packMatches, "packMatches.rds")
    saveRDS(packSeqs, "packSeqs.rds")
    message("Saved R objects to 'packMatches.rds' and 'packSeqs.rds'")
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_PACKFINDER_STEP_WISE_TRANSPOSON_SEARCH":',
        paste0('    packFinder: ', as.character(packageVersion('packFinder')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_wise_transposon_search.csv versions.yml
    """
}

workflow BIOC_PACKFINDER_STEP_WISE_TRANSPOSON_SEARCH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genome_sequence.fasta, tir_query.txt ] ]

    main:
    BIOC_PACKFINDER_STEP_WISE_TRANSPOSON_SEARCH(ch_input)

    emit:
    tables   = BIOC_PACKFINDER_STEP_WISE_TRANSPOSON_SEARCH.out.tables
    plots    = BIOC_PACKFINDER_STEP_WISE_TRANSPOSON_SEARCH.out.plots
    objects  = BIOC_PACKFINDER_STEP_WISE_TRANSPOSON_SEARCH.out.objects
    versions = BIOC_PACKFINDER_STEP_WISE_TRANSPOSON_SEARCH.out.versions
}
