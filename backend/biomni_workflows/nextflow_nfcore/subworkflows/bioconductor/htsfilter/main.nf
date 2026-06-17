#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HTSFilter — matrix_and_dataframe
// Filter high-throughput sequencing data in the form of a raw count matrix or data.frame using TMM normalization.
// Input: counts_matrix.csv, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-htsfilter:1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: HTSFilter
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract the expression matrix and condition labels
//  * 2. [Core Analysis] Run HTSFilter to find the optimal threshold and filter the matrix
//  * 3. [Core Analysis] Extract the filtered and removed data matrices

nextflow.enable.dsl = 2

process BIOC_HTSFILTER_MATRIX_AND_DATAFRAME {
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
    .bm_deps <- c("HTSFilter")
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
    library(HTSFilter)
    
    # 1. Read user input files
    counts <- read.csv("counts_matrix.csv", row.names = 1, check.names = FALSE)
    mat <- as.matrix(counts)
    
    metadata <- read.csv("sample_metadata.csv", row.names = 1, check.names = FALSE)
    # Align metadata with matrix columns
    metadata <- metadata[colnames(mat), , drop = FALSE]
    
    # Extract condition labels (use 'cell.line' if present, otherwise fallback to the first column)
    if ("cell.line" %in% colnames(metadata)) {
      conds <- as.character(metadata\$cell.line)
    } else {
      conds <- as.character(metadata[[1]])
    }
    
    # 2. Run HTSFilter to find the optimal threshold and filter the matrix
    # Capture the Jaccard index plot in a PDF file
    pdf("HTSFilter_jaccard_plot.pdf")
    filter <- HTSFilter(mat, conds, s.min=1, s.max=200, s.len=25)
    dev.off()
    
    # 3. Extract the filtered and removed data matrices
    mat <- filter\$filteredData
    dim(mat)
    dim(filter\$removedData)
    
    # 4. Write outputs to files
    write.csv(mat, "filtered_counts.csv", row.names = TRUE)
    write.csv(filter\$removedData, "removed_counts.csv", row.names = TRUE)
    saveRDS(filter, "HTSFilter_results.rds")

    writeLines(c(
        '"BIOC_HTSFILTER_MATRIX_AND_DATAFRAME":',
        paste0('    HTSFilter: ', as.character(packageVersion('HTSFilter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matrix_and_dataframe.csv versions.yml
    """
}

workflow BIOC_HTSFILTER_MATRIX_AND_DATAFRAME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_matrix.csv, sample_metadata.csv ] ]

    main:
    BIOC_HTSFILTER_MATRIX_AND_DATAFRAME(ch_input)

    emit:
    tables   = BIOC_HTSFILTER_MATRIX_AND_DATAFRAME.out.tables
    plots    = BIOC_HTSFILTER_MATRIX_AND_DATAFRAME.out.plots
    objects  = BIOC_HTSFILTER_MATRIX_AND_DATAFRAME.out.objects
    versions = BIOC_HTSFILTER_MATRIX_AND_DATAFRAME.out.versions
}
