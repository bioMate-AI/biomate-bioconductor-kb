#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rhinotypeR — amino_acid_visualization
// Visualize amino acid substitutions and alignments from either pre-aligned amino acid sequences or translated DNA sequences.
// Input: test_translated.fasta, user_sequences.fasta
// Container: quay.io/biocontainers/bioconductor-rhinotyper:1.4.0--r45hdfd78af_0
// R packages: Biostrings, msa, rhinotypeR
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, msa, rhinotypeR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import aligned amino acid sequences OR translate and align DNA sequences
//  * 2. [Visualization & Output] Plot amino acid alignments

nextflow.enable.dsl = 2

process BIOC_RHINOTYPER_AMINO_ACID_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("Biostrings", "msa", "rhinotypeR")
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
    library(rhinotypeR)
    library(Biostrings)
    library(msa)
    
    # ==========================================
    # STAGE 1: Import aligned amino acid sequences
    # ==========================================
    
    # Read the user-provided aligned amino acid sequences
    aa_seq <- Biostrings::readAAStringSet("test_translated.fasta")
    
    # ==========================================
    # STAGE 2: Plot amino acid alignments (Option 1)
    # ==========================================
    
    # Save the plot of pre-aligned amino acid sequences to a PDF file
    pdf("aa_plot_translated.pdf", width = 12, height = 8)
    plotAA(aa_seq)
    dev.off()
    
    # ==========================================
    # STAGE 3: Translate and align DNA sequences
    # ==========================================
    
    # Read the user-provided unaligned DNA sequences
    user_seqs <- Biostrings::readDNAStringSet("user_sequences.fasta")
    
    # Remove gaps before translation
    aln_no_gaps <- Biostrings::DNAStringSet(
      gsub("-", "", as.character(user_seqs))
    )
    
    # Translate DNA to amino acids
    aa <- Biostrings::translate(aln_no_gaps)
    
    # Align amino acid sequences (as plotAA expects equal width)
    aa_aln <- msa::msa(aa)
    
    # Transform to AAStringSet
    aa_aln <- as(aa_aln, "AAStringSet")
    
    # ==========================================
    # STAGE 4: Plot amino acid alignments (Option 2)
    # ==========================================
    
    # Save the plot of newly aligned amino acid sequences to a PDF file
    pdf("aa_plot_from_dna.pdf", width = 12, height = 8)
    plotAA(aa_aln)
    dev.off()
    
    # Save the generated alignment and objects for downstream analysis
    Biostrings::writeXStringSet(aa_aln, filepath = "aligned_user_amino_acids.fasta")
    saveRDS(aa_aln, file = "aligned_user_amino_acids.rds")

    writeLines(c(
        '"BIOC_RHINOTYPER_AMINO_ACID_VISUALIZATION":',
        paste0('    rhinotypeR: ', as.character(packageVersion('rhinotypeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_amino_acid_visualization.csv versions.yml
    """
}

workflow BIOC_RHINOTYPER_AMINO_ACID_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ test_translated.fasta, user_sequences.fasta ] ]

    main:
    BIOC_RHINOTYPER_AMINO_ACID_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_RHINOTYPER_AMINO_ACID_VISUALIZATION.out.tables
    plots    = BIOC_RHINOTYPER_AMINO_ACID_VISUALIZATION.out.plots
    objects  = BIOC_RHINOTYPER_AMINO_ACID_VISUALIZATION.out.objects
    versions = BIOC_RHINOTYPER_AMINO_ACID_VISUALIZATION.out.versions
}
