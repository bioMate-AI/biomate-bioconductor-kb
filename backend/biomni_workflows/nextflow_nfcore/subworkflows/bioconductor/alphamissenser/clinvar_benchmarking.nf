#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: AlphaMissenseR — clinvar_benchmarking
// Compare AlphaMissense predictions against clinically-validated ClinVar classifications.
// Input: uniprotId
// Container: quay.io/biocontainers/bioconductor-alphamissenser:1.6.1--r45hdfd78af_0
// R packages: AlphaMissenseR, dplyr, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: AlphaMissenseR, dplyr, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Access ClinVar classifications using clinvar_data()
//  * 2. [Core Analysis] Generate a benchmarking scatterplot using clinvar_plot()

nextflow.enable.dsl = 2

process BIOC_ALPHAMISSENSER_CLINVAR_BENCHMARKING {
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
    .bm_deps <- c("AlphaMissenseR", "dplyr", "ggplot2")
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
    library(AlphaMissenseR)
    library(dplyr)
    library(ggplot2)
    
    # Read user input
    uniprot_id_file <- "uniprotId"
    if (!file.exists(uniprot_id_file)) {
      stop("Required input file 'uniprotId' not found in the working directory.")
    }
    uniprot_id <- trimws(readLines(uniprot_id_file, n = 1, warn = FALSE))
    
    # 1. Access ClinVar classifications using clinvar_data()
    message("Accessing ClinVar classifications...")
    clinvar_tbl <- clinvar_data()
    
    # Save ClinVar data to CSV
    clinvar_df <- dplyr::collect(clinvar_tbl)
    write.csv(clinvar_df, "clinvar_classifications.csv", row.names = FALSE)
    message("Saved ClinVar classifications to 'clinvar_classifications.csv'")
    
    # 2. Generate a benchmarking scatterplot using clinvar_plot()
    message(paste("Generating benchmarking plot for UniProt ID:", uniprot_id))
    p <- clinvar_plot(uniprotId = uniprot_id)
    
    # Save the plot to PDF
    ggsave("clinvar_benchmarking_plot.pdf", plot = p, width = 10, height = 7)
    message("Saved benchmarking plot to 'clinvar_benchmarking_plot.pdf'")
    
    # Disconnect from DuckDB
    db_disconnect_all()

    writeLines(c(
        '"BIOC_ALPHAMISSENSER_CLINVAR_BENCHMARKING":',
        paste0('    AlphaMissenseR: ', as.character(packageVersion('AlphaMissenseR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clinvar_benchmarking.csv versions.yml
    """
}

workflow BIOC_ALPHAMISSENSER_CLINVAR_BENCHMARKING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ uniprotId ] ]

    main:
    BIOC_ALPHAMISSENSER_CLINVAR_BENCHMARKING(ch_input)

    emit:
    tables   = BIOC_ALPHAMISSENSER_CLINVAR_BENCHMARKING.out.tables
    plots    = BIOC_ALPHAMISSENSER_CLINVAR_BENCHMARKING.out.plots
    objects  = BIOC_ALPHAMISSENSER_CLINVAR_BENCHMARKING.out.objects
    versions = BIOC_ALPHAMISSENSER_CLINVAR_BENCHMARKING.out.versions
}
