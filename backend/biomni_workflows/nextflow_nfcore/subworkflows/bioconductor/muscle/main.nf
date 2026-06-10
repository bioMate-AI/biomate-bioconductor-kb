#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: muscle — multiple_sequence_alignment
// Perform multiple sequence alignment on nucleotide or amino acid sequences.
// Input: sequences.fasta
// Container: quay.io/biocontainers/bioconductor-muscle:3.52.0--r45ha27e39d_0
// R packages: Biostrings, muscle
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MUSCLE_MULTIPLE_SEQUENCE_ALIGNMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-muscle:3.52.0--r45ha27e39d_0"

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
    .bm_deps <- c("Biostrings", "muscle")
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
    library(muscle)
    library(Biostrings)
    
    # Verify user input file exists
    input_file <- "sequences.fasta"
    if (!file.exists(input_file)) {
      stop(paste("Error: Required input file", input_file, "not found in the working directory."))
    }
    
    # Read the unaligned sequences from the user-provided FASTA file.
    # We assign this to 'umax' to match the variable name in the documented code.
    umax <- readDNAStringSet(input_file, format = "fasta")
    
    # Perform multiple sequence alignment using the muscle function
    aln <- muscle(umax)
    
    # Adapt the documented file reading step using the user input file path
    file.path <- input_file
    orf <- readDNAStringSet(file.path, format = "fasta")
    
    # Perform alignments with various documented parameter constraints
    aln <- muscle(umax, diags = TRUE)
    aln <- muscle(umax, gapopen = -30)
    aln <- muscle(umax, quiet = TRUE)
    aln <- muscle(umax, maxhours = 24.0)
    
    # Save the final alignment object to an RDS file
    saveRDS(aln, file = "alignment_results.rds")
    
    # Write the aligned sequences to a FASTA file for downstream analysis
    aligned_set <- as(aln, "DNAStringSet")
    writeXStringSet(aligned_set, filepath = "aligned_sequences.fasta", format = "fasta")
    
    # Print completion message
    cat("Multiple sequence alignment completed successfully.\n")
    cat("Outputs saved:\n")
    cat(" - alignment_results.rds (DNAMultipleAlignment object)\n")
    cat(" - aligned_sequences.fasta (Aligned sequences in FASTA format)\n")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MUSCLE_MULTIPLE_SEQUENCE_ALIGNMENT":
        muscle: \$(Rscript -e 'cat(as.character(packageVersion("muscle")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiple_sequence_alignment.csv versions.yml
    """
}

workflow BIOC_MUSCLE_MULTIPLE_SEQUENCE_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sequences.fasta ] ]

    main:
    BIOC_MUSCLE_MULTIPLE_SEQUENCE_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_MUSCLE_MULTIPLE_SEQUENCE_ALIGNMENT.out.tables
    plots    = BIOC_MUSCLE_MULTIPLE_SEQUENCE_ALIGNMENT.out.plots
    objects  = BIOC_MUSCLE_MULTIPLE_SEQUENCE_ALIGNMENT.out.objects
    versions = BIOC_MUSCLE_MULTIPLE_SEQUENCE_ALIGNMENT.out.versions
}
