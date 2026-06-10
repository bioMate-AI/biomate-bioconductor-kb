#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: msa — alignment_masking_consensus_and_conservation
// Apply masks to an alignment, compute consensus matrices/sequences, and calculate position-specific conservation scores.
// Input: exampleAA.fasta
// Container: quay.io/biocontainers/bioconductor-msa:1.42.0--r45he8cd136_0
// R packages: Biostrings, IRanges, msa, pwalign
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSA_ALIGNMENT_MASKING_CONSENSUS_AND_CONSERVATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-msa:1.42.0--r45he8cd136_0"

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
    .bm_deps <- c("Biostrings", "IRanges", "msa", "pwalign")
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
    library(msa)
    library(Biostrings)
    library(IRanges)
    library(pwalign)
    
    # 1. Read and align sequences
    # Read the user-provided FASTA file from the working directory
    mySequenceFile <- "exampleAA.fasta"
    mySequences <- readAAStringSet(mySequenceFile)
    myFirstAlignment <- msa(mySequences)
    
    # 2. Apply a column mask using colmask and IRanges
    myMaskedAlignment <- myFirstAlignment
    colM <- IRanges(start=1, end=100)
    colmask(myMaskedAlignment) <- colM
    
    # 3. Retrieve the unmasked alignment
    unmasked_alignment <- unmasked(myMaskedAlignment)
    
    # 4. Compute the consensus matrix
    conMat <- consensusMatrix(myMaskedAlignment)
    
    # 5. Generate a threshold-based consensus sequence
    consSeq <- msaConsensusSequence(myFirstAlignment, type="upperlower", thresh=c(40, 20))
    
    # 6. Calculate position-specific conservation scores using a substitution matrix
    # Note: BLOSUM62 is directly exported by the pwalign package
    scores <- msaConservationScore(myFirstAlignment, BLOSUM62)
    
    # Write outputs to the working directory
    # Save alignment objects
    saveRDS(myFirstAlignment, "myFirstAlignment.rds")
    saveRDS(myMaskedAlignment, "myMaskedAlignment.rds")
    
    # Save unmasked sequences as a FASTA file
    writeXStringSet(unmasked_alignment, "unmasked_alignment.fasta")
    
    # Save consensus matrix as a CSV file
    write.csv(as.data.frame(conMat), "consensus_matrix.csv", row.names = TRUE)
    
    # Save consensus sequence as a text file
    writeLines(consSeq, "consensus_sequence.txt")
    
    # Save conservation scores as a CSV file
    scores_df <- data.frame(
      Position = seq_along(scores),
      Score = scores
    )
    write.csv(scores_df, "conservation_scores.csv", row.names = FALSE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MSA_ALIGNMENT_MASKING_CONSENSUS_AND_CONSERVATION":
        msa: \$(Rscript -e 'cat(as.character(packageVersion("msa")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alignment_masking_consensus_and_conservation.csv versions.yml
    """
}

workflow BIOC_MSA_ALIGNMENT_MASKING_CONSENSUS_AND_CONSERVATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exampleAA.fasta ] ]

    main:
    BIOC_MSA_ALIGNMENT_MASKING_CONSENSUS_AND_CONSERVATION(ch_input)

    emit:
    tables   = BIOC_MSA_ALIGNMENT_MASKING_CONSENSUS_AND_CONSERVATION.out.tables
    plots    = BIOC_MSA_ALIGNMENT_MASKING_CONSENSUS_AND_CONSERVATION.out.plots
    objects  = BIOC_MSA_ALIGNMENT_MASKING_CONSENSUS_AND_CONSERVATION.out.objects
    versions = BIOC_MSA_ALIGNMENT_MASKING_CONSENSUS_AND_CONSERVATION.out.versions
}
