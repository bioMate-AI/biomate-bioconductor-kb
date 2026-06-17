#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeoTcgaData — geo_chip_data_preprocessing
// Preprocess GEO microarray data by averaging duplicate gene symbols and resolving multi-mapped probe IDs.
// Input: file_gene_ave, input_file
// Container: quay.io/biocontainers/bioconductor-geotcgadata:2.10.0--r45hdfd78af_0
// R packages: GeoTcgaData
// Bioconductor: 3.20 | R: 4.4
// Requires: GeoTcgaData
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Average expression values of different IDs for the same gene using gene_ave
//  * 2. [Core Analysis] Resolve multi-mapped probe IDs by either assigning the expression to each gene using repAssign or deleting them using repRemove

nextflow.enable.dsl = 2

process BIOC_GEOTCGADATA_GEO_CHIP_DATA_PREPROCESSING {
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
    .bm_deps <- c("GeoTcgaData")
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
    
    # Load the required package
    library(GeoTcgaData)
    
    # Read the user input files from the working directory
    # file_gene_ave: data frame of gene expression with duplicate gene symbols
    # input_file: data frame of expression data with multi-mapped probe IDs
    file_gene_ave <- read.csv("file_gene_ave.csv", check.names = FALSE, stringsAsFactors = FALSE)
    input_file <- read.csv("input_file.csv", check.names = FALSE, stringsAsFactors = FALSE)
    
    # Stage 1: Average expression values of different IDs for the same gene
    result <- gene_ave(file_gene_ave, 1)
    
    # Stage 2: Resolve multi-mapped probe IDs
    # Option A: Assign the expression to each gene
    repAssign_result <- repAssign(input_file, " /// ")
    
    # Option B: Delete the multi-mapped probe IDs
    repRemove_result <- repRemove(input_file, " /// ")
    
    # Write the results to output CSV files
    write.csv(result, "gene_ave_result.csv", row.names = FALSE)
    write.csv(repAssign_result, "repAssign_result.csv", row.names = FALSE)
    write.csv(repRemove_result, "repRemove_result.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_GEOTCGADATA_GEO_CHIP_DATA_PREPROCESSING":',
        paste0('    GeoTcgaData: ', as.character(packageVersion('GeoTcgaData')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_geo_chip_data_preprocessing.csv versions.yml
    """
}

workflow BIOC_GEOTCGADATA_GEO_CHIP_DATA_PREPROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file_gene_ave, input_file ] ]

    main:
    BIOC_GEOTCGADATA_GEO_CHIP_DATA_PREPROCESSING(ch_input)

    emit:
    tables   = BIOC_GEOTCGADATA_GEO_CHIP_DATA_PREPROCESSING.out.tables
    plots    = BIOC_GEOTCGADATA_GEO_CHIP_DATA_PREPROCESSING.out.plots
    objects  = BIOC_GEOTCGADATA_GEO_CHIP_DATA_PREPROCESSING.out.objects
    versions = BIOC_GEOTCGADATA_GEO_CHIP_DATA_PREPROCESSING.out.versions
}
