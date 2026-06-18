#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tRNA — trna_structure_analysis_and_subsetting
// Extract specific tRNA structural elements and subset tRNA sequences based on structural features and base-pairing properties.
// Input: gr
// Container: quay.io/biocontainers/bioconductor-trna:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, GenomicRanges, Structstrings, tRNA
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract coordinates of specific tRNA structures
//  * 2. [Core Analysis] Retrieve sequences of specific tRNA structures with optional padding
//  * 3. [Core Analysis] Subset tRNAs based on structural features (unpaired bases, mismatches, bulges, or loop lengths)
//  * 4. [Core Analysis] Retrieve detailed base pairing and loop ID annotations

nextflow.enable.dsl = 2

process BIOC_TRNA_TRNA_STRUCTURE_ANALYSIS_AND_SUBSETTING {
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
    .bm_deps <- c("tRNA", "Structstrings", "GenomicRanges", "Biostrings")
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
    library(tRNA)
    library(Structstrings)
    library(GenomicRanges)
    library(Biostrings)
    
    # -----------------------------------------------------------------------------
    # Input Stage: Read the GRanges object from the working directory
    # -----------------------------------------------------------------------------
    if (file.exists("gr")) {
      gr <- readRDS("gr")
    } else if (file.exists("gr.rds")) {
      gr <- readRDS("gr.rds")
    } else {
      stop("Error: Input file 'gr' or 'gr.rds' not found in the working directory.")
    }
    
    # Ensure the input is a GRanges object
    if (!is(gr, "GRanges")) {
      stop("Error: The input object must be a GRanges object.")
    }
    
    # -----------------------------------------------------------------------------
    # Stage 1: Extract coordinates of specific tRNA structures
    # -----------------------------------------------------------------------------
    anticodon_coords <- gettRNAstructureGRanges(gr, structure = "anticodonLoop")
    
    # Save coordinates to RDS
    saveRDS(anticodon_coords, "anticodon_loop_coordinates.rds")
    
    
    # -----------------------------------------------------------------------------
    # Stage 2: Retrieve sequences of specific tRNA structures with optional padding
    # -----------------------------------------------------------------------------
    anticodon_seqs <- gettRNAstructureSeqs(gr, joinFeatures = TRUE, structure = "anticodonLoop")
    
    # Save anticodon loop sequences
    if (is(anticodon_seqs, "RNAStringSet") || is(anticodon_seqs, "DNAStringSet") || is(anticodon_seqs, "XStringSet")) {
      writeXStringSet(anticodon_seqs, "anticodon_loop_sequences.fasta")
    } else if ((is.list(anticodon_seqs) || is(anticodon_seqs, "List")) && length(anticodon_seqs) > 0) {
      writeXStringSet(anticodon_seqs[[1]], "anticodon_loop_sequences.fasta")
    }
    
    # Retrieve joined completely padded sequences for the first 10 tRNAs
    limit_idx <- min(10L, length(gr))
    seqs <- gettRNAstructureSeqs(gr[1L:limit_idx], joinCompletely = TRUE)
    
    # Save joined sequences
    writeXStringSet(seqs, "joined_trna_sequences.fasta")
    
    # Extract and save tRNA structure boundaries metadata
    struct_metadata <- metadata(seqs)[["tRNA_structures"]]
    saveRDS(struct_metadata, "trna_structures_metadata.rds")
    
    
    # -----------------------------------------------------------------------------
    # Stage 3: Subset tRNAs based on structural features
    # -----------------------------------------------------------------------------
    # Subset based on unpaired bases in the acceptor stem
    gr_unpaired <- gr[hasAcceptorStem(gr, unpaired = TRUE)]
    saveRDS(gr_unpaired, "subset_unpaired_acceptor.rds")
    
    # Subset based on mismatches in the acceptor stem
    gr_mismatches <- gr[hasAcceptorStem(gr, mismatches = TRUE)]
    saveRDS(gr_mismatches, "subset_mismatches_acceptor.rds")
    
    # Subset based on bulges in the acceptor stem
    gr_bulged <- gr[hasAcceptorStem(gr, bulged = TRUE)]
    saveRDS(gr_bulged, "subset_bulged_acceptor.rds")
    
    # Subset based on combination of different structure parameters
    gr_combined <- gr[hasAcceptorStem(gr, mismatches = TRUE) & hasDloop(gr, length = 8L)]
    saveRDS(gr_combined, "subset_combined_features.rds")
    
    
    # -----------------------------------------------------------------------------
    # Stage 4: Retrieve detailed base pairing and loop ID annotations
    # -----------------------------------------------------------------------------
    # Retrieve base pairing details for the first tRNA
    bp_list <- gettRNABasePairing(gr)
    if (length(bp_list) > 0) {
      bp_first <- head(bp_list[[1L]])
      write.csv(as.data.frame(bp_first), "base_pairing_first_trna.csv", row.names = FALSE)
    }
    
    # Retrieve loop IDs for the first tRNA
    loop_ids_list <- gettRNALoopIDs(gr)
    if (length(loop_ids_list) > 0) {
      loop_ids_first <- loop_ids_list[[1L]]
      write.csv(data.frame(Position = seq_along(loop_ids_first), LoopID = loop_ids_first), 
                "loop_ids_first_trna.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_TRNA_TRNA_STRUCTURE_ANALYSIS_AND_SUBSETTING":',
        paste0('    tRNA: ', as.character(packageVersion('tRNA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_trna_structure_analysis_and_subsetting.csv versions.yml
    """
}

workflow BIOC_TRNA_TRNA_STRUCTURE_ANALYSIS_AND_SUBSETTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gr ] ]

    main:
    BIOC_TRNA_TRNA_STRUCTURE_ANALYSIS_AND_SUBSETTING(ch_input)

    emit:
    tables   = BIOC_TRNA_TRNA_STRUCTURE_ANALYSIS_AND_SUBSETTING.out.tables
    plots    = BIOC_TRNA_TRNA_STRUCTURE_ANALYSIS_AND_SUBSETTING.out.plots
    objects  = BIOC_TRNA_TRNA_STRUCTURE_ANALYSIS_AND_SUBSETTING.out.objects
    versions = BIOC_TRNA_TRNA_STRUCTURE_ANALYSIS_AND_SUBSETTING.out.versions
}
