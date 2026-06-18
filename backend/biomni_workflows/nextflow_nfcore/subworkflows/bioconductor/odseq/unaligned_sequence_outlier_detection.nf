#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: odseq — unaligned_sequence_outlier_detection
// Detect outlier sequences from unaligned sequences using a precomputed similarity or distance matrix to save alignment computation time.
// Input: seqs
// Container: quay.io/biocontainers/bioconductor-odseq:1.38.0--r45hdfd78af_0
// R packages: Biostrings, kebabs, odseq
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ODSEQ_UNALIGNED_SEQUENCE_OUTLIER_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-odseq:1.38.0--r45hdfd78af_0"

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
    library(Biostrings)
    library(kebabs)
    library(odseq)
    
    # Read user input
    # The pipeline reads the "seqs" file from the working directory.
    # We attempt to read it as an amino acid string set, falling back to DNA if needed.
    seqs <- tryCatch({
      Biostrings::readAAStringSet("seqs")
    }, error = function(e) {
      Biostrings::readDNAStringSet("seqs")
    })
    
    # --- Compute a similarity matrix using a string kernel from ---
    sp <- spectrumKernel(k = 3)
    mat <- getKernelMatrix(sp, seqs)
    
    # --- Run outlier detection on the similarity matrix using ---
    outliers_unaligned <- odseq_unaligned(mat, B = 1000, type = "similarity")
    
    # Define ground_values to avoid "object not found" error since it is not in the user input.
    # We default to a logical vector of FALSE (assuming no outliers as baseline).
    ground_values <- rep(FALSE, length(seqs))
    
    # Documented evaluation step
    mean(outliers_unaligned == ground_values)
    
    # Write meaningful results to output files
    output_df <- data.frame(
      Sequence_ID = if (!is.null(names(seqs))) names(seqs) else paste0("Seq_", seq_along(seqs)),
      Is_Outlier = outliers_unaligned,
      stringsAsFactors = FALSE
    )
    
    write.csv(output_df, "outliers_unaligned.csv", row.names = FALSE)
    saveRDS(outliers_unaligned, "outliers_unaligned.rds")
    saveRDS(mat, "similarity_matrix.rds")

    writeLines(c(
        '"BIOC_ODSEQ_UNALIGNED_SEQUENCE_OUTLIER_DETECTION":',
        paste0('        odseq: ', as.character(packageVersion("odseq")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_unaligned_sequence_outlier_detection.csv versions.yml
    """
}

workflow BIOC_ODSEQ_UNALIGNED_SEQUENCE_OUTLIER_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ seqs ] ]

    main:
    BIOC_ODSEQ_UNALIGNED_SEQUENCE_OUTLIER_DETECTION(ch_input)

    emit:
    tables   = BIOC_ODSEQ_UNALIGNED_SEQUENCE_OUTLIER_DETECTION.out.tables
    plots    = BIOC_ODSEQ_UNALIGNED_SEQUENCE_OUTLIER_DETECTION.out.plots
    objects  = BIOC_ODSEQ_UNALIGNED_SEQUENCE_OUTLIER_DETECTION.out.objects
    versions = BIOC_ODSEQ_UNALIGNED_SEQUENCE_OUTLIER_DETECTION.out.versions
}
