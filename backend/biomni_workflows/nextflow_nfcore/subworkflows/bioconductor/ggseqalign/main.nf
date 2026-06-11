#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ggseqalign — pairwise_sequence_alignment_visualization
// Align query sequences to a reference subject sequence and visualize the mismatches, insertions, and deletions.
// Input: query_sequences.fa, subject_sequence
// Container: quay.io/biocontainers/bioconductor-ggseqalign:1.4.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, ggplot2, ggseqalign
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load query and subject sequences using Biostrings or character vectors
//  * 2. [Core Analysis] Generate the alignment table using alignment_table()
//  * 3. [Visualization & Output] Plot the alignment using plot_sequence_alignment() with optional customization

nextflow.enable.dsl = 2

process BIOC_GGSEQALIGN_PAIRWISE_SEQUENCE_ALIGNMENT_VISUALIZATION {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("ggseqalign", "Biostrings", "ggplot2")
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
    library(ggseqalign)
    library(Biostrings)
    library(ggplot2)
    
    # Helper function to robustly read DNA or AA sequences
    read_sequences <- function(filepath) {
      tryCatch({
        Biostrings::readDNAStringSet(filepath)
      }, error = function(e) {
        tryCatch({
          Biostrings::readAAStringSet(filepath)
        }, error = function(e2) {
          stop(paste("Failed to read sequence file:", filepath, "\nError details:", e2\$message))
        })
      })
    }
    
    # 1. Load query and subject sequences from the working directory
    query_file <- "query_sequences.fa"
    if (!file.exists(query_file)) {
      stop(paste("Required query sequence file '", query_file, "' not found in the working directory.", sep = ""))
    }
    query_sequences <- read_sequences(query_file)
    
    subject_file <- "subject_sequence"
    if (!file.exists(subject_file)) {
      if (file.exists("subject_sequence.fa")) {
        subject_file <- "subject_sequence.fa"
      } else {
        stop("Required subject sequence file 'subject_sequence' or 'subject_sequence.fa' not found in the working directory.")
      }
    }
    subject_sequence <- read_sequences(subject_file)
    
    # Ensure subject sequence is of length 1 as required by alignment_table
    if (length(subject_sequence) > 1) {
      message("Subject sequence file contains multiple sequences. Using the first sequence as the reference.")
      subject_sequence <- subject_sequence[1]
    }
    
    # 2. Generate the alignment table using alignment_table()
    alignment <- alignment_table(query_sequences, subject_sequence)
    
    # Save the alignment table and object to files
    write.csv(as.data.frame(alignment), "alignment_table.csv", row.names = FALSE)
    saveRDS(alignment, "alignment.rds")
    
    # 3. Plot the alignment using plot_sequence_alignment() with customization
    p <- plot_sequence_alignment(alignment) +
        theme(text = element_text(size = 15))
    
    # Save the plot to a PDF file
    ggsave("sequence_alignment_plot.pdf", plot = p, width = 12, height = 8)

    writeLines(c(
        '"BIOC_GGSEQALIGN_PAIRWISE_SEQUENCE_ALIGNMENT_VISUALIZATION":',
        paste0('    ggseqalign: ', as.character(packageVersion('ggseqalign')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pairwise_sequence_alignment_visualization.csv versions.yml
    """
}

workflow BIOC_GGSEQALIGN_PAIRWISE_SEQUENCE_ALIGNMENT_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ query_sequences.fa, subject_sequence ] ]

    main:
    BIOC_GGSEQALIGN_PAIRWISE_SEQUENCE_ALIGNMENT_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_GGSEQALIGN_PAIRWISE_SEQUENCE_ALIGNMENT_VISUALIZATION.out.tables
    plots    = BIOC_GGSEQALIGN_PAIRWISE_SEQUENCE_ALIGNMENT_VISUALIZATION.out.plots
    objects  = BIOC_GGSEQALIGN_PAIRWISE_SEQUENCE_ALIGNMENT_VISUALIZATION.out.objects
    versions = BIOC_GGSEQALIGN_PAIRWISE_SEQUENCE_ALIGNMENT_VISUALIZATION.out.versions
}
