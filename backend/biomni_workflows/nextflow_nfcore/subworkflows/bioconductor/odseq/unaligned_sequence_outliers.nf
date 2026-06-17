#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: odseq — unaligned_sequence_outliers
// Detect outlier sequences without performing a multiple sequence alignment by using a precomputed similarity matrix.
// Input: seqs.fasta
// Container: quay.io/biocontainers/bioconductor-odseq:1.38.0--r45hdfd78af_0
// R packages: Biostrings, kebabs, odseq
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, kebabs, odseq
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute a similarity matrix using a string kernel from the kebabs package
//  * 2. [Core Analysis] Run outlier detection on the similarity matrix using odseq_unaligned

nextflow.enable.dsl = 2

process BIOC_ODSEQ_UNALIGNED_SEQUENCE_OUTLIERS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("Biostrings", "kebabs", "odseq")
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
    library(Biostrings)
    library(kebabs)
    library(odseq)
    
    # Set seed for reproducibility (odseq_unaligned uses bootstrapping)
    set.seed(93)
    
    # 1. Read the user input FASTA file
    # The original dataset "seqs" consists of amino acid sequences, so we read as AAStringSet
    seqs <- Biostrings::readAAStringSet("seqs.fasta")
    
    # 2. Compute a similarity matrix using a string kernel from the kebabs package
    sp <- spectrumKernel(k = 3)
    mat <- getKernelMatrix(sp, seqs)
    
    # 3. Run outlier detection on the similarity matrix using odseq_unaligned
    outliers_unaligned <- odseq_unaligned(mat, B = 1000, type = "similarity")
    
    # 4. Write outputs to the working directory
    # Save the similarity matrix as an RDS object
    saveRDS(mat, "similarity_matrix.rds")
    
    # Save the logical outlier vector as an RDS object
    saveRDS(outliers_unaligned, "outliers_unaligned.rds")
    
    # Save a CSV table mapping sequence IDs to their outlier status
    output_df <- data.frame(
      sequence_id = names(seqs),
      is_outlier = outliers_unaligned,
      stringsAsFactors = FALSE
    )
    write.csv(output_df, "outlier_results.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_ODSEQ_UNALIGNED_SEQUENCE_OUTLIERS":',
        paste0('    odseq: ', as.character(packageVersion('odseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_unaligned_sequence_outliers.csv versions.yml
    """
}

workflow BIOC_ODSEQ_UNALIGNED_SEQUENCE_OUTLIERS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ seqs.fasta ] ]

    main:
    BIOC_ODSEQ_UNALIGNED_SEQUENCE_OUTLIERS(ch_input)

    emit:
    tables   = BIOC_ODSEQ_UNALIGNED_SEQUENCE_OUTLIERS.out.tables
    plots    = BIOC_ODSEQ_UNALIGNED_SEQUENCE_OUTLIERS.out.plots
    objects  = BIOC_ODSEQ_UNALIGNED_SEQUENCE_OUTLIERS.out.objects
    versions = BIOC_ODSEQ_UNALIGNED_SEQUENCE_OUTLIERS.out.versions
}
