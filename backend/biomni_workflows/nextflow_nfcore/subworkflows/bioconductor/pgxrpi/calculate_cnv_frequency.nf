#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pgxRpi — calculate_cnv_frequency
// Compute binned CNV frequencies from custom segment data.
// Input: segdata.tsv
// Container: quay.io/biocontainers/bioconductor-pgxrpi:1.6.0--r45hdfd78af_0
// R packages: GenomicRanges, pgxRpi
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PGXRPI_CALCULATE_CNV_FREQUENCY {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-pgxrpi:1.6.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicRanges", "pgxRpi")
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
    library(pgxRpi)
    library(GenomicRanges)
    
    # 1. Read the user-provided segment data
    # The file 'segdata.tsv' must exist in the working directory.
    # It should contain segment data with columns for sample ID, chromosome, start, end,
    # and CNV states (at index 6 and index 9).
    if (!file.exists("segdata.tsv")) {
      stop("Error: 'segdata.tsv' not found in the working directory.")
    }
    
    segdata <- read.delim("segdata.tsv", sep = "\t", header = TRUE, check.names = FALSE)
    
    # 2. Calculate CNV frequency using segtoFreq specifying the CNV state column index (column 6)
    segfreq1 <- segtoFreq(segdata, cnv_column_idx = 6, cohort_name = "c1")
    
    # 3. Calculate level-specific CNV frequency using EFO codes (column 9)
    segfreq2 <- segtoFreq(segdata, cnv_column_idx = 9, cohort_name = "c1")
    
    # 4. Save the meaningful results to output files
    # Save as RDS objects (since they are GRangesList objects)
    saveRDS(segfreq1, "segfreq1.rds")
    saveRDS(segfreq2, "segfreq2.rds")
    
    # Convert to data frames and save as CSV tables for accessibility
    segfreq1_df <- as.data.frame(segfreq1)
    segfreq2_df <- as.data.frame(segfreq2)
    write.csv(segfreq1_df, "segfreq1.csv", row.names = FALSE)
    write.csv(segfreq2_df, "segfreq2.csv", row.names = FALSE)
    
    # 5. Visualize the calculated CNV frequencies and save to a PDF
    pdf("cnv_frequency_plots.pdf", width = 10, height = 6)
    
    # Plot for standard CNV frequency (segfreq1)
    tryCatch({
      pgxFreqplot(segfreq1, filters = "c1")
    }, error = function(e) {
      message("Warning: Could not generate plot for segfreq1. ", e\$message)
    })
    
    # Plot for level-specific CNV frequency (segfreq2)
    tryCatch({
      pgxFreqplot(segfreq2, filters = "c1")
    }, error = function(e) {
      message("Warning: Could not generate plot for segfreq2. ", e\$message)
    })
    
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved: segfreq1.rds, segfreq2.rds, segfreq1.csv, segfreq2.csv, cnv_frequency_plots.pdf\n")

    writeLines(c(
        '"BIOC_PGXRPI_CALCULATE_CNV_FREQUENCY":',
        paste0('        pgxRpi: ', as.character(packageVersion("pgxRpi")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_calculate_cnv_frequency.csv versions.yml
    """
}

workflow BIOC_PGXRPI_CALCULATE_CNV_FREQUENCY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ segdata.tsv ] ]

    main:
    BIOC_PGXRPI_CALCULATE_CNV_FREQUENCY(ch_input)

    emit:
    tables   = BIOC_PGXRPI_CALCULATE_CNV_FREQUENCY.out.tables
    plots    = BIOC_PGXRPI_CALCULATE_CNV_FREQUENCY.out.plots
    objects  = BIOC_PGXRPI_CALCULATE_CNV_FREQUENCY.out.objects
    versions = BIOC_PGXRPI_CALCULATE_CNV_FREQUENCY.out.versions
}
