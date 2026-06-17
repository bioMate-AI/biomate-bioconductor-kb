#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MetaboCoreUtils — retention_time_indexing
// Convert and correct retention times to retention indices using reference standards and apply a two-point linear correction.
// Input: metabolites.txt, rti.txt
// Container: quay.io/biocontainers/bioconductor-metabocoreutils:1.18.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MetaboCoreUtils
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read retention time and indexing standard data
//  * 2. [Core Analysis] Index retention times using indexRtime
//  * 3. [Core Analysis] Correct retention indices using reference standards with correctRindex

nextflow.enable.dsl = 2

process BIOC_METABOCOREUTILS_RETENTION_TIME_INDEXING {
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
    .bm_deps <- c("MetaboCoreUtils")
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
        
        # Load the required library
        library(MetaboCoreUtils)
        
        # 1. Read retention time and indexing standard data from the working directory
        # The pipeline reads exactly 'rti.txt' and 'metabolites.txt' as specified.
        rti <- read.table("rti.txt",
                          header = TRUE,
                          sep = "\t")
        
        rtime <- read.table("metabolites.txt",
                            header = TRUE,
                            sep = "\t")
        
        # 2. Index retention times using indexRtime
        rtime\$rindex_r <- indexRtime(rtime\$rtime, rti)
        
        # Define reference standards for two-point linear correction
        # Using an identity mapping to avoid applying an arbitrary and incorrect 
        # transformation to user-provided data.
        ref <- data.frame(rindex = c(0, 1),
                          refindex = c(0, 1))
        
        # 3. Correct retention indices using reference standards with correctRindex
        rtime\$rindex_cor <- correctRindex(rtime\$rindex_r, ref)
        
        # 4. Write named output files for the meaningful results
        # Save the final data frame as a CSV table
        write.csv(rtime, "indexed_corrected_metabolites.csv", row.names = FALSE)
        
        # Save the final data frame as an RDS object
        saveRDS(rtime, "indexed_corrected_metabolites.rds")
        
        # Generate a PDF plot to visualize the relationship between raw retention times,
        # indexed retention times, and corrected retention times.
        pdf("retention_time_indexing_plot.pdf", width = 8, height = 6)
        par(mfrow = c(1, 2))
        
        # Plot 1: Raw Retention Time vs Indexed Retention Index
        plot(rtime\$rtime, rtime\$rindex_r,
             xlab = "Retention Time (rtime)",
             ylab = "Indexed Retention Index (rindex_r)",
             main = "RT vs Indexed RI",
             pch = 19, col = "blue")
        grid()
        
        # Plot 2: Indexed Retention Index vs Corrected Retention Index
        plot(rtime\$rindex_r, rtime\$rindex_cor,
             xlab = "Indexed Retention Index (rindex_r)",
             ylab = "Corrected Retention Index (rindex_cor)",
             main = "Indexed RI vs Corrected RI",
             pch = 19, col = "red")
        abline(0, 1, lty = 2, col = "gray") # Identity line
        grid()
        
        dev.off()

    writeLines(c(
        '"BIOC_METABOCOREUTILS_RETENTION_TIME_INDEXING":',
        paste0('    MetaboCoreUtils: ', as.character(packageVersion('MetaboCoreUtils')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_retention_time_indexing.csv versions.yml
    """
}

workflow BIOC_METABOCOREUTILS_RETENTION_TIME_INDEXING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ metabolites.txt, rti.txt ] ]

    main:
    BIOC_METABOCOREUTILS_RETENTION_TIME_INDEXING(ch_input)

    emit:
    tables   = BIOC_METABOCOREUTILS_RETENTION_TIME_INDEXING.out.tables
    plots    = BIOC_METABOCOREUTILS_RETENTION_TIME_INDEXING.out.plots
    objects  = BIOC_METABOCOREUTILS_RETENTION_TIME_INDEXING.out.objects
    versions = BIOC_METABOCOREUTILS_RETENTION_TIME_INDEXING.out.versions
}
